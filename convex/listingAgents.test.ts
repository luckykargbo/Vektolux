/// <reference types="vite/client" />
// Owner-authorised listing agents: Owner → authorises Agent → Agent represents THAT listing.
// Commission only with a valid active authorisation (and a fee rule with a commission); the owner
// can revoke; every change is in the audit trail; orders keep the terms they were priced with.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string };
const DAY = 24 * 60 * 60 * 1000;
let seq = 0;

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327400${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    } as any)
  );
  return { id, token };
}

async function subscribedAgent(t: T, admin: U, name = "agent", expiresIn = 30 * DAY): Promise<U> {
  const agent = await makeUser(t, name, "agent", { roleApprovedAt: Date.now() });
  await t.mutation(api.subscriptions.adminUpsertPlan, {
    sessionToken: admin.token, tierCode: "AGENT_M", name: "Agent Monthly", roleTarget: "agent", basePrice: 100, currency: "SLE",
    billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
  });
  await t.run(async (ctx) => {
    const p = (await ctx.db.query("subscription_plans").collect()).find((x) => x.tierCode === "AGENT_M")!;
    await ctx.db.insert("vendor_subscriptions", {
      userId: agent.id, planId: p._id, tierCode: "AGENT_M", status: "active", startDate: Date.now() - DAY, expiryDate: Date.now() + expiresIn,
      amountPaid: 100, currency: "SLE", paymentReference: `sub-${agent.id}`, paymentMethod: "wallet", autoRenew: false, createdAt: Date.now(), updatedAt: Date.now(),
    });
  });
  return agent;
}

const property = (t: T, ownerId: Id<"users">, category: string, price: number) =>
  t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId, title: "P", description: "d", category, price, currency: "SLE", address: "x", city: "Lumley", country: "Sierra Leone",
      latitude: 0, longitude: 0, geohash: "", imageUrls: [], availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
    } as any)
  );
const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });
const wallet = async (t: T, userId: Id<"users">) =>
  (await t.run(async (ctx) => (await ctx.db.query("walletBalances").collect()).find((w) => w.userId === userId)))?.availableBalance ?? 0;

const invite = (t: T, owner: U, propertyId: string, agent: U) =>
  t.mutation(api.listingAgents.authorizeListingAgent, { sessionToken: owner.token, listingType: "property", listingId: propertyId, agentUserId: agent.id });
const respond = (t: T, agent: U, id: string, accept: boolean) =>
  t.mutation(api.listingAgents.respondToListingAgentInvitation, { sessionToken: agent.token, authorizationId: id as Id<"listing_agent_authorizations">, accept });
const revoke = (t: T, who: U, id: string, reason = "no longer working together") =>
  t.mutation(api.listingAgents.revokeListingAgent, { sessionToken: who.token, authorizationId: id as Id<"listing_agent_authorizations">, reason });
const lease = (t: T, tenant: U, propertyId: Id<"realEstateListings">) =>
  t.mutation(api.realEstateEscrow.initiateRealEstateEscrow, {
    sessionToken: tenant.token, contractType: "LONG_TERM_LEASE", propertyListingId: propertyId, leaseDurationMonths: 12, paymentRail: "WALLET",
  } as any) as Promise<any>;
const contract = (t: T, id: string) => t.run(async (ctx) => ctx.db.get(id as Id<"re_escrow_contracts">)) as Promise<any>;

async function payout(t: T, tenant: U, contractId: string) {
  await t.mutation(api.realEstateEscrow.checkInShortStay, { sessionToken: tenant.token, contractId } as any);
  await t.run(async (ctx) => ctx.db.patch(contractId as Id<"re_escrow_contracts">, { stay24hAutoReleaseTimestamp: Date.now() - 1 }));
  await t.mutation(api.realEstateEscrow.releaseShortStayPayout24h, { sessionToken: tenant.token, contractId } as any);
}

