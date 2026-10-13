// convex/legacyRentalExposureReport.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — READ-ONLY diagnostic of HISTORICAL vehicle-rental financial exposure.
//
// Vehicle rental is no longer offered (escrow.initiateEscrowOrder and bookings.createBooking refuse
// it), but legacy orders and bookings keep their settlement lifecycle. Before any legacy rental logic
// is considered for retirement, this report shows what is still unresolved. It is INTERNAL (no client
// can call it), writes nothing, returns COUNTS ONLY (no ids, names, contact details, listing content
// or per-record amounts) and is bounded per call.
//
// TABLE SCOPE (explicit): escrow_orders (VEHICLE_RENTAL), bookings (bookingType vehicle_rental) and the
// records linked to them: transactions, escrow_disputes, escrow_payment_claims, payment_reversals,
// vehicle_inspections, vehicleListings. NOT covered: hotel_bookings, re_escrow_contracts,
// re_inspection_passes, wallet-level balances, and any provider-side state.
//
// OPEN CLAIMS ON BOOKINGS: escrow_payment_claims has no booking index, so the per-booking page cannot
// look claims up. legacyRentalClaimsPage walks the open claim statuses (existing by_status index) and
// resolves each claim to its rental order / rental booking, so every open claim on a rental is
// counted there (counts only). Its units are part of the coverage manifest.
//
// COMPLETENESS (stage 1C-6D): a report is complete only after EVERY required order status and booking
// settlement range was traversed to `isDone`. Each page carries `coverage` (the required sets) and the
// internal queries `legacyRentalCoverageManifest` / `legacyRentalCoverageCheck` (and the exported pure
// `assessLegacyRentalCoverage`) report what is still missing. Totals from a partial traversal must not
// be read as totals.
//
// NOT A SNAPSHOT: records and payments can change while a traversal is running. Each order is
// counted once in a completed traversal of STABLE data. Observed (see the 6E-3 tests):
//   * a record that moves FORWARD into a status not yet visited is counted in BOTH buckets;
//   * a record that moves into a status that was ALREADY walked, out of one not yet walked, is seen
//     in NEITHER (omitted);
//   * within one status, a record that leaves the bucket after its page was read stays counted, and
//     later pages no longer contain it.
// The coverage chain proves that every unit was traversed from start to end; it does NOT prove the
// data stood still. Quiet-window runs and a repeat run are the only mitigation. Results are
// diagnostic classifications, never a statement that any person owes money.
//
// CURRENCY (6E): amounts are never added across currency codes. Codes are compared exactly. An order
// whose escrow rows, payout mirror, claim, checkout or reversal carry a different code from the order
// is manual review (`reconciliation=currency_mismatch`, `payout=currency_mismatch`, or a
// `+currency_mismatch` suffix) and contributes NO held amount. Held amounts are reported per exposure
// AND per currency code; `ordersByCurrency` / `bookingsByCurrency` show which codes exist.
//
// COVERAGE CHAINS (6E): a unit is covered only when its collected pages are exactly one chain
// (cursorIn=null ... isDone) with no repeated, stray or stale page. Unknown units, unlabeled pages
// and unknown attested units make a run incomplete. Cursors are opaque and carry no run identifier:
// pages from two different traversals that happen to link would be accepted, so keep one run's
// pages together and never mix runs.
//
// ── LEDGER SEMANTICS (verified in walletCore.ts) ───────────────────────
// Rows of `transactions` with referenceType "vehicle_escrow" and referenceId = <order id>:
//   escrow_lock     buyer, amount = money moved INTO escrow (holdFunds, or a verified external payment)
//   escrow_release  buyer, amount = money moved OUT of escrow (includes the platform fee; the recipient
//                   gets amount - fee). Each release also writes a mirror `payout` row for the recipient
//                   with the same transactionId: payout rows are NOT counted, they would double count.
//   refund          buyer, amount = money returned from escrow to the buyer's available balance
// Reversals of a payout are recorded under referenceType "payment_reversal" (referenceId = the
// reversal id), so they never enter the escrow formula. They are linked through
// payment_reversals.releaseTransactionId (index by_release) and shown as separate evidence.
//
//   held remaining = Σ escrow_lock − Σ escrow_release − Σ refund      (completed rows, buyer-owned)
//
// PAYOUT MIRRORS: every completed release must have its mirror `payout` row (same transactionId code,
// recipient = the order's seller, same amount, net = amount - fee). A missing, mis-addressed or
// mis-sized mirror is reported (`payout=`) and sends the order to manual review: money that left
// escrow but did not demonstrably reach its recipient is never "reconciled".
//
// Order amount fields (split60ReleasedAmount, ...) are NOT used: dispute resolution moves money
// without updating them, so they are not authoritative.
// ═══════════════════════════════════════════════════════════════════════

import { internalQuery } from "./_generated/server";
import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { bookingEscrowSummary } from "./lib/bookingEscrow";
import { classifyVehicleListing, listingLifecycleOf } from "./vehicleClassificationReport";

export const RENTAL_ORDER_STATUSES = [
  "INITIATED",
  "PENDING_PAYMENT",
  "HELD_IN_ESCROW",
  "ESCROW_LOCKED",
  "PARTIALLY_RELEASED",
  "POST_INSPECTION_PENDING",
  "DISPUTED",
  "SETTLED",
  "REFUNDED",
  "CANCELLED",
] as const;
export type RentalOrderStatus = (typeof RENTAL_ORDER_STATUSES)[number];

// Booking settlement ranges of the existing `by_settlement_eligible` index, all five.
export const RENTAL_BOOKING_SOURCES = [
  "settlement:none",
  "settlement:held",
  "settlement:disputed",
  "settlement:released",
  "settlement:refunded",
] as const;

export const SCOPE_ORDERS = "escrow_orders_vehicle_rental_only";
export const SCOPE_BOOKINGS = "bookings_vehicle_rental_only";
export const SCOPE_CLAIMS = "open_payment_claims_vehicle_rental_only";
// Open claim statuses (the repo's own open set: accountDeletion.ts CLAIM_OPEN).
export const RENTAL_CLAIM_STATUSES = ["PENDING_PAYMENT", "PENDING_APPROVAL", "ESCROW_LOCKED"] as const;
export const SCOPE_EXCLUDES = [
  "hotel_bookings",
  "re_escrow_contracts",
  "re_inspection_passes",
  "wallet_level_balances",
  "provider_side_state",
  "transactions_outside_in_scope_references",
  "non_rental_orders_and_bookings",
] as const;

/**
 * What each exclusion means, so a reader of a result cannot take "no finding" for "no exposure".
 * Shown by legacyRentalCoverageManifest. Nothing here is read by any query.
 */
