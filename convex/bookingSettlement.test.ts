/// <reference types="vite/client" />
// Marketplace booking settlement: paid → held in escrow → released (buyer confirmation, 24h after
// the end with no dispute, or admin) or refunded (cancellation rules, admin). The vendor can never
// release; nothing is paid twice.

import { convexTest } from "convex-test";
import { afterEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string };
const HOUR = 60 * 60 * 1000;
const T0 = Date.UTC(2026, 10, 2, 9, 0, 0);
let seq = 0;

afterEach(() => vi.useRealTimers());
function at(ms: number) {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(ms));
}

async function makeUser(t: T, name: string, role = "client"): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327800${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
    } as any)
  );
  return { id, token };
}
const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });
const bal = (t: T, u: U) => t.query(api.wallet.getUserBalance, { sessionToken: u.token });
const booking = (t: T, id: Id<"bookings">) => t.run(async (ctx) => ctx.db.get(id)) as Promise<any>;

/** A real booking (hourly stay, server-priced: 4h × 100 = 400 + 5% = 420) paid from the wallet. */
async function paidBooking(t: T, startOffset = 2 * HOUR) {
  const admin = await makeUser(t, "admin", "admin");
  const buyer = await makeUser(t, "buyer");
  const vendor = await makeUser(t, "vendor");
  const listingId = await t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId: vendor.id, title: "Stay", description: "d", category: "hourly_guesthouse", price: 100, hourlyRate: 100, currency: "SLE",
      address: "x", city: "Lumley", country: "Sierra Leone", latitude: 0, longitude: 0, geohash: "", imageUrls: [],
      availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
    } as any)
  );
  await fund(t, buyer.id, 1000);
  const start = Date.now() + startOffset;
  const b: any = await t.mutation(api.bookings.createBooking, {
    sessionToken: buyer.token, listingId, listingType: "property", listingTitle: "Stay", bookingType: "hourly_guesthouse",
    startTime: start, endTime: start + 4 * HOUR, hours: 4,
  });
  expect(b.totalAmount).toBe(420);
  await t.mutation(api.payments.createEscrowPayment, { sessionToken: buyer.token, vendorId: vendor.id, amount: 420, referenceId: b.bookingId });
  return { admin, buyer, vendor, bookingId: b.bookingId as Id<"bookings">, start, end: start + 4 * HOUR };
}

// 420 total: Vektolux keeps round(420 × 15%) = 63, vendor 357
const VENDOR = 357;

// ─────────────────────────────────────────────────────────────────────
describe("payment puts the booking in a held state with a release time", () => {
  test("held, releaseEligibleAt = end + 24h, nothing paid out yet", async () => {
    at(T0);
    const t = convexTest(schema, modules);
    const { buyer, vendor, bookingId, end } = await paidBooking(t);
    const b = await booking(t, bookingId);
    expect(b).toMatchObject({ status: "confirmed", paymentStatus: "completed", settlementStatus: "held", releaseEligibleAt: end + 24 * HOUR });
    expect((await bal(t, buyer)).escrowBalance).toBe(420);
    expect((await bal(t, vendor)).availableBalance).toBe(0);
  });
});

describe("who can release", () => {
  test("the vendor can never release; the buyer cannot confirm before the start", async () => {
    at(T0);
    const t = convexTest(schema, modules);
    const { buyer, vendor, bookingId } = await paidBooking(t);
    await expect(t.mutation(api.bookings.confirmBookingCompletion, { sessionToken: vendor.token, bookingId })).rejects.toThrow(/not a party/i);
    await expect(t.mutation(api.bookings.confirmBookingCompletion, { sessionToken: buyer.token, bookingId })).rejects.toThrow(/after it has started/i);
    const b = await booking(t, bookingId);
    await expect(t.mutation(api.payments.releaseEscrowWithSplit, { sessionToken: vendor.token, transactionId: b.escrowId })).rejects.toThrow(/not a party/i);
    await expect(t.mutation(api.payments.releaseEscrowWithSplit, { sessionToken: buyer.token, transactionId: b.escrowId })).rejects.toThrow(/after it has started/i);
    expect((await bal(t, vendor)).availableBalance).toBe(0);
  });

  test("the buyer confirms after the start → vendor paid 85% once; booking completed", async () => {
    at(T0);
    const t = convexTest(schema, modules);
    const { buyer, vendor, bookingId, start } = await paidBooking(t);
    at(start + HOUR);
    const r: any = await t.mutation(api.bookings.confirmBookingCompletion, { sessionToken: buyer.token, bookingId });
    expect(r).toMatchObject({ vendorAmount: VENDOR, platformFee: 63 });
    await expect(t.mutation(api.bookings.confirmBookingCompletion, { sessionToken: buyer.token, bookingId })).rejects.toThrow();
    expect((await bal(t, vendor)).availableBalance).toBe(VENDOR);
    expect((await bal(t, buyer)).escrowBalance).toBe(0);
    expect(await booking(t, bookingId)).toMatchObject({ status: "completed", settlementStatus: "released", releasedBy: "buyer" });
    // the cron finds nothing left to release
    at(start + 100 * HOUR);
    expect(await t.mutation(internal.bookings.releaseDueBookings, {})).toMatchObject({ released: 0 });
    expect((await bal(t, vendor)).availableBalance).toBe(VENDOR);
  });
});

