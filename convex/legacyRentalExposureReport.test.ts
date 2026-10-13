/// <reference types="vite/client" />
// Stage 1C-6C: the legacy vehicle-rental exposure diagnostic. Synthetic records only. Every expected
// outcome below is written by hand from the documented ledger semantics; nothing is imported from
// the report's classifier or status sets.
//
// Ledger facts used (walletCore.ts): hold = one `escrow_lock` (buyer); release = a buyer-side
// `escrow_release` (amount incl. fee) plus a mirror `payout` row; refund = one `refund` (buyer).
// held remaining = locks - releases - refunds.
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import { assessLegacyRentalCoverage } from "./legacyRentalExposureReport";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;

// the ten order statuses, written out on purpose
const ALL_STATUSES = [
  "INITIATED", "PENDING_PAYMENT", "HELD_IN_ESCROW", "ESCROW_LOCKED", "PARTIALLY_RELEASED",
  "POST_INSPECTION_PENDING", "DISPUTED", "SETTLED", "REFUNDED", "CANCELLED",
];
const BOOKING_SOURCES = ["settlement:none", "settlement:held", "settlement:disputed", "settlement:released", "settlement:refunded"];
const CLAIM_STATUSES = ["PENDING_PAYMENT", "PENDING_APPROVAL", "ESCROW_LOCKED"];

