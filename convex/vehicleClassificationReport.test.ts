/// <reference types="vite/client" />
// Stage 1C-6A: the read-only vehicle classification report. Synthetic records only; counts only; no
// database change. Classification follows the STORED fields and never guesses an owner's intent:
// ambiguous, inconsistent and seed-like records get their own buckets for human review.
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";
import {
  categoryPricingContradicts, classifyVehicleListing, DEFAULT_PAGE_SIZE, hasSeedOrLegacySignature, MAX_PAGE_SIZE,
  PER_LISTING_SCAN,
} from "./vehicleClassificationReport";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}) {
  seq += 1;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327960${1000 + seq}`, name, role: role as any,
      isVerified: true, isActive: true, sessionToken: `sess_${name}_${seq}_0123456789abcdef`, updatedAt: Date.now(), ...extra,
    } as any)
  );
  return id;
}
const listing = (t: T, ownerId: Id<"users">, extra: Record<string, unknown>) =>
  t.run(async (ctx) =>
    ctx.db.insert("vehicleListings", {
      ownerId, title: "SECRET-TITLE", category: "car_sale", price: 1000, pricingType: "total_sale", location: "SECRET-PLACE",
      images: [], status: "AVAILABLE", createdAt: Date.now(), updatedAt: Date.now(), isPublished: true, isDeleted: false,
      licensePlate: "SECRET-PLATE", privateContactPhone: "+23200SECRET", ...extra,
    } as any)
  ) as Promise<Id<"vehicleListings">>;

async function runReport(t: T, numItems = 3) {
  const counts: Record<string, number> = {};
  const byClass: Record<string, number> = {};
  const pages: any[] = [];
  let cursor: string | null = null;
  let scanned = 0;
  for (let i = 0; i < 1000; i++) {
    const page: any = await t.query(internal.vehicleClassificationReport.classificationPage, { cursor, numItems });
    pages.push(page);
    scanned += page.scanned;
    for (const [k, n] of Object.entries(page.counts as Record<string, number>)) counts[k] = (counts[k] ?? 0) + n;
    for (const [k, n] of Object.entries(page.byClass as Record<string, number>)) byClass[k] = (byClass[k] ?? 0) + n;
    cursor = page.continueCursor;
    if (page.isDone) break;
  }
  return { counts, byClass, pages, scanned };
}

describe("pure classification rules", () => {
  const c = (o: Record<string, unknown>) => classifyVehicleListing({ category: "car_sale", pricingType: "total_sale", ...o } as any);
  test("each bucket, in evaluation order", () => {
    expect(c({})).toBe("sale_standard");
    expect(c({ category: "delivery_van" })).toBe("sale_commercial");
    expect(c({ category: "car_rental" })).toBe("sale_commercial"); // contradictory, flagged separately
    expect(c({ category: "car_rental", pricingType: "per_day", pricePerDay: 100 })).toBe("hire_daily_car");
    expect(c({ category: "delivery_van", pricingType: "per_day", pricePerDay: 100 })).toBe("hire_or_service_van");
    expect(c({ category: "sand_dump_truck", pricingType: "per_trip" })).toBe("haulage_service");
    expect(c({ category: "container_freight_truck", pricingType: "per_trip" })).toBe("haulage_service");
    // a sale price exists under hire pricing and no daily price: possible sale, needs review
    expect(c({ category: "delivery_van", pricingType: "per_day", salePrice: 5000 })).toBe("sale_intent_under_hire_pricing");
    // seed / pre-fleet signature wins over the hire buckets
    expect(c({ category: "car_rental", pricingType: "per_day", salePrice: 1, pricePerDay: 2 })).toBe("seed_or_demo_signature");
    expect(c({ category: "delivery_van", pricingType: "per_trip", listingIntent: "rental" })).toBe("seed_or_demo_signature");
    expect(c({ category: "delivery_van", pricingType: "per_trip", vehicleType: "delivery_van" })).toBe("seed_or_demo_signature");
    // everything else is flagged, not guessed
    expect(c({ category: "car_sale", pricingType: "per_day", pricePerDay: 1 })).toBe("inconsistent_or_other");
    expect(c({ category: "delivery_van", pricingType: "per_trip" })).toBe("inconsistent_or_other");
    expect(c({ category: "sand_dump_truck", pricingType: "per_day", pricePerDay: 1 })).toBe("inconsistent_or_other");
  });
  test("seed signature and contradiction helpers", () => {
    expect(hasSeedOrLegacySignature({ salePrice: 1, pricePerDay: 2 } as any)).toBe(true);
    expect(hasSeedOrLegacySignature({ salePrice: 1 } as any)).toBe(false);
    expect(hasSeedOrLegacySignature({ listingIntent: "sale" } as any)).toBe(true);
    expect(categoryPricingContradicts({ category: "car_rental", pricingType: "total_sale" })).toBe(true);
    expect(categoryPricingContradicts({ category: "car_sale", pricingType: "per_day" })).toBe(true);
    expect(categoryPricingContradicts({ category: "delivery_van", pricingType: "per_day" })).toBe(false);
  });
});

describe("classificationPage report", () => {
  test("counts every bucket with lifecycle, owner class and open transactions; returns counts only; changes nothing", async () => {
    const t = convexTest(schema, modules);
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const buyer = await makeUser(t, "buyer");
    const admin = await makeUser(t, "admin", "admin");
    const ghost = await makeUser(t, "ghost");
    await t.run(async (ctx) => ctx.db.delete(ghost));

    const sale = await listing(t, dealer, {});
    await listing(t, dealer, { category: "delivery_van" }); // sale_commercial
    await listing(t, dealer, { category: "car_rental", pricingType: "total_sale" }); // contradictory
    const hire = await listing(t, dealer, { category: "car_rental", pricingType: "per_day", pricePerDay: 100 });
    await listing(t, dealer, { category: "delivery_van", pricingType: "per_day", pricePerDay: 100 });
    await listing(t, dealer, { category: "sand_dump_truck", pricingType: "per_trip" });
    await listing(t, dealer, { category: "delivery_van", pricingType: "per_day", salePrice: 5000 });
    await listing(t, admin, { category: "car_rental", pricingType: "per_day", salePrice: 1, pricePerDay: 2, listingIntent: "rental" });
    await listing(t, dealer, { category: "car_sale", pricingType: "per_day", pricePerDay: 1 });
    await listing(t, ghost, { isDeleted: true, status: "TAKEN_DOWN" });
    await listing(t, dealer, { isPublished: false });
    await listing(t, dealer, { status: "SOLD" });

    // open transactions: a rental order and an open vehicle_rental booking on the hire listing, a
    // purchase order and a free inspection on the sale listing
    await t.run(async (ctx) => {
      const base = {
        currency: "SLE", baseRentalAmount: 0, refundableDepositAmount: 0, earnestFeeAmount: 0, fullPurchaseAmount: 0,
        grossEscrowAmount: 1, platformFeeAmount: 0, netMerchantExpected: 1, split60ReleasedAmount: 0, split40ReleasedAmount: 0,
        depositRefundedAmount: 0, depositDamageDeductedAmount: 0, createdAt: 1, updatedAt: 1,
        renterOrBuyerId: buyer, ownerOrSellerId: dealer,
      };
      await ctx.db.insert("escrow_orders", { ...base, orderCode: "R-1", orderType: "VEHICLE_RENTAL", vehicleListingId: hire, status: "HELD_IN_ESCROW" } as any);
      await ctx.db.insert("escrow_orders", { ...base, orderCode: "P-1", orderType: "VEHICLE_PURCHASE", vehicleListingId: sale, status: "PENDING_PAYMENT" } as any);
      const bk = { currency: "SLE", buyerId: buyer as string, vendorId: dealer as string, listingType: "vehicle", listingTitle: "x", startTime: 1, endTime: 2, subtotal: 0, serviceFee: 0, totalAmount: 0, paymentStatus: "completed", updatedAt: 1 };
      // a paid rental whose funds are held (a free confirmed record would be a free visit, not an obligation)
      await ctx.db.insert("bookings", { ...bk, txRef: "b1", listingId: hire as string, bookingType: "vehicle_rental", status: "confirmed", totalAmount: 100, settlementStatus: "held", escrowId: "esc-1" } as any);
      await ctx.db.insert("bookings", { ...bk, txRef: "b2", listingId: sale as string, bookingType: "vehicle_inspection", status: "confirmed" } as any);
    });

    const before = await t.run(async (ctx) => JSON.stringify([
      await ctx.db.query("vehicleListings").collect(), await ctx.db.query("escrow_orders").collect(),
      await ctx.db.query("bookings").collect(), await ctx.db.query("users").collect(),
    ]));
    const { counts, byClass, pages, scanned } = await runReport(t, 5); // several pages
    expect(pages.length).toBeGreaterThan(1);
    expect(scanned).toBe(12);

    expect(byClass).toEqual({
      sale_standard: 4, // sale, sold, unpublished, deleted/taken-down (owner missing)
      sale_commercial: 2,
      hire_daily_car: 1,
      hire_or_service_van: 1,
      haulage_service: 1,
      sale_intent_under_hire_pricing: 1,
      seed_or_demo_signature: 1,
      inconsistent_or_other: 1,
    });
    const find = (frag: string) => Object.entries(counts).filter(([k]) => frag.split("&").every((f) => k.includes(f)));
    // the open rental order + open rental booking are visible on the hire listing only
    expect(find("class=hire_daily_car&rentalOrders=open&rentalBookings=open")).toHaveLength(1);
    expect(find("rentalOrders=open")).toHaveLength(1);
    expect(find("class=sale_standard&purchaseOrders=open&inspections=any")).toHaveLength(1);
    // contradictory category/pricing is flagged, and so is the seed-like row (counted separately)
    expect(find("consistent=no").reduce((n, [, c]) => n + c, 0)).toBe(2);
    expect(find("provenance=seed_or_legacy_signature").reduce((n, [, c]) => n + c, 0)).toBe(1 + 0 + 0 + 0 + 0 + 0 + 0);
    // lifecycle and owner classes
    expect(find("lifecycle=sold")).toHaveLength(1);
    expect(find("lifecycle=unpublished")).toHaveLength(1);
    expect(find("lifecycle=deleted").length + find("lifecycle=taken_down").length).toBeGreaterThan(0);
    expect(find("owner=missing")).toHaveLength(1);
    expect(find("owner=admin")).toHaveLength(1);
    expect(find("owner=dealer_capability").reduce((n, [, c]) => n + c, 0)).toBe(10);

    // counts only: nothing identifying is returned (the opaque cursor is excluded from this check)
    const text = JSON.stringify(pages.map((p) => ({ ...p, continueCursor: undefined })));
    for (const secret of ["SECRET-TITLE", "SECRET-PLACE", "SECRET-PLATE", "SECRET", String(dealer), String(buyer), String(hire), String(sale)]) {
      expect(text).not.toContain(secret);
    }
    // read-only: listings, orders, bookings and users are byte-identical afterwards
    const after = await t.run(async (ctx) => JSON.stringify([
      await ctx.db.query("vehicleListings").collect(), await ctx.db.query("escrow_orders").collect(),
      await ctx.db.query("bookings").collect(), await ctx.db.query("users").collect(),
    ]));
    expect(after).toBe(before);
  });

  test("page size is bounded", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    for (let i = 0; i < 3; i++) await listing(t, owner, {});
    const page: any = await t.query(internal.vehicleClassificationReport.classificationPage, { cursor: null, numItems: 100000 });
    expect(page.scanned).toBe(3);
    expect(page.isDone).toBe(true);
  });
});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Stage 1C-6A hardening: page limits and COMPLETE vs SAMPLED outstanding-transaction counts.
// ─────────────────────────────────────────────────────────────────────────────────────────────
const insertOrder = (t: T, o: { listing: Id<"vehicleListings">; buyer: Id<"users">; owner: Id<"users">; type: string; status: string; at: number; code: string }) =>
  t.run(async (ctx) =>
    ctx.db.insert("escrow_orders", {
      orderCode: o.code, orderType: o.type, renterOrBuyerId: o.buyer, ownerOrSellerId: o.owner, vehicleListingId: o.listing,
      currency: "SLE", baseRentalAmount: 0, refundableDepositAmount: 0, earnestFeeAmount: 0, fullPurchaseAmount: 0,
      grossEscrowAmount: 1, platformFeeAmount: 0, netMerchantExpected: 1, split60ReleasedAmount: 0, split40ReleasedAmount: 0,
      depositRefundedAmount: 0, depositDamageDeductedAmount: 0, status: o.status, createdAt: o.at, updatedAt: o.at,
    } as any)
  );
const insertBooking = (
  t: T,
  b: {
    listing: string; listingType?: string; buyer: Id<"users">; owner: Id<"users">; type: string; status: string; at: number;
    settlement?: string; payment?: string; amount?: number; escrowId?: string;
  }
) =>
  t.run(async (ctx) =>
    ctx.db.insert("bookings", {
      listingId: b.listing, listingType: b.listingType ?? "vehicle", listingTitle: "x", buyerId: b.buyer as string, vendorId: b.owner as string,
      bookingType: b.type, status: b.status, startTime: b.at, endTime: b.at + 1, subtotal: 0, serviceFee: 0, totalAmount: b.amount ?? 0,
      currency: "SLE", paymentStatus: b.payment ?? "completed", updatedAt: b.at,
      ...(b.settlement ? { settlementStatus: b.settlement } : {}), ...(b.escrowId ? { escrowId: b.escrowId } : {}),
    } as any)
  );
async function onePage(t: T, numItems?: number, cursor: string | null = null) {
  return (await t.query(internal.vehicleClassificationReport.classificationPage, numItems === undefined ? { cursor } : { cursor, numItems })) as any;
}
// Written out here ON PURPOSE (not imported from the report) so a wrong list in the report is caught.
const ORDER_OUTSTANDING = ["INITIATED", "PENDING_PAYMENT", "HELD_IN_ESCROW", "ESCROW_LOCKED", "PARTIALLY_RELEASED", "POST_INSPECTION_PENDING", "DISPUTED"];
// The three disjoint settlement ranges (written out here on purpose).
const BOOKING_SOURCES = ["settlement:none", "settlement:held", "settlement:disputed"];
async function openTotals(t: T, kind: "orders" | "bookings", numItems = 7) {
  const statuses = kind === "orders" ? ORDER_OUTSTANDING : BOOKING_SOURCES;
  const counts: Record<string, number> = {};
  let scanned = 0;
  let scope: any = null;
  for (const status of statuses) {
    let cursor: string | null = null;
    for (let i = 0; i < 200; i++) {
      const p: any = await t.query(internal.vehicleClassificationReport.openTransactionsPage, { kind, status, cursor, numItems });
      scanned += p.scanned;
      scope = p.scope;
      for (const [k, n] of Object.entries(p.counts as Record<string, number>)) counts[k] = (counts[k] ?? 0) + n;
      cursor = p.continueCursor;
      if (p.isDone) break;
    }
  }
  return { counts, scanned, scope };
}

describe("page size limits", () => {
  test("documented constants", () => {
    expect(DEFAULT_PAGE_SIZE).toBe(50);
    expect(MAX_PAGE_SIZE).toBe(100);
    expect(PER_LISTING_SCAN).toBe(10);
  });
  test("default 50, maximum 100, lower bound 1; every page size visits each listing exactly once", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const classes = [
      {}, { category: "delivery_van" }, { category: "car_rental", pricingType: "per_day", pricePerDay: 5 },
      { category: "delivery_van", pricingType: "per_day", pricePerDay: 5 }, { category: "sand_dump_truck", pricingType: "per_trip" },
      { category: "delivery_van", pricingType: "per_day", salePrice: 9 }, { category: "car_sale", pricingType: "per_day", pricePerDay: 1 },
    ];
    for (let i = 0; i < 130; i++) await listing(t, owner, classes[i % classes.length]);

    expect((await onePage(t)).scanned).toBe(50); // default
    expect((await onePage(t, 100)).scanned).toBe(100);
    expect((await onePage(t, 100000)).scanned).toBe(100); // maximum
    expect((await onePage(t, 0)).scanned).toBe(1); // lower bound
    expect((await onePage(t, -5)).scanned).toBe(1);
    expect((await onePage(t, 7.9)).scanned).toBe(7);

    const baseline = await runReport(t, 100);
    for (const size of [1, 7, 33, 50, 100]) {
      const r = await runReport(t, size);
      expect(r.scanned, `page size ${size}`).toBe(130); // none skipped, none duplicated
      expect(r.counts, `page size ${size}`).toEqual(baseline.counts);
      expect(r.byClass).toEqual(baseline.byClass);
      expect(Object.values(r.counts).reduce((a, n) => a + n, 0)).toBe(130);
    }
  });
});

describe("outstanding transactions: complete totals vs sampled per-listing flags", () => {
  test("a listing with more records than the per-listing read cap is 'unknown' (never 'none'); the authoritative totals still count the older outstanding ones", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const buyer = await makeUser(t, "buyer");
    const hire = { category: "car_rental", pricingType: "per_day", pricePerDay: 100 };
    // OLD outstanding rental order, then 30 NEWER closed ones  -> outside the 10 most recent
    const oldOpen = await listing(t, owner, hire);
    // NEW outstanding order after 30 older closed ones           -> inside the 10 most recent
    const newOpen = await listing(t, owner, hire);
    // exactly 10 closed orders (= the cap)                        -> every record read, none open
    const fewClosed = await listing(t, owner, hire);
    // > 10 closed bookings and an OLD open rental booking         -> bookings flag unknown
    const oldOpenBooking = await listing(t, owner, hire);
    // mixed: open purchase order among recent, closed rental orders
    const mixed = await listing(t, owner, {});

    await insertOrder(t, { listing: oldOpen, buyer, owner, type: "VEHICLE_RENTAL", status: "HELD_IN_ESCROW", at: 1, code: "A-0" });
    for (let k = 1; k <= 30; k++) await insertOrder(t, { listing: oldOpen, buyer, owner, type: "VEHICLE_RENTAL", status: "SETTLED", at: 1 + k, code: `A-${k}` });
    for (let k = 0; k < 30; k++) await insertOrder(t, { listing: newOpen, buyer, owner, type: "VEHICLE_RENTAL", status: "REFUNDED", at: 1 + k, code: `B-${k}` });
    await insertOrder(t, { listing: newOpen, buyer, owner, type: "VEHICLE_RENTAL", status: "PARTIALLY_RELEASED", at: 100, code: "B-open" });
    for (let k = 0; k < 10; k++) await insertOrder(t, { listing: fewClosed, buyer, owner, type: "VEHICLE_RENTAL", status: "CANCELLED", at: 1 + k, code: `C-${k}` });
    await insertBooking(t, { listing: oldOpenBooking as string, buyer, owner, type: "vehicle_rental", status: "confirmed", at: 1, settlement: "held", amount: 300, escrowId: "esc-old" });
    for (let k = 1; k <= 30; k++) await insertBooking(t, { listing: oldOpenBooking as string, buyer, owner, type: "vehicle_rental", status: "completed", at: 1 + k, settlement: "released", amount: 300, escrowId: `esc-${k}` });
    await insertOrder(t, { listing: mixed, buyer, owner, type: "VEHICLE_PURCHASE", status: "DISPUTED", at: 5, code: "M-1" });
    await insertOrder(t, { listing: mixed, buyer, owner, type: "VEHICLE_RENTAL", status: "SETTLED", at: 4, code: "M-2" });
    // outstanding transactions that are NOT on vehicle listings are ignored by the vehicle totals
    await insertBooking(t, { listing: "some-property-id", listingType: "property", buyer, owner, type: "property_inspection", status: "confirmed", at: 9 });

    const before = await t.run(async (ctx) => JSON.stringify([
      await ctx.db.query("escrow_orders").collect(), await ctx.db.query("bookings").collect(), await ctx.db.query("vehicleListings").collect(),
    ]));
    const report = await runReport(t, 100);
    const find = (frag: string) => Object.entries(report.counts).filter(([k]) => frag.split("&").every((f) => k.includes(f))).reduce((n, [, c]) => n + c, 0);

    // per-listing flags (sampled, honest about it)
    expect(find("rentalOrders=open")).toBe(1); // newOpen: the open one is among the 10 most recent
    expect(find("rentalOrders=unknown")).toBe(1); // oldOpen: 31 records, none open in the newest 10 => NOT "none"
    expect(find("rentalOrders=none")).toBe(3); // fewClosed + oldOpenBooking + mixed (all records read)
    expect(find("purchaseOrders=open")).toBe(1); // mixed
    expect(find("rentalBookings=unknown")).toBe(1); // oldOpenBooking: 31 bookings, none open in the newest 10
    expect(find("rentalBookings=open")).toBe(0);
    const unknownListings = report.pages.reduce((n, p) => n + p.unknownListings, 0);
    // listings with at least one unknown flag: oldOpen (rental + purchase orders), newOpen (its purchase
    // flag: 31 orders, none an open purchase in the newest 10) and oldOpenBooking (bookings)
    expect(find("purchaseOrders=unknown")).toBe(2);
    expect(unknownListings).toBe(3);

    // authoritative totals (independent of the cap): every outstanding order and booking is counted
    const orders = await openTotals(t, "orders");
    const rental = (cls: string, status: string) => orders.counts[`scope=escrow_orders_table_only|kind=orders|status=${status}|type=VEHICLE_RENTAL|listingClass=${cls}|lifecycle=active`] ?? 0;
    expect(rental("hire_daily_car", "HELD_IN_ESCROW")).toBe(1); // the OLD one the sample cannot see
    expect(rental("hire_daily_car", "PARTIALLY_RELEASED")).toBe(1);
    expect(orders.counts["scope=escrow_orders_table_only|kind=orders|status=DISPUTED|type=VEHICLE_PURCHASE|listingClass=sale_standard|lifecycle=active"]).toBe(1);
    expect(Object.values(orders.counts).reduce((a, n) => a + n, 0)).toBe(3); // closed ones are not counted
    expect(orders.scanned).toBe(3);

    const bookings = await openTotals(t, "bookings");
    const held = Object.entries(bookings.counts).filter(([k]) => k.includes("obligation=funds_held") && k.includes("type=vehicle_rental") && k.includes("listingClass=hire_daily_car"));
    expect(held.reduce((n, [, c]) => n + c, 0)).toBe(1); // the OLD held booking the sample cannot see
    const visits = Object.entries(bookings.counts).filter(([k]) => k.includes("group=free_visit") && k.includes("type=property_inspection") && k.includes("listingClass=not_vehicle"));
    expect(visits.reduce((n, [, c]) => n + c, 0)).toBe(1); // a free property visit is NOT a financial obligation
    expect(Object.values(bookings.counts).reduce((a, n) => a + n, 0)).toBe(2); // the 30 released ones are not counted
    expect(bookings.scope).toMatchObject({ table: "bookings", scopeLabel: "bookings_table_only" });

    // same totals at every page size; nothing written
    for (const size of [1, 2, 100]) {
      expect((await openTotals(t, "orders", size)).counts).toEqual(orders.counts);
      expect((await openTotals(t, "bookings", size)).counts).toEqual(bookings.counts);
    }
    const after = await t.run(async (ctx) => JSON.stringify([
      await ctx.db.query("escrow_orders").collect(), await ctx.db.query("bookings").collect(), await ctx.db.query("vehicleListings").collect(),
    ]));
    expect(after).toBe(before);
    // no identifying text anywhere in the totals
    const text = JSON.stringify([orders, bookings]);
    for (const secret of ["A-0", "B-open", "SECRET", String(buyer), String(owner), String(oldOpen)]) expect(text).not.toContain(secret);
  });

  test("a listing's flags never depend on page size or page boundaries; the cap is exact (cap = complete, cap + 1 = unknown)", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const buyer = await makeUser(t, "buyer");
    const hire = { category: "car_rental", pricingType: "per_day", pricePerDay: 100 };
    const counts = [0, 3, PER_LISTING_SCAN, PER_LISTING_SCAN + 1, PER_LISTING_SCAN + 5];
    for (let i = 0; i < 30; i++) {
      const id = await listing(t, owner, hire);
      const n = counts[i % counts.length];
      for (let k = 0; k < n; k++) await insertOrder(t, { listing: id, buyer, owner, type: "VEHICLE_RENTAL", status: "SETTLED", at: k, code: `X-${i}-${k}` });
    }
    const baseline = await runReport(t, 100);
    const sum = (frag: string, c: Record<string, number>) => Object.entries(c).filter(([k]) => k.includes(frag)).reduce((n, [, x]) => n + x, 0);
    // 30 listings, 6 of each count: <= cap (0, 3, 10) are fully read => none; > cap (11, 15) => unknown
    expect(sum("rentalOrders=none", baseline.counts)).toBe(18);
    expect(sum("rentalOrders=unknown", baseline.counts)).toBe(12);
    for (const size of [1, 4, 9, 30, 100]) {
      const r = await runReport(t, size);
      expect(r.counts, `page size ${size}`).toEqual(baseline.counts);
    }
    const p = await onePage(t, 100);
    expect(p.unknownListings).toBe(12);
    // never more than cap + 1 reads per type per listing
    expect(p.transactionReads).toBeLessThanOrEqual(30 * 2 * (PER_LISTING_SCAN + 1));
  });

  test("openTransactionsPage accepts only outstanding statuses and is internal", async () => {
    const t = convexTest(schema, modules);
    await expect(
      t.query(internal.vehicleClassificationReport.openTransactionsPage, { kind: "orders", status: "SETTLED" })
    ).rejects.toThrow(/outstanding order status/i);
    for (const bad of ["completed", "status:completed", "status:declined", "settlement:released", "confirmed"]) {
      await expect(
        t.query(internal.vehicleClassificationReport.openTransactionsPage, { kind: "bookings", status: bad })
      ).rejects.toThrow(/booking count source/i);
    }
    const p: any = await t.query(internal.vehicleClassificationReport.openTransactionsPage, { kind: "orders", status: "HELD_IN_ESCROW" });
    expect(p).toMatchObject({ scanned: 0, counts: {}, isDone: true });
    expect(p.scope).toMatchObject({ table: "escrow_orders", scopeLabel: "escrow_orders_table_only" });
  });
});

// ─────────────────────────────────────────────────────────────────────────────────────────────
// Booking obligations (settlement-based enumeration). Every case is written out by hand with the
// category it must land in and WHY. Nothing here imports the report's classifier or status lists.
// ─────────────────────────────────────────────────────────────────────────────────────────────
type Esc = "locked" | "released" | "refunded" | "unrecorded" | "missing" | "other_booking" | undefined;
type Case = {
  name: string;
  status: string;
  type?: string;
  listingType?: string;
  payment?: string;
  amount?: number;
  settlement?: string;
  escrow?: Esc; // which escrow id the booking carries
  listing?: string;
  group: "financial_outstanding" | "unpaid" | "free_visit" | "closed" | "unresolved_candidate" | "anomaly";
  obligation: string;
  consistency?: string;
  counted: boolean; // does a full traversal return it?
  why: string;
};
const CASES: Case[] = [
  // ---- no settlement record, free
  { name: "free completed", status: "completed", amount: 0, group: "closed", obligation: "closed_completed", counted: true, why: "no money ever; finished" },
  { name: "free declined", status: "declined", amount: 0, listingType: "property", type: "property_inspection", group: "closed", obligation: "closed_declined", counted: true, why: "free viewing declined" },
  { name: "free cancelled", status: "cancelled", amount: 0, group: "closed", obligation: "closed_cancelled", counted: true, why: "free, cancelled" },
  { name: "free vehicle inspection stays confirmed", status: "confirmed", amount: 0, type: "vehicle_inspection", group: "free_visit", obligation: "free_visit_confirmed", counted: true, why: "free: confirmed is simply where it stays" },
  { name: "free visit requested", status: "requested", amount: 0, listingType: "property", type: "property_inspection", group: "free_visit", obligation: "free_visit_requested", counted: true, why: "awaiting owner, no money" },
  { name: "free booking that carries an escrow id", status: "confirmed", amount: 0, escrow: "locked", group: "anomaly", obligation: "anomaly_free_with_escrow_id", counted: true, why: "a free booking should have no escrow" },
  // ---- no settlement record, unpaid
  { name: "abandoned unpaid pending_payment", status: "pending_payment", amount: 100, payment: "pending", type: "vehicle_rental", group: "unpaid", obligation: "unpaid_pending_payment", counted: true, why: "no money moved, never expires" },
  { name: "unpaid and cancelled", status: "cancelled", amount: 100, payment: "pending", type: "vehicle_rental", group: "closed", obligation: "closed_cancelled_unpaid", counted: true, why: "never paid" },
  { name: "unpaid but carries an escrow id", status: "pending_payment", amount: 100, payment: "pending", escrow: "locked", group: "anomaly", obligation: "anomaly_escrow_id_without_payment", counted: true, why: "escrow id without a payment" },
  { name: "refunded payment with no settlement record", status: "cancelled", amount: 100, payment: "refunded", group: "anomaly", obligation: "anomaly_refunded_without_settlement", counted: true, why: "nothing proves the refund" },
  // ---- no settlement record, paid, no escrow id (old flow)
  { name: "old paid booking, confirmed, no escrow", status: "confirmed", amount: 100, payment: "completed", type: "vehicle_rental", group: "anomaly", obligation: "anomaly_paid_without_escrow_unverified", counted: true, why: "paid but money location unknown" },
  { name: "old paid booking, cancelled without refund evidence", status: "cancelled", amount: 100, payment: "completed", type: "vehicle_rental", group: "anomaly", obligation: "anomaly_cancelled_paid_without_refund_evidence", counted: true, why: "paid, cancelled, nothing shows a refund" },
  { name: "old paid booking, completed", status: "completed", amount: 100, payment: "completed", type: "vehicle_rental", group: "anomaly", obligation: "anomaly_terminal_paid_without_settlement", counted: true, why: "terminal status with money fields" },
  { name: "old paid booking, declined", status: "declined", amount: 100, payment: "completed", type: "vehicle_rental", group: "anomaly", obligation: "anomaly_terminal_paid_without_settlement", counted: true, why: "declined can hold no money by design" },
  { name: "paid yet pending_payment", status: "pending_payment", amount: 100, payment: "completed", type: "vehicle_rental", group: "anomaly", obligation: "anomaly_paid_but_pending_payment", counted: true, why: "payment and status contradict" },
  // ---- no settlement record, paid, escrow id: decided by the escrow transaction
  { name: "paid, escrow verified LOCKED, confirmed", status: "confirmed", amount: 100, payment: "completed", escrow: "locked", group: "financial_outstanding", obligation: "verified_funds_locked_no_settlement", counted: true, why: "the escrow transaction is locked: money is held" },
  { name: "paid, escrow verified LOCKED, status completed", status: "completed", amount: 100, payment: "completed", escrow: "locked", group: "financial_outstanding", obligation: "verified_funds_locked_no_settlement", consistency: "status_terminal_but_funds_held", counted: true, why: "locked escrow beats a terminal status" },
  { name: "paid, escrow already RELEASED", status: "confirmed", amount: 100, payment: "completed", escrow: "released", group: "closed", obligation: "closed_escrow_closed_no_settlement", counted: true, why: "money already paid out; only the booking record is incomplete" },
  { name: "paid, escrow already REFUNDED", status: "cancelled", amount: 100, payment: "completed", escrow: "refunded", group: "closed", obligation: "closed_escrow_closed_no_settlement", counted: true, why: "money already returned" },
  { name: "paid, escrow transaction missing", status: "confirmed", amount: 100, payment: "completed", escrow: "missing", group: "anomaly", obligation: "anomaly_escrow_missing_or_invalid", counted: true, why: "the escrow id resolves to nothing valid" },
  { name: "paid, escrow transaction belongs to another booking", status: "confirmed", amount: 100, payment: "completed", escrow: "other_booking", group: "anomaly", obligation: "anomaly_escrow_missing_or_invalid", counted: true, why: "not this booking's escrow, so it proves nothing" },
  { name: "paid, escrow status not recorded", status: "confirmed", amount: 100, payment: "completed", escrow: "unrecorded", group: "anomaly", obligation: "anomaly_escrow_state_unknown", counted: true, why: "a valid lock whose state is unknown" },
  // ---- settlement record present
  { name: "settlement held, status confirmed", status: "confirmed", amount: 100, payment: "completed", settlement: "held", escrow: "locked", group: "financial_outstanding", obligation: "funds_held", counted: true, why: "the settlement record says held" },
  { name: "settlement held, status completed", status: "completed", amount: 100, payment: "completed", settlement: "held", escrow: "locked", group: "financial_outstanding", obligation: "funds_held", consistency: "status_terminal_but_funds_held", counted: true, why: "settlement wins over status" },
  { name: "settlement disputed, status declined", status: "declined", amount: 100, payment: "completed", settlement: "disputed", escrow: "locked", group: "financial_outstanding", obligation: "funds_disputed", consistency: "status_terminal_but_funds_held", counted: true, why: "frozen funds under a terminal status" },
  { name: "held booking whose listing reference is invalid", status: "confirmed", amount: 100, payment: "completed", settlement: "held", escrow: "locked", listing: "not-a-real-id", type: "vehicle_inspection", group: "financial_outstanding", obligation: "funds_held", counted: true, why: "money held whatever its listing" },
  // ---- settled: not enumerated
  { name: "released and completed", status: "completed", amount: 100, payment: "completed", settlement: "released", escrow: "released", group: "closed", obligation: "closed_released", counted: false, why: "settled; the released range is not traversed" },
  { name: "refunded and cancelled", status: "cancelled", amount: 100, payment: "refunded", settlement: "refunded", escrow: "refunded", group: "closed", obligation: "closed_refunded", counted: false, why: "settled; the refunded range is not traversed" },
];

describe("booking obligations: disjoint settlement ranges, escrow verified", () => {
  async function seed(t: T) {
    const owner = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const buyer = await makeUser(t, "buyer");
    const car = (await listing(t, owner, {})) as string; // a real, active sale listing
    const walletId = await t.run(async (ctx) =>
      ctx.db.insert("walletBalances", { userId: buyer, availableBalance: 0, pendingBalance: 0, currency: "SLE", updatedAt: 1 } as any)
    );
    const otherBooking = await insertBooking(t, { listing: car, buyer, owner, type: "vehicle_inspection", status: "confirmed", at: 1 });
    for (const [i, c] of CASES.entries()) {
      const bookingId = await insertBooking(t, {
        listing: c.listing ?? (c.listingType === "property" ? "property-ref" : car), listingType: c.listingType, buyer, owner,
        type: c.type ?? "hourly_guesthouse", status: c.status, at: 100 + i, settlement: c.settlement, payment: c.payment ?? "completed",
        amount: c.amount ?? 0,
      });
      if (c.escrow) {
        let escrowId: string;
        if (c.escrow === "missing") {
          escrowId = String(buyer); // a real id of another table: does not resolve to a transaction
        } else {
          const txId = await t.run(async (ctx) =>
            ctx.db.insert("transactions", {
              walletId, userId: buyer, type: "escrow_lock", amount: 100, currency: "SLE", referenceType: "booking",
              referenceId: c.escrow === "other_booking" ? String(otherBooking) : String(bookingId),
              status: "completed", updatedAt: 1,
              ...(c.escrow === "unrecorded" ? {} : { escrowStatus: c.escrow === "other_booking" ? "locked" : c.escrow }),
            } as any)
          );
          escrowId = String(txId);
        }
        await t.run(async (ctx) => ctx.db.patch(bookingId, { escrowId } as any));
      }
    }
    return { owner, buyer, car };
  }
  // exact key-part matching ("closed_cancelled" must not also match "closed_cancelled_unpaid")
  const sum = (counts: Record<string, number>, frag: string[]) =>
    Object.entries(counts)
      .filter(([k]) => { const parts = new Set(k.split("|")); return frag.every((x) => parts.has(x)); })
      .reduce((a, [, v]) => a + v, 0);

  test("every case lands in its documented category, exactly once", async () => {
    const t = convexTest(schema, modules);
    await seed(t);
    const totals = await openTotals(t, "bookings", 4);
    // one extra row exists for the "belongs to another booking" fixture: a free confirmed inspection
    const counted = CASES.filter((c) => c.counted).length + 1;
    expect(Object.values(totals.counts).reduce((a, n) => a + n, 0), "no booking counted twice or dropped").toBe(counted);
    expect(totals.scanned).toBe(counted);

    // per case: the (group, obligation, status, consistency) combination appears exactly as many times
    // as the hand-written table says
    const expected = new Map<string, number>();
    for (const c of CASES.filter((x) => x.counted)) {
      const k = `group=${c.group}|obligation=${c.obligation}|status=${c.status}|`;
      expected.set(k + `consistency=${c.consistency ?? "ok"}`, (expected.get(k + `consistency=${c.consistency ?? "ok"}`) ?? 0) + 1);
    }
    expected.set("group=free_visit|obligation=free_visit_confirmed|status=confirmed|consistency=ok",
      (expected.get("group=free_visit|obligation=free_visit_confirmed|status=confirmed|consistency=ok") ?? 0) + 1); // the helper row
    for (const [frag, n] of expected) {
      const parts = frag.split("|");
      expect(sum(totals.counts, parts), frag).toBe(n);
    }
    // settled records are outside the traversal
    expect(sum(totals.counts, ["obligation=closed_released"])).toBe(0);
    expect(sum(totals.counts, ["obligation=closed_refunded"])).toBe(0);
  });

  test("funds are held ONLY for a settlement record or a verified locked escrow", async () => {
    const t = convexTest(schema, modules);
    await seed(t);
    const { counts } = await openTotals(t, "bookings", 100);
    // 3 settlement-record bookings + 1 invalid-listing one + 2 verified-locked-no-settlement
    expect(sum(counts, ["group=financial_outstanding"])).toBe(6);
    // 'paid' and 'has an escrow id' alone never produce a financial_outstanding row
    const heldKeys = Object.keys(counts).filter((k) => k.includes("group=financial_outstanding"));
    for (const k of heldKeys) {
      expect(k.includes("settlement=held") || k.includes("settlement=disputed") || k.includes("escrow=locked"), k).toBe(true);
    }
    // the escrow evidence is part of the key
    expect(sum(counts, ["obligation=verified_funds_locked_no_settlement", "escrow=locked"])).toBe(2);
    expect(sum(counts, ["obligation=closed_escrow_closed_no_settlement", "escrow=closed:released"])).toBe(1);
    expect(sum(counts, ["obligation=closed_escrow_closed_no_settlement", "escrow=closed:refunded"])).toBe(1);
    expect(sum(counts, ["obligation=anomaly_escrow_missing_or_invalid", "escrow=missing"])).toBe(2);
    expect(sum(counts, ["obligation=anomaly_escrow_state_unknown", "escrow=unknown"])).toBe(1);
    // free visits and unpaid bookings are separate from funds
    expect(sum(counts, ["group=free_visit"])).toBe(3); // incl. the helper row
    expect(sum(counts, ["group=unpaid"])).toBe(1);
    expect(sum(counts, ["group=free_visit", "settlement=none"])).toBe(3);
  });

  test("paid-and-terminal bookings are never silently 'closed'", async () => {
    const t = convexTest(schema, modules);
    await seed(t);
    const { counts } = await openTotals(t, "bookings", 100);
    for (const k of Object.keys(counts)) {
      if (k.includes("group=closed")) {
        // a closed record is free, never paid, settled, or a verified-closed escrow
        const ok = k.includes("payment=pending") || k.includes("escrow=closed:") || /obligation=closed_(completed|declined|cancelled)\|/.test(k);
        expect(ok, k).toBe(true);
        if (/obligation=closed_(completed|declined|cancelled)\|/.test(k)) expect(k, k).toContain("payment=completed");
      }
    }
    expect(sum(counts, ["obligation=anomaly_cancelled_paid_without_refund_evidence"])).toBe(1);
    expect(sum(counts, ["obligation=anomaly_terminal_paid_without_settlement"])).toBe(2);
  });

  test("scope labels, pagination (1, 2, 3, 50, 100), repeated runs and read-only behaviour", async () => {
    const t = convexTest(schema, modules);
    await seed(t);
    const snapshot = () => t.run(async (ctx) => JSON.stringify([await ctx.db.query("bookings").collect(), await ctx.db.query("transactions").collect()]));
    const before = await snapshot();
    const base = await openTotals(t, "bookings", 100);
    for (const k of Object.keys(base.counts)) expect(k.startsWith("scope=bookings_table_only|kind=bookings|")).toBe(true);
    expect(base.scope).toEqual({
      table: "bookings", scopeLabel: "bookings_table_only",
      excludes: ["hotel_bookings", "re_escrow_contracts", "re_inspection_passes", "other_tables"],
    });
    for (const size of [1, 2, 3, 50, 100]) {
      const r = await openTotals(t, "bookings", size);
      expect(r.counts, `page size ${size}`).toEqual(base.counts);
      expect(r.scanned).toBe(base.scanned);
    }
    expect((await openTotals(t, "bookings", 100)).counts).toEqual(base.counts); // repeated, unchanged data
    expect(await snapshot()).toBe(before);
    const text = JSON.stringify(base);
    for (const secret of ["not-a-real-id", "property-ref", "SECRET"]) expect(text).not.toContain(secret);
  });

  test("an invalid listing reference never drops the booking", async () => {
    const t = convexTest(schema, modules);
    await seed(t);
    const { counts } = await openTotals(t, "bookings", 100);
    expect(sum(counts, ["listingClass=listing_missing", "obligation=funds_held"])).toBe(1);
  });

  test("the per-listing rentalBookings flag: money or unpaid = open, unverified paid = unknown, free/settled = none", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const buyer = await makeUser(t, "buyer");
    const hire = { category: "car_rental", pricingType: "per_day", pricePerDay: 100 };
    const ids = { free: await listing(t, owner, hire), held: await listing(t, owner, hire), unpaid: await listing(t, owner, hire),
      released: await listing(t, owner, hire), unverified: await listing(t, owner, hire) };
    await insertBooking(t, { listing: ids.free as string, buyer, owner, type: "vehicle_rental", status: "confirmed", at: 1 });
    await insertBooking(t, { listing: ids.held as string, buyer, owner, type: "vehicle_rental", status: "confirmed", at: 1, settlement: "held", amount: 100, escrowId: "x" });
    await insertBooking(t, { listing: ids.unpaid as string, buyer, owner, type: "vehicle_rental", status: "pending_payment", at: 1, payment: "pending", amount: 100 });
    await insertBooking(t, { listing: ids.released as string, buyer, owner, type: "vehicle_rental", status: "completed", at: 1, settlement: "released", amount: 100, escrowId: "y" });
    await insertBooking(t, { listing: ids.unverified as string, buyer, owner, type: "vehicle_rental", status: "confirmed", at: 1, amount: 100, escrowId: "z" });
    const r = await runReport(t, 100);
    const s = (frag: string) => Object.entries(r.counts).filter(([k]) => k.includes(frag)).reduce((n, [, c]) => n + c, 0);
    expect(s("rentalBookings=open")).toBe(2); // held + unpaid
    expect(s("rentalBookings=none")).toBe(2); // free + released
    expect(s("rentalBookings=unknown")).toBe(1); // paid with an escrow id that this path does not verify
  });
});
