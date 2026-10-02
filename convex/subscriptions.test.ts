/// <reference types="vite/client" />
// Stage 3: business roles are granted only by admin approval; professional privileges and badges
// follow an ACTIVE, PAID subscription; expiry removes them; history is kept; renewal extends.

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { hashWalletPin } from "./lib/pin";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
const PIN = "1234";
const DAY = 24 * 60 * 60 * 1000;
let seq = 0;

async function makeUser(t: T, name: string, role: string = "client", extra: Record<string, unknown> = {}) {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@test.vektolux`, phone: `+2327800${String(1000 + seq)}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    })
  );
  const h = await hashWalletPin(id, PIN);
  await t.run(async (ctx) => ctx.db.patch(id, { walletPinHash: h }));
  return { id, token };
}
const approvedAgent = (t: T, name = "agent") => makeUser(t, name, "agent", { roleApprovedAt: Date.now() });
const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });
const balance = (t: T, u: { token: string }) => t.query(api.wallet.getUserBalance, { sessionToken: u.token });

async function plans(t: T) {
  const admin = await makeUser(t, "admin", "admin");
  const base = { currency: "SLE", features: [], isActive: true, sessionToken: admin.token, promoStart: undefined, promoEnd: undefined };
  await t.mutation(api.subscriptions.adminUpsertPlan, {
    ...base, tierCode: "AGENT_M", name: "Agent Monthly", roleTarget: "agent", basePrice: 100, billingInterval: "monthly", intervalDays: 30, discountPercent: 0,
  });
  await t.mutation(api.subscriptions.adminUpsertPlan, {
    ...base, tierCode: "AGENT_Y", name: "Agent Yearly", roleTarget: "agent", basePrice: 1000, billingInterval: "annual", intervalDays: 365, discountPercent: 20,
  });
  await t.mutation(api.subscriptions.adminUpsertPlan, {
    ...base, tierCode: "HOTEL_M", name: "Hotel Monthly", roleTarget: "hotel_operator", basePrice: 150, billingInterval: "monthly", intervalDays: 30, discountPercent: 0,
  });
  return admin;
}
let keyN = 0;
const key = () => `idem-key-${++keyN}-0123456789`;
const subscribe = (t: T, u: { token: string }, tierCode: string, pin = PIN, k = key()) =>
  t.mutation(api.subscriptions.subscribeWithWallet, { sessionToken: u.token, tierCode, pin, idempotencyKey: k });
const post = (t: T, u: { id: Id<"users">; token: string }) =>
  t.mutation(api.realEstate.createPropertyListing, {
    ownerId: u.id, sessionToken: u.token, title: "House", description: "Nice", category: "sale" as any, price: 1000,
    address: "private", city: "Bo", imageStorageIds: [],
  });
const status = (t: T, u: { token: string }) => t.query(api.subscriptions.getMyProfessionalStatus, { sessionToken: u.token });