// ─────────────────────────────────────────────────────────────────────
describe("who can authorise whom", () => {
  test("only the listing's owner can invite, and only an approved, subscribed agent", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const stranger = await makeUser(t, "stranger");
    const agent = await subscribedAgent(t, admin);
    const unapproved = await makeUser(t, "unapproved", "agent");
    const client = await makeUser(t, "client");
    const pid = await property(t, owner.id, "long_term_rent", 12_000);

    await expect(invite(t, stranger, pid, agent)).rejects.toThrow(/not found/i);
    await expect(invite(t, owner, pid, unapproved)).rejects.toThrow(/not an approved/i);
    await expect(invite(t, owner, pid, client)).rejects.toThrow(/not an approved/i);
    await expect(invite(t, owner, pid, owner)).rejects.toThrow(/yourself/i);
    const unsubscribed = await makeUser(t, "nosub", "agent", { roleApprovedAt: Date.now() });
    await expect(invite(t, owner, pid, unsubscribed)).rejects.toThrow(/subscription/i);

    const r = await invite(t, owner, pid, agent);
    expect(r.status).toBe("pending");
    // one pending/active agent per listing
    const other = await subscribedAgent(t, admin, "agent2");
    await expect(invite(t, owner, pid, other)).rejects.toThrow(/already has an agent/i);
  });

  test("only the invited agent can accept; the full lifecycle is in the audit trail", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const agent = await subscribedAgent(t, admin);
    const other = await subscribedAgent(t, admin, "other");
    const pid = await property(t, owner.id, "long_term_rent", 12_000);
    const { authorizationId } = await invite(t, owner, pid, agent);

    await expect(respond(t, other, authorizationId, true)).rejects.toThrow(/not found/i);
    await expect(respond(t, owner, authorizationId, true)).rejects.toThrow(/not found/i);
    expect((await respond(t, agent, authorizationId, true)).status).toBe("active");
    await expect(respond(t, agent, authorizationId, true)).rejects.toThrow(/already active/i);

    const stranger = await makeUser(t, "stranger");
    await expect(revoke(t, stranger, authorizationId)).rejects.toThrow(/not found/i);
    await expect(revoke(t, owner, authorizationId, "")).rejects.toThrow(/reason/i);
    await revoke(t, owner, authorizationId, "sold through another agency");
    await expect(revoke(t, owner, authorizationId)).rejects.toThrow(/already revoked/i);

    const rows: any[] = await t.query(api.listingAgents.getListingAgentAuthorizations, { sessionToken: owner.token, listingType: "property", listingId: pid });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ status: "revoked", revokedByRole: "owner", revokeReason: "sold through another agency" });
    expect(rows[0].invitedAt).toBeTypeOf("number");
    expect(rows[0].acceptedAt).toBeTypeOf("number");
    expect(rows[0].revokedAt).toBeTypeOf("number");
    expect(rows[0].events.map((e: any) => [e.action, e.actorRole])).toEqual([
      ["INVITED", "owner"], ["ACCEPTED", "agent"], ["REVOKED", "owner"],
    ]);
    // a stranger cannot read the listing's authorisations
    await expect(t.query(api.listingAgents.getListingAgentAuthorizations, { sessionToken: stranger.token, listingType: "property", listingId: pid })).rejects.toThrow(/not found/i);
  });

  test("the agent can withdraw and an admin can revoke; a declined invitation never becomes active", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const agent = await subscribedAgent(t, admin);
    const pid = await property(t, owner.id, "long_term_rent", 12_000);

    const a1 = await invite(t, owner, pid, agent);
    expect((await respond(t, agent, a1.authorizationId, false)).status).toBe("declined");
    await expect(respond(t, agent, a1.authorizationId, true)).rejects.toThrow(/already declined/i);

    const a2 = await invite(t, owner, pid, agent);
    await respond(t, agent, a2.authorizationId, true);
    expect((await revoke(t, agent, a2.authorizationId, "withdrawing")).status).toBe("revoked");

    const a3 = await invite(t, owner, pid, agent);
    await respond(t, agent, a3.authorizationId, true);
    await revoke(t, admin, a3.authorizationId, "fraud report under review");
    const row: any = await t.run(async (ctx) => ctx.db.get(a3.authorizationId as Id<"listing_agent_authorizations">));
    expect(row).toMatchObject({ status: "revoked", revokedByRole: "admin", revokedBy: admin.id });
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("commission only with a valid authorised relationship", () => {
  test("an active authorised agent earns the lease commission; the landlord gets the rent", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const tenant = await makeUser(t, "tenant");
    const agent = await subscribedAgent(t, admin);
    const pid = await property(t, owner.id, "long_term_rent", 12_000);
    const { authorizationId } = await invite(t, owner, pid, agent);
    await respond(t, agent, authorizationId, true);
    await fund(t, tenant.id, 20_000);

    const c = await lease(t, tenant, pid);
    expect(c.grossEscrowAmount).toBe(12_000 + 1_200 + 1_000); // rent + 10% commission (buyer pays) + caution
    expect(c.agentCommission).toBe(1_020);
    expect(c.platformFee).toBe(180);
    const doc = await contract(t, c.contractId);
    expect(doc.agentId).toBe(agent.id);
    expect(doc.agentAuthorizationId).toBe(authorizationId);
    expect(doc.feeSnapshot).toMatchObject({ agentApplied: true, agentCommissionGross: 1_200 });

    await payout(t, tenant, c.contractId);
    expect(await wallet(t, owner.id)).toBe(12_000);
    expect(await wallet(t, agent.id)).toBe(1_020);
  });

  test("a pending (not accepted) invitation gives no commission", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const tenant = await makeUser(t, "tenant");
    const agent = await subscribedAgent(t, admin);
    const pid = await property(t, owner.id, "long_term_rent", 12_000);
    await invite(t, owner, pid, agent);
    await fund(t, tenant.id, 20_000);
    const c = await lease(t, tenant, pid);
    expect(c.agentCommission).toBe(0);
    expect((await contract(t, c.contractId)).agentId).toBe(owner.id);
  });

  test("after the owner revokes, new orders have no commission; an order priced before keeps its terms", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const tenant = await makeUser(t, "tenant");
    const tenant2 = await makeUser(t, "tenant2");
    const agent = await subscribedAgent(t, admin);
    const pid = await property(t, owner.id, "long_term_rent", 12_000);
    const { authorizationId } = await invite(t, owner, pid, agent);
    await respond(t, agent, authorizationId, true);
    await fund(t, tenant.id, 20_000);
    await fund(t, tenant2.id, 20_000);

    const before = await lease(t, tenant, pid);
    await revoke(t, owner, authorizationId);
    // (the first lease occupies the listing in real life; here we only check pricing)
    const after = await lease(t, tenant2, pid);
    expect(before.agentCommission).toBe(1_020);
    expect(after.agentCommission).toBe(0);
    expect((await contract(t, after.contractId)).agentAuthorizationId).toBeUndefined();

    await payout(t, tenant, before.contractId);
    expect(await wallet(t, agent.id)).toBe(1_020); // the deal agreed while authorised is honoured
  });

  test("an agent whose subscription lapsed earns no commission on new orders", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const tenant = await makeUser(t, "tenant");
    const agent = await subscribedAgent(t, admin);
    const pid = await property(t, owner.id, "long_term_rent", 12_000);
    const { authorizationId } = await invite(t, owner, pid, agent);
    await respond(t, agent, authorizationId, true);
    await t.run(async (ctx) => {
      for (const s of await ctx.db.query("vendor_subscriptions").collect()) await ctx.db.patch(s._id, { expiryDate: Date.now() - 1 });
    });
    await fund(t, tenant.id, 20_000);
    const c = await lease(t, tenant, pid);
    expect(c.agentCommission).toBe(0);
  });

  test("a different owner's authorisation does not apply after the listing changes hands", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const newOwner = await makeUser(t, "newOwner");
    const tenant = await makeUser(t, "tenant");
    const agent = await subscribedAgent(t, admin);
    const pid = await property(t, owner.id, "long_term_rent", 12_000);
    const { authorizationId } = await invite(t, owner, pid, agent);
    await respond(t, agent, authorizationId, true);
    await t.run(async (ctx) => ctx.db.patch(pid, { ownerId: newOwner.id }));
    await fund(t, tenant.id, 20_000);
    expect((await lease(t, tenant, pid)).agentCommission).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("viewing tours", () => {
  test("a client cannot route the tour fee to an agent of their choice; the authorised agent runs it", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const client = await makeUser(t, "client");
    const rogue = await subscribedAgent(t, admin, "rogue");
    const pid = await property(t, owner.id, "sale", 50_000);
    await fund(t, client.id, 500);
    const book = () =>
      t.mutation(api.realEstateEscrow.initiateInspectionPass, {
        sessionToken: client.token, propertyListingId: pid, scheduledTimestamp: Date.now() + 3600_000, paymentRail: "WALLET", preferredAgentId: rogue.id,
      } as any) as Promise<any>;
    const p1 = await book();
    const d1: any = await t.run(async (ctx) => ctx.db.get(p1.passId as Id<"re_inspection_passes">));
    expect(d1.agentId).toBe(owner.id); // the client's preferred agent is ignored

    const agent = await subscribedAgent(t, admin, "authorised");
    const { authorizationId } = await invite(t, owner, pid, agent);
    await respond(t, agent, authorizationId, true);
    const p2 = await book();
    const d2: any = await t.run(async (ctx) => ctx.db.get(p2.passId as Id<"re_inspection_passes">));
    expect(d2.agentId).toBe(agent.id);
    expect(d2.agentAuthorizationId).toBe(authorizationId);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("admin listing-agent view", () => {
  test("admins see parties, listing, lifecycle, who revoked, audit trail and associated orders", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const tenant = await makeUser(t, "tenant");
    const agent = await subscribedAgent(t, admin);
    const pid = await property(t, owner.id, "long_term_rent", 12_000);
    const { authorizationId } = await invite(t, owner, pid, agent);
    await respond(t, agent, authorizationId, true);
    await fund(t, tenant.id, 20_000);
    const c = await lease(t, tenant, pid);
    await revoke(t, owner, authorizationId, "contract ended");

    await expect(t.query(api.listingAgents.adminListListingAgents, { sessionToken: owner.token })).rejects.toThrow(/administrator/i);
    const rows: any[] = await t.query(api.listingAgents.adminListListingAgents, { sessionToken: admin.token });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      status: "revoked", listingTitle: "P", revokedByRole: "owner", revokedByName: "owner", revokeReason: "contract ended",
      owner: { name: "owner" }, agent: { name: "agent" },
    });
    expect(rows[0].acceptedAt).toBeTypeOf("number");
    expect(rows[0].events.map((e: any) => e.action)).toEqual(["INVITED", "ACCEPTED", "REVOKED"]);
    expect(rows[0].orders).toHaveLength(1);
    expect(rows[0].orders[0]).toMatchObject({ kind: "contract", id: c.contractId, agentCommission: 1_020 });
    const onlyActive: any[] = await t.query(api.listingAgents.adminListListingAgents, { sessionToken: admin.token, status: "active" });
    expect(onlyActive).toHaveLength(0);
  });
});