export const SCOPE_EXCLUDES_DETAIL: Record<(typeof SCOPE_EXCLUDES)[number], string> = {
  hotel_bookings: "Hotel and guesthouse bookings live in their own table and are not inspected.",
  re_escrow_contracts: "Real-estate escrow contracts are not inspected; claims that point at a contract are only counted as skipped.",
  re_inspection_passes: "Real-estate inspection passes are not inspected.",
  wallet_level_balances:
    "Wallet balances (available / pending / escrow) are NOT compared with the order and booking ledgers; a wallet can disagree with a balanced order.",
  provider_side_state:
    "Only the platform's own record of provider checkouts and bank-transfer clearing is read. Whether the payment provider or a bank actually moved money (incl. late bank wires) is not queried.",
  transactions_outside_in_scope_references:
    "Money rows are found only under these references: vehicle_escrow:<orderId>, escrow_checkout:vehicle:<orderId>, <bookingType>:<bookingId>, escrow_checkout:booking:<bookingId>. A row recorded under any other reference (an untagged top-up, a manual adjustment) is invisible here. Reversals are found only through an in-scope release row.",
  non_rental_orders_and_bookings:
    "Only orderType VEHICLE_RENTAL orders and bookingType vehicle_rental bookings are walked. Vehicle purchase escrow, inspections and delivery/haulage are deliberately outside this report. Closed claims are seen only through their order; the claims walk covers open statuses.",
};

// An order makes ~8 indexed lookups, so pages are smaller than the listing report's.
export const DEFAULT_PAGE_SIZE = 25;
export const MAX_PAGE_SIZE = 50;
// Per-order lookup cap; a lookup that returns more than this is reported as TRUNCATED, never as complete.
export const PER_ORDER_LOOKUP_CAP = 25;

const OPEN_ORDER_STATUSES = new Set(["INITIATED", "PENDING_PAYMENT", "HELD_IN_ESCROW", "ESCROW_LOCKED", "PARTIALLY_RELEASED", "POST_INSPECTION_PENDING", "DISPUTED"]);
const FUNDS_EXPECTED_STATUSES = new Set(["HELD_IN_ESCROW", "ESCROW_LOCKED", "PARTIALLY_RELEASED", "POST_INSPECTION_PENDING", "DISPUTED", "SETTLED", "REFUNDED"]);
const FUNDS_OPEN_STATUSES = new Set(["HELD_IN_ESCROW", "ESCROW_LOCKED", "PARTIALLY_RELEASED", "POST_INSPECTION_PENDING", "DISPUTED"]);
const UNPAID_STATUSES = new Set(["INITIATED", "PENDING_PAYMENT"]);
const OPEN_CLAIM_STATUSES = new Set(["PENDING_PAYMENT", "PENDING_APPROVAL", "ESCROW_LOCKED"]);
const OPEN_DISPUTE_STATUSES = new Set(["OPENED", "UNDER_REVIEW"]);
const round2 = (n: number) => Math.round(n * 100) / 100;

// ─── per-order reconciliation ─────────────────────────────────────────

export type Reconciliation =
  | "nothing_held" // no funds expected and none recorded (unpaid or cancelled)
  | "balanced" // locks fully released or refunded
  | "held" // verified funds still held in escrow
  | "no_hold_transaction" // the status implies funds, but no verified hold exists
  | "movement_without_lock" // releases or refunds with no hold
  | "lock_amount_mismatch" // the hold differs from the order's gross amount
  | "overdrawn" // released + refunded exceed what was locked
  | "unpaid_with_locks" // an unpaid status, yet money was locked
  | "cancelled_with_locks" // a cancelled order that has holds
  | "ownership_mismatch" // an escrow row belongs to someone other than the order's buyer
  | "nonstandard_transaction_status" // an escrow row is disputed or reversed: not interpretable here
  | "pending_ledger_entries" // an escrow row is still pending: the ledger is not settled
  | "ledger_truncated" // more rows than the lookup cap: cannot be reconciled here
  | "currency_mismatch"; // the order and its escrow rows are not all in ONE currency: sums are meaningless

type Tx = Pick<Doc<"transactions">, "type" | "amount" | "userId" | "status"> & {
  currency?: string;
  escrowStatus?: string;
  transactionId?: string;
  netAmount?: number;
  feeAmount?: number;
  platformFeeAmount?: number;
};

const isEscrowType = (t: Pick<Tx, "type">) => t.type === "escrow_lock" || t.type === "escrow_release" || t.type === "refund";

/**
 * Distinct currency codes on a record and its money rows, compared EXACTLY (no case folding): "sle"
 * and "SLE" are different strings here and are reported, not merged. A missing or empty code counts
 * as its own value ("(none)"), so an unlabeled row can never be silently assumed to match.
 */
export function distinctCurrencies(...codes: Array<string | undefined | null>): string[] {
  return [...new Set(codes.map((c) => (typeof c === "string" && c.length > 0 ? c : "(none)")))].sort();
}

export function reconcileOrder(
  order: Pick<Doc<"escrow_orders">, "status" | "renterOrBuyerId" | "grossEscrowAmount"> & { currency?: string },
  txs: Tx[],
  truncated: boolean
): { result: Reconciliation; held: number; failedRows: number } {
  const failedRows = txs.filter((t) => isEscrowType(t) && t.status === "failed").length;
  const out = (result: Reconciliation, held = 0) => ({ result, held, failedRows });
  if (truncated) return out("ledger_truncated");
  if (txs.some((t) => isEscrowType(t) && (t.status === "disputed" || t.status === "reversed"))) {
    return out("nonstandard_transaction_status");
  }
  // an escrow row that is still pending is NOT ignored: the ledger is not settled
  if (txs.some((t) => isEscrowType(t) && t.status === "pending")) return out("pending_ledger_entries");
  const done = txs.filter((t) => t.status === "completed");
  const escrowRows = done.filter(isEscrowType);
  if (escrowRows.some((t) => String(t.userId) !== String(order.renterOrBuyerId))) return out("ownership_mismatch");
  // Amounts in different currencies must never be added together: any mix is manual review.
  if (distinctCurrencies(order.currency, ...escrowRows.map((t) => t.currency)).length > 1) return out("currency_mismatch");
  const sum = (type: string) => round2(escrowRows.filter((t) => t.type === type).reduce((a, t) => a + t.amount, 0));
  const lock = sum("escrow_lock");
  const release = sum("escrow_release");
  const refund = sum("refund");
  const held = round2(lock - release - refund);

  if (lock === 0 && release === 0 && refund === 0) {
    return out(FUNDS_EXPECTED_STATUSES.has(order.status) ? "no_hold_transaction" : "nothing_held");
  }
  if (lock === 0) return out("movement_without_lock");
  if (UNPAID_STATUSES.has(order.status)) return out("unpaid_with_locks", held);
  if (order.status === "CANCELLED") return out("cancelled_with_locks", held);
  if (round2(lock) !== round2(order.grossEscrowAmount)) return out("lock_amount_mismatch", held);
  if (held < -0.005) return out("overdrawn", held);
  if (held > 0.005) return out("held", held);
  return out("balanced");
}

