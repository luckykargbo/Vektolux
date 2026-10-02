// convex/feeRules.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Admin management of fee & commission rules (Finance → Fees & Commissions).
//
//  • A change is a NEW rule version; existing rows are never edited (history is permanent).
//  • A rule takes effect at `effectiveFrom` (now, or scheduled in the future; never backdated).
//  • A scheduled rule can be cancelled until it takes effect; an effective rule is replaced by
//    adding a newer version, not by editing it.
//  • Every change and cancellation is written to the audit log.
//  • Orders store a snapshot of the rule they were priced with, so changes here never affect
//    existing orders (lib/fees.ts).
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { requireAdminSession } from "./lib/auth";
import {
  computeFees,
  DEFAULT_FEE_TERMS,
  FEE_VERTICALS,
  FeeVertical,
  feeVerticalValidator,
  resolveFeeRule,
  VERTICAL_SHAPES,
} from "./lib/fees";

const MAX_FEE_BPS = 5000; // 50%: a typo guard, not a business limit
const MAX_SCHEDULE_AHEAD_MS = 365 * 24 * 60 * 60 * 1000;
const BACKDATE_TOLERANCE_MS = 60 * 1000;

function assertBps(name: string, value: number, max: number) {
  if (!Number.isInteger(value) || value < 0 || value > max) {
    throw new Error(`${name} must be a whole number of basis points between 0 and ${max} (100 bps = 1%).`);
  }
}

/** Current, scheduled and recent rules for every vertical (admin only). */
export const adminListFeeRules = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const now = Date.now();
    const names = new Map<string, string>();
    const nameOf = async (id: Id<"users"> | undefined) => {
      if (!id) return null;
      if (!names.has(id)) {
        const u = await ctx.db.get(id);
        names.set(id, u?.name ?? u?.email ?? "Unknown admin");
      }
      return names.get(id)!;
    };
    const out = [];
    for (const vertical of FEE_VERTICALS) {
      const current = await resolveFeeRule(ctx, vertical, now);
      const rows = await ctx.db
        .query("fee_rules")
        .withIndex("by_vertical_version", (q) => q.eq("vertical", vertical))
        .order("desc")
        .take(25);
      const history = [];
      for (const r of rows) {
        history.push({
          id: r._id as string,
          version: r.version,
          status: r.status,
          inEffect: r._id === current.ruleId,
          effectiveFrom: r.effectiveFrom,
          ownerFeeBps: r.ownerFeeBps,
          buyerFeeBps: r.buyerFeeBps,
          agentCommissionBps: r.agentCommissionBps,
          agentCommissionPayer: r.agentCommissionPayer,
          platformShareOfAgentCommissionBps: r.platformShareOfAgentCommissionBps,
          note: r.note,
          createdAt: r.createdAt,
          createdByName: await nameOf(r.createdBy),
          cancelledAt: r.cancelledAt ?? null,
          cancelledByName: await nameOf(r.cancelledBy),
          cancelReason: r.cancelReason ?? null,
        });
      }
      const shape = VERTICAL_SHAPES[vertical];
      // Worked example on a 1,000 order with the rule in effect now (with an authorised agent where
      // the flow supports agents), so admins see what each party gets.
      const example = computeFees(vertical, current.terms, 1000, { hasAgent: shape.agentCapable });
      out.push({
        vertical,
        label: shape.label,
        agentCapable: shape.agentCapable,
        rounding: shape.rounding,
        ownerFeeBase: shape.ownerFeeBase,
        defaults: DEFAULT_FEE_TERMS[vertical],
        current: { ...current.terms, source: current.source, version: current.version, ruleId: current.ruleId ?? null },
        example,
        scheduled: history.filter((r) => r.status === "active" && r.effectiveFrom > now),
        history,
      });
    }
    const audit = [];
    for (const action of ["FEE_RULE_CHANGED", "FEE_RULE_CANCELLED"] as const) {
      const logs = await ctx.db
        .query("audit_logs")
        .withIndex("by_action", (q) => q.eq("action", action))
        .order("desc")
        .take(50);
      for (const l of logs) {
        let detail: any = {};
        try {
          detail = JSON.parse(l.snapshot);
        } catch {
          detail = {};
        }
        audit.push({
          action,
          at: l.timestamp,
          seq: l._creationTime,
          adminName: await nameOf(l.adminUserId),
          vertical: detail.vertical ?? null,
          version: detail.version ?? null,
          effectiveFrom: detail.effectiveFrom ?? null,
          previous: detail.previous ?? null,
          next: detail.next ?? null,
          note: detail.note ?? detail.reason ?? null,
        });
      }
    }
    audit.sort((a, b) => b.at - a.at || b.seq - a.seq); // newest first; creation order breaks ties
    return { now, verticals: out, audit: audit.slice(0, 50).map(({ seq, ...rest }) => rest) };
  },
});