describe("automatic release 24h after the end", () => {
  test("not before end + 24h; then exactly once", async () => {
    at(T0);
    const t = convexTest(schema, modules);
    const { vendor, bookingId, end } = await paidBooking(t);
    at(end + 23 * HOUR);
    expect(await t.mutation(internal.bookings.releaseDueBookings, {})).toMatchObject({ released: 0 });
    expect((await bal(t, vendor)).availableBalance).toBe(0);
    at(end + 24 * HOUR + 1);
    expect(await t.mutation(internal.bookings.releaseDueBookings, {})).toMatchObject({ released: 1 });
    expect(await t.mutation(internal.bookings.releaseDueBookings, {})).toMatchObject({ released: 0 });
    expect((await bal(t, vendor)).availableBalance).toBe(VENDOR);
    expect(await booking(t, bookingId)).toMatchObject({ settlementStatus: "released", releasedBy: "auto" });
  });
});

describe("disputes freeze the escrow until an admin decides", () => {
  test("a dispute stops buyer release and auto-release; admin releases or refunds (audited)", async () => {
    at(T0);
    const t = convexTest(schema, modules);
    const { admin, buyer, vendor, bookingId, start, end } = await paidBooking(t);
    const stranger = await makeUser(t, "stranger");
    await expect(t.mutation(api.bookings.raiseBookingDispute, { sessionToken: stranger.token, bookingId, reason: "not mine at all" })).rejects.toThrow(/not found/i);
    await t.mutation(api.bookings.raiseBookingDispute, { sessionToken: buyer.token, bookingId, reason: "room was not available" });
    expect(await booking(t, bookingId)).toMatchObject({ status: "disputed", settlementStatus: "disputed", disputedBy: "buyer" });

    at(start + HOUR);
    await expect(t.mutation(api.bookings.confirmBookingCompletion, { sessionToken: buyer.token, bookingId })).rejects.toThrow(/disputed/i);
    await expect(
      t.mutation(api.bookings.cancelBooking, { sessionToken: buyer.token, bookingId, userId: buyer.id })
    ).rejects.toThrow(/disputed/i);
    at(end + 48 * HOUR);
    expect(await t.mutation(internal.bookings.releaseDueBookings, {})).toMatchObject({ released: 0 });
    expect((await bal(t, vendor)).availableBalance).toBe(0);

    await expect(
      t.mutation(api.bookings.adminResolveBookingDispute, { sessionToken: buyer.token, bookingId, resolution: "refund_buyer", note: "buyer wins here" })
    ).rejects.toThrow(/administrator/i);
    await expect(
      t.mutation(api.bookings.adminResolveBookingDispute, { sessionToken: admin.token, bookingId, resolution: "refund_buyer", note: "no" })
    ).rejects.toThrow(/note/i);
    await t.mutation(api.bookings.adminResolveBookingDispute, { sessionToken: admin.token, bookingId, resolution: "refund_buyer", note: "vendor confirmed the room was double-booked" });
    expect((await bal(t, buyer)).availableBalance).toBe(1000); // full refund incl. service fee
    expect((await bal(t, vendor)).availableBalance).toBe(0);
    expect(await booking(t, bookingId)).toMatchObject({ status: "cancelled", paymentStatus: "refunded", settlementStatus: "refunded" });
    const audit = await t.run(async (ctx) => (await ctx.db.query("audit_logs").collect()).filter((a) => a.action === "BOOKING_SETTLED"));
    expect(audit).toHaveLength(1);
    await expect(
      t.mutation(api.bookings.adminResolveBookingDispute, { sessionToken: admin.token, bookingId, resolution: "release_to_vendor", note: "second attempt" })
    ).rejects.toThrow(/no escrow/i);
  });

  test("the vendor can dispute too, and an admin can release to the vendor", async () => {
    at(T0);
    const t = convexTest(schema, modules);
    const { admin, vendor, bookingId } = await paidBooking(t);
    await t.mutation(api.bookings.raiseBookingDispute, { sessionToken: vendor.token, bookingId, reason: "guest damaged the room" });
    await t.mutation(api.bookings.adminResolveBookingDispute, { sessionToken: admin.token, bookingId, resolution: "release_to_vendor", note: "stay took place per check-in log" });
    expect((await bal(t, vendor)).availableBalance).toBe(VENDOR);
    expect(await booking(t, bookingId)).toMatchObject({ settlementStatus: "released", releasedBy: "admin" });
  });
});