export type PayoutEvidence =
  | "none_expected" // no completed release, no payout row
  | "complete" // every release has a correct recipient mirror
  | "missing" // a release without its payout mirror
  | "wrong_recipient" // the mirror was paid to someone other than the seller
  | "amount_mismatch" // the mirror's amount differs from the release
  | "net_mismatch" // the mirror's net differs from amount - fee
  | "currency_mismatch" // the mirror is in a different currency from the release
  | "unmatchable" // a release or payout without a transaction code to match on
  | "nonstandard_status" // the mirror is not completed
  | "orphan" // a payout with no matching release
  | "not_evaluated"; // the ledger was truncated or not interpretable

/**
 * Cross-checks each buyer-side `escrow_release` with its recipient mirror `payout` (same
 * transactionId). Worst finding wins: missing > wrong_recipient > currency_mismatch > amount_mismatch > net_mismatch >
 * unmatchable > nonstandard_status > orphan.
 */
export function payoutEvidenceOf(recipientId: unknown, txs: Tx[], interpretable: boolean): PayoutEvidence {
  if (!interpretable) return "not_evaluated";
  const releases = txs.filter((t) => t.type === "escrow_release" && t.status === "completed");
  const payouts = txs.filter((t) => t.type === "payout");
  if (releases.length === 0 && payouts.length === 0) return "none_expected";
  const found = new Set<string>();
  const problems: PayoutEvidence[] = [];
  for (const r of releases) {
    const code = r.transactionId;
    if (!code) { problems.push("unmatchable"); continue; }
    const mirror = payouts.find((p) => p.transactionId === code);
    if (!mirror) { problems.push("missing"); continue; }
    found.add(code);
    if (mirror.status !== "completed") { problems.push("nonstandard_status"); continue; }
    if (String(mirror.userId) !== String(recipientId)) problems.push("wrong_recipient");
    else if (distinctCurrencies(r.currency, mirror.currency).length > 1) problems.push("currency_mismatch");
    else if (round2(mirror.amount) !== round2(r.amount)) problems.push("amount_mismatch");
    else {
      const fee = round2(r.platformFeeAmount ?? r.feeAmount ?? 0);
      if (typeof mirror.netAmount === "number" && round2(mirror.netAmount) !== round2(r.amount - fee)) problems.push("net_mismatch");
    }
  }
  if (payouts.some((p) => !p.transactionId)) problems.push("unmatchable");
  else if (payouts.some((p) => !found.has(p.transactionId as string))) problems.push("orphan");
  const order: PayoutEvidence[] = ["missing", "wrong_recipient", "currency_mismatch", "amount_mismatch", "net_mismatch", "unmatchable", "nonstandard_status", "orphan"];
  for (const k of order) if (problems.includes(k)) return k;
  return "complete";
}

// ─── provider checkout evidence ───────────────────────────────────────

export type CheckoutEvidence = {
  kind: string; // none | pending_unresolved | completed | failed | nonstandard:<statuses>
  unresolved: boolean; // a pending attempt
  nonstandard: boolean; // disputed / reversed / any status the lifecycle does not define
  completed: boolean;
};

export function checkoutEvidenceOf(rows: Array<{ status: string }>): CheckoutEvidence {
  if (rows.length === 0) return { kind: "none", unresolved: false, nonstandard: false, completed: false };
  const known = new Set(["pending", "completed", "failed"]);
  const odd = [...new Set(rows.filter((r) => !known.has(r.status)).map((r) => r.status))].sort();
  const unresolved = rows.some((r) => r.status === "pending");
  const completed = rows.some((r) => r.status === "completed");
  const kind = odd.length
    ? `nonstandard:${odd.join("+")}`
    : unresolved
      ? "pending_unresolved"
      : completed
        ? "completed"
        : "failed";
  return { kind, unresolved, nonstandard: odd.length > 0, completed };
}

// ─── combined per-order exposure ──────────────────────────────────────
//
// PRECEDENCE (first match wins; every order has exactly one exposure):
//   1. manual_review  contradictions and unverifiable evidence: ownership/reference mismatches,
//                     truncated lookups, payout anomalies, nonstandard provider states, any
//                     reconciliation anomaly, open status with nothing held, terminal with funds held,
//                     an open dispute outside DISPUTED, DISPUTED without an open dispute, a completed
//                     checkout that never reached escrow, or any mixed-currency record
//   2. manual_review  (M6) VERIFIED held funds together with an open claim or an unresolved checkout:
//                     possible duplicate payment or duplicate claim against money already in escrow
//      manual_review  (M6b) NO held funds but BOTH an open claim and an unresolved checkout: two
//                     parallel payment routes whose outcome is uncertain
//   3. open_recovery  a payout reversal with an unrecovered shortfall
//   4. disputed_funds verified held funds under a genuine dispute (DISPUTED + open dispute)
//   5. funds_held     verified held funds with nothing else open
//   6. open_claim     an unreviewed claim on an order that holds no funds (unpaid or terminal)
//   7. pending_payment_attempt   an unresolved checkout on an order that holds no funds
//   8. unpaid_fundable           unpaid, nothing in flight
//   9. reconciled_terminal       terminal, balanced, payouts complete, nothing open
// Why this is safe: rule 2 only MOVES orders from funds_held / disputed_funds / open_recovery into
// manual_review (strictly more conservative); it never marks anything resolved. Orders without held
// funds are unaffected, so unpaid and terminal totals do not change. Evidence tallies are untouched
// and additionally count `orders_funded_with_open_claim` / `orders_funded_with_pending_checkout`.
// An unfunded order with only ONE of the two keeps open_claim / pending_payment_attempt.

export type Exposure =
  | "manual_review" // contradictory or unverifiable evidence
  | "open_recovery" // a payout reversal still has an unrecovered shortfall
  | "disputed_funds" // verified held funds under a dispute
  | "funds_held" // verified held funds
  | "open_claim" // an unreviewed payment claim
  | "pending_payment_attempt" // a provider checkout that is not resolved
  | "unpaid_fundable" // unpaid; a payment could still fund it
  | "reconciled_terminal"; // terminal and balanced, with nothing open

