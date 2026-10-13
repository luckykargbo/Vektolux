/// <reference types="vite/client" />
// Stage 1C-2 EVIDENCE: what happens when a professional subscription expires purely because time
// passes (no database write, no cron). Synthetic accounts and synthetic data only; no payment
// provider, no booking/rental flow. The clock is moved with fake Date; nothing else is faked.
//
// WHAT THIS PROVES: the server's access-control LOGIC denies expired professionals the moment the
// real clock passes `expiryDate`, with the subscription row untouched and `expireAndRemind` never run.
// WHAT IT CANNOT PROVE: convex-test re-executes every query, so it says nothing about Convex's
// query-result cache or what a client that stays subscribed is shown after time passes.
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";
import { hashWalletPin } from "./lib/pin";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string };
const MIN = 60 * 1000;
const DAY = 24 * 60 * MIN;
const T0 = Date.UTC(2026, 5, 1, 12, 0, 0);
const PIN = "4821";
let seq = 0;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(T0));
});
afterEach(() => vi.useRealTimers());

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327900${1000 + seq}`, name, role: role as any,
      isVerified: true, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    } as any)
  );
  return { id, token };
}
const makeBusiness = (t: T, name: string, extra: Record<string, unknown> = {}) =>
  makeUser(t, name, "client", {
    accountType: "BUSINESS", verificationStatus: "VERIFIED", businessName: `${name} Motors Ltd`, tinNumber: "TIN-0001", ...extra,
  });

async function ensurePlans(t: T, admin: U) {
  const plans: Record<string, string> = { AGENT_M: "agent", CAR_CO_M: "car_company" };
  for (const [tierCode, roleTarget] of Object.entries(plans)) {
    await t.mutation(api.subscriptions.adminUpsertPlan, {
      sessionToken: admin.token, tierCode, name: tierCode, roleTarget: roleTarget as any, basePrice: 100, currency: "SLE",
      billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
    });
  }
}
/** A synthetic ACTIVE subscription row that expires at `expiry`. */
async function giveSub(t: T, user: U, tierCode: string, expiry: number) {
  await t.run(async (ctx) => {
    const p = (await ctx.db.query("subscription_plans").collect()).find((x) => x.tierCode === tierCode)!;
    await ctx.db.insert("vendor_subscriptions", {
      userId: user.id, planId: p._id, tierCode, status: "active", startDate: Date.now() - DAY, expiryDate: expiry,
      amountPaid: 100, currency: "SLE", paymentReference: `sub-${tierCode}-${user.id}`, paymentMethod: "wallet", autoRenew: false,
      createdAt: Date.now(), updatedAt: Date.now(),
    });
  });
}
const fund = (t: T, u: U, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId: u.id, amount, provider: "TEST", providerReference: `f-${u.id}-${seq++}` });
const setPin = async (t: T, u: U) => {
  const h = await hashWalletPin(u.id, PIN);
  await t.run(async (ctx) => ctx.db.patch(u.id, { walletPinHash: h }));
};
const status = (t: T, u: U) => t.query(api.subscriptions.getMyProfessionalStatus, { sessionToken: u.token }) as Promise<any>;
const subRows = (t: T) => t.run(async (ctx) => ctx.db.query("vendor_subscriptions").collect());
const postProperty = (t: T, u: U) =>
  t.mutation(api.realEstate.createPropertyListing, {
    ownerId: u.id, sessionToken: u.token, title: "Villa", description: "Nice", category: "sale", price: 1, address: "x",
    city: "Lumley", imageStorageIds: [],
  });
const postVehicle = (t: T, u: U, capability?: string) =>
  t.mutation(api.mobility.createVehicleListing, {
    ownerId: u.id, sessionToken: u.token, make: "Toyota", model: "Prado", year: 2022, salePrice: 900000, imageStorageIds: [],
    category: "car_sale", listingIntent: "sale", ...(capability ? { postingCapability: capability } : {}),
  } as any);
/** Anonymous public browse: the same call an ordinary customer's app makes. */
const publicHas = async (t: T, id: string) => {
  const has = (x: unknown) => JSON.stringify(x).includes(id);
  const detail = await t.query(api.mobility.getVehicleById, { listingId: id } as any);
  return {
    byCategory: has(await t.query(api.mobility.getVehiclesByCategory, { category: "all" } as any)),
    list: has(await t.query(api.mobility.listVehicles, { category: "all" } as any)),
    detail: detail !== null,
  };
};
const purchase = (t: T, buyer: U, id: string, payFromWallet = true) =>
  t.mutation(api.escrow.initiateEscrowOrder, {
    sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: id, payFromWallet,
  } as any) as Promise<any>;

async function companyScene(t: T, expiry: number) {
  const admin = await makeUser(t, "admin", "admin");
  await ensurePlans(t, admin);
  const co = await makeBusiness(t, "co");
  const app: any = await t.mutation(api.users.applyRoleUpgrade, {
    sessionToken: co.token, userId: co.id, targetRole: "car_company" as any,
  } as any);
  await t.mutation(api.roles.adminDecideRoleApplication, {
    sessionToken: admin.token, applicationId: app.applicationId, decision: "approve",
  } as any);
  await giveSub(t, co, "CAR_CO_M", expiry);
  const buyer = await makeUser(t, "buyer");
  await fund(t, buyer, 50_000_000);
  return { admin, co, buyer };
}

describe("subscription expiry caused ONLY by the passage of time", () => {
  test("S1+S3 agent: allowed before expiry; denied after the clock passes expiry with NO database write", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: T0 });
    await giveSub(t, agent, "AGENT_M", T0 + 10 * MIN);

    // S1: active
    expect((await status(t, agent)).verifiedAgent).toBe(true);
    const existing = (await postProperty(t, agent)) as string;
    expect(existing).toBeTypeOf("string");

    // snapshot, then ONLY the clock moves
    const before = JSON.stringify(await subRows(t));
    vi.setSystemTime(new Date(T0 + 11 * MIN));

    // S3: no write happened, yet every professional capability is denied
    expect(JSON.stringify(await subRows(t))).toBe(before); // row still status "active", untouched
    expect((await subRows(t))[0].status).toBe("active");
    expect((await status(t, agent)).verifiedAgent).toBe(false);
    expect((await status(t, agent)).canPostProperty).toBe(false);
    await expect(postProperty(t, agent)).rejects.toThrow(/subscription is not active/i);
    // history is kept: the existing listing is still there
    expect(await t.run(async (ctx) => ctx.db.get(existing as Id<"realEstateListings">))).not.toBeNull();
  });

  test("S2 an already-expired subscription grants nothing", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: T0 });
    await giveSub(t, agent, "AGENT_M", T0 - 1000);
    expect((await status(t, agent)).verifiedAgent).toBe(false);
    await expect(postProperty(t, agent)).rejects.toThrow(/subscription is not active/i);
  });

  test("S3+S5+S6+S7 car company: discovery, NEW orders and an existing order after time-only expiry", async () => {
    const t = convexTest(schema, modules);
    const { co, buyer } = await companyScene(t, T0 + 10 * MIN);
    const listing = (await postVehicle(t, co)) as string;
    // an individual dealer, for the ordinary-customer (S6) control
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: T0 });
    const free = (await postVehicle(t, dealer)) as string;

    // S1: active company is visible and orderable
    expect(await publicHas(t, listing)).toEqual({ byCategory: true, list: true, detail: true });
    // S7: an order that is funded BEFORE expiry, and one created but not yet paid
    const funded = await purchase(t, buyer, listing);
    expect(funded.status).toBe("HELD_IN_ESCROW");
    const unpaid = await purchase(t, buyer, listing, false);
    expect(unpaid.status).toBe("PENDING_PAYMENT");

    const subsBefore = JSON.stringify(await subRows(t));
    const ordersBefore = JSON.stringify(await t.run(async (ctx) => ctx.db.query("escrow_orders").collect()));
    vi.setSystemTime(new Date(T0 + 11 * MIN)); // time passes; nothing is written

    expect(JSON.stringify(await subRows(t))).toBe(subsBefore);
    // S3: public discovery no longer shows the company listing (a freshly executed query)
    expect(await publicHas(t, listing)).toEqual({ byCategory: false, list: false, detail: false });
    // S6: ordinary customer browsing of an individual dealer is unaffected
    expect(await publicHas(t, free)).toEqual({ byCategory: true, list: true, detail: true });
    // S5: a NEW eligible transaction on the lapsed company is refused; the company cannot post new vehicles
    await expect(purchase(t, buyer, listing)).rejects.toThrow(/not available/i);
    await expect(postVehicle(t, co)).rejects.toThrow(/subscription is not active/i);
    expect((await status(t, co)).hasActiveCarCompanySubscription).toBe(false);
    // S7: the existing orders are untouched, and the funded one completes normally
    expect(JSON.stringify(await t.run(async (ctx) => ctx.db.query("escrow_orders").collect()))).toBe(ordersBefore);
    const released = await t.mutation(api.escrow.releaseDealEscrowFunds, {
      sessionToken: buyer.token, escrowOrderId: funded.escrowOrderId,
    });
    expect(released.success).toBe(true);
    expect(((await t.run(async (ctx) => ctx.db.get(funded.escrowOrderId))) as any).status).toBe("SETTLED");
    // ...but a buyer can still buy from the individual dealer
    expect((await purchase(t, buyer, free)).status).toBe("HELD_IN_ESCROW");
  });

  test("S4 renewal after expiry restores access, renewing the same row (real wallet purchase, synthetic funds)", async () => {
    const t = convexTest(schema, modules);
    const { co, buyer } = await companyScene(t, T0 + 10 * MIN);
    const listing = (await postVehicle(t, co)) as string;
    vi.setSystemTime(new Date(T0 + 11 * MIN));
    expect(await publicHas(t, listing)).toEqual({ byCategory: false, list: false, detail: false });
    await expect(postVehicle(t, co)).rejects.toThrow(/subscription is not active/i);

    await fund(t, co, 1000);
    await setPin(t, co);
    const r: any = await t.mutation(api.subscriptions.subscribeWithWallet, {
      sessionToken: co.token, tierCode: "CAR_CO_M", pin: PIN, idempotencyKey: "renew-after-expiry-0001",
    });
    expect(r.success).toBe(true);
    const rows = await subRows(t);
    expect(rows).toHaveLength(1); // renewed, not duplicated
    expect(rows[0].expiryDate).toBeGreaterThan(T0 + 11 * MIN);

    expect(await publicHas(t, listing)).toEqual({ byCategory: true, list: true, detail: true });
    await expect(postVehicle(t, co)).resolves.toBeTypeOf("string");
    expect((await purchase(t, buyer, listing)).status).toBe("HELD_IN_ESCROW");
  });

  test("the expiry job is never needed and was never run by these tests", async () => {
    const t = convexTest(schema, modules);
    const { co } = await companyScene(t, T0 + 10 * MIN);
    await postVehicle(t, co);
    vi.setSystemTime(new Date(T0 + 11 * MIN));
    const rows = await subRows(t);
    expect(rows[0].status).toBe("active"); // expireAndRemind did not run: the status is still "active"
    expect(rows[0].expiryDate).toBeLessThan(Date.now());
    const notes = await t.run(async (ctx) => ctx.db.query("user_notifications").collect());
    expect(notes.some((n) => /subscription expired/i.test(n.title))).toBe(false);
  });
});
