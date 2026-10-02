/// <reference types="vite/client" />
// Legacy-agent subscription policy: one FIXED 14-day grace window (launch + 14 days) for agents
// approved before the launch; everyone else needs a paid, active subscription. Time is pinned with
// fake timers and the launch timestamp is injected through the test-only hook (the production
// constant stays null).

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { hashWalletPin } from "./lib/pin";
import {
  configuredPolicyLaunchTimestamp,
  LEGACY_GRACE_PERIOD_MS,
  LEGACY_SUBSCRIPTION_POLICY_LAUNCH_TIMESTAMP,
  legacyAgentGrace,
} from "./lib/permissions";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;

const DAY = 24 * 60 * 60 * 1000;
const LAUNCH = Date.UTC(2026, 9, 15, 0, 0, 0); // TEST-ONLY injected value, not a production date
const GRACE_END = LAUNCH + 14 * DAY;
const PIN = "1234";
let seq = 0;

function setNow(ms: number) {
  vi.setSystemTime(new Date(ms));
}
function injectLaunch(value: unknown) {
  (globalThis as any).__VEKTOLUX_TEST_POLICY_LAUNCH_TS__ = value;
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  setNow(LAUNCH + 1 * DAY);
  injectLaunch(LAUNCH);
});
afterEach(() => {
  delete (globalThis as any).__VEKTOLUX_TEST_POLICY_LAUNCH_TS__;
  vi.useRealTimers();
});