export function exposureOf(a: {
  status: string;
  reconciliation: Reconciliation;
  disputeOpen: boolean;
  disputeTruncated: boolean;
  claimOpen: boolean;
  claimTruncated: boolean;
  checkoutUnresolved: boolean;
  checkoutTruncated: boolean;
  recoveryOpen: boolean;
  recoveryTruncated: boolean;
  mismatchFlag: boolean; // any dispute/claim/recovery ownership or reference contradiction
  payout?: PayoutEvidence;
  checkoutNonstandard?: boolean;
  checkoutCompleted?: boolean;
}): Exposure {
  const rec = a.reconciliation;
  const funded = FUNDS_OPEN_STATUSES.has(a.status);
  // contradictions first (never hidden behind a terminal status)
  if (a.mismatchFlag || a.disputeTruncated || a.claimTruncated || a.checkoutTruncated || a.recoveryTruncated) return "manual_review";
  // money that left escrow but did not demonstrably reach its recipient is never reconciled
  const payout = a.payout ?? "none_expected";
  if (payout !== "none_expected" && payout !== "complete" && payout !== "not_evaluated") return "manual_review";
  // a provider payment in a disputed / reversed / undefined state is not "failed" and not "resolved"
  if (a.checkoutNonstandard) return "manual_review";
  // a completed provider payment that never reached escrow must be explained (wallet credit?)
  if (a.checkoutCompleted && (rec === "nothing_held" || rec === "no_hold_transaction")) return "manual_review";
  if (
    rec === "no_hold_transaction" || rec === "movement_without_lock" || rec === "lock_amount_mismatch" || rec === "overdrawn" ||
    rec === "unpaid_with_locks" || rec === "cancelled_with_locks" || rec === "ownership_mismatch" || rec === "ledger_truncated" ||
    rec === "nonstandard_transaction_status" || rec === "pending_ledger_entries" || rec === "currency_mismatch"
  ) return "manual_review";
  if (funded && (rec === "balanced" || rec === "nothing_held")) return "manual_review"; // open status, nothing held
  if ((a.status === "SETTLED" || a.status === "REFUNDED") && rec === "held") return "manual_review"; // terminal but funds held
  // an open dispute must coincide with a DISPUTED order: on any other status the two contradict
  if (a.disputeOpen && a.status !== "DISPUTED") return "manual_review";
  if (a.status === "DISPUTED" && !a.disputeOpen) return "manual_review"; // disputed status without an open dispute

  // M6: verified held funds PLUS an unresolved payment route (an open claim, or a provider checkout
  // that is still pending) is not a clean "funds held": it can mean a duplicate payment or a duplicate
  // claim against money that is already in escrow. It is surfaced as manual review, before the
  // funds-held / disputed-funds / open-recovery labels could present the order as understood.
  if (rec === "held" && (a.claimOpen || a.checkoutUnresolved)) return "manual_review";

  // Two parallel unresolved payment routes (an open claim AND a pending checkout) on an order that
  // holds no verified funds: either can still fund or credit it, so the outcome is uncertain.
  if (rec !== "held" && a.claimOpen && a.checkoutUnresolved) return "manual_review";

  if (a.recoveryOpen) return "open_recovery";
  if (rec === "held" && (a.status === "DISPUTED" || a.disputeOpen)) return "disputed_funds";
  if (rec === "held") return "funds_held";
  if (a.claimOpen) return "open_claim";
  if (a.checkoutUnresolved) return "pending_payment_attempt";
  if (UNPAID_STATUSES.has(a.status)) return "unpaid_fundable";
  if ((a.status === "SETTLED" || a.status === "REFUNDED") && rec === "balanced") return "reconciled_terminal";
  if (a.status === "CANCELLED" && rec === "nothing_held") return "reconciled_terminal";
  return "manual_review";
}

// ─── queries ──────────────────────────────────────────────────────────

function clampPage(n: number | undefined): number {
  const requested = Math.floor(n ?? DEFAULT_PAGE_SIZE);
  return Math.max(1, Math.min(Number.isFinite(requested) ? requested : DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE));
}

const scopeOf = (label: string, tables: string[]) => ({ scopeLabel: label, tables, excludes: [...SCOPE_EXCLUDES] });

/**
 * One page of legacy VEHICLE_RENTAL orders of ONE status (all ten statuses must be visited; terminal
 * ones too, because a terminal-looking order can still have open evidence). Each order yields ONE
 * combined key; related evidence is also summarised separately in `evidence` (these are counts of
 * ORDERS having the evidence, not sums of related rows, and must not be added to the totals).
 */
