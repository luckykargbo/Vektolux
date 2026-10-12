// convex/escrowExpiry.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Expiry of UNPAID escrow orders (vehicle orders, real-estate contracts, inspection passes).
//
// Approved policy (docs/escrow-order-expiry-plan.md):
//   • vehicle orders / real-estate contracts on the WALLET or MOBILE_MONEY rail expire after 14 days;
//   • BANK_TRANSFER orders/contracts are NEVER expired automatically (a wire can arrive at any time and
//     leaves no record until an admin confirms it);
//   • an inspection pass expires at its own deadline (scheduled time + 4 h = otpExpiresAt);
//   • nothing with unresolved payment evidence, held/moved funds, a claim, a dispute, a reversal or a
//     cleared transfer is ever expired.
//
// What expiry does: sets the record CANCELLED (+ cancelledAt/Reason/By), closes the caution-deposit row
// (VOID, heldAmount 0) and marks milestones CANCELLED, notifies the parties. It NEVER touches a wallet,
// a transaction or a ledger row.
//
// Safety: every record is re-evaluated and written inside the SAME mutation (serializable), and the
// transition is guarded by its own status, so it is idempotent and cannot interleave with funding: a
// concurrent funding either commits first (the record is then not unpaid and is skipped) or retries and
// finds CANCELLED. Money that arrives later is never lost: Monime and claim approvals credit the WALLET
// before attempting to fund; the admin bank confirmation credits the wallet for a cancelled order.
//
// The cron entry is behind JOB_SWITCHES.ESCROW_ORDER_EXPIRY_JOBS_ENABLED (default OFF). The admin
// dry-run is read-only.
// ═══════════════════════════════════════════════════════════════════════

import { v } from "convex/values";
import { internalMutation, query } from "./_generated/server";
import { requireAdmin } from "./lib/auth";

export const UNPAID_ORDER_EXPIRY_MS = 14 * 24 * 60 * 60 * 1000;
const EXPIRABLE_RAILS = ["MOBILE_MONEY", "WALLET"] as const;
const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;
const CANDIDATE_WINDOW_FACTOR = 4;

export type Evaluation = { eligible: boolean; blockers: string[] };
type Db = { db: any };

const days = (ms: number) => Math.floor(ms / (24 * 60 * 60 * 1000));

async function anyTx(ctx: Db, referenceType: string, referenceId: string) {
  return await ctx.db
    .query("transactions")
    .withIndex("by_reference", (q: any) => q.eq("referenceType", referenceType).eq("referenceId", referenceId))
    .take(5);
}

/** Evidence of provider payment for a checkout tag: anything that is not a definitively FAILED attempt. */
async function unresolvedProviderPayment(ctx: Db, tag: string): Promise<boolean> {
  const rows = await anyTx(ctx, "escrow_checkout", tag);
  return rows.some((t: any) => t.status !== "failed");
}

function railBlockers(o: { paymentRail?: string; paymentProvider?: string; bankEscrowReference?: string; bankClearingStatus?: string }): string[] {
  const out: string[] = [];
  if (o.paymentRail === "BANK_TRANSFER" || o.paymentProvider === "BANK_TRANSFER" || o.bankEscrowReference || o.bankClearingStatus) {
    out.push("BANK_TRANSFER_RAIL");
  } else if (!o.paymentRail || !(EXPIRABLE_RAILS as readonly string[]).includes(o.paymentRail)) {
    out.push("RAIL_NOT_ELIGIBLE");
  }
  return out;
}

async function openReversalFor(ctx: Db, referenceId: string): Promise<boolean> {
  const rows = await ctx.db.query("payment_reversals").withIndex("by_status", (q: any) => q.eq("status", "pending_recovery")).take(200);
  return rows.some((r: any) => r.referenceId === referenceId);
}

// ─── eligibility ─────────────────────────────────────────────────────

