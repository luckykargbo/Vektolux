// convex/reversals.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Admin: refunds AFTER a payout (Finance → Reversals & Recovery).
//
//  • A settled payout is never edited: a refund creates a reversal with its own transaction and
//    ledger ids (walletCore.reverseSettledRelease).
//  • The recipient is never taken below zero and the buyer is credited only what was really
//    recovered. A shortfall stays OPEN ("pending_recovery") until an admin retries, has the
//    platform cover it, or writes it off — each step audited.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { requireAdminSession } from "./lib/auth";
import { closeReversalRecovery, retryReversalRecovery, reverseSettledRelease } from "./walletCore";

function requireNote(raw: string, what: string): string {
  const note = raw.trim();
  if (note.length < 5) throw new Error(`${what} is required (at least 5 characters).`);
  return note;
}

/** Reverses one completed escrow release (refund after payout). */
export const adminReverseRelease = mutation({
  args: { sessionToken: v.optional(v.string()), releaseTransactionId: v.id("transactions"), reason: v.string() },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    const reason = requireNote(args.reason, "A reason");
    const r = await reverseSettledRelease(ctx, { releaseTransactionId: args.releaseTransactionId, reason, actorId: adminId });
    if (!r.duplicate) {
      await ctx.db.insert("audit_logs", {
        adminUserId: adminId,
        action: "PAYMENT_REVERSED",
        targetTransactionId: r.reversalId as string,
        snapshot: JSON.stringify({
          releaseTransactionId: args.releaseTransactionId,
          refundedToBuyer: r.refundedToBuyer,
          outstanding: r.outstanding,
          status: r.status,
          reason,
        }),
        timestamp: Date.now(),
      });
    }
    return { ...r, reversalId: r.reversalId as string };
  },
});

/** Retries recovery of an open shortfall from the recipient's current available balance. */
export const adminRetryRecovery = mutation({
  args: { sessionToken: v.optional(v.string()), reversalId: v.id("payment_reversals"), note: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    const r = await retryReversalRecovery(ctx, { reversalId: args.reversalId, actorId: adminId, note: args.note?.trim() });
    if (r.recovered > 0) {
      await ctx.db.insert("audit_logs", {
        adminUserId: adminId,
        action: "RECOVERY_RETRIED",
        targetTransactionId: args.reversalId as string,
        snapshot: JSON.stringify({ recovered: r.recovered, outstanding: r.outstanding, status: r.status }),
        timestamp: Date.now(),
      });
    }
    return r;
  },
});

/** Closes an open recovery case: the platform covers the shortfall, or it is written off. */
export const adminCloseRecovery = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    reversalId: v.id("payment_reversals"),
    resolution: v.union(v.literal("platform_covered"), v.literal("written_off")),
    note: v.string(),
  },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    const note = requireNote(args.note, "A note");
    const r = await closeReversalRecovery(ctx, { reversalId: args.reversalId, resolution: args.resolution, actorId: adminId, note });
    await ctx.db.insert("audit_logs", {
      adminUserId: adminId,
      action: "RECOVERY_CLOSED",
      targetTransactionId: args.reversalId as string,
      snapshot: JSON.stringify({ resolution: r.status, amount: r.amount, note }),
      timestamp: Date.now(),
    });
    return r;
  },
});