async function makeUser(t: T, name: string, extra: Record<string, unknown> = {}) {
  seq += 1;
  return t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@synthetic.invalid`, phone: `+2327970${1000 + seq}`, name: `SECRET-${name}`, role: "client",
      isVerified: true, isActive: true, updatedAt: Date.now(), ...extra,
    } as any)
  ) as Promise<Id<"users">>;
}

type World = { t: T; buyer: Id<"users">; owner: Id<"users">; other: Id<"users">; wallet: Id<"walletBalances">; listing: Id<"vehicleListings"> };
async function world(t: T): Promise<World> {
  const owner = await makeUser(t, "owner", { role: "dealer", roleApprovedAt: Date.now() });
  const buyer = await makeUser(t, "buyer");
  const other = await makeUser(t, "stranger");
  const wallet = await t.run(async (ctx) =>
    ctx.db.insert("walletBalances", { userId: buyer, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: 1 } as any)
  );
  const listing = await t.run(async (ctx) =>
    ctx.db.insert("vehicleListings", {
      ownerId: owner, title: "SECRET-TITLE", category: "car_rental", price: 100, pricingType: "per_day", pricePerDay: 100,
      location: "SECRET-PLACE", images: [], status: "AVAILABLE", createdAt: 1, updatedAt: 1, isPublished: true, isDeleted: false,
    } as any)
  );
  return { t, buyer, owner, other, wallet, listing: listing as Id<"vehicleListings"> };
}

async function order(w: World, o: { status: string; gross?: number; rail?: string; bank?: string; listing?: Id<"vehicleListings">; currency?: string }) {
  seq += 1;
  return w.t.run(async (ctx) =>
    ctx.db.insert("escrow_orders", {
      orderCode: `LEG-${seq}`, orderType: "VEHICLE_RENTAL", renterOrBuyerId: w.buyer, ownerOrSellerId: w.owner,
      vehicleListingId: o.listing ?? w.listing, currency: o.currency ?? "SLE", baseRentalAmount: 300, refundableDepositAmount: 500, earnestFeeAmount: 0,
      fullPurchaseAmount: 0, grossEscrowAmount: o.gross ?? 809, platformFeeAmount: 45, netMerchantExpected: 255,
      split60ReleasedAmount: 0, split40ReleasedAmount: 0, depositRefundedAmount: 0, depositDamageDeductedAmount: 0,
      status: o.status, paymentRail: o.rail ?? "WALLET", ...(o.bank ? { bankClearingStatus: o.bank } : {}), createdAt: 1, updatedAt: 1,
    } as any)
  ) as Promise<Id<"escrow_orders">>;
}
const tx = (w: World, row: Record<string, unknown>) =>
  w.t.run(async (ctx) =>
    ctx.db.insert("transactions", { walletId: w.wallet, userId: w.buyer, currency: "SLE", status: "completed", updatedAt: 1, ...row } as any)
  ) as Promise<Id<"transactions">>;
const lock = (w: World, orderId: Id<"escrow_orders">, amount: number, user?: Id<"users">) =>
  tx(w, { type: "escrow_lock", amount, escrowStatus: "locked", referenceType: "vehicle_escrow", referenceId: orderId, ...(user ? { userId: user } : {}) });
let txCode = 0;
async function release(w: World, orderId: Id<"escrow_orders">, amount: number, fee: number, mirror: Record<string, unknown> | false = {}) {
  // a release writes a buyer-side row and a recipient mirror sharing one transaction code (walletCore)
  const code = `TXC-${++txCode}`;
  const id = await tx(w, { transactionId: code, type: "escrow_release", amount, feeAmount: fee, platformFeeAmount: fee, escrowStatus: "released", counterpartyId: w.owner, referenceType: "vehicle_escrow", referenceId: orderId });
  if (mirror !== false) {
    await tx(w, { transactionId: code, type: "payout", amount, netAmount: amount - fee, userId: w.owner, counterpartyId: w.buyer, referenceType: "vehicle_escrow", referenceId: orderId, ...mirror });
  }
  return id;
}
const refund = (w: World, orderId: Id<"escrow_orders">, amount: number) =>
  tx(w, { type: "refund", amount, escrowStatus: "refunded", referenceType: "vehicle_escrow", referenceId: orderId });
const dispute = (w: World, orderId: Id<"escrow_orders">, status: string) =>
  w.t.run(async (ctx) =>
    ctx.db.insert("escrow_disputes", { escrowOrderId: orderId, openedByUserId: w.buyer, reason: "x", claimedRepairCost: 1, evidenceMediaUrls: [], status, openedAt: 1 } as any)
  );
const claim = (w: World, orderId: Id<"escrow_orders">, status: string, user?: Id<"users">) =>
  w.t.run(async (ctx) =>
    ctx.db.insert("escrow_payment_claims", {
      escrowOrderId: orderId, userId: user ?? w.buyer, amount: 809, currency: "SLE", providerId: "p", paymentType: "MANUAL_CLAIM",
      transactionReference: `ref-${++seq}`, status, createdAt: 1,
    } as any)
  );
const checkout = (w: World, tag: string, status: string) =>
  tx(w, { type: "top_up", amount: 809, referenceType: "escrow_checkout", referenceId: tag, status, gatewayProvider: "MONIME_X", gatewayReference: `g-${++seq}` });
const reversal = (w: World, releaseTx: Id<"transactions">, orderId: string, status: string, refType = "vehicle_escrow") =>
  w.t.run(async (ctx) =>
    ctx.db.insert("payment_reversals", {
      releaseTransactionId: releaseTx, buyerId: w.buyer, recipientId: w.owner, currency: "SLE", referenceType: refType, referenceId: orderId,
      originalAmount: 180, platformFeeReversed: 27, recipientNetOwed: 153, recoveredFromRecipient: 0, platformCoveredAmount: 0,
      writtenOffAmount: 0, refundedToBuyer: 27, outstandingAmount: 153, status, reason: "x", createdBy: w.owner, createdAt: 1, updatedAt: 1,
    } as any)
  );
const preTrip = (w: World, orderId: Id<"escrow_orders">) =>
  w.t.run(async (ctx) =>
    ctx.db.insert("vehicle_inspections", {
      escrowOrderId: orderId, inspectorId: w.owner, inspectionType: "PRE_TRIP_RENTAL", odometerReadingKm: 1, fuelTankPercentage: 50,
      photoFrontUrl: "a", photoRearUrl: "a", photoLeftSideUrl: "a", photoRightSideUrl: "a", photoInteriorUrl: "a", photoDashboardOdometerUrl: "a",
      qrTokenHash: "q", status: "COMPLETED_CLEAN", createdAt: 1,
    } as any)
  );
const booking = (w: World, b: Record<string, unknown>) =>
  w.t.run(async (ctx) =>
    ctx.db.insert("bookings", {
      listingId: w.listing as string, listingType: "vehicle", listingTitle: "x", buyerId: w.buyer as string, vendorId: w.owner as string,
      bookingType: "vehicle_rental", status: "confirmed", startTime: 1, endTime: 2, subtotal: 100, serviceFee: 0, totalAmount: 100,
      currency: "SLE", paymentStatus: "completed", updatedAt: 1, ...b,
    } as any)
  ) as Promise<Id<"bookings">>;

// ─── runners ───
async function walkOrders(t: T, numItems?: number) {
  const counts: Record<string, number> = {};
  const exposure: Record<string, number> = {};
  const evidence: Record<string, number> = {};
  const held: Record<string, number> = {};
  let scanned = 0;
  const pages: any[] = [];
  let scope: any;
  for (const status of ALL_STATUSES) {
    let cursor: string | null = null;
    for (let i = 0; i < 500; i++) {
      const p: any = await t.query(internal.legacyRentalExposureReport.legacyRentalOrdersPage, numItems === undefined ? { status, cursor } : { status, cursor, numItems });
      pages.push(p); scanned += p.scanned; scope = p.scope;
      for (const [k, n] of Object.entries(p.counts as Record<string, number>)) counts[k] = (counts[k] ?? 0) + n;
      for (const [k, n] of Object.entries(p.exposureTotals as Record<string, number>)) exposure[k] = (exposure[k] ?? 0) + n;
      for (const [k, n] of Object.entries(p.evidence as Record<string, number>)) evidence[k] = (evidence[k] ?? 0) + n;
      for (const [k, byCur] of Object.entries(p.heldAmountByExposure as Record<string, Record<string, number>>)) {
        for (const [cur, n] of Object.entries(byCur)) held[`${k}|${cur}`] = Math.round(((held[`${k}|${cur}`] ?? 0) + n) * 100) / 100;
      }
      cursor = p.continueCursor;
      if (p.isDone) break;
    }
  }
  return { counts, exposure, evidence, held, scanned, pages, scope };
}
async function walkBookings(t: T, numItems?: number) {
  const counts: Record<string, number> = {};
  const evidence: Record<string, number> = {};
  let scanned = 0, rental = 0, skipped = 0;
  const pages: any[] = [];
  for (const source of BOOKING_SOURCES) {
    let cursor: string | null = null;
    for (let i = 0; i < 500; i++) {
      const p: any = await t.query(internal.legacyRentalExposureReport.legacyRentalBookingsPage, numItems === undefined ? { source, cursor } : { source, cursor, numItems });
      pages.push(p); scanned += p.scanned; rental += p.rentalBookings; skipped += p.skippedOtherTypes;
      for (const [k, n] of Object.entries(p.counts as Record<string, number>)) counts[k] = (counts[k] ?? 0) + n;
      for (const [k, n] of Object.entries(p.evidence as Record<string, number>)) evidence[k] = (evidence[k] ?? 0) + n;
      cursor = p.continueCursor;
      if (p.isDone) break;
    }
  }
  return { counts, evidence, scanned, rental, skipped, pages };
}
async function walkClaims(t: T, numItems?: number) {
  const counts: Record<string, number> = {};
  const pages: any[] = [];
  let rental = 0, skipped = 0;
  for (const status of CLAIM_STATUSES) {
    let cursor: string | null = null;
    for (let i = 0; i < 500; i++) {
      const p: any = await t.query(internal.legacyRentalExposureReport.legacyRentalClaimsPage, numItems === undefined ? { status, cursor } : { status, cursor, numItems });
      pages.push(p); rental += p.rentalClaims; skipped += p.skippedOtherTargets;
      for (const [k, n] of Object.entries(p.counts as Record<string, number>)) counts[k] = (counts[k] ?? 0) + n;
      cursor = p.continueCursor;
      if (p.isDone) break;
    }
  }
  return { counts, pages, rental, skipped };
}
// exact key-part matching
const n = (counts: Record<string, number>, ...parts: string[]) =>
  Object.entries(counts).filter(([k]) => { const s = new Set(k.split("|")); return parts.every((p) => s.has(p)); }).reduce((a, [, v]) => a + v, 0);
const total = (c: Record<string, number>) => Object.values(c).reduce((a, v) => a + v, 0);

describe("legacy rental ORDERS: reconciliation and combined exposure", () => {
  test("each hand-authored scenario lands in exactly one exposure, with its evidence kept separate", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);

    // 1. funded, hold verified (gross 809), pre-trip inspection recorded
    const funded = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, funded, 809);
    await preTrip(w, funded);
    // 2. partially released: 60% net 153 + fee 27 = 180 released; 629 still held (incl. 500 deposit)
    const partial = await order(w, { status: "PARTIALLY_RELEASED" });
    await lock(w, partial, 809);
    await release(w, partial, 180, 27);
    await preTrip(w, partial);
    // 3. fully reconciled terminal: 809 = 180 + 129 released + 500 deposit refunded
    const settled = await order(w, { status: "SETTLED" });
    await lock(w, settled, 809);
    await release(w, settled, 180, 27);
    await release(w, settled, 129, 18);
    await refund(w, settled, 500);
    await preTrip(w, settled);
    // 4. held-looking, no hold transaction at all
    await order(w, { status: "HELD_IN_ESCROW" });
    // 5. cancelled, with a pending Monime checkout for THIS order
    const cancelled = await order(w, { status: "CANCELLED" });
    await checkout(w, `vehicle:${cancelled}`, "pending");
    // 6. pending bank transfer (unpaid)
    await order(w, { status: "PENDING_PAYMENT", rail: "BANK_TRANSFER", bank: "PENDING_TRANSFER" });
    // 7. disputed with an open dispute; 629 held
    const disputed = await order(w, { status: "DISPUTED" });
    await lock(w, disputed, 809);
    await release(w, disputed, 180, 27);
    await dispute(w, disputed, "OPENED");
    // 8. a dispute attached to a settled (non-disputed) order
    const strayDispute = await order(w, { status: "SETTLED" });
    await lock(w, strayDispute, 809);
    await release(w, strayDispute, 309, 45);
    await refund(w, strayDispute, 500);
    await dispute(w, strayDispute, "OPENED");
    // 9. an open claim on a terminal, balanced order
    const claimed = await order(w, { status: "REFUNDED" });
    await lock(w, claimed, 809);
    await refund(w, claimed, 809);
    await claim(w, claimed, "PENDING_APPROVAL");
    // 10. an open recovery linked through the release row
    const recovered = await order(w, { status: "SETTLED" });
    await lock(w, recovered, 809);
    const rel = await release(w, recovered, 309, 45);
    await refund(w, recovered, 500);
    await reversal(w, rel, recovered as string, "pending_recovery");

    const r = await walkOrders(t);
    expect(r.scanned).toBe(10);
    expect(total(r.counts)).toBe(10); // every order exactly once
    expect(r.scope.scopeLabel).toBe("escrow_orders_vehicle_rental_only");
    expect(r.scope.excludes).toContain("hotel_bookings");

    // combined categories (hand-computed)
    expect(r.exposure).toEqual({
      funds_held: 2, // funded + partial
      reconciled_terminal: 1, // settled
      manual_review: 2, // no hold transaction + stray dispute
      pending_payment_attempt: 1, // cancelled with pending checkout
      unpaid_fundable: 1, // bank pending
      disputed_funds: 1,
      open_claim: 1,
      open_recovery: 1,
    });
    // reconciliation per scenario
    expect(n(r.counts, "status=HELD_IN_ESCROW", "reconciliation=held")).toBe(1); // funded
    expect(n(r.counts, "status=PARTIALLY_RELEASED", "reconciliation=held")).toBe(1);
    expect(n(r.counts, "status=SETTLED", "reconciliation=balanced")).toBe(3); // settled, stray dispute, recovered
    expect(n(r.counts, "status=HELD_IN_ESCROW", "reconciliation=no_hold_transaction", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=REFUNDED", "reconciliation=balanced", "claim=open", "exposure=open_claim")).toBe(1);
    expect(n(r.counts, "status=CANCELLED", "checkout=pending_unresolved", "reconciliation=nothing_held", "exposure=pending_payment_attempt")).toBe(1);
    expect(n(r.counts, "status=PENDING_PAYMENT", "rail=BANK_TRANSFER", "bank=bank_pending", "exposure=unpaid_fundable")).toBe(1);
    expect(n(r.counts, "status=DISPUTED", "dispute=open", "exposure=disputed_funds")).toBe(1);
    expect(n(r.counts, "status=SETTLED", "dispute=open", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=SETTLED", "recovery=open", "exposure=open_recovery")).toBe(1);
    // a terminal status alone never resolves an order
    expect(n(r.counts, "exposure=reconciled_terminal")).toBe(1);
    // verified held amounts (aggregates): funded 809; partial 629; disputed 629
    expect(r.held).toEqual({ "funds_held|SLE": 1438, "disputed_funds|SLE": 629 });
    // evidence tallies are per ORDER and are not additive with the totals
    expect(r.evidence.orders_with_verified_held_funds).toBe(3);
    expect(r.evidence.orders_with_open_dispute).toBe(2);
    expect(r.evidence.orders_with_open_claim).toBe(1);
    expect(r.evidence.orders_with_unresolved_checkout).toBe(1);
    expect(r.evidence.orders_with_open_recovery).toBe(1);
    // pre-trip evidence: present on funded, partial, settled; the other open ones lack it
    expect(n(r.counts, "preTrip=present")).toBe(3);
    expect(r.evidence.open_orders_without_pre_trip_inspection).toBe(3); // no-hold, bank pending, disputed
  });

  test("records of a DIFFERENT order, user or reference never attach", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const a = await order(w, { status: "PENDING_PAYMENT" });
    const b = await order(w, { status: "PENDING_PAYMENT" });
    // a pending checkout and a lock that belong to b must not appear on a
    await checkout(w, `vehicle:${b}`, "pending");
    // a hold under a's reference but owned by a stranger is an ownership mismatch -> manual review
    const c = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, c, 809, w.other);
    // a claim by a stranger on d
    const d = await order(w, { status: "SETTLED" });
    await lock(w, d, 809);
    await release(w, d, 309, 45);
    await refund(w, d, 500);
    await claim(w, d, "REJECTED", w.other);
    const r = await walkOrders(t);
    expect(total(r.counts)).toBe(4);
    expect(n(r.counts, "status=PENDING_PAYMENT", "checkout=none")).toBe(1); // a
    expect(n(r.counts, "status=PENDING_PAYMENT", "checkout=pending_unresolved")).toBe(1); // b
    expect(n(r.counts, "reconciliation=ownership_mismatch", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=SETTLED", "claim=closed+owner_mismatch", "exposure=manual_review")).toBe(1);
    void a;
  });

  test("a recovery whose reference does not match the order is flagged, not trusted", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const o = await order(w, { status: "SETTLED" });
    await lock(w, o, 809);
    const rel = await release(w, o, 309, 45);
    await refund(w, o, 500);
    await reversal(w, rel, "some-other-order", "pending_recovery");
    const r = await walkOrders(t);
    expect(n(r.counts, "recovery=open+reference_mismatch", "exposure=manual_review")).toBe(1);
  });

  test("ledger anomalies stay visible whatever the status says", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const wrongAmount = await order(w, { status: "HELD_IN_ESCROW", gross: 809 });
    await lock(w, wrongAmount, 700);
    const over = await order(w, { status: "SETTLED" });
    await lock(w, over, 809);
    await release(w, over, 809, 45);
    await refund(w, over, 100);
    const settledStillHeld = await order(w, { status: "SETTLED" });
    await lock(w, settledStillHeld, 809);
    await release(w, settledStillHeld, 180, 27);
    const openButEmpty = await order(w, { status: "PARTIALLY_RELEASED" });
    await lock(w, openButEmpty, 809);
    await release(w, openButEmpty, 809, 45);
    const cancelledLocked = await order(w, { status: "CANCELLED" });
    await lock(w, cancelledLocked, 809);
    const unpaidLocked = await order(w, { status: "PENDING_PAYMENT" });
    await lock(w, unpaidLocked, 809);
    const moveNoLock = await order(w, { status: "SETTLED" });
    await refund(w, moveNoLock, 809);
    const reversedRow = await order(w, { status: "SETTLED" });
    await lock(w, reversedRow, 809);
    await tx(w, { type: "escrow_release", amount: 809, status: "reversed", referenceType: "vehicle_escrow", referenceId: reversedRow });
    const r = await walkOrders(t);
    expect(total(r.counts)).toBe(8);
    expect(r.exposure).toEqual({ manual_review: 8 });
    expect(n(r.counts, "reconciliation=lock_amount_mismatch")).toBe(1);
    expect(n(r.counts, "reconciliation=overdrawn")).toBe(1);
    expect(n(r.counts, "status=SETTLED", "reconciliation=held")).toBe(1); // terminal yet 629 held
    expect(n(r.counts, "status=PARTIALLY_RELEASED", "reconciliation=balanced")).toBe(1); // open yet nothing held
    expect(n(r.counts, "reconciliation=cancelled_with_locks")).toBe(1);
    expect(n(r.counts, "reconciliation=unpaid_with_locks")).toBe(1);
    expect(n(r.counts, "reconciliation=movement_without_lock")).toBe(1);
    expect(n(r.counts, "reconciliation=nonstandard_transaction_status")).toBe(1);
  });

  test("listing evidence: missing listing, deleted listing, and a class for a normal one", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const deleted = await t.run(async (ctx) =>
      ctx.db.insert("vehicleListings", {
        ownerId: w.owner, title: "x", category: "delivery_van", price: 1, pricingType: "per_day", pricePerDay: 1, location: "x", images: [],
        status: "AVAILABLE", createdAt: 1, updatedAt: 1, isDeleted: true,
      } as any)
    );
    const gone = await t.run(async (ctx) =>
      ctx.db.insert("vehicleListings", {
        ownerId: w.owner, title: "x", category: "car_rental", price: 1, pricingType: "per_day", pricePerDay: 1, location: "x", images: [],
        status: "AVAILABLE", createdAt: 1, updatedAt: 1,
      } as any)
    );
    await order(w, { status: "PENDING_PAYMENT" });
    await order(w, { status: "PENDING_PAYMENT", listing: deleted as Id<"vehicleListings"> });
    await order(w, { status: "PENDING_PAYMENT", listing: gone as Id<"vehicleListings"> });
    await t.run(async (ctx) => ctx.db.delete(gone));
    const r = await walkOrders(t);
    expect(total(r.counts)).toBe(3);
    expect(n(r.counts, "listing=hire_daily_car:active")).toBe(1);
    expect(n(r.counts, "listing=hire_or_service_van:deleted")).toBe(1);
    expect(n(r.counts, "listing=missing")).toBe(1);
    expect(r.evidence.orders_with_missing_listing).toBe(1);
  });

  test("every status is traversed, including the three that no code writes; empty data is clean", async () => {
    const t = convexTest(schema, modules);
    const empty = await walkOrders(t);
    expect(empty.scanned).toBe(0);
    expect(total(empty.counts)).toBe(0);

    const w = await world(t);
    for (const status of ALL_STATUSES) await order(w, { status });
    const r = await walkOrders(t);
    expect(r.scanned).toBe(10);
    for (const status of ALL_STATUSES) expect(n(r.counts, `status=${status}`), status).toBe(1);
    // nothing is reconciled merely because its status is terminal: SETTLED/REFUNDED have no holds
    expect(n(r.counts, "status=SETTLED", "reconciliation=no_hold_transaction", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=REFUNDED", "reconciliation=no_hold_transaction", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=CANCELLED", "exposure=reconciled_terminal")).toBe(1); // never funded, none found
  });

  test("stable totals across page sizes 1, 2, 3, 50, 100 and repeated runs; read-only; counts only", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    for (let i = 0; i < 7; i++) {
      const o = await order(w, { status: i % 2 ? "HELD_IN_ESCROW" : "SETTLED" });
      await lock(w, o, 809);
      if (i % 2 === 0) { await release(w, o, 309, 45); await refund(w, o, 500); }
    }
    const digest = () =>
      t.run(async (ctx) =>
        JSON.stringify([
          await ctx.db.query("escrow_orders").collect(), await ctx.db.query("transactions").collect(),
          await ctx.db.query("escrow_disputes").collect(), await ctx.db.query("payment_reversals").collect(),
          await ctx.db.query("bookings").collect(), await ctx.db.query("vehicleListings").collect(),
        ])
      );
    const before = await digest();
    const base = await walkOrders(t, 50);
    expect(base.scanned).toBe(7);
    for (const size of [1, 2, 3, 50, 100]) {
      const r = await walkOrders(t, size);
      expect(r.counts, `size ${size}`).toEqual(base.counts);
      expect(r.exposure).toEqual(base.exposure);
      expect(r.scanned).toBe(7);
    }
    expect((await walkOrders(t)).counts).toEqual(base.counts); // default size, repeated
    // the maximum page size is enforced
    const big: any = await t.query(internal.legacyRentalExposureReport.legacyRentalOrdersPage, { status: "SETTLED", numItems: 100000 });
    expect(big.scanned).toBeLessThanOrEqual(50);
    expect(await digest()).toBe(before);
    const text = JSON.stringify(base.pages.map((p) => ({ ...p, continueCursor: undefined })));
    for (const secret of ["SECRET", "synthetic.invalid", "LEG-", "+232", String(w.buyer), String(w.owner)]) expect(text).not.toContain(secret);
  });

  test("internal only: no public function exists, and bad statuses are refused", async () => {
    const t = convexTest(schema, modules);
    // Every registered Convex function this module exports is INTERNAL (not callable by any client).
    // (convex-test cannot enforce the public/internal split itself; the disposable-backend run does.)
    const mod: Record<string, any> = await import("./legacyRentalExposureReport");
    const registered = Object.entries(mod).filter(([, f]) => f && (f.isQuery || f.isMutation || f.isAction));
    expect(registered.map(([k]) => k).sort()).toEqual([
      "legacyRentalBookingsPage", "legacyRentalClaimsPage", "legacyRentalCoverageCheck", "legacyRentalCoverageManifest", "legacyRentalOrdersPage",
    ]);
    for (const [name, f] of registered) expect(f.isInternal, name).toBe(true);
    await expect(t.query(internal.legacyRentalExposureReport.legacyRentalOrdersPage, { status: "FUNDED" })).rejects.toThrow(/rental order status/i);
    await expect(t.query(internal.legacyRentalExposureReport.legacyRentalBookingsPage, { source: "status:confirmed" })).rejects.toThrow(/settlement source/i);
  });
});

describe("legacy rental BOOKINGS: settlement ranges, ledger and contradictions", () => {
  test("paid bookings without escrow ids, settled-but-contradictory records and checkouts", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);

    // 12a. old flow: paid, confirmed, no escrow id, no settlement record, nothing in the ledger
    await booking(w, {});
    // 12b. paid, no settlement record, but the ledger shows a LOCKED escrow under its reference
    const lockedNoRecord = await booking(w, {});
    await tx(w, { type: "escrow_lock", amount: 100, escrowStatus: "locked", referenceType: "vehicle_rental", referenceId: lockedNoRecord });
    // 13. held, ledger balanced (lock 100, release 100): money moved though settlement still says held
    const heldMoved = await booking(w, { settlementStatus: "held" });
    await tx(w, { type: "escrow_lock", amount: 100, escrowStatus: "locked", referenceType: "vehicle_rental", referenceId: heldMoved });
    await tx(w, { transactionId: "BK-HELDMOVED", type: "escrow_release", amount: 100, feeAmount: 0, escrowStatus: "released", referenceType: "vehicle_rental", referenceId: heldMoved }); // no payout mirror written
    // held under a terminal status
    const heldTerminal = await booking(w, { settlementStatus: "held", status: "completed" });
    await tx(w, { type: "escrow_lock", amount: 100, escrowStatus: "locked", referenceType: "vehicle_rental", referenceId: heldTerminal });
    // disputed settlement while status says confirmed
    await booking(w, { settlementStatus: "disputed", status: "confirmed" });
    // released but status not completed
    await booking(w, { settlementStatus: "released", status: "confirmed" });
    // refunded but status completed
    await booking(w, { settlementStatus: "refunded", status: "completed", paymentStatus: "refunded" });
    // released while the ledger still shows the escrow locked
    const releasedLocked = await booking(w, { settlementStatus: "released", status: "completed" });
    await tx(w, { type: "escrow_lock", amount: 100, escrowStatus: "locked", referenceType: "vehicle_rental", referenceId: releasedLocked });
    // consistent: released + completed, lock 100 release 100
    const clean = await booking(w, { settlementStatus: "released", status: "completed" });
    await tx(w, { type: "escrow_lock", amount: 100, escrowStatus: "locked", referenceType: "vehicle_rental", referenceId: clean });
    await tx(w, { transactionId: "BK-CLEAN", type: "escrow_release", amount: 100, feeAmount: 0, escrowStatus: "released", referenceType: "vehicle_rental", referenceId: clean });
    await tx(w, { transactionId: "BK-CLEAN", type: "payout", amount: 100, netAmount: 100, userId: w.owner, referenceType: "vehicle_rental", referenceId: clean });
    // unpaid with an unresolved checkout for this booking
    const unpaid = await booking(w, { status: "pending_payment", paymentStatus: "pending" });
    await checkout(w, `booking:${unpaid}`, "pending");
    // a free vehicle inspection is not a rental and is skipped, not counted
    await booking(w, { bookingType: "vehicle_inspection", totalAmount: 0, subtotal: 0 });

    const r = await walkBookings(t);
    expect(r.skipped).toBe(1);
    expect(r.rental).toBe(10);
    expect(total(r.counts)).toBe(10); // each rental booking exactly once across the five ranges
    expect(n(r.counts, "settlement=none", "status=confirmed", "ledger=no_escrow_rows", "escrowId=none", "contradictions=paid_without_escrow_evidence")).toBe(1);
    expect(n(r.counts, "settlement=none", "ledger=locked_remaining", "contradictions=locked_without_settlement_record")).toBe(1);
    expect(n(r.counts, "settlement=held", "ledger=balanced", "payout=missing", "contradictions=held_but_ledger_balanced+payout_missing")).toBe(1); // held although the ledger moved the money, and no payout mirror
    expect(n(r.counts, "settlement=held", "status=completed", "contradictions=held_under_terminal_status")).toBe(1);
    expect(n(r.counts, "settlement=disputed", "contradictions=disputed_status_differs+held_without_escrow_rows")).toBe(1);
    expect(n(r.counts, "settlement=released", "status=confirmed", "contradictions=released_status_not_completed")).toBe(1);
    expect(n(r.counts, "settlement=refunded", "status=completed", "contradictions=refunded_status_not_cancelled")).toBe(1);
    expect(n(r.counts, "settlement=released", "ledger=locked_remaining", "contradictions=settled_but_escrow_locked")).toBe(1);
    expect(n(r.counts, "settlement=released", "status=completed", "ledger=balanced", "contradictions=none")).toBe(1);
    expect(n(r.counts, "settlement=none", "status=pending_payment", "checkout=pending_unresolved")).toBe(1);
    expect(r.evidence.rental_bookings_with_contradictions).toBe(8);
    expect(r.evidence.rental_bookings_with_unresolved_checkout).toBe(1);
    expect(r.evidence.rental_bookings_with_escrow_still_locked).toBe(3); // locked-no-record, held-terminal, released-locked
    void heldMoved;
  });

  test("page sizes and repeated runs agree; read-only; scope is labelled", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    for (let i = 0; i < 6; i++) await booking(w, { settlementStatus: i % 3 === 0 ? "held" : i % 3 === 1 ? "released" : undefined, status: i % 3 === 1 ? "completed" : "confirmed" });
    const digest = () => t.run(async (ctx) => JSON.stringify([await ctx.db.query("bookings").collect(), await ctx.db.query("transactions").collect()]));
    const before = await digest();
    const base = await walkBookings(t, 50);
    expect(base.rental).toBe(6);
    for (const size of [1, 2, 3, 50, 100]) expect((await walkBookings(t, size)).counts, `size ${size}`).toEqual(base.counts);
    expect((await walkBookings(t)).counts).toEqual(base.counts);
    for (const k of Object.keys(base.counts)) expect(k.startsWith("scope=bookings_vehicle_rental_only|")).toBe(true);
    expect(base.pages[0].scope.excludes).toContain("re_escrow_contracts");
    expect(await digest()).toBe(before);
    expect(JSON.stringify(base.pages.map((p) => ({ ...p, continueCursor: undefined })))).not.toContain("SECRET");
  });
});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Stage 1C-6D regression tests: payout mirrors (H1), coverage manifest (H2), invalid booking escrow
// ids (M1), nonstandard provider states (M2), pending ledger entries (M3), open dispute vs order
// status (M4), plus the documented M5-M7 behaviour. Expected values are written by hand.
// ─────────────────────────────────────────────────────────────────────────────────────────────
async function settled(w: World, mirror: Record<string, unknown> | false = {}) {
  const o = await order(w, { status: "SETTLED" });
  await lock(w, o, 809);
  await release(w, o, 309, 45, mirror);
  await refund(w, o, 500);
  return o;
}

describe("H1: recipient payout mirrors", () => {
  test("a balanced ledger is NOT reconciled unless every release reached its recipient", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    await settled(w); // correct mirror
    await settled(w, false); // release without any mirror
    await settled(w, { userId: w.other }); // mirror paid to a stranger
    await settled(w, { amount: 300, netAmount: 255 }); // mirror of a different size
    await settled(w, { netAmount: 1 }); // net does not equal amount - fee
    await settled(w, { status: "pending" }); // mirror not completed
    const unmatchable = await order(w, { status: "SETTLED" }); // release row without a transaction code
    await lock(w, unmatchable, 809);
    await tx(w, { type: "escrow_release", amount: 309, feeAmount: 45, platformFeeAmount: 45, escrowStatus: "released", counterpartyId: w.owner, referenceType: "vehicle_escrow", referenceId: unmatchable });
    await refund(w, unmatchable, 500);
    const orphan = await settled(w); // a correct release plus a payout that belongs to no release
    await tx(w, { transactionId: "ORPHAN-1", type: "payout", amount: 50, netAmount: 50, userId: w.owner, referenceType: "vehicle_escrow", referenceId: orphan });

    const r = await walkOrders(t);
    expect(total(r.counts)).toBe(8);
    // every one of these is "balanced" by the escrow formula; only the first is truly reconciled
    expect(n(r.counts, "reconciliation=balanced")).toBe(8);
    expect(n(r.counts, "payout=complete", "exposure=reconciled_terminal")).toBe(1);
    expect(n(r.counts, "payout=missing", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "payout=wrong_recipient", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "payout=amount_mismatch", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "payout=net_mismatch", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "payout=nonstandard_status", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "payout=unmatchable", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "payout=orphan", "exposure=manual_review")).toBe(1);
    expect(r.evidence.orders_with_payout_anomaly).toBe(7);
  });

  test("a rental booking release without its vendor mirror is flagged; a correct one is not", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const mk = async (code: string, mirror: Record<string, unknown> | false) => {
      const b = await booking(w, { settlementStatus: "released", status: "completed" });
      await tx(w, { type: "escrow_lock", amount: 100, escrowStatus: "locked", referenceType: "vehicle_rental", referenceId: b });
      await tx(w, { transactionId: code, type: "escrow_release", amount: 100, feeAmount: 15, platformFeeAmount: 15, escrowStatus: "released", referenceType: "vehicle_rental", referenceId: b });
      if (mirror !== false) await tx(w, { transactionId: code, type: "payout", amount: 100, netAmount: 85, userId: w.owner, referenceType: "vehicle_rental", referenceId: b, ...mirror });
    };
    await mk("OK-1", {});
    await mk("MISS-1", false);
    await mk("WRONG-1", { userId: w.other });
    const r = await walkBookings(t);
    expect(r.rental).toBe(3);
    expect(n(r.counts, "payout=complete", "contradictions=none")).toBe(1);
    expect(n(r.counts, "payout=missing", "contradictions=payout_missing")).toBe(1);
    expect(n(r.counts, "payout=wrong_recipient", "contradictions=payout_wrong_recipient")).toBe(1);
  });
});

describe("H2: scan-completeness manifest", () => {
  test("every page states its required units, and omitted units are reported as missing", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    await settled(w);
    await booking(w, {});
    const o: any = await t.query(internal.legacyRentalExposureReport.legacyRentalOrdersPage, { status: "SETTLED" });
    expect(o.coverage.kind).toBe("orders");
    expect(o.coverage.unit).toBe("SETTLED");
    expect(o.coverage.required).toEqual(ALL_STATUSES);
    const b: any = await t.query(internal.legacyRentalExposureReport.legacyRentalBookingsPage, { source: "settlement:none" });
    expect(b.coverage.required).toEqual(BOOKING_SOURCES);
    const cl: any = await t.query(internal.legacyRentalExposureReport.legacyRentalClaimsPage, { status: "PENDING_APPROVAL" });
    expect(cl.coverage.required).toEqual(CLAIM_STATUSES);

    const full = await walkOrders(t);
    const fullB = await walkBookings(t);
    const fullC = await walkClaims(t);
    expect(assessLegacyRentalCoverage([...full.pages, ...fullB.pages, ...fullC.pages])).toEqual({ complete: true, missingOrders: [], missingBookings: [], missingClaims: [], unknownUnits: [], inconsistentUnits: [], unattributablePages: 0 });
    // without the claims traversal a report is incomplete too
    expect(assessLegacyRentalCoverage([...full.pages, ...fullB.pages]).missingClaims).toEqual(CLAIM_STATUSES);
    // leaving out one status, or one settlement range, can never read as complete
    const noCancelled = full.pages.filter((p: any) => p.coverage.unit !== "CANCELLED");
    expect(assessLegacyRentalCoverage([...noCancelled, ...fullB.pages, ...fullC.pages])).toMatchObject({ complete: false, missingOrders: ["CANCELLED"], missingBookings: [], missingClaims: [] });
    const noReleased = fullB.pages.filter((p: any) => p.coverage.unit !== "settlement:released");
    expect(assessLegacyRentalCoverage([...full.pages, ...noReleased, ...fullC.pages])).toMatchObject({ complete: false, missingOrders: [], missingBookings: ["settlement:released"], missingClaims: [] });
    // a unit that was started but not finished (isDone false) does not count
    const unfinished = full.pages.map((p: any) => (p.coverage.unit === "SETTLED" ? { ...p, isDone: false } : p));
    expect(assessLegacyRentalCoverage([...unfinished, ...fullB.pages, ...fullC.pages]).missingOrders).toEqual(["SETTLED"]);
    expect(assessLegacyRentalCoverage([]).complete).toBe(false);
  });

  test("a lone final page, or a chain with a gap, is not coverage", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    for (let i = 0; i < 5; i++) await order(w, { status: "SETTLED" });
    const bk = await walkBookings(t);
    const cl = await walkClaims(t);
    bk.pages.push(...cl.pages);
    const orderPagesExcept = async (size: number) => {
      const pages: any[] = [];
      for (const status of ALL_STATUSES) {
        let cursor: string | null = null;
        for (let i = 0; i < 50; i++) {
          const p: any = await t.query(internal.legacyRentalExposureReport.legacyRentalOrdersPage, { status, cursor, numItems: size });
          pages.push(p); cursor = p.continueCursor; if (p.isDone) break;
        }
      }
      return pages;
    };
    const pages = await orderPagesExcept(2); // SETTLED needs several pages
    const settled = pages.filter((p: any) => p.coverage.unit === "SETTLED");
    expect(settled.length).toBeGreaterThan(2);
    expect(assessLegacyRentalCoverage([...pages, ...bk.pages]).complete).toBe(true);
    // only the last page of SETTLED: isDone is true, but the traversal never started
    const lastOnly = [...pages.filter((p: any) => p.coverage.unit !== "SETTLED"), settled[settled.length - 1]];
    expect(assessLegacyRentalCoverage([...lastOnly, ...bk.pages]).missingOrders).toEqual(["SETTLED"]);
    // a gap in the middle of the chain
    const gap = pages.filter((p: any) => !(p.coverage.unit === "SETTLED" && p === settled[1]));
    expect(assessLegacyRentalCoverage([...gap, ...bk.pages]).missingOrders).toEqual(["SETTLED"]);
  });

  test("the manifest and the check query tell an operator exactly what is missing", async () => {
    const t = convexTest(schema, modules);
    const m: any = await t.query(internal.legacyRentalExposureReport.legacyRentalCoverageManifest, {});
    expect(m.required.orders).toEqual(ALL_STATUSES);
    expect(m.required.bookings).toEqual(BOOKING_SOURCES);
    expect(m.required.claims).toEqual(CLAIM_STATUSES);
    expect(m.scope.excludes).toContain("hotel_bookings");
    const partial: any = await t.query(internal.legacyRentalExposureReport.legacyRentalCoverageCheck, {
      ordersCompleted: ALL_STATUSES.filter((s) => s !== "DISPUTED" && s !== "CANCELLED"),
      bookingsCompleted: BOOKING_SOURCES.filter((s) => s !== "settlement:refunded").concat(["status:confirmed"]),
      claimsCompleted: ["PENDING_PAYMENT"],
    });
    expect(partial).toEqual({
      complete: false, missingOrders: ["DISPUTED", "CANCELLED"], missingBookings: ["settlement:refunded"],
      missingClaims: ["PENDING_APPROVAL", "ESCROW_LOCKED"], unknownUnits: ["status:confirmed"],
    });
    const all: any = await t.query(internal.legacyRentalExposureReport.legacyRentalCoverageCheck, { ordersCompleted: ALL_STATUSES, bookingsCompleted: BOOKING_SOURCES, claimsCompleted: CLAIM_STATUSES });
    expect(all.complete).toBe(true);
  });
});

describe("M1: bookings with an invalid or unrecorded escrow id", () => {
  test("none of them reads as 'no contradictions'", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    // paid, no settlement, escrow id that resolves to nothing
    await booking(w, { escrowId: String(w.buyer) });
    // paid, no settlement, a valid lock transaction whose escrow status was never recorded
    const unrecorded = await booking(w, {});
    const txU = await tx(w, { type: "escrow_lock", amount: 100, referenceType: "other", referenceId: unrecorded });
    await t.run(async (ctx) => ctx.db.patch(unrecorded, { escrowId: String(txU) } as any));
    // paid, no settlement, valid LOCKED escrow found only through the escrow id (not under the booking's reference)
    const locked = await booking(w, {});
    const txL = await tx(w, { type: "escrow_lock", amount: 100, escrowStatus: "locked", referenceType: "other", referenceId: locked });
    await t.run(async (ctx) => ctx.db.patch(locked, { escrowId: String(txL) } as any));
    // a held settlement whose escrow id is not valid
    await booking(w, { settlementStatus: "held", escrowId: String(w.buyer) });
    // an UNPAID booking that nevertheless carries an escrow id
    await booking(w, { status: "pending_payment", paymentStatus: "pending", escrowId: String(w.buyer) });
    const r = await walkBookings(t);
    expect(r.rental).toBe(5);
    expect(n(r.counts, "settlement=none", "status=pending_payment", "contradictions=escrow_id_on_unpaid_booking")).toBe(1);
    expect(n(r.counts, "settlement=none", "escrowId=invalid", "contradictions=escrow_id_invalid")).toBe(1);
    expect(n(r.counts, "settlement=none", "escrowId=unrecorded", "contradictions=escrow_state_unrecorded")).toBe(1);
    expect(n(r.counts, "settlement=none", "escrowId=locked", "contradictions=escrow_locked_without_settlement_record")).toBe(1);
    expect(n(r.counts, "settlement=held", "escrowId=invalid")).toBe(1);
    expect(n(r.counts, "contradictions=none")).toBe(0);
    expect(r.evidence.rental_bookings_with_contradictions).toBe(5);
  });
});

describe("M2: nonstandard provider states are preserved", () => {
  test("disputed and reversed checkouts are not 'failed' and are not resolved", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const a = await settled(w);
    await checkout(w, `vehicle:${a}`, "disputed");
    await checkout(w, `vehicle:${a}`, "reversed");
    const b = await settled(w);
    await checkout(w, `vehicle:${b}`, "failed"); // an ordinary failure stays ordinary
    const r = await walkOrders(t);
    expect(n(r.counts, "checkout=nonstandard:disputed+reversed", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "checkout=failed", "exposure=reconciled_terminal")).toBe(1);
    expect(r.evidence.orders_with_nonstandard_checkout).toBe(1);

    const u = await booking(w, { status: "pending_payment", paymentStatus: "pending" });
    await checkout(w, `booking:${u}`, "reversed");
    const rb = await walkBookings(t);
    expect(n(rb.counts, "checkout=nonstandard:reversed", "contradictions=nonstandard_checkout_status")).toBe(1);
  });
});

describe("M3: pending ledger entries are reported", () => {
  test("a pending escrow row is not silently ignored; a failed row is noted but does not change the result", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const pendingLock = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, pendingLock, 809);
    await tx(w, { type: "escrow_release", amount: 100, status: "pending", referenceType: "vehicle_escrow", referenceId: pendingLock });
    const failedRow = await settled(w);
    await tx(w, { type: "escrow_lock", amount: 809, status: "failed", referenceType: "vehicle_escrow", referenceId: failedRow });
    const r = await walkOrders(t);
    expect(n(r.counts, "reconciliation=pending_ledger_entries", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "reconciliation=balanced", "ledgerNotes=failed_rows_ignored", "exposure=reconciled_terminal")).toBe(1);
    expect(r.evidence.orders_with_pending_ledger_entries).toBe(1);
    expect(r.evidence.orders_with_failed_ledger_rows_ignored).toBe(1);

    const b = await booking(w, { settlementStatus: "held" });
    await tx(w, { type: "escrow_lock", amount: 100, escrowStatus: "locked", referenceType: "vehicle_rental", referenceId: b });
    await tx(w, { type: "escrow_release", amount: 100, status: "pending", referenceType: "vehicle_rental", referenceId: b });
    const rb = await walkBookings(t);
    expect(n(rb.counts, "ledger=pending_entries", "contradictions=pending_ledger_entries")).toBe(1);
  });
});

describe("M4: an open dispute must coincide with a DISPUTED order", () => {
  test("held funds with an open dispute on a non-disputed order go to manual review", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const heldOpen = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, heldOpen, 809);
    await dispute(w, heldOpen, "OPENED");
    const partial = await order(w, { status: "PARTIALLY_RELEASED" });
    await lock(w, partial, 809);
    await release(w, partial, 180, 27);
    await dispute(w, partial, "UNDER_REVIEW");
    const proper = await order(w, { status: "DISPUTED" });
    await lock(w, proper, 809);
    await release(w, proper, 180, 27);
    await dispute(w, proper, "OPENED");
    const r = await walkOrders(t);
    expect(n(r.counts, "status=HELD_IN_ESCROW", "dispute=open", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=PARTIALLY_RELEASED", "dispute=open", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=DISPUTED", "dispute=open", "exposure=disputed_funds")).toBe(1); // consistent: a genuine dispute
  });
});

describe("M5-M7: documented behaviour", () => {
  test("M5: the held aggregate is labelled verified-only and unverifiable orders are counted", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const funded = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, funded, 809);
    await order(w, { status: "HELD_IN_ESCROW" }); // no hold transaction
    const stranger = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, stranger, 809, w.other); // someone else's hold
    const page: any = await t.query(internal.legacyRentalExposureReport.legacyRentalOrdersPage, { status: "HELD_IN_ESCROW" });
    expect(page.heldAmountScope).toBe("verified_held_only");
    expect(page.heldAmountByExposure).toEqual({ funds_held: { SLE: 809 } });
    expect(page.evidence.orders_with_unverifiable_amount).toBe(2);
  });

  test("M6 (resolved): funded orders with an open claim or a pending checkout are manual review", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    // ordinary funded orders: unchanged
    const plain = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, plain, 809);
    const plainPartial = await order(w, { status: "PARTIALLY_RELEASED" });
    await lock(w, plainPartial, 809);
    await release(w, plainPartial, 180, 27);
    // funded + closed claim + completed/failed checkouts: nothing unresolved, so still funds_held
    const closedStuff = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, closedStuff, 809);
    await claim(w, closedStuff, "APPROVED");
    await checkout(w, `vehicle:${closedStuff}`, "completed");
    await checkout(w, `vehicle:${closedStuff}`, "failed");
    // funded + open claim
    const withClaim = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, withClaim, 809);
    await claim(w, withClaim, "PENDING_APPROVAL");
    // funded + pending checkout
    const withCheckout = await order(w, { status: "PARTIALLY_RELEASED" });
    await lock(w, withCheckout, 809);
    await release(w, withCheckout, 180, 27);
    await checkout(w, `vehicle:${withCheckout}`, "pending");
    // a genuinely disputed, funded order that ALSO has an open claim
    const disputedClaim = await order(w, { status: "DISPUTED" });
    await lock(w, disputedClaim, 809);
    await release(w, disputedClaim, 180, 27);
    await dispute(w, disputedClaim, "OPENED");
    await claim(w, disputedClaim, "PENDING_APPROVAL");
    // a genuinely disputed, funded order with nothing else: still disputed_funds
    const disputedPlain = await order(w, { status: "DISPUTED" });
    await lock(w, disputedPlain, 809);
    await release(w, disputedPlain, 180, 27);
    await dispute(w, disputedPlain, "OPENED");
    // UNFUNDED orders are unaffected: open claim -> open_claim, pending checkout -> pending_payment_attempt
    const unpaidClaim = await order(w, { status: "PENDING_PAYMENT" });
    await claim(w, unpaidClaim, "PENDING_APPROVAL");
    const unpaidCheckout = await order(w, { status: "PENDING_PAYMENT" });
    await checkout(w, `vehicle:${unpaidCheckout}`, "pending");
    const terminalClaim = await settled(w);
    await claim(w, terminalClaim, "PENDING_APPROVAL");

    const r = await walkOrders(t);
    expect(total(r.counts)).toBe(10);
    expect(r.exposure).toEqual({
      funds_held: 3, // plain, plain partial, funded with only CLOSED claim / completed + failed checkouts
      manual_review: 3, // funded + open claim, funded + pending checkout, disputed + funded + open claim
      disputed_funds: 1, // genuinely disputed with nothing else open
      open_claim: 2, // unpaid with an open claim, terminal balanced with an open claim (unchanged)
      pending_payment_attempt: 1, // unpaid with a pending checkout (unchanged)
    });
    expect(n(r.counts, "status=HELD_IN_ESCROW", "reconciliation=held", "claim=open", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=PARTIALLY_RELEASED", "reconciliation=held", "checkout=pending_unresolved", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=DISPUTED", "dispute=open", "claim=open", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=DISPUTED", "dispute=open", "claim=none", "exposure=disputed_funds")).toBe(1);
    // existing evidence tallies are preserved, and the funded-specific ones are added
    expect(r.evidence.orders_with_open_claim).toBe(4); // funded, disputed+claim, unpaid, terminal
    expect(r.evidence.orders_with_unresolved_checkout).toBe(2);
    expect(r.evidence.orders_funded_with_open_claim).toBe(2);
    expect(r.evidence.orders_funded_with_pending_checkout).toBe(1);
    // the verified held amount of the manual-review orders is still reported (under manual_review)
    expect(r.held["manual_review|SLE"]).toBe(809 + 629 + 629);
  });

  test("M7: a completed provider checkout that never reached escrow is manual review", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const cancelled = await order(w, { status: "CANCELLED" });
    await checkout(w, `vehicle:${cancelled}`, "completed");
    const unpaid = await order(w, { status: "PENDING_PAYMENT" });
    await checkout(w, `vehicle:${unpaid}`, "completed");
    const funded = await order(w, { status: "HELD_IN_ESCROW" }); // the normal case: payment then hold
    await checkout(w, `vehicle:${funded}`, "completed");
    await lock(w, funded, 809);
    const r = await walkOrders(t);
    expect(n(r.counts, "status=CANCELLED", "checkout=completed", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=PENDING_PAYMENT", "checkout=completed", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=HELD_IN_ESCROW", "checkout=completed", "exposure=funds_held")).toBe(1);
  });
});

describe("M6 for bookings", () => {
  test("a held or disputed rental booking with a pending provider checkout is flagged", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const mk = async (extra: Record<string, unknown>, pendingCheckout: boolean) => {
      const b = await booking(w, extra);
      await tx(w, { type: "escrow_lock", amount: 100, escrowStatus: "locked", referenceType: "vehicle_rental", referenceId: b });
      if (pendingCheckout) await checkout(w, `booking:${b}`, "pending");
      return b;
    };
    await mk({ settlementStatus: "held" }, false); // ordinary held booking
    await mk({ settlementStatus: "held" }, true); // held + pending checkout
    await mk({ settlementStatus: "disputed", status: "disputed" }, true); // disputed + pending checkout
    const unpaid = await booking(w, { status: "pending_payment", paymentStatus: "pending" });
    await checkout(w, `booking:${unpaid}`, "pending"); // unfunded: not this contradiction
    const r = await walkBookings(t);
    expect(r.rental).toBe(4);
    expect(n(r.counts, "settlement=held", "checkout=none", "contradictions=none")).toBe(1);
    expect(n(r.counts, "settlement=held", "checkout=pending_unresolved", "contradictions=funded_with_pending_checkout")).toBe(1);
    expect(n(r.counts, "settlement=disputed", "checkout=pending_unresolved", "contradictions=disputed_status_differs+funded_with_pending_checkout")).toBe(0);
    expect(n(r.counts, "settlement=disputed", "checkout=pending_unresolved", "contradictions=funded_with_pending_checkout")).toBe(1);
    expect(n(r.counts, "settlement=none", "status=pending_payment", "checkout=pending_unresolved", "contradictions=none")).toBe(1);
    expect(r.evidence.rental_bookings_funded_with_pending_checkout).toBe(2);
    expect(r.evidence.rental_bookings_with_unresolved_checkout).toBe(3); // existing tally preserved
  });
});

describe("combined unfunded payment routes (M6b) and open claims on bookings", () => {
  test("an unfunded order with BOTH an open claim and a pending checkout is manual review; with only one it is not", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const both = await order(w, { status: "PENDING_PAYMENT" });
    await claim(w, both, "PENDING_APPROVAL");
    await checkout(w, `vehicle:${both}`, "pending");
    const onlyClaim = await order(w, { status: "PENDING_PAYMENT" });
    await claim(w, onlyClaim, "PENDING_APPROVAL");
    const onlyCheckout = await order(w, { status: "PENDING_PAYMENT" });
    await checkout(w, `vehicle:${onlyCheckout}`, "pending");
    const claimClosed = await order(w, { status: "PENDING_PAYMENT" });
    await claim(w, claimClosed, "REJECTED");
    await checkout(w, `vehicle:${claimClosed}`, "pending"); // closed claim + pending checkout
    const terminalBoth = await settled(w); // balanced terminal with both routes open
    await claim(w, terminalBoth, "PENDING_APPROVAL");
    await checkout(w, `vehicle:${terminalBoth}`, "pending");
    const r = await walkOrders(t);
    expect(total(r.counts)).toBe(5);
    expect(r.exposure).toEqual({
      manual_review: 2, // unfunded both, terminal both
      open_claim: 1, // only a claim
      pending_payment_attempt: 2, // only a checkout; closed claim + checkout
    });
    expect(n(r.counts, "status=PENDING_PAYMENT", "claim=open", "checkout=pending_unresolved", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=SETTLED", "claim=open", "checkout=pending_unresolved", "exposure=manual_review")).toBe(1);
    // evidence tallies are preserved
    expect(r.evidence.orders_with_open_claim).toBe(3);
    expect(r.evidence.orders_with_unresolved_checkout).toBe(4);
  });

  test("open claims on rental bookings and rental orders are discoverable, with counts only", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const claimFor = (extra: Record<string, unknown>) =>
      t.run(async (ctx) =>
        ctx.db.insert("escrow_payment_claims", {
          userId: w.buyer, amount: 100, currency: "SLE", providerId: "p", paymentType: "MANUAL_CLAIM",
          transactionReference: `CLAIMREF-${++seq}`, createdAt: 1, ...extra,
        } as any)
      );
    const heldBooking = await booking(w, { settlementStatus: "held" });
    const unpaidBooking = await booking(w, { status: "pending_payment", paymentStatus: "pending" });
    const inspection = await booking(w, { bookingType: "vehicle_inspection", totalAmount: 0 });
    const rentalOrder = await order(w, { status: "HELD_IN_ESCROW" });
    const purchaseOrder = await t.run(async (ctx) =>
      ctx.db.insert("escrow_orders", {
        orderCode: `PUR-${++seq}`, orderType: "VEHICLE_PURCHASE", renterOrBuyerId: w.buyer, ownerOrSellerId: w.owner, vehicleListingId: w.listing,
        currency: "SLE", baseRentalAmount: 0, refundableDepositAmount: 0, earnestFeeAmount: 0, fullPurchaseAmount: 1, grossEscrowAmount: 1,
        platformFeeAmount: 0, netMerchantExpected: 1, split60ReleasedAmount: 0, split40ReleasedAmount: 0, depositRefundedAmount: 0,
        depositDamageDeductedAmount: 0, status: "PENDING_PAYMENT", createdAt: 1, updatedAt: 1,
      } as any)
    );
    await claimFor({ status: "PENDING_APPROVAL", bookingId: heldBooking as string }); // funded rental booking
    await claimFor({ status: "PENDING_APPROVAL", bookingId: unpaidBooking as string }); // unfunded rental booking
    await claimFor({ status: "PENDING_PAYMENT", bookingId: unpaidBooking as string });
    await claimFor({ status: "PENDING_APPROVAL", escrowOrderId: rentalOrder }); // funded rental order
    await claimFor({ status: "PENDING_APPROVAL", bookingId: "not-a-booking" }); // dangling
    await claimFor({ status: "PENDING_APPROVAL", bookingId: inspection as string }); // not a rental: skipped
    await claimFor({ status: "PENDING_APPROVAL", escrowOrderId: purchaseOrder }); // purchase: skipped
    await claimFor({ status: "APPROVED", bookingId: heldBooking as string }); // closed: not traversed

    const before = await t.run(async (ctx) => JSON.stringify(await ctx.db.query("escrow_payment_claims").collect()));
    const r = await walkClaims(t);
    expect(r.rental).toBe(5);
    expect(r.skipped).toBe(2);
    expect(n(r.counts, "claimStatus=PENDING_APPROVAL", "target=rental_booking", "settlement=held", "funded=yes")).toBe(1);
    expect(n(r.counts, "claimStatus=PENDING_APPROVAL", "target=rental_booking", "settlement=none", "funded=no")).toBe(1);
    expect(n(r.counts, "claimStatus=PENDING_PAYMENT", "target=rental_booking", "settlement=none")).toBe(1);
    expect(n(r.counts, "target=rental_order", "orderStatus=HELD_IN_ESCROW", "funded=yes")).toBe(1);
    expect(n(r.counts, "target=booking_missing")).toBe(1);
    for (const size of [1, 2, 3, 50]) expect((await walkClaims(t, size)).counts, `size ${size}`).toEqual(r.counts);
    expect(await t.run(async (ctx) => JSON.stringify(await ctx.db.query("escrow_payment_claims").collect()))).toBe(before);
    const text = JSON.stringify(r.pages.map((p: any) => ({ ...p, continueCursor: undefined })));
    for (const secret of ["CLAIMREF", "not-a-booking", String(w.buyer), String(heldBooking)]) expect(text).not.toContain(secret);
    await expect(t.query(internal.legacyRentalExposureReport.legacyRentalClaimsPage, { status: "APPROVED" })).rejects.toThrow(/open claim status/i);
  });
});

// ═══════════════════════════════════════════════════════════════════════
// Stage 1C-6E hardening: currency, coverage-cursor integrity, mid-pagination change, page-size bounds.
// Synthetic records only. Expectations are written by hand.
// ═══════════════════════════════════════════════════════════════════════

const ordersPage = (t: T, args: Record<string, unknown>) => t.query(internal.legacyRentalExposureReport.legacyRentalOrdersPage, args as any) as Promise<any>;

describe("6E-1: currency is never mixed into an aggregate", () => {
  test("an escrow row in another currency than its order is manual review and is excluded from held amounts", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const clean = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, clean, 809);
    const mixed = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, mixed, 809, undefined);
    await tx(w, { type: "escrow_lock", amount: 100, currency: "USD", escrowStatus: "locked", referenceType: "vehicle_escrow", referenceId: mixed });
    const p = await ordersPage(t, { status: "HELD_IN_ESCROW" });
    expect(n(p.counts, "reconciliation=currency_mismatch", "exposure=manual_review")).toBe(1);
    expect(n(p.counts, "reconciliation=held", "exposure=funds_held")).toBe(1);
    // only the clean order's 809 is in the aggregate, and it is labelled with its currency
    expect(p.heldAmountByExposure).toEqual({ funds_held: { SLE: 809 } });
    expect(p.evidence.orders_with_currency_mismatch).toBe(1);
    expect(p.evidence.orders_with_unverifiable_amount).toBe(1);
  });

  test("an order labelled in a different currency than its rows is manual review", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const o = await order(w, { status: "HELD_IN_ESCROW", currency: "USD" });
    await lock(w, o, 809); // the row says SLE
    const p = await ordersPage(t, { status: "HELD_IN_ESCROW" });
    expect(n(p.counts, "reconciliation=currency_mismatch", "exposure=manual_review", "currency=USD")).toBe(1);
    expect(p.heldAmountByExposure).toEqual({});
  });

  test("single-currency orders in different currencies are kept apart, never summed", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const a = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, a, 809);
    const b = await order(w, { status: "HELD_IN_ESCROW", currency: "USD", gross: 500 });
    await tx(w, { type: "escrow_lock", amount: 500, currency: "USD", escrowStatus: "locked", referenceType: "vehicle_escrow", referenceId: b });
    const p = await ordersPage(t, { status: "HELD_IN_ESCROW" });
    expect(p.heldAmountByExposure).toEqual({ funds_held: { SLE: 809, USD: 500 } });
    expect(p.ordersByCurrency).toEqual({ SLE: 1, USD: 1 });
    expect(p.evidence.orders_with_currency_mismatch).toBeUndefined();
  });

  test("currency codes are compared exactly: a lower-case or missing code is reported, not merged", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const lower = await order(w, { status: "HELD_IN_ESCROW" });
    await tx(w, { type: "escrow_lock", amount: 809, currency: "sle", escrowStatus: "locked", referenceType: "vehicle_escrow", referenceId: lower });
    const blank = await order(w, { status: "HELD_IN_ESCROW" });
    await tx(w, { type: "escrow_lock", amount: 809, currency: "", escrowStatus: "locked", referenceType: "vehicle_escrow", referenceId: blank });
    const p = await ordersPage(t, { status: "HELD_IN_ESCROW" });
    expect(n(p.counts, "reconciliation=currency_mismatch", "exposure=manual_review")).toBe(2);
    expect(p.heldAmountByExposure).toEqual({});
  });

  test("a payout mirror in another currency, and a claim/checkout/reversal in another currency, are contradictions", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const payoutOrder = await order(w, { status: "PARTIALLY_RELEASED" });
    await lock(w, payoutOrder, 809);
    await release(w, payoutOrder, 180, 27, { currency: "USD" });
    const claimOrder = await order(w, { status: "REFUNDED", currency: "USD" });
    await tx(w, { type: "escrow_lock", amount: 809, currency: "USD", escrowStatus: "locked", referenceType: "vehicle_escrow", referenceId: claimOrder });
    await tx(w, { type: "refund", amount: 809, currency: "USD", escrowStatus: "refunded", referenceType: "vehicle_escrow", referenceId: claimOrder });
    await claim(w, claimOrder, "PENDING_APPROVAL"); // claims are SLE
    const ckOrder = await order(w, { status: "CANCELLED" });
    await checkout(w, `vehicle:${ckOrder}`, "completed");
    const ckBad = await order(w, { status: "CANCELLED", currency: "USD" });
    await tx(w, { type: "top_up", amount: 1, currency: "SLE", referenceType: "escrow_checkout", referenceId: `vehicle:${ckBad}`, status: "failed", gatewayProvider: "MONIME_X", gatewayReference: "g-ck" });
    const r = await walkOrders(t);
    expect(n(r.counts, "status=PARTIALLY_RELEASED", "payout=currency_mismatch", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=REFUNDED", "claim=open+currency_mismatch", "exposure=manual_review")).toBe(1);
    expect(n(r.counts, "status=CANCELLED", "currency=USD", "checkout=failed+currency_mismatch", "exposure=manual_review")).toBe(1);
    expect(r.evidence.orders_with_currency_mismatch).toBe(3);
  });

  test("bookings and claims pages surface currency mismatches and tally declared currencies", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const b = await booking(w, { settlementStatus: "held", status: "confirmed" });
    await tx(w, { type: "escrow_lock", amount: 100, currency: "USD", escrowStatus: "locked", referenceType: "vehicle_rental", referenceId: b });
    const ok = await booking(w, { settlementStatus: "held", status: "confirmed" });
    await tx(w, { type: "escrow_lock", amount: 100, escrowStatus: "locked", referenceType: "vehicle_rental", referenceId: ok });
    const page: any = await t.query(internal.legacyRentalExposureReport.legacyRentalBookingsPage, { source: "settlement:held" });
    expect(n(page.counts, "ledger=currency_mismatch")).toBe(1);
    expect(n(page.counts, "ledger=locked_remaining")).toBe(1);
    expect(page.counts[Object.keys(page.counts).find((k) => k.includes("ledger=currency_mismatch"))!]).toBe(1);
    expect(Object.keys(page.counts).find((k) => k.includes("ledger=currency_mismatch"))).toContain("ledger_currency_mismatch");
    expect(page.evidence.rental_bookings_with_currency_mismatch).toBe(1);
    expect(page.bookingsByCurrency).toEqual({ SLE: 2 });
    // claim on a USD booking: the claim is SLE
    const usd = await booking(w, { settlementStatus: "held", currency: "USD" });
    await t.run(async (ctx) =>
      ctx.db.insert("escrow_payment_claims", {
        bookingId: usd as string, userId: w.buyer, amount: 1, currency: "SLE", providerId: "p", paymentType: "MANUAL_CLAIM",
        transactionReference: `ref-${++seq}`, status: "PENDING_APPROVAL", createdAt: 1,
      } as any)
    );
    const cl: any = await t.query(internal.legacyRentalExposureReport.legacyRentalClaimsPage, { status: "PENDING_APPROVAL" });
    expect(n(cl.counts, "target=rental_booking", "currency=mismatch")).toBe(1);
  });
});

describe("6E-2: coverage cursors cannot be accepted as complete unless the chain is exact", () => {
  // Build collections with small pages so every unit has a multi-page chain.
  async function fixtureCollection() {
    const t = convexTest(schema, modules);
    const w = await world(t);
    for (let i = 0; i < 5; i++) await order(w, { status: "SETTLED" });
    await booking(w, {});
    const pages: any[] = [];
    const walkUnit = async (fn: any, key: string, unit: string, size: number) => {
      let cursor: string | null = null;
      for (let i = 0; i < 50; i++) {
        const p: any = await t.query(fn, { [key]: unit, cursor, numItems: size });
        pages.push(p); cursor = p.continueCursor; if (p.isDone) break;
      }
    };
    for (const s of ALL_STATUSES) await walkUnit(internal.legacyRentalExposureReport.legacyRentalOrdersPage, "status", s, 2);
    for (const s of BOOKING_SOURCES) await walkUnit(internal.legacyRentalExposureReport.legacyRentalBookingsPage, "source", s, 2);
    for (const s of CLAIM_STATUSES) await walkUnit(internal.legacyRentalExposureReport.legacyRentalClaimsPage, "status", s, 2);
    return { t, w, pages };
  }
  const settledPages = (pages: any[]) => pages.filter((p) => p.coverage.kind === "orders" && p.coverage.unit === "SETTLED");

  test("baseline: an exact chain is complete", async () => {
    const { pages } = await fixtureCollection();
    expect(settledPages(pages).length).toBeGreaterThanOrEqual(3);
    expect(assessLegacyRentalCoverage(pages).complete).toBe(true);
  });

  test("a repeated page (same cursor twice) is refused, not summed", async () => {
    const { pages } = await fixtureCollection();
    const dup = [...pages, settledPages(pages)[1]];
    const r = assessLegacyRentalCoverage(dup);
    expect(r.complete).toBe(false);
    expect(r.missingOrders).toEqual(["SETTLED"]);
    expect(r.inconsistentUnits).toEqual(["orders:SETTLED"]);
  });

  test("a stale page from another traversal (cursor not on the chain) is refused", async () => {
    const { pages } = await fixtureCollection();
    const stale = { ...settledPages(pages)[1], cursorIn: "stale-cursor-from-an-earlier-run", continueCursor: "other" };
    const r = assessLegacyRentalCoverage([...pages, stale]);
    expect(r.complete).toBe(false);
    expect(r.inconsistentUnits).toEqual(["orders:SETTLED"]);
  });

  test("a tampered continueCursor breaks the chain at that page", async () => {
    const { pages } = await fixtureCollection();
    const first = settledPages(pages)[0];
    const tampered = pages.map((p) => (p === first ? { ...p, continueCursor: "tampered" } : p));
    const r = assessLegacyRentalCoverage(tampered);
    expect(r.complete).toBe(false);
    expect(r.missingOrders).toEqual(["SETTLED"]);
  });

  test("a looping chain never terminates as complete", async () => {
    const { pages } = await fixtureCollection();
    const sp = settledPages(pages);
    const looped = pages.map((p) => (p === sp[1] ? { ...p, continueCursor: p.cursorIn, isDone: false } : p));
    const r = assessLegacyRentalCoverage(looped.filter((p) => !sp.slice(2).includes(p)));
    expect(r.complete).toBe(false);
    expect(r.missingOrders).toEqual(["SETTLED"]);
  });

  test("a cursor taken from one unit cannot stand in for another unit's start", async () => {
    const { pages } = await fixtureCollection();
    const sp = settledPages(pages);
    // relabel SETTLED's second page as REFUNDED's only page: it starts mid-chain, so REFUNDED has no start
    const foreign = { ...sp[1], coverage: { ...sp[1].coverage, unit: "REFUNDED" } };
    const withoutRefunded = pages.filter((p) => !(p.coverage.kind === "orders" && p.coverage.unit === "REFUNDED"));
    const r = assessLegacyRentalCoverage([...withoutRefunded, foreign]);
    expect(r.complete).toBe(false);
    expect(r.missingOrders).toEqual(["REFUNDED"]);
  });

  test("a page with no cursorIn field does not count as a start", async () => {
    const { pages } = await fixtureCollection();
    const sp = settledPages(pages);
    const noField = pages.map((p) => { if (p !== sp[0]) return p; const { cursorIn: _c, ...rest } = p; return rest; });
    const r = assessLegacyRentalCoverage(noField);
    expect(r.complete).toBe(false);
    expect(r.missingOrders).toEqual(["SETTLED"]);
  });

  test("a missing required unit, an unfinished unit and a missing last page are all incomplete", async () => {
    const { pages } = await fixtureCollection();
    const sp = settledPages(pages);
    expect(assessLegacyRentalCoverage(pages.filter((p) => p !== sp[sp.length - 1])).missingOrders).toEqual(["SETTLED"]); // last page missing
    expect(assessLegacyRentalCoverage(pages.filter((p) => p.coverage.unit !== "settlement:held")).missingBookings).toEqual(["settlement:held"]);
    expect(assessLegacyRentalCoverage(pages.map((p) => (p === sp[sp.length - 1] ? { ...p, isDone: false } : p))).complete).toBe(false);
  });

  test("an unknown unit or an unlabeled page invalidates an otherwise complete collection", async () => {
    const { pages } = await fixtureCollection();
    const unknown = assessLegacyRentalCoverage([...pages, { coverage: { kind: "orders", unit: "SHIPPED" }, isDone: true, cursorIn: null }]);
    expect(unknown.complete).toBe(false);
    expect(unknown.unknownUnits).toEqual(["orders:SHIPPED"]);
    const wrongKind = assessLegacyRentalCoverage([...pages, { coverage: { kind: "hotel_bookings", unit: "x" }, isDone: true, cursorIn: null }]);
    expect(wrongKind.complete).toBe(false);
    const unlabeled = assessLegacyRentalCoverage([...pages, { isDone: true, cursorIn: null }]);
    expect(unlabeled.complete).toBe(false);
    expect(unlabeled.unattributablePages).toBe(1);
  });

  test("the operator-attested check also refuses unknown units", async () => {
    const t = convexTest(schema, modules);
    const r: any = await t.query(internal.legacyRentalExposureReport.legacyRentalCoverageCheck, {
      ordersCompleted: [...ALL_STATUSES, "SHIPPED"], bookingsCompleted: BOOKING_SOURCES, claimsCompleted: CLAIM_STATUSES,
    });
    expect(r.missingOrders).toEqual([]);
    expect(r.unknownUnits).toEqual(["SHIPPED"]);
    expect(r.complete).toBe(false);
  });

  test("a garbage cursor handed to the real queries does not return a page that could be mistaken for a start", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    for (let i = 0; i < 3; i++) await order(w, { status: "SETTLED" });
    let outcome: any;
    try { outcome = await ordersPage(t, { status: "SETTLED", cursor: "not-a-real-cursor", numItems: 2 }); } catch (e) { outcome = { threw: true }; }
    if (!outcome.threw) {
      // if a backend tolerated it, the page still reports the cursor it was given, so it is never a start
      expect(outcome.cursorIn).toBe("not-a-real-cursor");
      expect(assessLegacyRentalCoverage([outcome]).missingOrders).toContain("SETTLED");
    }
  });
});

describe("6E-3: records that change status between pages (NOT a snapshot)", () => {
  test("a record that moves FORWARD into a status not yet visited is counted in both buckets", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const mover = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, mover, 809);
    const stay = await order(w, { status: "HELD_IN_ESCROW" });
    await lock(w, stay, 809);
    // a small page of HELD_IN_ESCROW: the mover is seen as funded and held
    const first = await ordersPage(t, { status: "HELD_IN_ESCROW", numItems: 5 });
    expect(first.scanned).toBe(2);
    // ...then it is fully released and settled before the SETTLED bucket is visited
    await release(w, mover, 180, 27);
    await release(w, mover, 129, 18);
    await refund(w, mover, 500);
    await t.run(async (ctx) => ctx.db.patch(mover, { status: "SETTLED" }));
    const settledBucket = await ordersPage(t, { status: "SETTLED" });
    expect(settledBucket.scanned).toBe(1);
    // total scanned across the traversal = 3 for 2 distinct orders: counted twice, once per bucket
    expect(first.scanned + settledBucket.scanned).toBe(3);
  });

  test("a record that moves BACK into a bucket already walked can be missed entirely (mechanism demonstration)", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const mover = await order(w, { status: "ESCROW_LOCKED" }); // not yet visited
    await lock(w, mover, 809);
    const early = await ordersPage(t, { status: "HELD_IN_ESCROW" }); // visited first
    expect(early.scanned).toBe(0);
    // moved into the already-walked bucket (direct patch: the product lifecycle moves forward, but any
    // such change would be invisible to the traversal)
    await t.run(async (ctx) => ctx.db.patch(mover, { status: "HELD_IN_ESCROW" }));
    const later = await ordersPage(t, { status: "ESCROW_LOCKED" });
    expect(later.scanned).toBe(0);
    // seen in neither bucket: omitted from this traversal
    expect(early.scanned + later.scanned).toBe(0);
  });

  test("within one bucket, a record changing status after its page was read still counts as read; later pages do not see it", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    const ids: Id<"escrow_orders">[] = [];
    for (let i = 0; i < 4; i++) ids.push(await order(w, { status: "SETTLED" }));
    const p1 = await ordersPage(t, { status: "SETTLED", cursor: null, numItems: 2 });
    expect(p1.scanned).toBe(2);
    expect(p1.isDone).toBe(false);
    // the third order is cancelled before page 2 is read
    await t.run(async (ctx) => ctx.db.patch(ids[2], { status: "CANCELLED" }));
    const p2 = await ordersPage(t, { status: "SETTLED", cursor: p1.continueCursor, numItems: 2 });
    expect(p2.scanned).toBe(1); // only the fourth: the cancelled one left the bucket
    // the chain is still unbroken, so the coverage check accepts it for SETTLED even though the data moved
    const chain = [p1, p2.isDone ? p2 : await ordersPage(t, { status: "SETTLED", cursor: p2.continueCursor, numItems: 2 })];
    expect(assessLegacyRentalCoverage(chain).missingOrders).not.toContain("SETTLED");
  });

  test("coverage describes traversal, never consistency: the response says so", async () => {
    const t = convexTest(schema, modules);
    const m: any = await t.query(internal.legacyRentalExposureReport.legacyRentalCoverageManifest, {});
    expect(m.instruction).toContain("Not a transactional snapshot");
  });
});

describe("6E-4: page-size bounds", () => {
  test("MAX_PAGE_SIZE, MAX_PAGE_SIZE + 1 and absurd values never return more than the maximum", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    for (let i = 0; i < 53; i++) await order(w, { status: "CANCELLED" });
    const m: any = await t.query(internal.legacyRentalExposureReport.legacyRentalCoverageManifest, {});
    const max = m.pageSizes.max as number;
    const def = m.pageSizes.default as number;
    expect(max).toBe(50);
    expect(def).toBe(25);
    const scanned = async (numItems: unknown) => (await ordersPage(t, { status: "CANCELLED", ...(numItems === undefined ? {} : { numItems }) })).scanned as number;
    expect(await scanned(undefined)).toBe(def);
    expect(await scanned(max)).toBe(max);
    expect(await scanned(max + 1)).toBe(max);
    expect(await scanned(1_000_000)).toBe(max);
    expect(await scanned(def)).toBe(def);
    expect(await scanned(1)).toBe(1);
  });

  test("zero, negative, fractional and non-finite sizes are clamped to a usable value", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    for (let i = 0; i < 30; i++) await order(w, { status: "CANCELLED" });
    const scanned = async (numItems: number) => (await ordersPage(t, { status: "CANCELLED", numItems })).scanned as number;
    expect(await scanned(0)).toBe(1);
    expect(await scanned(-5)).toBe(1);
    expect(await scanned(2.9)).toBe(2);
    // NaN and Infinity are not valid Convex numbers for the page argument; if the runtime accepts them
    // they fall back to the default / maximum rather than an unbounded page
    for (const bad of [Number.NaN, Number.POSITIVE_INFINITY]) {
      let got: number | "rejected";
      try { got = await scanned(bad); } catch { got = "rejected"; }
      expect(got === "rejected" || (got >= 1 && got <= 50)).toBe(true);
    }
  });

  test("the same bound applies to the bookings and claims pages", async () => {
    const t = convexTest(schema, modules);
    const w = await world(t);
    for (let i = 0; i < 52; i++) await booking(w, {});
    const b: any = await t.query(internal.legacyRentalExposureReport.legacyRentalBookingsPage, { source: "settlement:none", numItems: 51 });
    expect(b.scanned).toBe(50);
    const c: any = await t.query(internal.legacyRentalExposureReport.legacyRentalClaimsPage, { status: "PENDING_PAYMENT", numItems: 51 });
    expect(c.scanned).toBe(0);
  });

  test("an unknown unit is refused rather than returning an empty complete-looking page", async () => {
    const t = convexTest(schema, modules);
    await expect(ordersPage(t, { status: "SHIPPED" })).rejects.toThrow();
    await expect(t.query(internal.legacyRentalExposureReport.legacyRentalBookingsPage, { source: "settlement:unknown" })).rejects.toThrow();
    await expect(t.query(internal.legacyRentalExposureReport.legacyRentalClaimsPage, { status: "APPROVED" })).rejects.toThrow();
  });
});

describe("6E-5: exclusions are explained", () => {
  test("every excluded evidence source has a written explanation in the manifest", async () => {
    const t = convexTest(schema, modules);
    const m: any = await t.query(internal.legacyRentalExposureReport.legacyRentalCoverageManifest, {});
    expect(m.scope.excludes.length).toBeGreaterThan(0);
    for (const id of m.scope.excludes) {
      expect(typeof m.scope.excludesDetail[id]).toBe("string");
      expect(m.scope.excludesDetail[id].length).toBeGreaterThan(20);
    }
    expect(m.scope.excludes).toEqual(expect.arrayContaining(["wallet_level_balances", "provider_side_state", "transactions_outside_in_scope_references"]));
  });
});
