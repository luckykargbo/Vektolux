// convex/monimeWebhooks.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Monime webhook event ledger (duplicate / replay protection).
//
// Monime keeps the same event.id across its own retries, and during the migration window the same
// real-world event may reach us through two webhooks. This ledger makes event handling at-most-once
// per event id while still allowing a retry after a failed attempt. It is a SECOND line of defence:
// every money movement is also idempotent on its own (provider reference / idempotency key), so a
// duplicate delivery can never create a duplicate credit, payout, escrow funding or ledger entry.
// ═══════════════════════════════════════════════════════════════════════

import { internalMutation } from "./_generated/server";
import { v } from "convex/values";

const STALE_PROCESSING_MS = 2 * 60 * 1000;
const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

/** Claims an event for processing. fresh=false means it is done (or being handled right now). */
export const claimEvent = internalMutation({
  args: { eventId: v.string(), eventName: v.string(), objectId: v.string() },
  handler: async (ctx, args) => {
    const now = Date.now();
    const existing = await ctx.db
      .query("monime_webhook_events")
      .withIndex("by_eventId", (q) => q.eq("eventId", args.eventId))
      .first();
    if (!existing) {
      await ctx.db.insert("monime_webhook_events", {
        eventId: args.eventId,
        eventName: args.eventName,
        objectId: args.objectId,
        status: "processing",
        attempts: 1,
        receivedAt: now,
      });
      return { fresh: true };
    }
    if (existing.status === "done") return { fresh: false };
    if (existing.status === "processing" && now - existing.receivedAt < STALE_PROCESSING_MS) return { fresh: false };
    // failed, or a stale "processing" claim: allow a retry
    await ctx.db.patch(existing._id, { status: "processing", attempts: existing.attempts + 1, receivedAt: now });
    return { fresh: true };
  },
});

export const finishEvent = internalMutation({
  args: { eventId: v.string(), ok: v.boolean(), outcome: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const row = await ctx.db
      .query("monime_webhook_events")
      .withIndex("by_eventId", (q) => q.eq("eventId", args.eventId))
      .first();
    if (!row) return;
    await ctx.db.patch(row._id, {
      status: args.ok ? "done" : "failed",
      completedAt: Date.now(),
      outcome: args.outcome?.slice(0, 60),
    });
  },
});

/** Daily housekeeping: events older than 30 days are dropped (replays are rejected after 5 minutes anyway). */
export const purgeOldEvents = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = Date.now() - RETENTION_MS;
    const old = await ctx.db
      .query("monime_webhook_events")
      .withIndex("by_receivedAt", (q) => q.lt("receivedAt", cutoff))
      .take(200);
    for (const row of old) await ctx.db.delete(row._id);
    return { deleted: old.length };
  },
});
