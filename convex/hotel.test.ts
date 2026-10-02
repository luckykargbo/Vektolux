/// <reference types="vite/client" />
// Hospitality escrow: real money in, real money out, nothing minted.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;

async function makeUser(t: T, name: string, role: string = "client") {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@test.vektolux`,
      phone: `+2327800${String(1000 + seq)}`,
      name,
      role: role as any,
      isVerified: false,
      isActive: true,
      sessionToken: token,
      updatedAt: Date.now(),
    })
  );
  return { id, token };
}

const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, {
    userId, amount, provider: "TEST_PROVIDER", providerReference: `fund-${userId}-${seq++}`,
  });

const balance = (t: T, u: { token: string }) => t.query(api.wallet.getUserBalance, { sessionToken: u.token });

/** A hotel operator who may take bookings: approved role + an ACTIVE paid subscription. */
async function makeEligible(ctx: any, operatorId: Id<"users">) {
  const now = Date.now();
  await ctx.db.patch(operatorId, { role: "hotel_operator", roleApprovedAt: now });
  const planId = await ctx.db.insert("subscription_plans", {
    name: "Hotel", tierCode: `HOTEL_T_${operatorId}`, roleTarget: "hotel_operator", basePrice: 1, currency: "SLE", billingInterval: "monthly",
    intervalDays: 30, discountPercent: 0, isActive: true, features: [], createdAt: now, updatedAt: now,
  });
  await ctx.db.insert("vendor_subscriptions", {
    userId: operatorId, planId, tierCode: `HOTEL_T_${operatorId}`, status: "active", startDate: now - 1000, expiryDate: now + 365 * 24 * 3600 * 1000,
    amountPaid: 1, currency: "SLE", paymentReference: `t-${operatorId}`, paymentMethod: "wallet", autoRenew: false, createdAt: now, updatedAt: now,
  });
}

async function makeRoom(t: T, operatorId: Id<"users">, pricePerNight = 1000) {
  return t.run(async (ctx) => {
    await makeEligible(ctx, operatorId);
    const hotelId = await ctx.db.insert("hotel_profiles", {
      userId: operatorId, businessName: "Test Hotel", operationalType: "hotel", isVerified: true,
      verificationStatus: "verified", address: "a", city: "Freetown", phone: "+23276000000",
      amenities: [], mediaUrls: [], description: "d", supportsHourlyStays: false, updatedAt: Date.now(),
    });
    const roomId = await ctx.db.insert("hotel_rooms", {
      hotelId, name: "Room 1", roomType: "Standard", pricePerNight, supportsHourly: false, capacityGuests: 2,
      bedConfiguration: "1 king", amenities: [], images: [], isAvailable: true, totalRoomUnits: 1,
      createdAt: Date.now(), updatedAt: Date.now(),
    });
    return { hotelId, roomId };
  });
}

const DAY = 24 * 3600 * 1000;
const stay = () => ({
  guestName: "Guest", guestPhone: "+23276111111", bookingCategory: "nightly" as const,
  checkInTimestamp: Date.now() + DAY, checkOutTimestamp: Date.now() + 2 * DAY, numberOfGuests: 1, numberOfNights: 1,
});

describe("hotel bookings", () => {
  test("a booking is only confirmed when real funds are held; the price comes from the room", async () => {
    const t = convexTest(schema, modules);
    const operator = await makeUser(t, "operator", "hotel_operator");
    const guest = await makeUser(t, "guest");
    const { hotelId, roomId } = await makeRoom(t, operator.id, 1000);

    // no funds -> no booking at all (rolled back), nothing marked paid
    await expect(
      t.mutation(api.hotelBookings.createBookingWithEscrow, { sessionToken: guest.token, hotelId, roomId, ...stay() })
    ).rejects.toThrow(/INSUFFICIENT_FUNDS/);
    expect(await t.run(async (ctx) => (await ctx.db.query("hotel_bookings").collect()).length)).toBe(0);

    await fund(t, guest.id, 1500);
    const res: any = await t.mutation(api.hotelBookings.createBookingWithEscrow, { sessionToken: guest.token, hotelId, roomId, ...stay() });
    expect(res.status).toBe("in_escrow");
    expect(res.subtotalAmount).toBe(1000);
    const b = await balance(t, guest);
    expect(b.availableBalance).toBe(500);
    expect(b.escrowBalance).toBe(1000);
  });

  test("the guest is the authenticated user; nobody can book as someone else", async () => {
    const t = convexTest(schema, modules);
    const operator = await makeUser(t, "operator", "hotel_operator");
    const victim = await makeUser(t, "victim");
    const attacker = await makeUser(t, "attacker");
    const { hotelId, roomId } = await makeRoom(t, operator.id);
    await fund(t, victim.id, 5000);
    await expect(
      t.mutation(api.hotelBookings.createBookingWithEscrow, { sessionToken: attacker.token, guestId: victim.id, hotelId, roomId, ...stay() })
    ).rejects.toThrow(/another user/i);
    await expect(
      t.mutation(api.hotelBookings.createBookingWithEscrow, { hotelId, roomId, ...stay() })
    ).rejects.toThrow(/authentication/i);
    expect((await balance(t, victim)).availableBalance).toBe(5000);
  });

  test("release pays the operator from escrow net of commission, exactly once", async () => {
    const t = convexTest(schema, modules);
    const operator = await makeUser(t, "operator", "hotel_operator");
    const guest = await makeUser(t, "guest");
    const stranger = await makeUser(t, "stranger");
    const { hotelId, roomId } = await makeRoom(t, operator.id, 1000);
    await fund(t, guest.id, 1000);
    const res: any = await t.mutation(api.hotelBookings.createBookingWithEscrow, { sessionToken: guest.token, hotelId, roomId, ...stay() });
    await t.mutation(api.hotelBookings.confirmCheckIn, { sessionToken: guest.token, bookingId: res.bookingId });

    await expect(
      t.mutation(api.hotelBookings.releaseEscrowPayout, { sessionToken: stranger.token, bookingId: res.bookingId })
    ).rejects.toThrow(/not a party/i);

    await t.mutation(api.hotelBookings.releaseEscrowPayout, { sessionToken: guest.token, bookingId: res.bookingId });
    await expect(
      t.mutation(api.hotelBookings.releaseEscrowPayout, { sessionToken: guest.token, bookingId: res.bookingId })
    ).rejects.toThrow();

    expect((await balance(t, operator)).availableBalance).toBe(900); // 1000 − 10%
    const g = await balance(t, guest);
    expect(g.escrowBalance).toBe(0);
    expect(g.availableBalance).toBe(0);
  });

  test("a booking with no real escrow behind it cannot mint money on release", async () => {
    const t = convexTest(schema, modules);
    const operator = await makeUser(t, "operator", "hotel_operator");
    const guest = await makeUser(t, "guest");
    const admin = await makeUser(t, "admin", "admin");
    const { hotelId, roomId } = await makeRoom(t, operator.id);
    const bookingId = await t.run(async (ctx) =>
      ctx.db.insert("hotel_bookings", {
        bookingReference: "HB-LEGACY", hotelId, roomId, guestId: guest.id, guestName: "G", guestPhone: "1",
        bookingCategory: "nightly", checkInTimestamp: 1, checkOutTimestamp: 2, numberOfGuests: 1,
        subtotalAmount: 5000, platformCommissionRate: 0.1, platformCommissionAmount: 500, operatorPayoutAmount: 4500,
        currency: "SLE", status: "checked_in", createdAt: Date.now(), updatedAt: Date.now(),
      })
    );
    await expect(
      t.mutation(api.hotelBookings.releaseEscrowPayout, { sessionToken: admin.token, bookingId })
    ).rejects.toThrow(/ESCROW_INSUFFICIENT/);
    expect((await balance(t, operator)).availableBalance).toBe(0);
  });

  test("a disputed booking is refunded from escrow by an admin only", async () => {
    const t = convexTest(schema, modules);
    const operator = await makeUser(t, "operator", "hotel_operator");
    const guest = await makeUser(t, "guest");
    const admin = await makeUser(t, "admin", "admin");
    const { hotelId, roomId } = await makeRoom(t, operator.id, 800);
    await fund(t, guest.id, 800);
    const res: any = await t.mutation(api.hotelBookings.createBookingWithEscrow, { sessionToken: guest.token, hotelId, roomId, ...stay() });
    await t.mutation(api.hotelBookings.raiseDispute, { sessionToken: guest.token, bookingId: res.bookingId, reason: "not as described" });

    await expect(
      t.mutation(api.hotelBookings.adminResolveDispute, { sessionToken: guest.token, bookingId: res.bookingId, resolution: "refund_guest", adminNotes: "x" })
    ).rejects.toThrow(/administrator/i);
    await expect(
      t.mutation(api.hotelBookings.adminResolveDispute, { bookingId: res.bookingId, resolution: "refund_guest", adminNotes: "x" })
    ).rejects.toThrow(/authentication/i);

    await t.mutation(api.hotelBookings.adminResolveDispute, { sessionToken: admin.token, bookingId: res.bookingId, resolution: "refund_guest", adminNotes: "ok" });
    const g = await balance(t, guest);
    expect(g.availableBalance).toBe(800);
    expect(g.escrowBalance).toBe(0);
  });

  test("a pending booking is confirmed only by a provider-verified payment (once, full amount)", async () => {
    const t = convexTest(schema, modules);
    const operator = await makeUser(t, "operator", "hotel_operator");
    const guest = await makeUser(t, "guest");
    const { hotelId, roomId } = await makeRoom(t, operator.id, 600);
    const res: any = await t.mutation(api.hotelBookings.createBookingWithEscrow, {
      sessionToken: guest.token, hotelId, roomId, payFromWallet: false, ...stay(),
    });
    expect(res.status).toBe("pending_payment");

    await expect(
      t.mutation(internal.hotelBookings.confirmHotelBookingPayment, { bookingId: res.bookingId, providerReference: "MM-1", amountPaid: 10 })
    ).rejects.toThrow(/AMOUNT_MISMATCH/);

    await t.mutation(internal.hotelBookings.confirmHotelBookingPayment, { bookingId: res.bookingId, providerReference: "MM-1", amountPaid: 600 });
    await t.mutation(internal.hotelBookings.confirmHotelBookingPayment, { bookingId: res.bookingId, providerReference: "MM-1", amountPaid: 600 });
    const g = await balance(t, guest);
    expect(g.availableBalance).toBe(0); // no wallet top-up involved
    expect(g.escrowBalance).toBe(600); // funded once
  });

  test("the escrow overview (guest names/phones) is admin-only", async () => {
    const t = convexTest(schema, modules);
    const client = await makeUser(t, "client");
    await expect(t.query(api.hotelBookings.adminGetEscrowFunds, {})).rejects.toThrow(/authentication/i);
    await expect(t.query(api.hotelBookings.adminGetEscrowFunds, { sessionToken: client.token })).rejects.toThrow(/administrator/i);
  });
});