/** Reversals (optionally by status) with their event history (admin only). */
export const adminListReversals = query({
  args: {
    sessionToken: v.optional(v.string()),
    status: v.optional(
      v.union(
        v.literal("completed"),
        v.literal("pending_recovery"),
        v.literal("recovered"),
        v.literal("platform_covered"),
        v.literal("written_off")
      )
    ),
  },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const rows = args.status
      ? await ctx.db.query("payment_reversals").withIndex("by_status", (q) => q.eq("status", args.status!)).order("desc").take(100)
      : await ctx.db.query("payment_reversals").order("desc").take(100);
    const names = new Map<string, { name: string; email: string | null }>();
    const person = async (id: Id<"users"> | undefined) => {
      if (!id) return null;
      if (!names.has(id)) {
        const u = await ctx.db.get(id);
        names.set(id, { name: u?.name ?? "Unknown user", email: u?.email ?? null });
      }
      return names.get(id)!;
    };
    const out = [];
    for (const r of rows) {
      const events = await ctx.db
        .query("payment_reversal_events")
        .withIndex("by_reversal", (q) => q.eq("reversalId", r._id))
        .collect();
      const release = await ctx.db.get(r.releaseTransactionId);
      const eventsOut = [];
      for (const e of events) {
        eventsOut.push({
          action: e.action,
          amount: e.amount,
          transactionCode: e.transactionCode ?? null,
          ledgerCode: e.ledgerCode ?? null,
          note: e.note ?? null,
          at: e.at,
          actorName: (await person(e.actorId))?.name ?? null,
        });
      }
      out.push({
        ...r,
        id: r._id as string,
        buyer: await person(r.buyerId),
        recipient: await person(r.recipientId),
        createdByName: (await person(r.createdBy))?.name ?? null,
        closedByName: (await person(r.closedBy))?.name ?? null,
        protectionActive: r.status === "pending_recovery" && r.withdrawalProtection !== "lifted",
        originalRelease: release
          ? {
              transactionCode: release.transactionId ?? null,
              amount: release.amount,
              platformFee: release.platformFeeAmount ?? release.feeAmount ?? 0,
              referenceType: release.referenceType ?? null,
              referenceId: release.referenceId ?? null,
              releasedAt: release.createdAt ?? null,
            }
          : null,
        events: eventsOut,
      });
    }
    return out;
  },
});

/**
 * Lifts or restores the protection that keeps an open recovery's outstanding amount from being
 * withdrawn/transferred/spent by the recipient (admin only, note required, audited).
 */
export const adminSetRecoveryProtection = mutation({
  args: { sessionToken: v.optional(v.string()), reversalId: v.id("payment_reversals"), lifted: v.boolean(), note: v.string() },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    const note = requireNote(args.note, "A note");
    const rev = await ctx.db.get(args.reversalId);
    if (!rev) throw new Error("Reversal not found.");
    if (rev.status !== "pending_recovery") throw new Error("Only an open recovery case has a protection to change.");
    const next = args.lifted ? "lifted" : "active";
    if ((rev.withdrawalProtection ?? "active") === next) throw new Error(`The protection is already ${next}.`);
    const now = Date.now();
    await ctx.db.patch(rev._id, {
      withdrawalProtection: next,
      protectionChangedBy: adminId,
      protectionChangedAt: now,
      protectionNote: note.slice(0, 500),
      updatedAt: now,
    });
    await ctx.db.insert("payment_reversal_events", {
      reversalId: rev._id,
      action: args.lifted ? "PROTECTION_LIFTED" : "PROTECTION_RESTORED",
      amount: rev.outstandingAmount,
      actorId: adminId,
      note: note.slice(0, 500),
      at: now,
    });
    await ctx.db.insert("audit_logs", {
      adminUserId: adminId,
      action: "RECOVERY_PROTECTION_CHANGED",
      targetTransactionId: rev._id as string,
      snapshot: JSON.stringify({ protection: next, outstanding: rev.outstandingAmount, note }),
      timestamp: now,
    });
    return { withdrawalProtection: next };
  },
});

/** Recent completed escrow releases (buyer side) that an admin can reverse. */
export const adminListRecentReleases = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const rows = await ctx.db.query("transactions").withIndex("by_status", (q) => q.eq("status", "completed")).order("desc").take(1000);
    const out = [];
    for (const r of rows) {
      if (r.type !== "escrow_release" || !r.counterpartyId) continue;
      const reversed = await ctx.db
        .query("payment_reversals")
        .withIndex("by_release", (q) => q.eq("releaseTransactionId", r._id))
        .first();
      const [buyer, recipient] = [await ctx.db.get(r.userId), await ctx.db.get(r.counterpartyId)];
      out.push({
        id: r._id as string,
        transactionCode: r.transactionId ?? null,
        amount: r.amount,
        platformFee: r.platformFeeAmount ?? r.feeAmount ?? 0,
        currency: r.currency,
        referenceType: r.referenceType ?? null,
        referenceId: r.referenceId ?? null,
        releasedAt: r.createdAt ?? null,
        buyerName: buyer?.name ?? null,
        recipientName: recipient?.name ?? null,
        reversalId: reversed ? (reversed._id as string) : null,
      });
      if (out.length >= 100) break;
    }
    return out;
  },
});