// ─────────────────────────────────────────────────────────────────────
describe("roles are granted only by admin approval", () => {
  test("registering as an agent stores a client + a pending application, and grants nothing", async () => {
    const t = convexTest(schema, modules);
    const r: any = await t.mutation(api.auth.registerUser, {
      name: "New Agent", email: "newagent@test.vektolux", phone: "+23279111222", password: "longpassword1", role: "Real Estate Agent",
    });
    expect(r.success).toBe(true);
    expect(r.role).toBe("client");
    expect(r.pendingApplicationRole).toBe("agent");
    const user = await t.run(async (ctx) => ctx.db.get(r.userId as Id<"users">));
    expect(user?.role).toBe("client");
    const apps = await t.run(async (ctx) => ctx.db.query("role_applications").collect());
    expect(apps).toHaveLength(1);
    expect(apps[0].status).toBe("pending");
    await expect(post(t, { id: r.userId, token: r.sessionToken })).rejects.toThrow(/approved/i);
  });

  test("an unapproved stored 'agent' role cannot post even with a subscription", async () => {
    const t = convexTest(schema, modules);
    await plans(t);
    const u = await makeUser(t, "selfagent", "agent");
    await fund(t, u.id, 500);
    await expect(subscribe(t, u, "AGENT_M")).rejects.toThrow(/approved Real Estate Agent/);
    await expect(post(t, u)).rejects.toThrow(/approved/i);
  });

  test("admin approval flow: apply -> approve -> role set; duplicate pending blocked; non-admin cannot decide", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const u = await makeUser(t, "owner");
    const res = await t.mutation(api.users.applyRoleUpgrade, { sessionToken: u.token, userId: u.id, targetRole: "property_owner" });
    expect(res.success).toBe(true);
    const dup = await t.mutation(api.users.applyRoleUpgrade, { sessionToken: u.token, userId: u.id, targetRole: "agent" });
    expect(dup.success).toBe(false);

    const appId = res.applicationId as Id<"role_applications">;
    await expect(
      t.mutation(api.roles.adminDecideRoleApplication, { sessionToken: u.token, applicationId: appId, decision: "approve" })
    ).rejects.toThrow();
    await t.mutation(api.roles.adminDecideRoleApplication, { sessionToken: admin.token, applicationId: appId, decision: "approve" });
    const after = await t.run(async (ctx) => ctx.db.get(u.id));
    expect(after?.role).toBe("property_owner");
    expect(after?.roleApprovedAt).toBeTypeOf("number");
    // Real Estate Owner posts without a subscription
    await expect(post(t, u)).resolves.toBeTypeOf("string");

    // suspension removes the role (history kept)
    await expect(
      t.mutation(api.roles.adminDecideRoleApplication, { sessionToken: admin.token, applicationId: appId, decision: "suspend" })
    ).rejects.toThrow(/reason/);
    await t.mutation(api.roles.adminDecideRoleApplication, { sessionToken: admin.token, applicationId: appId, decision: "suspend", notes: "fraud report" });
    expect((await t.run(async (ctx) => ctx.db.get(u.id)))?.role).toBe("client");
    await expect(post(t, u)).rejects.toThrow(/approved/i);
    const logs = await t.run(async (ctx) => ctx.db.query("audit_logs").collect());
    expect(logs.map((l) => l.action)).toEqual(expect.arrayContaining(["ROLE_APPROVED", "ROLE_SUSPENDED"]));
  });

  test("the removed driver role can no longer be applied for", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "driver");
    await expect(
      t.mutation(api.users.applyRoleUpgrade, { sessionToken: u.token, userId: u.id, targetRole: "driver" as any })
    ).rejects.toThrow();
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("subscriptions (wallet payment)", () => {
  test("approved agent without a subscription cannot post; monthly subscription enables posting + badge", async () => {
    const t = convexTest(schema, modules);
    await plans(t);
    const a = await approvedAgent(t);
    await expect(post(t, a)).rejects.toThrow(/subscription is not active/);
    expect((await status(t, a)).verifiedAgent).toBe(false);

    await fund(t, a.id, 150);
    const r: any = await subscribe(t, a, "AGENT_M");
    expect(r.success).toBe(true);
    expect(r.amountCharged).toBe(100);
    expect((await balance(t, a)).availableBalance).toBe(50);
    expect((await status(t, a)).verifiedAgent).toBe(true);
    expect((await t.query(api.subscriptions.getProfessionalBadge, { userId: a.id })).verifiedAgent).toBe(true);
    await expect(post(t, a)).resolves.toBeTypeOf("string");

    // revenue is booked as SUBSCRIPTION_REVENUE on the ledger
    const entries = await t.run(async (ctx) => ctx.db.query("ledger_entries").collect());
    expect(entries.some((e) => e.accountType === "SUBSCRIPTION_REVENUE" && e.direction === "CREDIT" && e.amount === 100)).toBe(true);
  });

  test("yearly plan applies the admin discount (server-side price)", async () => {
    const t = convexTest(schema, modules);
    await plans(t);
    const a = await approvedAgent(t);
    await fund(t, a.id, 1000);
    const r: any = await subscribe(t, a, "AGENT_Y");
    expect(r.amountCharged).toBe(800);
    expect(r.expiryDate - Date.now()).toBeGreaterThan(364 * DAY);
  });

  test("insufficient funds, wrong PIN and idempotent replays never double-charge", async () => {
    const t = convexTest(schema, modules);
    await plans(t);
    const a = await approvedAgent(t);
    await fund(t, a.id, 50);
    await expect(subscribe(t, a, "AGENT_M")).rejects.toThrow(/INSUFFICIENT_FUNDS/);
    await fund(t, a.id, 200);
    const bad: any = await subscribe(t, a, "AGENT_M", "9999");
    expect(bad.success).toBe(false);
    expect((await balance(t, a)).availableBalance).toBe(250);

    const k = key();
    await subscribe(t, a, "AGENT_M", PIN, k);
    const replay: any = await subscribe(t, a, "AGENT_M", PIN, k);
    expect(replay.duplicate).toBe(true);
    expect((await balance(t, a)).availableBalance).toBe(150);
    // paying again while far from expiry is refused (anti double-pay)
    await expect(subscribe(t, a, "AGENT_M")).rejects.toThrow(/Renewal opens/);
  });

  test("a hotel plan requires an approved hotel owner; an agent cannot buy it", async () => {
    const t = convexTest(schema, modules);
    await plans(t);
    const a = await approvedAgent(t);
    await fund(t, a.id, 500);
    await expect(subscribe(t, a, "HOTEL_M")).rejects.toThrow(/Hotel/);
    const h = await makeUser(t, "hotel", "hotel_operator", { roleApprovedAt: Date.now() });
    await fund(t, h.id, 500);
    await subscribe(t, h, "HOTEL_M");
    expect((await status(t, h)).verifiedHotel).toBe(true);
  });

  test("expiry removes privileges and badge, keeps history; renewal reactivates", async () => {
    const t = convexTest(schema, modules);
    await plans(t);
    const a = await approvedAgent(t);
    await fund(t, a.id, 500);
    await subscribe(t, a, "AGENT_M");
    const listingId = await post(t, a);

    // jump past expiry
    await t.run(async (ctx) => {
      const s = (await ctx.db.query("vendor_subscriptions").collect())[0];
      await ctx.db.patch(s._id, { expiryDate: Date.now() - 1000 });
    });
    // privileges follow the real expiry date even before the cron runs
    await expect(post(t, a)).rejects.toThrow(/subscription is not active/);
    expect((await status(t, a)).verifiedAgent).toBe(false);

    const res = await t.mutation(internal.subscriptions.expireAndRemind, {});
    expect(res.expired).toBe(1);
    const subs = await t.run(async (ctx) => ctx.db.query("vendor_subscriptions").collect());
    expect(subs[0].status).toBe("expired");
    expect(await t.run(async (ctx) => ctx.db.get(listingId as Id<"realEstateListings">))).not.toBeNull(); // history kept

    await subscribe(t, a, "AGENT_M");
    expect((await status(t, a)).verifiedAgent).toBe(true);
    expect(await t.run(async (ctx) => ctx.db.query("vendor_subscriptions").collect())).toHaveLength(1); // renewed, not duplicated
  });

  test("renewal inside the window extends from the current expiry; reminder sent once", async () => {
    const t = convexTest(schema, modules);
    await plans(t);
    const a = await approvedAgent(t);
    await fund(t, a.id, 500);
    await subscribe(t, a, "AGENT_M");
    const soon = Date.now() + 2 * DAY;
    await t.run(async (ctx) => {
      const s = (await ctx.db.query("vendor_subscriptions").collect())[0];
      await ctx.db.patch(s._id, { expiryDate: soon });
    });
    expect((await t.mutation(internal.subscriptions.expireAndRemind, {})).reminded).toBe(1);
    expect((await t.mutation(internal.subscriptions.expireAndRemind, {})).reminded).toBe(0);
    const r: any = await subscribe(t, a, "AGENT_M");
    expect(r.expiryDate).toBe(soon + 30 * DAY);
  });

  test("only admins change plans or grant subscriptions (audited)", async () => {
    const t = convexTest(schema, modules);
    const admin = await plans(t);
    const a = await approvedAgent(t);
    await expect(
      t.mutation(api.subscriptions.adminUpsertPlan, {
        sessionToken: a.token, tierCode: "AGENT_M", name: "x", roleTarget: "agent", basePrice: 1, currency: "SLE",
        billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
      })
    ).rejects.toThrow();
    await expect(
      t.mutation(api.subscriptions.adminGrantSubscription, { sessionToken: a.token, userId: a.id, tierCode: "AGENT_M", reason: "please" })
    ).rejects.toThrow();
    await t.mutation(api.subscriptions.adminGrantSubscription, { sessionToken: admin.token, userId: a.id, tierCode: "AGENT_M", reason: "launch partner" });
    expect((await status(t, a)).verifiedAgent).toBe(true);
    const logs = await t.run(async (ctx) => ctx.db.query("audit_logs").collect());
    expect(logs.map((l) => l.action)).toEqual(expect.arrayContaining(["SUBSCRIPTION_PLAN_CHANGED", "SUBSCRIPTION_GRANTED"]));
  });

  test("explore lists an agent only while their subscription is active", async () => {
    const t = convexTest(schema, modules);
    await plans(t);
    const a = await approvedAgent(t, "Visible Agent");
    const names = async () => ((await t.query(api.explore.getExploreFeed, {})) as any).topAgentsAndDealers.map((x: any) => x.name);
    expect(await names()).not.toContain("Visible Agent");
    await fund(t, a.id, 200);
    await subscribe(t, a, "AGENT_M");
    expect(await names()).toContain("Visible Agent");
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("subscriptions (direct Monime payment, verified by Monime's API)", () => {
  const sessions = new Map<string, any>();
  beforeEach(() => {
    sessions.clear();
    process.env.MONIME_SPACE_ID = "spc-test";
    process.env.MONIME_ACCESS_TOKEN = "test-token";
    process.env.MONIME_API_BASE_URL = "https://fake.monime.test/v1";
    vi.stubGlobal("fetch", async (url: string, init?: any) => {
      const u = String(url);
      const json = (status: number, body: any) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
      if (u.endsWith("/checkout-sessions") && init?.method === "POST") {
        const body = JSON.parse(init.body);
        const id = `scs-${++seq}abcd`;
        sessions.set(id, { id, status: "pending", lineItems: { data: body.lineItems }, metadata: body.metadata });
        return json(200, { success: true, result: { id, redirectUrl: `https://checkout.test/${id}` } });
      }
      const m = u.match(/\/checkout-sessions\/([^/?]+)$/);
      if (m) {
        const s = sessions.get(m[1]);
        return s ? json(200, { success: true, result: s }) : json(404, {});
      }
      return json(404, {});
    });
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    delete process.env.MONIME_SPACE_ID;
    delete process.env.MONIME_ACCESS_TOKEN;
    delete process.env.MONIME_API_BASE_URL;
  });

  test("the server quotes the price; activation happens only after Monime reports the session completed", async () => {
    const t = convexTest(schema, modules);
    await plans(t);
    const a = await approvedAgent(t);
    // client tries to pay 1 SLE for a 100 SLE plan: the server ignores the client amount
    const init: any = await t.action(api.payments.initiateMoniMePayment, {
      sessionToken: a.token, amount: 1, subscriptionTierCode: "AGENT_M", phoneNumber: "076123456",
    });
    expect(init.success).toBe(true);
    const [sessionId] = [...sessions.keys()];
    expect(sessions.get(sessionId).lineItems.data[0].price.value).toBe(10000);
    const tx = await t.run(async (ctx) => ctx.db.query("transactions").collect());
    expect(tx[0].gatewayReference).toBe(sessionId);

    // still pending at Monime -> nothing happens
    await t.action(internal.payments.settleMoniMeReference, { reference: sessionId });
    expect((await status(t, a)).verifiedAgent).toBe(false);

    sessions.get(sessionId).status = "completed";
    await t.action(internal.payments.settleMoniMeReference, { reference: sessionId });
    await t.action(internal.payments.settleMoniMeReference, { reference: sessionId }); // replay
    expect((await status(t, a)).verifiedAgent).toBe(true);
    expect((await balance(t, a)).availableBalance).toBe(0); // deposit 100 -> charged 100
    expect(await t.run(async (ctx) => ctx.db.query("vendor_subscriptions").collect())).toHaveLength(1);
  });

  test("an expired checkout is marked failed and credits nothing", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "payer");
    await t.action(api.payments.initiateMoniMePayment, { sessionToken: u.token, amount: 50, phoneNumber: "076123456" });
    const [sessionId] = [...sessions.keys()];
    sessions.get(sessionId).status = "expired";
    await t.action(internal.payments.settleMoniMeReference, { reference: sessionId });
    const tx = await t.run(async (ctx) => ctx.db.query("transactions").collect());
    expect(tx[0].status).toBe("failed");
    expect((await balance(t, u)).availableBalance).toBe(0);
  });

  test("an ineligible user cannot start a subscription checkout", async () => {
    const t = convexTest(schema, modules);
    await plans(t);
    const c = await makeUser(t, "client");
    await expect(
      t.action(api.payments.initiateMoniMePayment, { sessionToken: c.token, amount: 100, subscriptionTierCode: "AGENT_M", phoneNumber: "076123456" })
    ).rejects.toThrow(/approved Real Estate Agent/);
    expect(sessions.size).toBe(0);
  });
});
