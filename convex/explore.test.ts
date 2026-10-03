/// <reference types="vite/client" />
// Explore feed: real card details flow through (nothing invented), and the public feed never
// exposes an exact address, GPS coordinates, map pin or private phone number.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
let seq = 0;

async function owner(t: ReturnType<typeof convexTest>, name: string): Promise<Id<"users">> {
  seq += 1;
  return t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327000${1000 + seq}`, name, role: "client" as any,
      isVerified: false, isActive: true, sessionToken: `sess_${name}_${seq}_0123456789abcdef`, updatedAt: Date.now(),
    } as any)
  );
}

const SECRET_STREET = "17 Hidden Close";
const SECRET_PHONE = "+23277555999";

describe("explore feed", () => {
  test("carries the real property / vehicle details to both the recommended and the section lists", async () => {
    const t = convexTest(schema, modules);
    const ownerId = await owner(t, "seller");
    await t.run(async (ctx) => {
      await ctx.db.insert("realEstateListings", {
        ownerId, title: "Hill House", description: "d", category: "sale", price: 320000, currency: "SLE", address: SECRET_STREET, city: "Freetown",
        district: "Western Area Urban", country: "Sierra Leone", latitude: 8.4012, longitude: -13.2123, geohash: "abc", imageUrls: [],
        privateContactPhone: SECRET_PHONE, availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0,
        bedrooms: 3, bathrooms: 2, areaSqM: 167, updatedAt: Date.now(),
      } as any);
      await ctx.db.insert("realEstateListings", {
        ownerId, title: "Bare Plot", description: "d", category: "sale", price: 75000, currency: "SLE", address: SECRET_STREET, city: "Bo",
        country: "Sierra Leone", latitude: 7.9, longitude: -11.7, geohash: "abd", imageUrls: [], availabilityStatus: "available",
        isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
      } as any);
      await ctx.db.insert("vehicleListings", {
        ownerId, title: "Prado", make: "Toyota", model: "Land Cruiser Prado", year: 2021, category: "car_sale", price: 45000, pricingType: "total_sale",
        currency: "SLE", images: [], location: "Freetown", latitude: 8.4, longitude: -13.2, geohash: "x", status: "AVAILABLE", isPublished: true,
        fuelType: "Diesel", transmission: "Automatic", createdAt: Date.now(), updatedAt: Date.now(),
      } as any);
    });

    const feed: any = await t.query(api.explore.getExploreFeed, { limit: 10 });
    const house = feed.propertiesNearYou.find((p: any) => p.title === "Hill House");
    expect(house).toMatchObject({ category: "sale", bedrooms: 3, bathrooms: 2, areaSqM: 167, price: 320000 });
    // a listing without those details simply lacks them (the app shows nothing for them)
    const plot = feed.propertiesNearYou.find((p: any) => p.title === "Bare Plot");
    expect(plot.bedrooms).toBeUndefined();
    expect(plot.areaSqM).toBeUndefined();
    const car = feed.vehiclesForSaleAndHire[0];
    expect(car).toMatchObject({ year: 2021, fuelType: "Diesel", transmission: "Automatic", pricingType: "total_sale" });

    // the recommended list now carries the same real fields
    const recHouse = feed.recommended.find((r: any) => r.title === "Hill House");
    expect(recHouse).toMatchObject({ type: "property", category: "sale", bedrooms: 3, bathrooms: 2, areaSqM: 167 });
    const recCar = feed.recommended.find((r: any) => r.type === "vehicle");
    expect(recCar).toMatchObject({ category: "car_sale", pricingType: "total_sale", year: 2021, fuelType: "Diesel", transmission: "Automatic" });
  });

  test("the public feed never exposes the exact address, coordinates, geohash or private phone", async () => {
    const t = convexTest(schema, modules);
    const ownerId = await owner(t, "seller");
    await t.run(async (ctx) => {
      await ctx.db.insert("realEstateListings", {
        ownerId, title: "Hill House", description: "d", category: "sale", price: 320000, currency: "SLE", address: SECRET_STREET, city: "Freetown",
        country: "Sierra Leone", latitude: 8.4012, longitude: -13.2123, geohash: "abc", imageUrls: [], privateContactPhone: SECRET_PHONE,
        availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
      } as any);
    });
    const text = JSON.stringify(await t.query(api.explore.getExploreFeed, { limit: 10 }));
    expect(text).not.toContain(SECRET_STREET);
    expect(text).not.toContain(SECRET_PHONE);
    expect(text).not.toContain("8.4012");
    expect(text).not.toContain("-13.2123");
    expect(text).not.toMatch(/latitude|longitude|geohash|privateContactPhone|"address"/);
  });
});
