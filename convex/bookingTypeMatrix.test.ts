/// <reference types="vite/client" />
// Stage 1C-5A: which booking types exist for which listing type, and that vehicle rental / daily hire
// can no longer be booked. Rejections are decided before any listing read or write.
//   property listing -> property_inspection, hourly_guesthouse      (unchanged)
//   vehicle listing  -> vehicle_inspection only (free pre-purchase inspection / test drive)
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;
const HOUR = 3600 * 1000;

async function makeUser(t: T, name: string) {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327950${1000 + seq}`, name, role: "client",
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
    })
  );
  return { id, token };
}
const makeProperty = (t: T, ownerId: Id<"users">) =>
  t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId, title: "Guest house", description: "d", category: "hourly_guesthouse", price: 0, hourlyRate: 100,
      currency: "SLE", address: "a", city: "Freetown", country: "SL", latitude: 8.4, longitude: -13.2, geohash: "abc",
      imageUrls: [], availabilityStatus: "available", isFeatured: false, viewCount: 0, updatedAt: Date.now(),
    } as any)
  );
const makeVehicle = (t: T, ownerId: Id<"users">, pricingType: "total_sale" | "per_day" = "total_sale") =>
  t.run(async (ctx) =>
    ctx.db.insert("vehicleListings", {
      ownerId, title: "Toyota Hilux", category: pricingType === "total_sale" ? "car_sale" : "car_rental", price: 100000, pricingType,
      pricePerDay: pricingType === "per_day" ? 100 : undefined, images: [], createdAt: Date.now(), location: "Bo",
      latitude: 0, longitude: 0, geohash: "", status: "AVAILABLE", isPublished: true, isDeleted: false, updatedAt: Date.now(),
    } as any)
  );
const book = (t: T, buyer: { token: string }, listingId: string, listingType: "property" | "vehicle", bookingType: string, extra: Record<string, unknown> = {}) =>
  t.mutation(api.bookings.createBooking, {
    sessionToken: buyer.token, listingId, listingType, listingTitle: "x", bookingType,
    startTime: Date.now() + 24 * HOUR, endTime: Date.now() + 48 * HOUR, days: 1, hours: 2, ...extra,
  } as any) as Promise<any>;
const snapshot = (t: T) =>
  t.run(async (ctx) => ({
    bookings: await ctx.db.query("bookings").collect(),
    transactions: await ctx.db.query("transactions").collect(),
    ledger: await ctx.db.query("ledger_entries").collect(),
    wallets: await ctx.db.query("walletBalances").collect(),
    notifications: await ctx.db.query("user_notifications").collect(),
    orders: await ctx.db.query("escrow_orders").collect(),
    vehicles: await ctx.db.query("vehicleListings").collect(),
    properties: await ctx.db.query("realEstateListings").collect(),
  }));

describe("createBooking: allowed (listing type, booking type) pairs", () => {
  test("a NEW vehicle_rental booking is refused for any listing, leaving no record", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const sale = (await makeVehicle(t, owner.id)) as string;
    const hire = (await makeVehicle(t, owner.id, "per_day")) as string;
    const property = (await makeProperty(t, owner.id)) as string;
    const before = await snapshot(t);
    for (const [id, listingType] of [[sale, "vehicle"], [hire, "vehicle"], [property, "property"]] as const) {
      await expect(book(t, buyer, id, listingType, "vehicle_rental")).rejects.toThrow(/no longer available/i);
      // a client-supplied rate / vendor changes nothing
      await expect(book(t, buyer, id, listingType, "vehicle_rental", { rate: 1, vendorId: buyer.id })).rejects.toThrow(/no longer available/i);
    }
    expect(await snapshot(t)).toEqual(before);
  });

  test("mismatched pairs are refused: a vehicle cannot be booked as a guesthouse, a property not as a vehicle inspection", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const car = (await makeVehicle(t, owner.id)) as string;
    const property = (await makeProperty(t, owner.id)) as string;
    const before = await snapshot(t);
    await expect(book(t, buyer, car, "vehicle", "hourly_guesthouse")).rejects.toThrow(/not available for this listing/i);
    await expect(book(t, buyer, car, "vehicle", "property_inspection")).rejects.toThrow(/not available for this listing/i);
    await expect(book(t, buyer, property, "property", "vehicle_inspection")).rejects.toThrow(/not available for this listing/i);
    expect(await snapshot(t)).toEqual(before);
  });

  test("pre-purchase vehicle_inspection scheduling still works: free, confirmed, no money moves", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const car = (await makeVehicle(t, owner.id)) as string;
    const before = await snapshot(t);
    const r = await book(t, buyer, car, "vehicle", "vehicle_inspection");
    expect(r.status).toBe("confirmed");
    expect(r.paymentStatus).toBe("completed");
    expect(r.totalAmount).toBe(0);
    const after = await snapshot(t);
    expect(after.bookings).toHaveLength(1);
    expect(after.transactions).toEqual(before.transactions);
    expect(after.ledger).toEqual(before.ledger);
    expect(after.wallets).toEqual(before.wallets);
    expect(after.orders).toEqual(before.orders);
  });

  test("guesthouse and property site-visit bookings are unchanged", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const property = (await makeProperty(t, owner.id)) as string;
    const stay = await book(t, buyer, property, "property", "hourly_guesthouse", { startTime: Date.now() + 24 * HOUR, endTime: Date.now() + 26 * HOUR });
    expect(stay.subtotal).toBe(200); // 100/hour x 2 hours, from the listing
    expect(stay.status).toBe("pending_payment");
    const visit = await book(t, buyer, property, "property", "property_inspection", { startTime: Date.now() + 30 * HOUR, endTime: Date.now() + 31 * HOUR });
    expect(visit.status).toBe("requested");
  });
});