export const legacyRentalOrdersPage = internalQuery({
  args: {
    status: v.string(),
    cursor: v.optional(v.union(v.string(), v.null())),
    numItems: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    if (!(RENTAL_ORDER_STATUSES as readonly string[]).includes(args.status)) throw new Error("Not a rental order status.");
    const numItems = clampPage(args.numItems);
    const page = await ctx.db
      .query("escrow_orders")
      .withIndex("by_type_status", (q) => q.eq("orderType", "VEHICLE_RENTAL").eq("status", args.status as RentalOrderStatus))
      .paginate({ cursor: args.cursor ?? null, numItems });

    const CAP = PER_ORDER_LOOKUP_CAP;
    const counts: Record<string, number> = {};
    const exposureTotals: Record<string, number> = {};
    // verified held amount per exposure AND per currency: amounts of different currencies are never summed
    const heldByExposure: Record<string, Record<string, number>> = {};
    const currencyTally: Record<string, number> = {};
    const evidence: Record<string, number> = {};
    const bump = (m: Record<string, number>, k: string, n = 1) => { m[k] = (m[k] ?? 0) + n; };

    for (const o of page.page) {
      const id = o._id as string;

      // 1. escrow money rows (+ payout mirrors are fetched but never counted)
      const txs = await ctx.db
        .query("transactions")
        .withIndex("by_reference", (q) => q.eq("referenceType", "vehicle_escrow").eq("referenceId", id))
        .take(CAP + 1);
      const ledgerTruncated = txs.length > CAP;
      const ledgerRows = txs.slice(0, CAP);
      const rec = reconcileOrder(o, ledgerRows, ledgerTruncated);
      const interpretable = !ledgerTruncated &&
        rec.result !== "nonstandard_transaction_status" && rec.result !== "pending_ledger_entries" && rec.result !== "ownership_mismatch" &&
        rec.result !== "currency_mismatch";
      const payout = payoutEvidenceOf(o.ownerOrSellerId, ledgerRows, interpretable);

      // 2. disputes
      const disputes = await ctx.db.query("escrow_disputes").withIndex("by_order", (q) => q.eq("escrowOrderId", o._id)).take(CAP + 1);
      const disputeTruncated = disputes.length > CAP;
      const disputeOpen = disputes.some((d) => OPEN_DISPUTE_STATUSES.has(d.status));
      const disputeKind = disputes.length === 0 ? "none" : disputeOpen ? "open" : "resolved";

      // 3. payment claims
      const claims = await ctx.db.query("escrow_payment_claims").withIndex("by_escrowOrderId", (q) => q.eq("escrowOrderId", o._id)).take(CAP + 1);
      const claimTruncated = claims.length > CAP;
      const claimOpen = claims.some((c) => OPEN_CLAIM_STATUSES.has(c.status));
      const claimOwnerMismatch = claims.some((c) => String(c.userId) !== String(o.renterOrBuyerId));
      const claimKind = claims.length === 0 ? "none" : claimOpen ? "open" : "closed";

      // 4. provider checkouts for this order (tag "vehicle:<orderId>")
      const checkouts = await ctx.db
        .query("transactions")
        .withIndex("by_reference", (q) => q.eq("referenceType", "escrow_checkout").eq("referenceId", `vehicle:${id}`))
        .take(CAP + 1);
      const checkoutTruncated = checkouts.length > CAP;
      const ckEvidence = checkoutEvidenceOf(checkouts.slice(0, CAP));
      const checkoutUnresolved = ckEvidence.unresolved;
      const checkoutKind = ckEvidence.kind;
      const checkoutOwnerMismatch = checkouts.some((t) => String(t.userId) !== String(o.renterOrBuyerId));
      const checkoutCurrencyMismatch = checkouts.slice(0, CAP).some((t) => distinctCurrencies(o.currency, t.currency).length > 1);

      // 5. payout reversals, linked through each buyer-side release row (index by_release)
      let recoveryOpen = false;
      let recoveryAny = false;
      let recoveryRefMismatch = false;
      let recoveryCurrencyMismatch = false;
      const recoveryTruncated = false;
      for (const t of txs.slice(0, CAP).filter((x) => x.type === "escrow_release" && x.status === "completed")) {
        const reversals = await ctx.db.query("payment_reversals").withIndex("by_release", (q) => q.eq("releaseTransactionId", t._id)).take(3);
        for (const r of reversals) {
          recoveryAny = true;
          if (r.status === "pending_recovery") recoveryOpen = true;
          if (r.referenceType !== "vehicle_escrow" || r.referenceId !== id) recoveryRefMismatch = true;
          if (distinctCurrencies(o.currency, r.currency).length > 1) recoveryCurrencyMismatch = true;
        }
      }
      const recoveryKind = recoveryOpen ? "open" : recoveryAny ? "closed" : "none";

      // 6. pre-trip inspection evidence (required before the 60% handoff release)
      const preTrip = await ctx.db
        .query("vehicle_inspections")
        .withIndex("by_order_type", (q) => q.eq("escrowOrderId", o._id).eq("inspectionType", "PRE_TRIP_RENTAL"))
        .first();
      const preTripKind = preTrip ? "present" : "absent";

      // 7. the listing, as it is now
      const listing = await ctx.db.get(o.vehicleListingId);
      const listingKind = listing ? `${classifyVehicleListing(listing)}:${listingLifecycleOf(listing)}` : "missing";

      const claimCurrencyMismatch = claims.slice(0, CAP).some((c) => distinctCurrencies(o.currency, c.currency).length > 1);
      const mismatchFlag = claimOwnerMismatch || checkoutOwnerMismatch || recoveryRefMismatch ||
        claimCurrencyMismatch || checkoutCurrencyMismatch || recoveryCurrencyMismatch;
      const exposure = exposureOf({
        status: o.status,
        reconciliation: rec.result,
        disputeOpen,
        disputeTruncated,
        claimOpen,
        claimTruncated,
        checkoutUnresolved,
        checkoutTruncated,
        recoveryOpen,
        recoveryTruncated,
        mismatchFlag,
        payout,
        checkoutNonstandard: ckEvidence.nonstandard,
        checkoutCompleted: ckEvidence.completed,
      });

      const rail = o.paymentRail ?? "none";
      const bankPending = o.bankClearingStatus === "PENDING_TRANSFER" && UNPAID_STATUSES.has(o.status) ? "bank_pending" : "no";
      const key = [
        `scope=${SCOPE_ORDERS}`,
        `exposure=${exposure}`,
        `status=${o.status}`,
        `rail=${rail}`,
        `bank=${bankPending}`,
        `reconciliation=${rec.result}`,
        `currency=${distinctCurrencies(o.currency).join("+")}`,
        `payout=${payout}`,
        `ledgerNotes=${rec.failedRows > 0 ? "failed_rows_ignored" : "none"}`,
        `dispute=${disputeKind}${disputeTruncated ? "+truncated" : ""}`,
        `claim=${claimKind}${claimTruncated ? "+truncated" : ""}${claimOwnerMismatch ? "+owner_mismatch" : ""}${claimCurrencyMismatch ? "+currency_mismatch" : ""}`,
        `checkout=${checkoutKind}${checkoutTruncated ? "+truncated" : ""}${checkoutOwnerMismatch ? "+owner_mismatch" : ""}${checkoutCurrencyMismatch ? "+currency_mismatch" : ""}`,
        `recovery=${recoveryKind}${recoveryRefMismatch ? "+reference_mismatch" : ""}${recoveryCurrencyMismatch ? "+currency_mismatch" : ""}`,
        `preTrip=${preTripKind}`,
        `listing=${listingKind}`,
      ].join("|");
      bump(counts, key);
      bump(exposureTotals, exposure);
      bump(currencyTally, distinctCurrencies(o.currency)[0]);
      if (rec.held > 0) {
        const cur = distinctCurrencies(o.currency)[0];
        heldByExposure[exposure] = heldByExposure[exposure] ?? {};
        heldByExposure[exposure][cur] = (heldByExposure[exposure][cur] ?? 0) + rec.held;
      }
      if (rec.result === "currency_mismatch" || claimCurrencyMismatch || checkoutCurrencyMismatch || recoveryCurrencyMismatch || payout === "currency_mismatch") {
        bump(evidence, "orders_with_currency_mismatch");
      }
      // separate evidence tallies: orders HAVING each kind of evidence (not additive)
      if (disputeOpen) bump(evidence, "orders_with_open_dispute");
      if (claimOpen) bump(evidence, "orders_with_open_claim");
      if (checkoutUnresolved) bump(evidence, "orders_with_unresolved_checkout");
      if (recoveryOpen) bump(evidence, "orders_with_open_recovery");
      if (rec.result === "held") bump(evidence, "orders_with_verified_held_funds");
      if (rec.result === "held" && claimOpen) bump(evidence, "orders_funded_with_open_claim");
      if (rec.result === "held" && checkoutUnresolved) bump(evidence, "orders_funded_with_pending_checkout");
      if (OPEN_ORDER_STATUSES.has(o.status) && preTripKind === "absent") bump(evidence, "open_orders_without_pre_trip_inspection");
      if (!listing) bump(evidence, "orders_with_missing_listing");
      if (payout !== "none_expected" && payout !== "complete" && payout !== "not_evaluated") bump(evidence, "orders_with_payout_anomaly");
      if (ckEvidence.nonstandard) bump(evidence, "orders_with_nonstandard_checkout");
      if (rec.result === "pending_ledger_entries") bump(evidence, "orders_with_pending_ledger_entries");
      if (rec.failedRows > 0) bump(evidence, "orders_with_failed_ledger_rows_ignored");
      // orders whose held amount is NOT verified: the held-amount aggregate excludes them
      if (rec.result !== "held" && rec.result !== "balanced" && rec.result !== "nothing_held") bump(evidence, "orders_with_unverifiable_amount");
    }
    return {
      scope: scopeOf(SCOPE_ORDERS, ["escrow_orders", "transactions", "escrow_disputes", "escrow_payment_claims", "payment_reversals", "vehicle_inspections", "vehicleListings"]),
      status: args.status,
      scanned: page.page.length,
      counts,
      exposureTotals,
      // aggregate amount still held, per exposure and then per currency code (an aggregate, not a
      // per-record amount). Never add figures from different currency codes together.
      heldAmountByExposure: Object.fromEntries(
        Object.entries(heldByExposure).map(([k, byCur]) => [k, Object.fromEntries(Object.entries(byCur).map(([c, n]) => [c, round2(n)]))])
      ),
      // number of scanned orders per declared order currency ("(none)" when unlabeled)
      ordersByCurrency: currencyTally,
      // The aggregate counts VERIFIED held funds only. Orders counted in
      // evidence.orders_with_unverifiable_amount may hold money that is not included.
      heldAmountScope: "verified_held_only" as const,
      evidence,
      coverage: coverageOf("orders", args.status),
      cursorIn: args.cursor ?? null,
      isDone: page.isDone,
      continueCursor: page.continueCursor,
    };
  },
});

