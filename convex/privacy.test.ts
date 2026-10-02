/// <reference types="vite/client" />
// Exact location and private owner contact must never leave the backend publicly.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";
import { publicLocation } from "./lib/slLocations";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;

const SECRET_STREET = "12 Secretstreet Avenue";
const SECRET_PHONE = "+23279888777";
const LAT = 8.48413;
const LNG = -13.23456;
const GEOHASH = "ec2xyz9";

function assertNoLeak(payload: unknown) {
  const json = JSON.stringify(payload);
  expect(json).not.toContain("Secretstreet");
  expect(json).not.toContain(SECRET_PHONE);
  expect(json).not.toContain(String(LAT));
  expect(json).not.toContain(String(LNG));
  expect(json).not.toContain(GEOHASH);
}

async function seed(t: T) {
  return t.run(async (ctx) => {
    const ownerId = await ctx.db.insert("users", {
      email: "owner@test.vektolux", phone: SECRET_PHONE, name: "Owner", role: "agent",
      isVerified: true, isActive: true, sessionToken: "sess_owner_0123456789abcdef", updatedAt: Date.now(),
    });
    const viewerId = await ctx.db.insert("users", {
      email: "viewer@test.vektolux", phone: "+23276000001", name: "Viewer", role: "client",
      isVerified: false, isActive: true, sessionToken: "sess_viewer_0123456789abcdef", updatedAt: Date.now(),
    });
    const propertyId = await ctx.db.insert("realEstateListings", {
      ownerId, title: "Family House", description: "Nice", category: "sale", price: 5000, currency: "SLE",
      address: `${SECRET_STREET}, Lumley`, city: "Lumley", country: "Sierra Leone",
      latitude: LAT, longitude: LNG, geohash: GEOHASH, imageUrls: [], privateContactPhone: SECRET_PHONE,
      availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
    });
    const vehicleId = await ctx.db.insert("vehicleListings", {
      ownerId, title: "Toyota", category: "car_sale", price: 100, pricingType: "total_sale", images: [], createdAt: Date.now(), location: `${SECRET_STREET}, Bo`,
      latitude: LAT, longitude: LNG, geohash: GEOHASH, privateContactPhone: SECRET_PHONE,
      status: "AVAILABLE", isPublished: true, updatedAt: Date.now(),
    } as any);
    await ctx.db.insert("follows", { followerId: viewerId, followingId: ownerId, createdAt: Date.now() });
    return { ownerId, viewerId, propertyId, vehicleId };
  });
}

describe("public listing responses never contain exact location or private contact", () => {
  test("property list / detail / profile posts / social feed / explore", async () => {
    const t = convexTest(schema, modules);
    const { ownerId, viewerId, propertyId } = await seed(t);

    const list: any = await t.query(api.realEstate.listProperties, {});
    expect(list.length).toBeGreaterThan(0);
    assertNoLeak(list);
    expect(list[0].address).toBe("Inside Lumley, Sierra Leone");

    const detail: any = await t.query(api.realEstate.getPropertyById, { listingId: propertyId });
    assertNoLeak(detail);
    expect(detail.publicLocation).toBe("Inside Lumley, Sierra Leone");

    assertNoLeak(await t.query(api.users.getUserPosts, { userId: ownerId }));
    const feed: any[] = await t.query(api.social.getSocialFeed, { userId: viewerId });
    expect(feed.some((i) => i.type === "property")).toBe(true); // the feed really contains the listing
    assertNoLeak(feed);
    assertNoLeak(await t.query(api.explore.getExploreFeed, {} as any));
  });

  test("searching by street address finds nothing (addresses are not searchable)", async () => {
    const t = convexTest(schema, modules);
    await seed(t);
    const r: any = await t.query(api.explore.searchExplore, { searchQuery: "Secretstreet" } as any);
    expect(r.properties).toHaveLength(0);
  });

  test("vehicle detail and lists do not expose seller coordinates or phone", async () => {
    const t = convexTest(schema, modules);
    const { vehicleId } = await seed(t);
    assertNoLeak(await t.query(api.mobility.getVehicleById, { listingId: vehicleId }));
    assertNoLeak(await t.query(api.mobility.listVehicles, {} as any));
  });

  test("the admin listing overview is admin-only", async () => {
    const t = convexTest(schema, modules);
    await seed(t);
    await expect(t.query(api.admin.getAdminListings, { vertical: "all" } as any)).rejects.toThrow(/authentication/i);
    await expect(
      t.query(api.admin.getAdminListings, { vertical: "all", sessionToken: "sess_viewer_0123456789abcdef" } as any)
    ).rejects.toThrow(/administrator/i);
  });
});

describe("generalized location is built only from the Sierra Leone allow-list", () => {
  test("known towns and districts", () => {
    expect(publicLocation("Freetown")).toBe("Inside Freetown, Sierra Leone");
    expect(publicLocation("kenema")).toBe("Inside Kenema, Sierra Leone");
    expect(publicLocation("Koidu Town")).toBe("Inside Koidu, Sierra Leone");
    expect(publicLocation(undefined, "Kailahun")).toBe("Inside Kailahun, Sierra Leone");
  });
  test("free text (e.g. a typed street address) is never echoed", () => {
    expect(publicLocation("5 Wilkinson Road, my house")).toBe("Inside Sierra Leone");
    expect(publicLocation("")).toBe("Inside Sierra Leone");
  });
  test("the public locations list covers every district", async () => {
    const t = convexTest(schema, modules);
    const locs: any[] = await t.query(api.locations.getSierraLeoneLocations, {});
    expect(locs.length).toBe(16);
    expect(new Set(locs.map((l) => l.region)).size).toBe(5);
  });
});
