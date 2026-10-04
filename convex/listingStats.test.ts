/// <reference types="vite/client" />
// Listing statistics and money shown to agents are server-derived: views are counted once per
// signed-in viewer per day (not the owner, not the listing's agent, not guests), inquiries are
// counted when they happen, and earnings come only from completed payouts credited to the user.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
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
      email: `${name}${seq}@t.vx`, phone: `+2327300${1000 + seq}`, name, role: role as any,
      isVerified: true, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    } as any)
  );
  return { id, token };
}

const property = (t: T, ownerId: Id<"users">, extra: Record<string, unknown> = {}) =>
  t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId, title: "Sea View", description: "d", category: "sale", price: 1, currency: "SLE", address: "77 Hidden Way",
      city: "Lumley", country: "Sierra Leone", latitude: 8.41, longitude: -13.2, geohash: "", imageUrls: [],
      privateContactPhone: "+23277000111", availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0,
      updatedAt: Date.now(), ...extra,
    } as any)
  );
const view = (t: T, listingId: string, u?: U) =>
  t.mutation(api.listingStats.recordPropertyView, { listingId, ...(u ? { sessionToken: u.token } : {}) });
const views = async (t: T, id: Id<"realEstateListings">) => (await t.run(async (ctx) => ctx.db.get(id)))!.viewCount;

describe("views", () => {
  test("one per signed-in viewer per day; guests, the owner and drafts are not counted", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
    const a = await makeUser(t, "a");
    const b = await makeUser(t, "b");
    const id = await property(t, owner.id);
    expect(await view(t, id)).toEqual({ counted: false }); // guest
    expect(await view(t, id, owner)).toEqual({ counted: false });
    expect(await view(t, id, a)).toEqual({ counted: true });
    expect(await view(t, id, a)).toEqual({ counted: false }); // same day again
    expect(await view(t, id, b)).toEqual({ counted: true });
    expect(await views(t, id)).toBe(2);
    const draft = await property(t, owner.id, { isPublished: false });
    expect(await view(t, draft, a)).toEqual({ counted: false });
    expect(await views(t, draft)).toBe(0);
  });
});

describe("inquiries", () => {
  test("the inquiry count follows real inquiries", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
    const id = await property(t, owner.id);
    for (const name of ["x", "y"]) {
      const c = await makeUser(t, name);
      await t.mutation(api.adminPortal.submitContactRequest, {
        sessionToken: c.token, buyerId: c.id, listingId: id, listingType: "property", message: "Still available?",
      });
    }
    const mine: any[] = await t.query(api.realEstate.getMyPropertyListings, { ownerId: owner.id, sessionToken: owner.token });
    expect(mine.find((l) => l._id === id).inquiryCount).toBe(2);
  });
});

describe("earnings", () => {
  test("only completed payouts credited to the user count — never deposits, pending payouts or withdrawals", async () => {
    const t = convexTest(schema, modules);
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: Date.now() });
    expect(await t.query(api.walletCore.getEarningsSummary, { sessionToken: agent.token })).toMatchObject({ totalEarned: 0, count: 0 });
    // a real deposit creates the wallet (and is not an earning)
    await t.mutation(internal.walletCore.creditVerifiedDeposit, { userId: agent.id, amount: 10_000, provider: "TEST", providerReference: `d-${seq++}` });
    const walletId = (await t.run(async (ctx) => (await ctx.db.query("walletBalances").collect()).find((w) => w.userId === agent.id)))!._id;
    const tx = (extra: Record<string, unknown>) =>
      t.run(async (ctx) =>
        ctx.db.insert("transactions", {
          walletId, userId: agent.id, type: "payout", amount: 100, currency: "SLE", status: "completed", updatedAt: Date.now(), ...extra,
        } as any)
      );
    await tx({ amount: 250, netAmount: 212.5 });
    await tx({ status: "pending", amount: 999 });
    await tx({ agentNumber: "+232760000", amount: 50 }); // a legacy withdrawal row
    expect(await t.query(api.walletCore.getEarningsSummary, { sessionToken: agent.token })).toMatchObject({ totalEarned: 212.5, count: 1 });
    // another user's earnings are never visible
    const other = await makeUser(t, "other");
    expect(await t.query(api.walletCore.getEarningsSummary, { sessionToken: other.token })).toMatchObject({ totalEarned: 0 });
  });
});

describe("private data stays private for agents and the public", () => {
  test("the owner's street address, coordinates and phone never reach an authorised agent or the public", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: Date.now() });
    // an eligible (subscribed) agent, actively authorised by the owner for this listing
    await t.run(async (ctx) => {
      const planId = await ctx.db.insert("subscription_plans", {
        name: "Agent", tierCode: "AGENT_T", roleTarget: "agent", basePrice: 1, currency: "SLE", billingInterval: "monthly",
        intervalDays: 30, discountPercent: 0, isActive: true, features: [], createdAt: Date.now(), updatedAt: Date.now(),
      });
      await ctx.db.insert("vendor_subscriptions", {
        userId: agent.id, planId, tierCode: "AGENT_T", status: "active", startDate: Date.now() - 1000, expiryDate: Date.now() + 86_400_000,
        amountPaid: 1, currency: "SLE", paymentReference: "p", paymentMethod: "wallet", autoRenew: false, createdAt: Date.now(), updatedAt: Date.now(),
      });
    });
    const id = await property(t, owner.id, { isPublished: false }); // a draft the agent may open
    await t.run(async (ctx) =>
      ctx.db.insert("listing_agent_authorizations", {
        ownerId: owner.id, agentId: agent.id, listingType: "property", listingId: id as string, status: "active",
        invitedAt: Date.now(), acceptedAt: Date.now(), updatedAt: Date.now(),
      } as any)
    );
    const asAgent: any = await t.query(api.realEstate.getPropertyById, { listingId: id, sessionToken: agent.token });
    const asPublic: any = await t.query(api.realEstate.getPropertyById, { listingId: id });
    expect(asPublic).toBeNull(); // a draft is not public
    expect(asAgent).not.toBeNull(); // the authorised agent may open it…
    const text = JSON.stringify(asAgent);
    for (const secret of ["77 Hidden Way", "+23277000111", "8.41"]) expect(text).not.toContain(secret);
  });
});