/** Adds a new rule version for a vertical, effective now or at a future time (admin only). */
export const adminSetFeeRule = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    vertical: feeVerticalValidator,
    ownerFeeBps: v.number(),
    buyerFeeBps: v.number(),
    agentCommissionBps: v.number(),
    agentCommissionPayer: v.union(v.literal("buyer"), v.literal("owner")),
    platformShareOfAgentCommissionBps: v.number(),
    effectiveFrom: v.optional(v.number()),
    note: v.string(),
  },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    const vertical = args.vertical as FeeVertical;
    const now = Date.now();

    assertBps("ownerFeeBps", args.ownerFeeBps, MAX_FEE_BPS);
    assertBps("buyerFeeBps", args.buyerFeeBps, MAX_FEE_BPS);
    assertBps("agentCommissionBps", args.agentCommissionBps, MAX_FEE_BPS);
    assertBps("platformShareOfAgentCommissionBps", args.platformShareOfAgentCommissionBps, 10000);
    if (!VERTICAL_SHAPES[vertical].agentCapable && (args.agentCommissionBps > 0 || args.platformShareOfAgentCommissionBps > 0)) {
      throw new Error(`${VERTICAL_SHAPES[vertical].label} does not support agent commissions yet.`);
    }
    if (VERTICAL_SHAPES[vertical].ownerFeeBase === "buyer_total" && args.agentCommissionBps > 0) {
      throw new Error("This vertical does not support agent commissions.");
    }
    const note = args.note.trim();
    if (note.length < 5) throw new Error("A note explaining the change is required.");

    const effectiveFrom = args.effectiveFrom ?? now;
    if (!Number.isInteger(effectiveFrom) || effectiveFrom < now - BACKDATE_TOLERANCE_MS) {
      throw new Error("A fee rule cannot be backdated.");
    }
    if (effectiveFrom > now + MAX_SCHEDULE_AHEAD_MS) throw new Error("A fee rule can be scheduled at most one year ahead.");

    const last = await ctx.db
      .query("fee_rules")
      .withIndex("by_vertical_version", (q) => q.eq("vertical", vertical))
      .order("desc")
      .first();
    const version = (last?.version ?? 0) + 1;
    const ruleId = await ctx.db.insert("fee_rules", {
      vertical,
      version,
      ownerFeeBps: args.ownerFeeBps,
      buyerFeeBps: args.buyerFeeBps,
      agentCommissionBps: args.agentCommissionBps,
      agentCommissionPayer: args.agentCommissionPayer,
      platformShareOfAgentCommissionBps: args.platformShareOfAgentCommissionBps,
      effectiveFrom,
      status: "active",
      note: note.slice(0, 500),
      createdBy: adminId,
      createdAt: now,
    });
    const previous = await resolveFeeRule(ctx, vertical, effectiveFrom - 1);
    await ctx.db.insert("audit_logs", {
      adminUserId: adminId,
      action: "FEE_RULE_CHANGED",
      targetTransactionId: ruleId as string,
      snapshot: JSON.stringify({
        vertical,
        version,
        effectiveFrom,
        previous: { ...previous.terms, source: previous.source, version: previous.version },
        next: {
          ownerFeeBps: args.ownerFeeBps,
          buyerFeeBps: args.buyerFeeBps,
          agentCommissionBps: args.agentCommissionBps,
          agentCommissionPayer: args.agentCommissionPayer,
          platformShareOfAgentCommissionBps: args.platformShareOfAgentCommissionBps,
        },
        note,
      }),
      timestamp: now,
    });
    return { ruleId: ruleId as string, version, effectiveFrom };
  },
});

/** Cancels a rule that has NOT taken effect yet (admin only). */
export const adminCancelScheduledFeeRule = mutation({
  args: { sessionToken: v.optional(v.string()), ruleId: v.id("fee_rules"), reason: v.string() },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    const rule = await ctx.db.get(args.ruleId);
    if (!rule) throw new Error("Fee rule not found.");
    if (rule.status !== "active") throw new Error("This rule is already cancelled.");
    const now = Date.now();
    if (rule.effectiveFrom <= now) {
      throw new Error("This rule is already in effect. Add a new version to change the fees.");
    }
    const reason = args.reason.trim();
    if (reason.length < 5) throw new Error("A reason is required.");
    await ctx.db.patch(rule._id, { status: "cancelled", cancelledBy: adminId, cancelledAt: now, cancelReason: reason.slice(0, 500) });
    await ctx.db.insert("audit_logs", {
      adminUserId: adminId,
      action: "FEE_RULE_CANCELLED",
      targetTransactionId: rule._id as string,
      snapshot: JSON.stringify({ vertical: rule.vertical, version: rule.version, effectiveFrom: rule.effectiveFrom, reason }),
      timestamp: now,
    });
    return { success: true };
  },
});
