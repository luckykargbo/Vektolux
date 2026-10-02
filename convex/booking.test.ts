/// <reference types="vite/client" />
// Booking prices, buyer and vendor are decided by the server — never by the client.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;

async function makeUser(t: T, name: string) {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@test.vektolux`,
      phone: `+2327900${String(1000 + seq)}`,
      name,
      role: "client",
      isVerified: false,
      isActive: true,
      sessionToken: token,
      updatedAt: Date.now(),
    })
  );
  return { id, token };
}

const makeListing = (t: T, ownerId: Id<"users">, hourlyRate?: number) =>
  t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId, title: "Guest house", description: "d", category: "hourly_guesthouse", price: 0, hourlyRate,
      currency: "SLE", address: "a", city: "Freetown", country: "SL", latitude: 8.4, longitude: -13.2, geohash: "abc",
      imageUrls: [], availabilityStatus: "available", isFeatured: false, viewCount: 0, updatedAt: Date.now(),
    })
  );

const HOUR = 3600 * 1000;
const base = (listingId: string) => ({
  listingId,
  listingType: "property" as const,
  listingTitle: "Guest house",
  bookingType: "hourly_guesthouse" as const,
  startTime: Date.now() + 24 * HOUR,
  endTime: Date.now() + 26 * HOUR,
});

describe("createBooking", () => {
  test("price comes from the listing; a client-supplied rate, buyer and vendor are ignored", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const attacker = await makeUser(t, "attacker");
    const listingId = await makeListing(t, owner.id, 100);

    const res: any = await t.mutation(api.bookings.createBooking, {
      ...base(listingId),
      sessionToken: buyer.token,
      rate: 1, // tampered price
      vendorId: attacker.id, // tampered payee
    });
    expect(res.subtotal).toBe(200); // 100/hour × 2 hours
    expect(res.serviceFee).toBe(10);
    expect(res.totalAmount).toBe(210);

    const row = await t.run(async (ctx) => ctx.db.get(res.bookingId as Id<"bookings">));
    expect(row?.buyerId).toBe(buyer.id);
    expect(row?.vendorId).toBe(owner.id); // the listing's owner, not the attacker
  });

  test("a booking cannot be created for another user or without a session", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const other = await makeUser(t, "other");
    const listingId = await makeListing(t, owner.id, 100);
    await expect(
      t.mutation(api.bookings.createBooking, { ...base(listingId), sessionToken: other.token, buyerId: buyer.id })
    ).rejects.toThrow(/another user/i);
    await expect(t.mutation(api.bookings.createBooking, { ...base(listingId), buyerId: buyer.id })).rejects.toThrow(/authentication/i);
  });

  test("a listing without a configured rate is refused (no invented default price)", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const listingId = await makeListing(t, owner.id, undefined);
    await expect(
      t.mutation(api.bookings.createBooking, { ...base(listingId), sessionToken: buyer.token })
    ).rejects.toThrow(/no hourly rate/i);
  });

  test("you cannot book your own listing", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const listingId = await makeListing(t, owner.id, 100);
    await expect(
      t.mutation(api.bookings.createBooking, { ...base(listingId), sessionToken: owner.token })
    ).rejects.toThrow(/own listing/i);
  });
});

describe("earnings summary", () => {
  test("sums only the caller's completed payouts; withdrawals and other users are excluded", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    const walletA = await t.run(async (ctx) =>
      ctx.db.insert("walletBalances", { userId: a.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: Date.now() }));
    const walletB = await t.run(async (ctx) =>
      ctx.db.insert("walletBalances", { userId: b.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: Date.now() }));
    const row = (userId: Id<"users">, walletId: Id<"walletBalances">, amount: number, extra: any = {}) => ({
      walletId, userId, type: "payout" as const, amount, netAmount: amount, currency: "SLE", status: "completed" as const, updatedAt: Date.now(), ...extra,
    });
    await t.run(async (ctx) => {
      await ctx.db.insert("transactions", row(a.id, walletA, 300));
      await ctx.db.insert("transactions", row(a.id, walletA, 200));
      await ctx.db.insert("transactions", row(a.id, walletA, 999, { status: "pending" })); // not completed
      await ctx.db.insert("transactions", row(a.id, walletA, 50, { agentNumber: "+23276000000" })); // legacy withdrawal
      await ctx.db.insert("transactions", row(b.id, walletB, 7777)); // another user
    });
    const sa: any = await t.query(api.walletCore.getEarningsSummary, { sessionToken: a.token });
    expect(sa.totalEarned).toBe(500);
    expect(sa.count).toBe(2);
    const sb: any = await t.query(api.walletCore.getEarningsSummary, { sessionToken: b.token });
    expect(sb.totalEarned).toBe(7777);
    await expect(t.query(api.walletCore.getEarningsSummary, {})).rejects.toThrow(/authentication/i);
  });
});