/**
 * One page of vehicle_rental BOOKINGS from ONE settlement range of the existing
 * `by_settlement_eligible` index (none / held / disputed / released / refunded). The ranges are
 * disjoint, so a booking is counted once in a completed traversal. Non-rental bookings in the range
 * are skipped and only tallied as `skippedOtherTypes`.
 *
 * Money is verified from the transactions recorded under (referenceType = the booking type,
 * referenceId = the booking id), the same reference the booking escrow lock writes, and from the
 * escrow id's own transaction (bookingEscrowSummary).
 */
export const legacyRentalBookingsPage = internalQuery({
  args: {
    source: v.string(),
    cursor: v.optional(v.union(v.string(), v.null())),
    numItems: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    if (!(RENTAL_BOOKING_SOURCES as readonly string[]).includes(args.source)) throw new Error("Not a booking settlement source.");
    const numItems = clampPage(args.numItems);
    const value = args.source.split(":")[1] as "none" | "held" | "disputed" | "released" | "refunded";
    const page = await ctx.db
      .query("bookings")
      .withIndex("by_settlement_eligible", (q) => q.eq("settlementStatus", value === "none" ? undefined : value))
      .paginate({ cursor: args.cursor ?? null, numItems });

    const CAP = PER_ORDER_LOOKUP_CAP;
    const counts: Record<string, number> = {};
    const evidence: Record<string, number> = {};
    const currencyTally: Record<string, number> = {};
    let skippedOtherTypes = 0;
    let rentalBookings = 0;
    const bump = (m: Record<string, number>, k: string) => { m[k] = (m[k] ?? 0) + 1; };

    for (const b of page.page) {
      if (b.bookingType !== "vehicle_rental") { skippedOtherTypes++; continue; }
      rentalBookings++;

      // money recorded under the booking's own reference
      const rows = await ctx.db
        .query("transactions")
        .withIndex("by_reference", (q) => q.eq("referenceType", "vehicle_rental").eq("referenceId", b._id as string))
        .take(CAP + 1);
      const truncated = rows.length > CAP;
      const ledgerRows = rows.slice(0, CAP);
      const isEsc = (t: { type: string }) => t.type === "escrow_lock" || t.type === "escrow_release" || t.type === "refund";
      const pendingRows = ledgerRows.some((t) => isEsc(t) && t.status === "pending");
      const oddRows = ledgerRows.some((t) => isEsc(t) && (t.status === "disputed" || t.status === "reversed"));
      const done = ledgerRows.filter((t) => t.status === "completed");
      const owned = done.filter(isEsc);
      const foreign = owned.some((t) => String(t.userId) !== String(b.buyerId));
      // the booking and every escrow money row must share ONE currency, or the sums mean nothing
      const mixedCurrency = distinctCurrencies(b.currency, ...owned.map((t) => t.currency)).length > 1;
      const sum = (type: string) => round2(owned.filter((t) => t.type === type).reduce((a, t) => a + t.amount, 0));
      const lock = sum("escrow_lock");
      const held = round2(lock - sum("escrow_release") - sum("refund"));
      const ledger = truncated
        ? "truncated"
        : oddRows
          ? "nonstandard_status"
          : pendingRows
            ? "pending_entries"
            : foreign
              ? "ownership_mismatch"
              : mixedCurrency
                ? "currency_mismatch"
                : lock === 0 && owned.length === 0
                ? "no_escrow_rows"
                : lock === 0
                  ? "movement_without_lock"
                  : held < -0.005
                    ? "overdrawn"
                    : held > 0.005
                      ? "locked_remaining"
                      : "balanced";
      // every release must have reached the vendor (same check as for orders)
      const payout = payoutEvidenceOf(
        b.vendorId,
        ledgerRows as unknown as Tx[],
        !truncated && !oddRows && !pendingRows && !foreign && !mixedCurrency
      );

      // the escrow id's own transaction (same verification the booking report uses)
      let escrowId = "none";
      if (b.escrowId) {
        const s = await bookingEscrowSummary(ctx, b);
        escrowId = !s ? "invalid" : s.escrowStatus === "locked" ? "locked" : s.escrowStatus === "released" || s.escrowStatus === "refunded" ? `closed:${s.escrowStatus}` : "unrecorded";
      }

      const checkouts = await ctx.db
        .query("transactions")
        .withIndex("by_reference", (q) => q.eq("referenceType", "escrow_checkout").eq("referenceId", `booking:${b._id}`))
        .take(CAP + 1);
      const ck = checkoutEvidenceOf(checkouts.slice(0, CAP));
      const checkout = checkouts.length > CAP ? "truncated" : ck.kind;

      // contradictions between the booking's status, its settlement record and the money
      const s = b.settlementStatus;
      const paid = b.paymentStatus === "completed" && b.totalAmount > 0;
      const contradictions: string[] = [];
      if (s === "released" && b.status !== "completed") contradictions.push("released_status_not_completed");
      if (s === "refunded" && b.status !== "cancelled") contradictions.push("refunded_status_not_cancelled");
      if ((s === "released" || s === "refunded") && (ledger === "locked_remaining" || escrowId === "locked")) contradictions.push("settled_but_escrow_locked");
      if (s === "held" && (b.status === "completed" || b.status === "cancelled" || b.status === "declined")) contradictions.push("held_under_terminal_status");
      if (s === "disputed" && b.status !== "disputed") contradictions.push("disputed_status_differs");
      if ((s === "held" || s === "disputed") && ledger === "balanced") contradictions.push("held_but_ledger_balanced");
      if ((s === "held" || s === "disputed") && ledger === "no_escrow_rows") contradictions.push("held_without_escrow_rows");
      if (!s && paid && ledger === "locked_remaining") contradictions.push("locked_without_settlement_record");
      if (!s && paid && ledger === "no_escrow_rows" && escrowId === "none") contradictions.push("paid_without_escrow_evidence");
      // an escrow id that does not resolve to a valid lock for this booking, or whose state is not
      // recorded, is NOT reliable settlement evidence (M1)
      if (b.escrowId && escrowId === "invalid" && (paid || s === "held" || s === "disputed" || s === "released" || s === "refunded")) {
        contradictions.push("escrow_id_invalid");
      }
      if (b.escrowId && escrowId === "unrecorded" && (paid || s === "held" || s === "disputed")) contradictions.push("escrow_state_unrecorded");
      // an escrow id on a booking that is not paid and has no settlement record
      if (b.escrowId && !paid && !s && b.totalAmount > 0) contradictions.push("escrow_id_on_unpaid_booking");
      if (!s && paid && escrowId === "locked") contradictions.push("escrow_locked_without_settlement_record");
      if (ledger === "ownership_mismatch" || ledger === "truncated" || ledger === "currency_mismatch") contradictions.push(`ledger_${ledger}`);
      // a provider checkout in another currency than the booking
      if (checkouts.slice(0, CAP).some((t) => distinctCurrencies(b.currency, t.currency).length > 1)) contradictions.push("checkout_currency_mismatch");
      if (ledger === "pending_entries") contradictions.push("pending_ledger_entries");
      if (ledger === "nonstandard_status") contradictions.push("nonstandard_ledger_status");
      if (payout !== "none_expected" && payout !== "complete" && payout !== "not_evaluated") contradictions.push(`payout_${payout}`);
      if (ck.nonstandard) contradictions.push("nonstandard_checkout_status");
      // money held in escrow AND a provider checkout still pending: a possible duplicate payment
      if (ck.unresolved && (s === "held" || s === "disputed" || ledger === "locked_remaining" || escrowId === "locked")) {
        contradictions.push("funded_with_pending_checkout");
      }
      if (ck.completed && !s && paid === false && b.totalAmount > 0) contradictions.push("completed_checkout_booking_unpaid");

      const key = [
        `scope=${SCOPE_BOOKINGS}`,
        `settlement=${s ?? "none"}`,
        `status=${b.status}`,
        `payment=${b.paymentStatus}`,
        `free=${b.totalAmount === 0 ? "yes" : "no"}`,
        `escrowId=${escrowId}`,
        `ledger=${ledger}`,
        `payout=${payout}`,
        `checkout=${checkout}`,
        `contradictions=${contradictions.length ? contradictions.sort().join("+") : "none"}`,
      ].join("|");
      bump(counts, key);
      if (contradictions.length) bump(evidence, "rental_bookings_with_contradictions");
      if (ck.unresolved) bump(evidence, "rental_bookings_with_unresolved_checkout");
      if (contradictions.includes("funded_with_pending_checkout")) bump(evidence, "rental_bookings_funded_with_pending_checkout");
      if (ledger === "locked_remaining" || escrowId === "locked") bump(evidence, "rental_bookings_with_escrow_still_locked");
      if (contradictions.some((c) => c.includes("currency_mismatch"))) bump(evidence, "rental_bookings_with_currency_mismatch");
      const cur = distinctCurrencies(b.currency)[0];
      currencyTally[cur] = (currencyTally[cur] ?? 0) + 1;
    }
    return {
      scope: scopeOf(SCOPE_BOOKINGS, ["bookings", "transactions"]),
      source: args.source,
      scanned: page.page.length,
      rentalBookings,
      skippedOtherTypes,
      counts,
      evidence,
      // rental bookings per declared booking currency ("(none)" when unlabeled); no amounts are summed here
      bookingsByCurrency: currencyTally,
      coverage: coverageOf("bookings", args.source),
      cursorIn: args.cursor ?? null,
      isDone: page.isDone,
      continueCursor: page.continueCursor,
    };
  },
});