export async function evaluateVehicleOrder(ctx: Db, order: any, now: number): Promise<Evaluation> {
  const blockers: string[] = [];
  if (order.status !== "PENDING_PAYMENT") blockers.push("NOT_AWAITING_PAYMENT");
  if (now - order.createdAt < UNPAID_ORDER_EXPIRY_MS) blockers.push("TOO_RECENT");
  blockers.push(...railBlockers(order));
  if ((order.split60ReleasedAmount ?? 0) > 0 || (order.split40ReleasedAmount ?? 0) > 0 || (order.depositRefundedAmount ?? 0) > 0) {
    blockers.push("FUNDS_ALREADY_MOVED");
  }
  if ((await anyTx(ctx, "vehicle_escrow", order._id as string)).length > 0) blockers.push("FUNDS_HELD_OR_MOVED");
  if (await unresolvedProviderPayment(ctx, `vehicle:${order._id}`)) blockers.push("PROVIDER_PAYMENT_UNRESOLVED");
  const claims = await ctx.db.query("escrow_payment_claims").withIndex("by_escrowOrderId", (q: any) => q.eq("escrowOrderId", order._id)).take(20);
  if (claims.some((c: any) => c.status !== "REJECTED")) blockers.push("CLAIM_PRESENT");
  const disputes = await ctx.db.query("escrow_disputes").withIndex("by_order", (q: any) => q.eq("escrowOrderId", order._id)).take(1);
  if (disputes.length > 0) blockers.push("DISPUTE");
  const ledger = await ctx.db.query("ledger_transactions").withIndex("by_order", (q: any) => q.eq("escrowOrderId", order._id)).take(1);
  if (ledger.length > 0) blockers.push("LEDGER_ACTIVITY");
  if (await openReversalFor(ctx, order._id as string)) blockers.push("REVERSAL");
  return { eligible: blockers.length === 0, blockers };
}

export async function evaluateContract(ctx: Db, c: any, now: number): Promise<Evaluation> {
  const blockers: string[] = [];
  if (c.currentState !== "CREATED") blockers.push("NOT_AWAITING_PAYMENT");
  if (now - c.createdAt < UNPAID_ORDER_EXPIRY_MS) blockers.push("TOO_RECENT");
  blockers.push(...railBlockers(c));
  if ((c.escrowHeldRemaining ?? 0) > 0 || (c.releasedBeneficiaryAmount ?? 0) > 0 || (c.refundedClientAmount ?? 0) > 0) {
    blockers.push("FUNDS_ALREADY_MOVED");
  }
  if ((await anyTx(ctx, "re_escrow", c._id as string)).length > 0) blockers.push("FUNDS_HELD_OR_MOVED");
  if (await unresolvedProviderPayment(ctx, `re:${c._id}`)) blockers.push("PROVIDER_PAYMENT_UNRESOLVED");
  const claims = await ctx.db.query("escrow_payment_claims").withIndex("by_reContractId", (q: any) => q.eq("reContractId", c._id)).take(20);
  if (claims.some((x: any) => x.status !== "REJECTED")) blockers.push("CLAIM_PRESENT");
  const disputes = await ctx.db.query("re_escrow_disputes").withIndex("by_contract", (q: any) => q.eq("contractId", c._id)).take(1);
  if (disputes.length > 0) blockers.push("DISPUTE");
  const deposits = await ctx.db.query("re_caution_deposits").withIndex("by_contract", (q: any) => q.eq("contractId", c._id)).take(10);
  if (deposits.some((d: any) => d.status !== "LOCKED" || (d.refundedAmount ?? 0) > 0 || (d.deductionClaimAmount ?? 0) > 0)) {
    blockers.push("CAUTION_DEPOSIT_ACTIVE");
  }
  const milestones = await ctx.db.query("re_escrow_milestones").withIndex("by_contract", (q: any) => q.eq("contractId", c._id)).take(20);
  if (milestones.some((m: any) => m.isVerified === true || m.state !== "CREATED")) blockers.push("MILESTONE_ACTIVE");
  if (await openReversalFor(ctx, c._id as string)) blockers.push("REVERSAL");
  return { eligible: blockers.length === 0, blockers };
}

export async function evaluatePass(ctx: Db, p: any, now: number): Promise<Evaluation> {
  const blockers: string[] = [];
  if (p.status !== "CREATED") blockers.push("NOT_AWAITING_PAYMENT");
  if (!(typeof p.otpExpiresAt === "number" && now >= p.otpExpiresAt)) blockers.push("BEFORE_DEADLINE");
  if (p.verifiedAt !== undefined || (p.failedAttempts ?? 0) > 0) blockers.push("PASS_USED");
  if ((await anyTx(ctx, "re_inspection_pass", p._id as string)).length > 0) blockers.push("FUNDS_HELD_OR_MOVED");
  if (await unresolvedProviderPayment(ctx, `pass:${p._id}`)) blockers.push("PROVIDER_PAYMENT_UNRESOLVED");
  if (await openReversalFor(ctx, p._id as string)) blockers.push("REVERSAL");
  return { eligible: blockers.length === 0, blockers };
}

// ─── candidates (bounded) ────────────────────────────────────────────