async function makeUser(t: T, name: string, fields: Record<string, unknown>) {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327700${2000 + seq}`, name, role: "client",
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(), ...fields,
    } as any)
  );
  await t.run(async (ctx) => ctx.db.patch(id, { walletPinHash: await hashWalletPin(id, PIN) }));
  return { id, token };
}
const legacyA = (t: T, name = "legacyA") => makeUser(t, name, { role: "agent", isVerifiedAgent: true }); // old flow, no roleApprovedAt
const legacyB = (t: T, name = "legacyB") => makeUser(t, name, { role: "agent", roleApprovedAt: LAUNCH - 30 * DAY });
const newAgent = (t: T, name = "newAgent") => makeUser(t, name, { role: "agent", roleApprovedAt: LAUNCH + 2 * 60 * 60 * 1000 });

const status = (t: T, u: { token: string }) => t.query(api.subscriptions.getMyProfessionalStatus, { sessionToken: u.token }) as Promise<any>;
const post = (t: T, u: { id: Id<"users">; token: string }) =>
  t.mutation(api.realEstate.createPropertyListing, {
    ownerId: u.id, sessionToken: u.token, title: "House", description: "Nice", category: "sale" as any, price: 1000,
    address: "private", city: "Bo", imageStorageIds: [],
  });

async function plan(t: T) {
  const admin = await makeUser(t, "admin", { role: "admin" });
  await t.mutation(api.subscriptions.adminUpsertPlan, {
    sessionToken: admin.token, tierCode: "AGENT_M", name: "Agent Monthly", roleTarget: "agent", basePrice: 100, currency: "SLE",
    billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
  });
}
async function subscribe(t: T, u: { id: Id<"users">; token: string }) {
  await t.mutation(internal.walletCore.creditVerifiedDeposit, { userId: u.id, amount: 500, provider: "TEST", providerReference: `f-${u.id}-${seq++}` });
  return t.mutation(api.subscriptions.subscribeWithWallet, { sessionToken: u.token, tierCode: "AGENT_M", pin: PIN, idempotencyKey: `sub-key-${seq++}-0123456789` });
}

// ─────────────────────────────────────────────────────────────────────
describe("eligibility", () => {
  test("1. legacy path A: approved by the old flow (isVerifiedAgent, no roleApprovedAt)", async () => {
    const t = convexTest(schema, modules);
    const s = await status(t, await legacyA(t));
    expect(s.isInGracePeriod).toBe(true);
    expect(s.hasActiveSubscription).toBe(false);
    expect(s.gracePeriodEndsAt).toBe(GRACE_END);
  });

  test("2. legacy path B: roleApprovedAt before the launch", async () => {
    const t = convexTest(schema, modules);
    const s = await status(t, await legacyB(t));
    expect(s.isInGracePeriod).toBe(true);
    expect(s.gracePeriodEndsAt).toBe(GRACE_END);
  });

  test("3. a pending application does not qualify", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "pending", { role: "client" });
    await t.mutation(api.users.applyRoleUpgrade, { sessionToken: u.token, userId: u.id, targetRole: "agent" });
    const s = await status(t, u);
    expect(s.isInGracePeriod).toBe(false);
    expect(s.gracePeriodEndsAt).toBeNull();
    await expect(post(t, u)).rejects.toThrow(/approved/i);
  });

  test("4. merely selecting the agent role (never approved) does not qualify", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "selfAgent", { role: "agent" });
    expect((await status(t, u)).isInGracePeriod).toBe(false);
    await expect(post(t, u)).rejects.toThrow(/approved/i);
  });

  test("5. an agent approved after the launch does not qualify", async () => {
    const t = convexTest(schema, modules);
    const s = await status(t, await newAgent(t));
    expect(s.isInGracePeriod).toBe(false);
    expect(s.gracePeriodEndsAt).toBeNull();
    expect(s.legacyGraceEndedAt).toBeNull();
  });

  test("seed/admin and suspended accounts never qualify; the review report lists only real candidates", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "seedAdmin", { role: "admin", isVerifiedAgent: true, isVerifiedMerchant: true });
    const suspended = await makeUser(t, "suspended", { role: "client", isVerifiedAgent: false });
    const inactive = await makeUser(t, "inactive", { role: "agent", isVerifiedAgent: true, isActive: false });
    const a = await legacyA(t, "Real Legacy A");
    const b = await legacyB(t, "Real Legacy B");
    await newAgent(t, "After Launch");
    for (const u of [admin, suspended, inactive]) {
      const doc = await t.run(async (ctx) => ctx.db.get(u.id));
      expect(legacyAgentGrace(doc!, Date.now(), LAUNCH).eligible).toBe(false);
    }
    const report: any = await t.query(internal.subscriptions.legacyAgentPolicyReport, { plannedLaunchTimestamp: LAUNCH });
    expect(report.eligibleCount).toBe(2);
    expect(report.candidates.map((c: any) => c.userId).sort()).toEqual([a.id, b.id].sort());
    expect(report.graceEndsAt).toBe(GRACE_END);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("the window is fixed", () => {
  test("6. exactly 14 days from the launch; boundary is exclusive", async () => {
    const t = convexTest(schema, modules);
    const u = await legacyA(t);
    expect(GRACE_END - LAUNCH).toBe(14 * DAY);
    expect(LEGACY_GRACE_PERIOD_MS).toBe(14 * DAY);
    setNow(GRACE_END - 1);
    await expect(post(t, u)).resolves.toBeTypeOf("string");
    setNow(GRACE_END);
    await expect(post(t, u)).rejects.toThrow(/grace period ended/);
  });

  test("7 + 9. repeated status checks at different times never move the end date", async () => {
    const t = convexTest(schema, modules);
    const u = await legacyA(t);
    const seen = new Set<number>();
    for (const offset of [0, 1, 3, 7, 10, 13]) {
      setNow(LAUNCH + offset * DAY + 123);
      for (let i = 0; i < 3; i++) seen.add((await status(t, u)).gracePeriodEndsAt);
    }
    expect([...seen]).toEqual([GRACE_END]);
    // listing creation and subscription checks do not move it either
    await post(t, u);
    await t.query(api.subscriptions.getUserActiveSubscription, { sessionToken: u.token });
    expect((await status(t, u)).gracePeriodEndsAt).toBe(GRACE_END);
  });

  test("8 + 9. logout/login, a new device or a reinstall (new session) does not reset it", async () => {
    const t = convexTest(schema, modules);
    const u = await legacyB(t);
    const first = (await status(t, u)).gracePeriodEndsAt;
    setNow(LAUNCH + 9 * DAY);
    for (let device = 0; device < 3; device++) {
      const newToken = `sess_newdevice_${device}_0123456789abcdef`;
      await t.run(async (ctx) => ctx.db.patch(u.id, { sessionToken: newToken })); // what a fresh login does
      const s = await status(t, { token: newToken });
      expect(s.gracePeriodEndsAt).toBe(first);
      expect(s.isInGracePeriod).toBe(true);
    }
    // nothing per-user was written that could carry a moving date
    const doc: any = await t.run(async (ctx) => ctx.db.get(u.id));
    expect(Object.keys(doc).some((k) => /grace/i.test(k))).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("publishing (server-side authorization)", () => {
  test("10. a legacy agent can publish during the grace period", async () => {
    const t = convexTest(schema, modules);
    await expect(post(t, await legacyA(t))).resolves.toBeTypeOf("string");
    await expect(post(t, await legacyB(t))).resolves.toBeTypeOf("string");
  });

  test("11. after the grace period, without a subscription, publishing is refused", async () => {
    const t = convexTest(schema, modules);
    const u = await legacyA(t);
    setNow(GRACE_END + DAY);
    const s = await status(t, u);
    expect(s.isInGracePeriod).toBe(false);
    expect(s.hasActiveSubscription).toBe(false);
    expect(s.legacyGraceEndedAt).toBe(GRACE_END);
    await expect(post(t, u)).rejects.toThrow(/grace period ended/);
  });

  test("12. a new agent cannot publish without a subscription (no grace)", async () => {
    const t = convexTest(schema, modules);
    await expect(post(t, await newAgent(t))).rejects.toThrow(/subscription is not active/);
  });

  test("13. an active paid subscription allows publishing", async () => {
    const t = convexTest(schema, modules);
    await plan(t);
    const u = await newAgent(t);
    await subscribe(t, u);
    const s = await status(t, u);
    expect(s.hasActiveSubscription).toBe(true);
    expect(s.isInGracePeriod).toBe(false);
    await expect(post(t, u)).resolves.toBeTypeOf("string");
  });

  test("14. a subscription bought during the grace period becomes authoritative", async () => {
    const t = convexTest(schema, modules);
    await plan(t);
    const u = await legacyA(t);
    setNow(LAUNCH + 3 * DAY);
    await subscribe(t, u); // 30 days from now
    const s = await status(t, u);
    expect(s.hasActiveSubscription).toBe(true);
    expect(s.isInGracePeriod).toBe(false); // a paid subscription is never shown as "grace"
    expect(s.gracePeriodEndsAt).toBeNull();
    setNow(GRACE_END + DAY); // grace over, subscription still running
    await expect(post(t, u)).resolves.toBeTypeOf("string");
  });

  test("15. once both the grace period and the subscription have ended, publishing is refused", async () => {
    const t = convexTest(schema, modules);
    await plan(t);
    const u = await legacyB(t);
    await subscribe(t, u);
    setNow(LAUNCH + 60 * DAY); // subscription (30 d) and grace (14 d) both over
    const s = await status(t, u);
    expect(s.hasActiveSubscription).toBe(false);
    expect(s.isInGracePeriod).toBe(false);
    await expect(post(t, u)).rejects.toThrow();
  });

  test("16. client-supplied grace/subscription values cannot bypass authorization", async () => {
    const t = convexTest(schema, modules);
    const u = await newAgent(t);
    // extra args are rejected by Convex argument validation…
    await expect(
      t.mutation(api.realEstate.createPropertyListing, {
        ownerId: u.id, sessionToken: u.token, title: "x", description: "y", category: "sale", price: 1, address: "a", imageStorageIds: [],
        hasActiveSubscription: true, isInGracePeriod: true, gracePeriodEndsAt: Date.now() + 999 * DAY,
      } as any)
    ).rejects.toThrow();
    await expect(
      t.query(api.subscriptions.getMyProfessionalStatus, { sessionToken: u.token, isInGracePeriod: true } as any)
    ).rejects.toThrow();
    // …and another user's session (e.g. an eligible legacy agent's) cannot be borrowed for this account.
    const legacy = await legacyA(t);
    await expect(
      t.mutation(api.realEstate.createPropertyListing, {
        ownerId: u.id, sessionToken: legacy.token, title: "x", description: "y", category: "sale", price: 1, address: "a", imageStorageIds: [],
      } as any)
    ).rejects.toThrow();
  });

  test("re-publishing an unpublished listing needs the same permission (no back door after the grace period)", async () => {
    const t = convexTest(schema, modules);
    const u = await legacyA(t);
    const listingId = await post(t, u);
    await t.mutation(api.realEstate.updatePropertyListing, { listingId, ownerId: u.id, sessionToken: u.token, isPublished: false });
    setNow(GRACE_END + DAY);
    await expect(
      t.mutation(api.realEstate.updatePropertyListing, { listingId, ownerId: u.id, sessionToken: u.token, isPublished: true })
    ).rejects.toThrow(/grace period ended/);
    // other edits remain possible, and unpublishing is always allowed
    await expect(
      t.mutation(api.realEstate.updatePropertyListing, { listingId, ownerId: u.id, sessionToken: u.token, title: "Updated" })
    ).resolves.toBeTruthy();
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("the payment-dunning field is a different concept", () => {
  async function dunningRecord(t: T, userId: Id<"users">, dunningEndsAt: number) {
    await plan(t);
    await t.run(async (ctx) => {
      const p = (await ctx.db.query("subscription_plans").collect()).find((x) => x.tierCode === "AGENT_M");
      await ctx.db.insert("vendor_subscriptions", {
        userId, planId: p!._id, tierCode: "AGENT_M", status: "dunning",
        startDate: Date.now() - 40 * DAY, expiryDate: Date.now() - 10 * DAY, gracePeriodEndsAt: dunningEndsAt,
        amountPaid: 100, currency: "SLE", paymentReference: `dun-${userId}`, paymentMethod: "wallet", autoRenew: false,
        createdAt: Date.now(), updatedAt: Date.now(),
      });
    });
  }

  test("a NEW agent with a dunning record gets no grace period, no subscription and cannot post", async () => {
    const t = convexTest(schema, modules);
    const u = await newAgent(t);
    await dunningRecord(t, u.id, Date.now() + 365 * DAY);
    const s = await status(t, u);
    expect(s.hasActiveSubscription).toBe(false);
    expect(s.isInGracePeriod).toBe(false);
    expect(s.gracePeriodEndsAt).toBeNull();
    await expect(post(t, u)).rejects.toThrow(/subscription is not active/);
    // the subscription response no longer exposes the ambiguous dunning field at all
    const sub: any = await t.query(api.subscriptions.getUserActiveSubscription, { sessionToken: u.token });
    expect(sub).not.toBeNull();
    expect("gracePeriodEndsAt" in sub).toBe(false);
  });

  test("a LEGACY agent's grace end is the policy value, never the dunning date", async () => {
    const t = convexTest(schema, modules);
    const u = await legacyA(t);
    await dunningRecord(t, u.id, LAUNCH + 300 * DAY);
    const s = await status(t, u);
    expect(s.isInGracePeriod).toBe(true);
    expect(s.gracePeriodEndsAt).toBe(GRACE_END);
    setNow(GRACE_END + DAY); // policy grace over; the (later) dunning date must not keep posting open
    const after = await status(t, u);
    expect(after.isInGracePeriod).toBe(false);
    expect(after.gracePeriodEndsAt).toBeNull();
    await expect(post(t, u)).rejects.toThrow(/grace period ended/);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("fail-safe configuration", () => {
  test("17. with no launch timestamp configured, NOBODY gets a grace period", async () => {
    const t = convexTest(schema, modules);
    injectLaunch(undefined); // production state: the constant is null
    expect(LEGACY_SUBSCRIPTION_POLICY_LAUNCH_TIMESTAMP).toBeNull();
    expect(configuredPolicyLaunchTimestamp()).toBeNull();
    for (const u of [await legacyA(t), await legacyB(t)]) {
      const s = await status(t, u);
      expect(s.subscriptionPolicyConfigured).toBe(false);
      expect(s.isInGracePeriod).toBe(false);
      expect(s.gracePeriodEndsAt).toBeNull();
      await expect(post(t, u)).rejects.toThrow(/subscription is not active/);
    }
  });

  test("an implausible launch value (seconds instead of ms, NaN, string) is treated as NOT configured", async () => {
    const t = convexTest(schema, modules);
    const u = await legacyA(t);
    for (const bad of [Math.floor(LAUNCH / 1000), Number.NaN, String(LAUNCH), LAUNCH + 0.5, -1]) {
      injectLaunch(bad);
      expect(configuredPolicyLaunchTimestamp()).toBeNull();
      expect((await status(t, u)).isInGracePeriod).toBe(false);
    }
  });

  test("the test-only injection hook is ignored outside Vitest", () => {
    const original = process.env.VITEST;
    try {
      process.env.VITEST = "false";
      injectLaunch(LAUNCH);
      expect(configuredPolicyLaunchTimestamp()).toBeNull(); // falls back to the (null) production constant
    } finally {
      process.env.VITEST = original;
    }
  });
});