/**
 * OPEN payment claims (escrow_payment_claims in PENDING_PAYMENT / PENDING_APPROVAL / ESCROW_LOCKED)
 * that point at a vehicle RENTAL order or a vehicle_rental BOOKING. The table has no booking index,
 * so claims are walked by status (existing `by_status` index, bounded by open claims) and each is
 * resolved to its target. This is how open claims on BOOKINGS become visible (the per-booking page
 * cannot look them up). Counts only: no ids, references, amounts or names.
 */
export const legacyRentalClaimsPage = internalQuery({
  args: {
    status: v.string(),
    cursor: v.optional(v.union(v.string(), v.null())),
    numItems: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    if (!(RENTAL_CLAIM_STATUSES as readonly string[]).includes(args.status)) throw new Error("Not an open claim status.");
    const numItems = clampPage(args.numItems);
    const page = await ctx.db
      .query("escrow_payment_claims")
      .withIndex("by_status", (q) => q.eq("status", args.status as (typeof RENTAL_CLAIM_STATUSES)[number]))
      .paginate({ cursor: args.cursor ?? null, numItems });

    const counts: Record<string, number> = {};
    let skippedOtherTargets = 0;
    let rentalClaims = 0;
    for (const c of page.page) {
      let target = "";
      let detail = "";
      if (c.escrowOrderId) {
        const o = await ctx.db.get(c.escrowOrderId);
        if (!o) { target = "order_missing"; }
        else if (o.orderType !== "VEHICLE_RENTAL") { skippedOtherTargets++; continue; }
        else {
          target = "rental_order";
          detail = `orderStatus=${o.status}|funded=${FUNDS_OPEN_STATUSES.has(o.status) ? "yes" : "no"}|currency=${distinctCurrencies(o.currency, c.currency).length > 1 ? "mismatch" : "match"}`;
        }
      } else if (c.bookingId) {
        const id = ctx.db.normalizeId("bookings", c.bookingId);
        const b = id ? await ctx.db.get(id) : null;
        if (!b) { target = "booking_missing"; }
        else if (b.bookingType !== "vehicle_rental") { skippedOtherTargets++; continue; }
        else {
          target = "rental_booking";
          const funded = b.settlementStatus === "held" || b.settlementStatus === "disputed" ? "yes" : "no";
          detail = `bookingStatus=${b.status}|settlement=${b.settlementStatus ?? "none"}|funded=${funded}|currency=${distinctCurrencies(b.currency, c.currency).length > 1 ? "mismatch" : "match"}`;
        }
      } else {
        skippedOtherTargets++; // a real-estate contract claim or an unlinked claim: not a vehicle rental
        continue;
      }
      rentalClaims++;
      const key = [`scope=${SCOPE_CLAIMS}`, `claimStatus=${c.status}`, `target=${target}`, detail].filter(Boolean).join("|");
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return {
      scope: scopeOf(SCOPE_CLAIMS, ["escrow_payment_claims", "escrow_orders", "bookings"]),
      status: args.status,
      scanned: page.page.length,
      rentalClaims,
      skippedOtherTargets,
      counts,
      coverage: coverageOf("claims", args.status),
      cursorIn: args.cursor ?? null,
      isDone: page.isDone,
      continueCursor: page.continueCursor,
    };
  },
});

// ─── scan-completeness manifest (H2) ──────────────────────────────────

export const COVERAGE_REQUIRED = {
  orders: [...RENTAL_ORDER_STATUSES] as string[],
  bookings: [...RENTAL_BOOKING_SOURCES] as string[],
  claims: [...RENTAL_CLAIM_STATUSES] as string[],
};

/** Embedded in every page: what a COMPLETE report requires, and which unit this call covered. */
function coverageOf(kind: "orders" | "bookings" | "claims", unit: string) {
  return {
    kind,
    unit,
    required: COVERAGE_REQUIRED[kind],
    rule:
      "Totals are complete only after EVERY required unit of EVERY kind was traversed until isDone=true. " +
      "Use legacyRentalCoverageCheck with the units you finished to see what is missing.",
  };
}

/**
 * Pure completeness assessment over collected page responses. A unit counts as covered only when its
 * pages form an UNBROKEN chain: a page that started from the beginning (cursorIn = null), each next
 * page starting at the previous page's continueCursor, ending with a page that reported isDone. A
 * lone final page, or a chain with a gap, leaves the unit missing.
 */
export function assessLegacyRentalCoverage(
  pages: Array<{
    coverage?: { kind: string; unit: string };
    isDone?: boolean;
    cursorIn?: string | null;
    continueCursor?: string;
  }>
): {
  complete: boolean;
  missingOrders: string[];
  missingBookings: string[];
  missingClaims: string[];
  /** pages whose kind or unit is not one this report defines: the collection is not what was asked for */
  unknownUnits: string[];
  /** units whose collected pages repeat a cursor or include a page outside the one chain */
  inconsistentUnits: string[];
  /** pages with no usable coverage label at all: they cannot be attributed to any unit */
  unattributablePages: number;
} {
  const byUnit = new Map<string, typeof pages>();
  const unknownUnits = new Set<string>();
  let unattributablePages = 0;
  for (const p of pages) {
    const c = p.coverage;
    if (!c || typeof c.kind !== "string" || typeof c.unit !== "string") { unattributablePages++; continue; }
    const required = (COVERAGE_REQUIRED as Record<string, string[]>)[c.kind];
    if (!required || !required.includes(c.unit)) { unknownUnits.add(`${c.kind}:${c.unit}`); continue; }
    const key = `${c.kind}:${c.unit}`;
    byUnit.set(key, [...(byUnit.get(key) ?? []), p]);
  }
  // A unit is covered only when its collected pages are EXACTLY one unbroken chain: the first page has
  // cursorIn === null (a missing cursorIn is not a start), every next page begins at the previous
  // page's continueCursor, the last page reports isDone === true, and NO collected page of that unit
  // lies outside the chain (a repeated cursor, a stray or stale page, or a looping chain is a
  // collection that cannot be summed safely, so it is refused and listed in `inconsistentUnits`).
  const inconsistentUnits = new Set<string>();
  const covered = (kind: "orders" | "bookings" | "claims", unit: string): boolean => {
    const list = byUnit.get(`${kind}:${unit}`) ?? [];
    const starts = list.filter((p) => p.cursorIn === null);
    if (starts.length === 0) return false;
    let page: (typeof list)[number] | undefined = starts[0];
    const visited = new Set<(typeof list)[number]>();
    let done = false;
    while (page && !visited.has(page)) {
      visited.add(page);
      if (page.isDone === true) { done = true; break; }
      const next: string | undefined = page.continueCursor;
      page = next ? list.find((p) => p.cursorIn === next) : undefined;
    }
    if (done && visited.size !== list.length) { inconsistentUnits.add(`${kind}:${unit}`); return false; }
    return done;
  };
  const missingOrders = COVERAGE_REQUIRED.orders.filter((u) => !covered("orders", u));
  const missingBookings = COVERAGE_REQUIRED.bookings.filter((u) => !covered("bookings", u));
  const missingClaims = COVERAGE_REQUIRED.claims.filter((u) => !covered("claims", u));
  return {
    // an unknown unit or an unattributable page means the collection is not the report that was asked
    // for, so it can never read as complete, even when every required unit is also present
    complete:
      missingOrders.length === 0 && missingBookings.length === 0 && missingClaims.length === 0 &&
      unknownUnits.size === 0 && unattributablePages === 0,
    missingOrders,
    missingBookings,
    missingClaims,
    unknownUnits: [...unknownUnits].sort(),
    inconsistentUnits: [...inconsistentUnits].sort(),
    unattributablePages,
  };
}

/** The exact units a complete legacy-rental report must traverse (no data is read). */
export const legacyRentalCoverageManifest = internalQuery({
  args: {},
  handler: async () => ({
    required: COVERAGE_REQUIRED,
    scope: { orders: SCOPE_ORDERS, bookings: SCOPE_BOOKINGS, claims: SCOPE_CLAIMS, excludes: [...SCOPE_EXCLUDES], excludesDetail: SCOPE_EXCLUDES_DETAIL },
    pageSizes: { default: DEFAULT_PAGE_SIZE, max: MAX_PAGE_SIZE },
    instruction:
      "Call legacyRentalOrdersPage once per required order status, legacyRentalBookingsPage once per " +
      "required booking source and legacyRentalClaimsPage once per required claim status, following " +
      "continueCursor until isDone=true for each. Not a transactional snapshot.",
  }),
});

/** Which required units are still missing, given the units the operator finished (isDone=true). */
export const legacyRentalCoverageCheck = internalQuery({
  args: { ordersCompleted: v.array(v.string()), bookingsCompleted: v.array(v.string()), claimsCompleted: v.array(v.string()) },
  handler: async (_ctx, args) => {
    const o = new Set(args.ordersCompleted);
    const b = new Set(args.bookingsCompleted);
    const c = new Set(args.claimsCompleted);
    const missingOrders = COVERAGE_REQUIRED.orders.filter((u) => !o.has(u));
    const missingBookings = COVERAGE_REQUIRED.bookings.filter((u) => !b.has(u));
    const missingClaims = COVERAGE_REQUIRED.claims.filter((u) => !c.has(u));
    const unknown = [
      ...args.ordersCompleted.filter((u) => !COVERAGE_REQUIRED.orders.includes(u)),
      ...args.bookingsCompleted.filter((u) => !COVERAGE_REQUIRED.bookings.includes(u)),
      ...args.claimsCompleted.filter((u) => !COVERAGE_REQUIRED.claims.includes(u)),
    ];
    return {
      // unknown units invalidate the attestation: the operator did not report on this report's units
      complete: missingOrders.length === 0 && missingBookings.length === 0 && missingClaims.length === 0 && unknown.length === 0,
      missingOrders,
      missingBookings,
      missingClaims,
      unknownUnits: unknown,
    };
  },
});

export type { Id };