async function vehicleCandidates(ctx: Db, now: number, window: number) {
  const cutoff = now - UNPAID_ORDER_EXPIRY_MS;
  const out: any[] = [];
  for (const rail of EXPIRABLE_RAILS) {
    out.push(
      ...(await ctx.db
        .query("escrow_orders")
        .withIndex("by_status_rail_createdAt", (q: any) => q.eq("status", "PENDING_PAYMENT").eq("paymentRail", rail).lte("createdAt", cutoff))
        .order("asc")
        .take(window))
    );
  }
  return out.sort((a, b) => a.createdAt - b.createdAt).slice(0, window);
}

async function contractCandidates(ctx: Db, now: number, window: number) {
  const cutoff = now - UNPAID_ORDER_EXPIRY_MS;
  const out: any[] = [];
  for (const rail of EXPIRABLE_RAILS) {
    out.push(
      ...(await ctx.db
        .query("re_escrow_contracts")
        .withIndex("by_state_rail_createdAt", (q: any) => q.eq("currentState", "CREATED").eq("paymentRail", rail).lte("createdAt", cutoff))
        .order("asc")
        .take(window))
    );
  }
  return out.sort((a, b) => a.createdAt - b.createdAt).slice(0, window);
}

async function passCandidates(ctx: Db, now: number, window: number) {
  const rows = await ctx.db.query("re_inspection_passes").withIndex("by_status", (q: any) => q.eq("status", "CREATED")).take(window * 4);
  return rows.filter((p: any) => typeof p.otpExpiresAt === "number" && p.otpExpiresAt <= now).slice(0, window);
}

// ─── the transition ──────────────────────────────────────────────────

const REASON = "unpaid_expired";
const BY = "system_expiry";

async function notify(ctx: Db, userId: any, title: string, body: string, now: number) {
  if (!userId) return;
  await ctx.db.insert("user_notifications", { userId: userId as string, targetType: "single_user", title, body, read: false, createdAt: now });
}

const PAYMENT_NOTE =
  "If you already sent money for it, please contact Vektolux support with your payment reference.";

async function expireVehicle(ctx: Db, order: any, now: number) {
  await ctx.db.patch(order._id, { status: "CANCELLED", cancelledAt: now, cancelReason: REASON, cancelledBy: BY, updatedAt: now });
  await notify(
    ctx, order.renterOrBuyerId, "Unpaid order cancelled",
    `Your order ${order.orderCode} was cancelled because no payment was received within 14 days. ${PAYMENT_NOTE}`, now
  );
  await notify(
    ctx, order.ownerOrSellerId, "Order cancelled",
    `Order ${order.orderCode} was cancelled because the buyer's payment was not received within 14 days.`, now
  );
}

async function expireContract(ctx: Db, c: any, now: number) {
  await ctx.db.patch(c._id, { currentState: "CANCELLED", cancelledAt: now, cancelReason: REASON, cancelledBy: BY, updatedAt: now });
  const deposits = await ctx.db.query("re_caution_deposits").withIndex("by_contract", (q: any) => q.eq("contractId", c._id)).take(10);
  for (const d of deposits) {
    // Nothing was ever deposited: the row is kept for history but no longer claims a held amount.
    await ctx.db.patch(d._id, { status: "VOID", heldAmount: 0, settledAt: now });
  }
  const milestones = await ctx.db.query("re_escrow_milestones").withIndex("by_contract", (q: any) => q.eq("contractId", c._id)).take(20);
  for (const m of milestones) await ctx.db.patch(m._id, { state: "CANCELLED" });
  await notify(
    ctx, c.clientId, "Unpaid contract cancelled",
    `Your escrow contract ${c.contractCode} was cancelled because no payment was received within 14 days. ${PAYMENT_NOTE}`, now
  );
  await notify(
    ctx, c.beneficiaryId, "Contract cancelled",
    `Escrow contract ${c.contractCode} was cancelled because the client's payment was not received within 14 days.`, now
  );
}

async function expirePass(ctx: Db, p: any, now: number) {
  await ctx.db.patch(p._id, { status: "CANCELLED", cancelledAt: now, cancelReason: REASON, cancelledBy: BY });
  await notify(
    ctx, p.clientId, "Unpaid viewing pass cancelled",
    `Your viewing pass was cancelled because it was not paid before the scheduled visit time passed. ${PAYMENT_NOTE}`, now
  );
  await notify(ctx, p.agentId, "Viewing pass cancelled", "A viewing pass was cancelled because it was not paid before the scheduled time.", now);
}