describe("cancellation of a paid booking", () => {
  test("buyer before the start: full refund including the service fee", async () => {
    at(T0);
    const t = convexTest(schema, modules);
    const { buyer, vendor, bookingId } = await paidBooking(t);
    const r: any = await t.mutation(api.bookings.cancelBooking, { sessionToken: buyer.token, bookingId, userId: buyer.id, reason: "plans changed" });
    expect(r.refunded).toBe(420);
    const b = await bal(t, buyer);
    expect(b.availableBalance).toBe(1000);
    expect(b.escrowBalance).toBe(0);
    expect((await bal(t, vendor)).availableBalance).toBe(0);
    expect(await booking(t, bookingId)).toMatchObject({ status: "cancelled", settlementStatus: "refunded", refundReason: "plans changed" });
    await expect(t.mutation(api.bookings.cancelBooking, { sessionToken: buyer.token, bookingId, userId: buyer.id })).rejects.toThrow(/already cancelled/i);
  });

  test("buyer after the start must dispute instead; the vendor can still cancel with a full refund", async () => {
    at(T0);
    const t = convexTest(schema, modules);
    const { buyer, vendor, bookingId, start } = await paidBooking(t);
    at(start + HOUR);
    await expect(t.mutation(api.bookings.cancelBooking, { sessionToken: buyer.token, bookingId, userId: buyer.id })).rejects.toThrow(/dispute/i);
    await t.mutation(api.bookings.cancelBooking, { sessionToken: vendor.token, bookingId, userId: vendor.id, reason: "maintenance issue" });
    expect((await bal(t, buyer)).availableBalance).toBe(1000);
  });

  test("an unpaid booking is cancelled without moving money; a released booking cannot be cancelled", async () => {
    at(T0);
    const t = convexTest(schema, modules);
    const { buyer, bookingId, start } = await paidBooking(t);
    at(start + HOUR);
    await t.mutation(api.bookings.confirmBookingCompletion, { sessionToken: buyer.token, bookingId });
    await expect(t.mutation(api.bookings.cancelBooking, { sessionToken: buyer.token, bookingId, userId: buyer.id })).rejects.toThrow(/completed/i);

    const unpaid = await t.run(async (ctx) =>
      ctx.db.insert("bookings", {
        listingId: "l2", listingType: "property", listingTitle: "Other", buyerId: buyer.id as string, vendorId: "x",
        bookingType: "hourly_guesthouse", status: "pending_payment", startTime: 1, endTime: 2, subtotal: 10, serviceFee: 0,
        totalAmount: 10, currency: "SLE", paymentStatus: "pending", updatedAt: Date.now(),
      })
    );
    const before = await bal(t, buyer);
    const r: any = await t.mutation(api.bookings.cancelBooking, { sessionToken: buyer.token, bookingId: unpaid, userId: buyer.id });
    expect(r.refunded).toBe(0);
    expect(await bal(t, buyer)).toEqual(before);
  });
});

describe("admin view", () => {
  test("held and disputed booking escrows are listed for admins only", async () => {
    at(T0);
    const t = convexTest(schema, modules);
    const { admin, buyer, bookingId } = await paidBooking(t);
    await expect(t.query(api.bookings.adminListBookingEscrows, { sessionToken: buyer.token })).rejects.toThrow(/administrator/i);
    const rows: any[] = await t.query(api.bookings.adminListBookingEscrows, { sessionToken: admin.token });
    expect(rows.map((r) => r._id)).toEqual([bookingId]);
  });
});
