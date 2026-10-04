/// <reference types="vite/client" />
// Saved listings (the heart): a server record owned by the signed-in account, kept across logins
// and devices, removed for real when un-saved, and counted in the listing's real saveCount.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string };
let seq = 0;

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327700${1000 + seq}`, name, role: role as any,
      isVerified: true, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    } as any)
  );
  return { id, token };
}

const property = (t: T, ownerId: Id<"users">, extra: Record<string, unknown> = {}) =>
  t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId, title: "Garden Flat", description: "d", category: "long_term_rent", price: 1200000, currency: "SLE", address: "9 Secret Lane",
      city: "Lumley", country: "Sierra Leone", latitude: 8.4, longitude: -13.2, geohash: "", imageUrls: ["https://cdn.example/1.jpg"],
      availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(), ...extra,
    } as any)
  );

const toggle = (t: T, u: U, listingId: string) =>
  t.mutation(api.savedListings.toggleSavedListing, { sessionToken: u.token, listingType: "property", listingId });
const ids = async (t: T, u: U) =>
  ((await t.query(api.savedListings.getMySavedListingIds, { sessionToken: u.token })) as any[]).map((r) => r.listingId);
const saveCount = async (t: T, id: Id<"realEstateListings">) => (await t.run(async (ctx) => ctx.db.get(id)))?.saveCount ?? 0;

describe("saved listings", () => {
  test("a save belongs to the signed-in account; other people cannot see it", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
    const client = await makeUser(t, "client");
    const stranger = await makeUser(t, "stranger");
    const id = await property(t, owner.id);
    expect(await toggle(t, client, id)).toEqual({ saved: true });
    const rows = await t.run(async (ctx) => ctx.db.query("saved_listings").collect());
    expect(rows).toHaveLength(1);
    expect(rows[0].userId).toBe(client.id);
    expect(await ids(t, client)).toEqual([id]);
    expect(await ids(t, stranger)).toEqual([]);
  });

  test("saves survive logging out and in again (a new session) and any other device", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
    const client = await makeUser(t, "client");
    const id = await property(t, owner.id);
    await toggle(t, client, id);
    // log out + log in elsewhere: the account gets a brand-new session token
    const newToken = "sess_relogin_on_another_phone_0123456789";
    await t.run(async (ctx) => ctx.db.patch(client.id, { sessionToken: newToken }));
    expect(await ids(t, { id: client.id, token: newToken })).toEqual([id]);
    await expect(ids(t, client)).rejects.toThrow(/log in/i); // the old session no longer works
  });

  test("tapping again removes the server record; saveCount follows the real records", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
    const a = await makeUser(t, "a");
    const b = await makeUser(t, "b");
    const c = await makeUser(t, "c");
    const id = await property(t, owner.id);
    for (const u of [a, b, c]) await toggle(t, u, id);
    expect(await saveCount(t, id)).toBe(3);
    expect(await toggle(t, b, id)).toEqual({ saved: false });
    expect(await saveCount(t, id)).toBe(2);
    const rows = await t.run(async (ctx) => ctx.db.query("saved_listings").collect());
    expect(rows.map((r) => r.userId).sort()).toEqual([a.id, c.id].sort());
    // the owner sees the real count
    const mine: any[] = await t.query(api.realEstate.getMyPropertyListings, { ownerId: owner.id, sessionToken: owner.token });
    expect(mine.find((l) => l._id === id).saveCount).toBe(2);
  });

  test("only public listings can be saved; guests and owners cannot save", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
    const client = await makeUser(t, "client");
    const draft = await property(t, owner.id, { isPublished: false });
    const pending = await property(t, owner.id, { moderationStatus: "pending_review" });
    const live = await property(t, owner.id);
    await expect(toggle(t, client, draft)).rejects.toThrow(/no longer available/i);
    await expect(toggle(t, client, pending)).rejects.toThrow(/no longer available/i);
    await expect(toggle(t, owner, live)).rejects.toThrow(/your own/i);
    await expect(
      t.mutation(api.savedListings.toggleSavedListing, { listingType: "property", listingId: live })
    ).rejects.toThrow(/log in/i);
  });

  test("the saved list shows public cards only; a listing that went private is kept but without details", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
    const client = await makeUser(t, "client");
    const id = await property(t, owner.id);
    await toggle(t, client, id);
    let list: any[] = await t.query(api.savedListings.getMySavedListings, { sessionToken: client.token });
    expect(list[0]).toMatchObject({ listingId: id, available: true, title: "Garden Flat", imageUrl: "https://cdn.example/1.jpg" });
    expect(JSON.stringify(list)).not.toContain("9 Secret Lane");
    await t.run(async (ctx) => ctx.db.patch(id, { moderationStatus: "removed" }));
    list = await t.query(api.savedListings.getMySavedListings, { sessionToken: client.token });
    expect(list[0]).toEqual({ listingType: "property", listingId: id, savedAt: list[0].savedAt, available: false });
    // un-saving still works after it went private
    expect(await toggle(t, client, id)).toEqual({ saved: false });
  });
});