export const expireUnpaidOrders = internalMutation({
  args: { limit: v.optional(v.number()), now: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const now = args.now ?? Date.now();
    const limit = Math.min(Math.max(Math.floor(args.limit ?? DEFAULT_LIMIT), 1), MAX_LIMIT);
    const window = limit * CANDIDATE_WINDOW_FACTOR;
    const result = {
      vehicleOrders: 0,
      contracts: 0,
      passes: 0,
      blocked: {} as Record<string, number>,
    };
    const bump = (codes: string[]) => {
      for (const c of codes) result.blocked[c] = (result.blocked[c] ?? 0) + 1;
    };
    let budget = limit;

    for (const order of await vehicleCandidates(ctx, now, window)) {
      if (budget <= 0) break;
      const e = await evaluateVehicleOrder(ctx, order, now);
      if (!e.eligible) { bump(e.blockers); continue; }
      await expireVehicle(ctx, order, now);
      result.vehicleOrders++;
      budget--;
    }
    for (const c of await contractCandidates(ctx, now, window)) {
      if (budget <= 0) break;
      const e = await evaluateContract(ctx, c, now);
      if (!e.eligible) { bump(e.blockers); continue; }
      await expireContract(ctx, c, now);
      result.contracts++;
      budget--;
    }
    for (const p of await passCandidates(ctx, now, window)) {
      if (budget <= 0) break;
      const e = await evaluatePass(ctx, p, now);
      if (!e.eligible) { bump(e.blockers); continue; }
      await expirePass(ctx, p, now);
      result.passes++;
      budget--;
    }
    return result;
  },
});

// ─── admin dry-run (READ-ONLY) ───────────────────────────────────────

export const adminExpiryDryRun = query({
  args: { sessionToken: v.optional(v.string()), limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    await requireAdmin(ctx, { sessionToken: args.sessionToken });
    const now = Date.now();
    const limit = Math.min(Math.max(Math.floor(args.limit ?? 50), 1), MAX_LIMIT);
    const eligible: Array<{ kind: string; id: string; code: string; ageDays: number }> = [];
    const blocked: Array<{ kind: string; id: string; code: string; ageDays: number; blockers: string[] }> = [];

    const run = async (kind: string, rows: any[], codeOf: (r: any) => string, ageOf: (r: any) => number, evaluate: (r: any) => Promise<Evaluation>) => {
      for (const r of rows) {
        const e = await evaluate(r);
        const base = { kind, id: r._id as string, code: codeOf(r), ageDays: days(now - ageOf(r)) };
        if (e.eligible) eligible.push(base);
        else blocked.push({ ...base, blockers: e.blockers });
      }
    };
    await run("vehicle_order", await vehicleCandidates(ctx, now, limit), (o) => o.orderCode, (o) => o.createdAt, (o) => evaluateVehicleOrder(ctx, o, now));
    await run("re_contract", await contractCandidates(ctx, now, limit), (c) => c.contractCode, (c) => c.createdAt, (c) => evaluateContract(ctx, c, now));
    await run("inspection_pass", await passCandidates(ctx, now, limit), (p) => String(p._id), (p) => p.createdAt, (p) => evaluatePass(ctx, p, now));

    // Orders the batch never considers (bank-transfer rail) are listed separately so admins can review them.
    const bankOrders = await ctx.db
      .query("escrow_orders")
      .withIndex("by_status_rail_createdAt", (q: any) => q.eq("status", "PENDING_PAYMENT").eq("paymentRail", "BANK_TRANSFER").lte("createdAt", now - UNPAID_ORDER_EXPIRY_MS))
      .take(limit);
    const bankContracts = await ctx.db
      .query("re_escrow_contracts")
      .withIndex("by_state_rail_createdAt", (q: any) => q.eq("currentState", "CREATED").eq("paymentRail", "BANK_TRANSFER").lte("createdAt", now - UNPAID_ORDER_EXPIRY_MS))
      .take(limit);

    return {
      now,
      policy: { expiryDays: 14, expirableRails: EXPIRABLE_RAILS, bankTransferExpiresAutomatically: false, passDeadline: "scheduled + 4h" },
      eligible,
      blocked,
      bankTransferAwaitingAdminReview: [
        ...bankOrders.map((o: any) => ({ kind: "vehicle_order", id: o._id as string, code: o.orderCode, ageDays: days(now - o.createdAt) })),
        ...bankContracts.map((c: any) => ({ kind: "re_contract", id: c._id as string, code: c.contractCode, ageDays: days(now - c.createdAt) })),
      ],
    };
  },
});
