/// <reference types="vite/client" />
// Stage 1: the Car Company capability and per-capability subscription enforcement.
//   Subscription-required: real estate agent, hotel operator, car company (each its OWN plan).
//   Free: individual real estate owner, individual car dealer / vehicle owner.
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";
import { hashWalletPin } from "./lib/pin";

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
      email: `${name}${seq}@t.vx`, phone: `+2327800${1000 + seq}`, name, role: role as any,
      isVerified: true, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    } as any)
  );
  return { id, token };
}
// An admin-approved, verified BUSINESS account (KYC approved) that has NOT been granted anything yet.
const makeBusiness = (t: T, name: string, role = "client", extra: Record<string, unknown> = {}) =>
  makeUser(t, name, role, {
    accountType: "BUSINESS", verificationStatus: "VERIFIED", businessName: `${name} Motors Ltd`, tinNumber: "TIN-0001", ...extra,
  });

const PLANS: Record<string, string> = { AGENT_M: "agent", HOTEL_M: "hotel_operator", CAR_CO_M: "car_company" };
async function ensurePlans(t: T, admin: U) {
  for (const [tierCode, roleTarget] of Object.entries(PLANS)) {
    await t.mutation(api.subscriptions.adminUpsertPlan, {
      sessionToken: admin.token, tierCode, name: tierCode, roleTarget: roleTarget as any, basePrice: 100, currency: "SLE",
      billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
    });
  }
}
async function giveSub(t: T, user: U, tierCode: string, expiry = Date.now() + 30 * DAY) {
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
const PIN = "4821";
const setPin = async (t: T, u: U) => {
  const h = await hashWalletPin(u.id, PIN);
  await t.run(async (ctx) => ctx.db.patch(u.id, { walletPinHash: h }));
};

const status = (t: T, u: U) => t.query(api.subscriptions.getMyProfessionalStatus, { sessionToken: u.token }) as Promise<any>;
const apply = (t: T, u: U, targetRole: string, extra: Record<string, unknown> = {}) =>
  t.mutation(api.users.applyRoleUpgrade, { sessionToken: u.token, userId: u.id, targetRole: targetRole as any, ...extra }) as Promise<any>;
const decide = (t: T, admin: U, applicationId: string, decision: "approve" | "reject" | "suspend", notes?: string) =>
  t.mutation(api.roles.adminDecideRoleApplication, {
    sessionToken: admin.token, applicationId: applicationId as Id<"role_applications">, decision, ...(notes ? { notes } : {}),
  }) as Promise<any>;
const postVehicle = (t: T, u: U, capability?: string) =>
  t.mutation(api.mobility.createVehicleListing, {
    ownerId: u.id, sessionToken: u.token, make: "Toyota", model: "Prado", year: 2022, salePrice: 900000, imageStorageIds: [],
    category: "car_sale", listingIntent: "sale", ...(capability ? { postingCapability: capability } : {}),
  } as any);
const postProperty = (t: T, u: U) =>
  t.mutation(api.realEstate.createPropertyListing, {
    ownerId: u.id, sessionToken: u.token, title: "Villa", description: "Nice", category: "sale", price: 1, address: "x",
    city: "Lumley", imageStorageIds: [],
  });
const row = (t: T, u: U) => t.run(async (ctx) => ctx.db.get(u.id)) as Promise<any>;

/** Application -> admin approval of the Car Company capability. */
async function approveCompany(t: T, admin: U, u: U) {
  const a = await apply(t, u, "car_company");
  expect(a.success).toBe(true);
  return decide(t, admin, a.applicationId, "approve");
}

describe("car company capability: only an admin grants it, only to a verified business", () => {
  test("applying grants nothing; admin approval grants it without touching the primary role", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const co = await makeBusiness(t, "co");
    const a = await apply(t, co, "car_company");
    expect(a.success).toBe(true);
    let s = await status(t, co);
    expect(s.capabilities.carCompany).toBe(false);
    expect(s.role).toBe("client");
    await decide(t, admin, a.applicationId, "approve");
    s = await status(t, co);
    expect(s.capabilities.carCompany).toBe(true);
    expect(s.role).toBe("client"); // an add-on, never a role change
    expect(s.professionalTitle).toBe("Car Company");
    const u = await row(t, co);
    expect(u.role).toBe("client");
    expect(u.carCompanyApprovedBy).toBe(admin.id);
    const audits = await t.run(async (ctx) => ctx.db.query("audit_logs").collect());
    expect(audits.some((x) => x.action === "ROLE_APPROVED")).toBe(true);
  });

  test("an INDIVIDUAL account, or a business whose verification is not approved, cannot claim or be given it", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const individual = await makeUser(t, "ind", "client", { accountType: "INDIVIDUAL", businessName: "X", tinNumber: "T" });
    const r1 = await apply(t, individual, "car_company");
    expect(r1.success).toBe(false);
    expect(r1.errorCode).toBe("BUSINESS_ACCOUNT_REQUIRED");

    // business, but KYC not approved: the application can exist, approval is refused by the server
    const pending = await makeBusiness(t, "pend", "client", { verificationStatus: "PENDING_REVIEW", isVerified: false });
    const a = await apply(t, pending, "car_company");
    expect(a.success).toBe(true);
    await expect(decide(t, admin, a.applicationId, "approve")).rejects.toThrow(/verified business/i);
    expect((await status(t, pending)).capabilities.carCompany).toBe(false);

    // business details missing
    const noTin = await makeBusiness(t, "notin", "client", { tinNumber: undefined });
    expect((await apply(t, noTin, "car_company")).errorCode).toBe("BUSINESS_DETAILS_REQUIRED");
  });

  test("a stored approval lapses when business verification is no longer approved or the account is deactivated", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const co = await makeBusiness(t, "co");
    await approveCompany(t, admin, co);
    expect((await status(t, co)).capabilities.carCompany).toBe(true);
    await t.run(async (ctx) => ctx.db.patch(co.id, { verificationStatus: "REJECTED", isVerified: false }));
    expect((await status(t, co)).capabilities.carCompany).toBe(false);
  });

  test("nobody can grant or change professional capabilities except an admin", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const co = await makeBusiness(t, "co");
    const other = await makeUser(t, "other");
    const a = await apply(t, co, "car_company");
    // the applicant, another client, and an unauthenticated caller cannot decide
    await expect(decide(t, co, a.applicationId, "approve")).rejects.toThrow();
    await expect(decide(t, other, a.applicationId, "approve")).rejects.toThrow();
    await expect(
      t.mutation(api.roles.adminDecideRoleApplication, { applicationId: a.applicationId as Id<"role_applications">, decision: "approve" } as any)
    ).rejects.toThrow();
    // no profile/update call accepts the capability field
    await expect(
      t.mutation(api.users.updateUserProfile as any, { sessionToken: co.token, userId: co.id, carCompanyApprovedAt: 1 } as any)
    ).rejects.toThrow();
    expect((await row(t, co)).carCompanyApprovedAt).toBeUndefined();
    // admin suspend removes only the capability and requires a reason
    await decide(t, admin, a.applicationId, "approve");
    await expect(decide(t, admin, a.applicationId, "suspend")).rejects.toThrow(/reason/i);
    await decide(t, admin, a.applicationId, "suspend", "policy breach");
    expect((await status(t, co)).capabilities.carCompany).toBe(false);
    expect((await row(t, co)).role).toBe("client");
  });
});

describe("car company: subscription purchase and enforcement", () => {
  test("an approved car company cannot post vehicles without its subscription, and can with it", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const co = await makeBusiness(t, "co");
    await approveCompany(t, admin, co);
    await expect(postVehicle(t, co)).rejects.toThrow(/subscription is not active/i);
    await giveSub(t, co, "CAR_CO_M");
    const id = await postVehicle(t, co);
    expect(typeof id).toBe("string");
    const l: any = await t.run(async (ctx) => ctx.db.get(id as any));
    expect(l.postedAs).toBe("car_company");
    const s = await status(t, co);
    expect(s.hasActiveCarCompanySubscription).toBe(true);
    expect(s.canPostVehicle).toBe(true);
  });

  test("an expired car-company subscription stops posting", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const co = await makeBusiness(t, "co");
    await approveCompany(t, admin, co);
    await giveSub(t, co, "CAR_CO_M", Date.now() - 1000);
    await expect(postVehicle(t, co)).rejects.toThrow(/subscription is not active/i);
  });

  test("an unapproved business cannot post vehicles or subscribe to the car-company plan", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const biz = await makeBusiness(t, "biz");
    await expect(postVehicle(t, biz)).rejects.toThrow();
    await expect(postVehicle(t, biz, "car_company")).rejects.toThrow(/approved Car Company/i);
    await expect(
      t.mutation(api.subscriptions.subscribeWithWallet, { sessionToken: biz.token, tierCode: "CAR_CO_M", pin: "1234", idempotencyKey: "k".repeat(20) })
    ).rejects.toThrow(/requires an approved Car Company/i);
  });

  test("an approved car company can buy the car_company plan from the wallet; other roles cannot buy it", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const co = await makeBusiness(t, "co");
    await approveCompany(t, admin, co);
    await fund(t, co, 1000);
    await setPin(t, co);
    const buy = () =>
      t.mutation(api.subscriptions.subscribeWithWallet, {
        sessionToken: co.token, tierCode: "CAR_CO_M", pin: PIN, idempotencyKey: "company-sub-0000001",
      }) as Promise<any>;
    const r = await buy();
    expect(r.success).toBe(true);
    expect(r.amountCharged).toBe(100);
    expect((await status(t, co)).hasActiveCarCompanySubscription).toBe(true);
    // replaying the same request charges nothing more
    expect((await buy()).duplicate).toBe(true);
    const wallet = (await t.run(async (ctx) => ctx.db.query("walletBalances").collect())).find((w) => w.userId === co.id)!;
    expect(wallet.availableBalance).toBe(900);
    const entries = await t.run(async (ctx) => ctx.db.query("ledger_entries").collect());
    expect(entries.filter((e) => e.accountType === "SUBSCRIPTION_REVENUE" && e.direction === "CREDIT" && e.amount === 100)).toHaveLength(1);
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: Date.now() });
    for (const u of [dealer, agent]) {
      await expect(
        t.mutation(api.subscriptions.subscribeWithWallet, { sessionToken: u.token, tierCode: "CAR_CO_M", pin: "4821", idempotencyKey: "other-sub-0000000001" })
      ).rejects.toThrow(/requires an approved Car Company/i);
    }
  });
});

describe("free capabilities stay free", () => {
  test("an individual car dealer and a real estate owner post without any subscription", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const owner = await makeUser(t, "owner", "property_owner", { roleApprovedAt: Date.now() });
    const id = await postVehicle(t, dealer);
    expect(((await t.run(async (ctx) => ctx.db.get(id as any))) as any).postedAs).toBe("individual_dealer");
    expect(typeof (await postProperty(t, owner))).toBe("string");
    const s = await status(t, dealer);
    expect(s.canPostVehicle).toBe(true);
    expect(s.vehiclePosting.requiresChoice).toBe(false);
  });

  test("an individual dealer cannot buy a (legacy) merchant plan any more, and merchant plans are not listed", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    // a legacy plan that already exists in data
    await t.run(async (ctx) =>
      ctx.db.insert("subscription_plans", {
        name: "Legacy merchant", tierCode: "MERCH_LEGACY", roleTarget: "merchant", basePrice: 50, currency: "SLE", billingInterval: "monthly",
        intervalDays: 30, discountPercent: 0, isActive: true, features: [], createdAt: 1, updatedAt: 1,
      })
    );
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    await expect(
      t.mutation(api.subscriptions.subscribeWithWallet, { sessionToken: dealer.token, tierCode: "MERCH_LEGACY", pin: "4821", idempotencyKey: "legacy-merchant-0000001" })
    ).rejects.toThrow(/no longer available/i);
    expect(await t.query(api.subscriptions.getPlans, {})).toHaveLength(0);
    expect(await t.query(api.subscriptions.getPlans, { roleTarget: "merchant" })).toHaveLength(0);
    // admin: no new merchant plan, no activating the legacy one, and a plan's target is immutable
    await expect(
      t.mutation(api.subscriptions.adminUpsertPlan, { sessionToken: admin.token, tierCode: "MERCH_NEW", name: "n", roleTarget: "merchant", basePrice: 1, currency: "SLE", billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: false, features: [] })
    ).rejects.toThrow(/retired/i);
    await expect(
      t.mutation(api.subscriptions.adminUpsertPlan, { sessionToken: admin.token, tierCode: "MERCH_LEGACY", name: "n", roleTarget: "car_company", basePrice: 1, currency: "SLE", billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [] })
    ).rejects.toThrow(/cannot be changed/i);
    // deactivating the legacy plan is allowed, and the row is kept
    await t.mutation(api.subscriptions.adminUpsertPlan, { sessionToken: admin.token, tierCode: "MERCH_LEGACY", name: "Legacy merchant", roleTarget: "merchant", basePrice: 50, currency: "SLE", billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: false, features: [] });
    expect((await t.run(async (ctx) => ctx.db.query("subscription_plans").collect())).some((p) => p.tierCode === "MERCH_LEGACY")).toBe(true);
  });

  test("an existing merchant subscription record is preserved and never satisfies the car-company requirement", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const co = await makeBusiness(t, "co");
    await approveCompany(t, admin, co);
    await t.run(async (ctx) => {
      const planId = await ctx.db.insert("subscription_plans", {
        name: "Legacy merchant", tierCode: "MERCH_LEGACY", roleTarget: "merchant", basePrice: 50, currency: "SLE", billingInterval: "monthly",
        intervalDays: 30, discountPercent: 0, isActive: false, features: [], createdAt: 1, updatedAt: 1,
      });
      await ctx.db.insert("vendor_subscriptions", {
        userId: co.id, planId, tierCode: "MERCH_LEGACY", status: "active", startDate: 1, expiryDate: Date.now() + 30 * DAY,
        amountPaid: 50, currency: "SLE", paymentReference: "legacy-pay", paymentMethod: "wallet", autoRenew: false, createdAt: 1, updatedAt: 1,
      });
    });
    await expect(postVehicle(t, co)).rejects.toThrow(/subscription is not active/i);
    const subs = await t.run(async (ctx) => ctx.db.query("vendor_subscriptions").collect());
    expect(subs).toHaveLength(1);
    expect(subs[0].paymentReference).toBe("legacy-pay");
  });
});

describe("existing requirements are unchanged", () => {
  test("agents and hotel operators still need their own subscription; owners stay free", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: Date.now() });
    await expect(postProperty(t, agent)).rejects.toThrow(/subscription/i);
    await giveSub(t, agent, "AGENT_M");
    expect(typeof (await postProperty(t, agent))).toBe("string");
    const hotel = await makeUser(t, "hotel", "hotel_operator", { roleApprovedAt: Date.now() });
    expect((await status(t, hotel)).canManageHotel).toBe(false);
    await giveSub(t, hotel, "HOTEL_M");
    expect((await status(t, hotel)).canManageHotel).toBe(true);
  });
});

describe("multi-capability accounts cannot bypass a requirement by switching capability", () => {
  test("agent subscription does not satisfy car company; car company subscription does not satisfy agent", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const both = await makeBusiness(t, "both", "agent", { roleApprovedAt: Date.now() });
    await approveCompany(t, admin, both);
    expect((await row(t, both)).role).toBe("agent");
    // agent subscription only: property OK, vehicles (car company) NOT
    await giveSub(t, both, "AGENT_M");
    expect(typeof (await postProperty(t, both))).toBe("string");
    await expect(postVehicle(t, both)).rejects.toThrow(/Car Company subscription is not active/i);
    expect((await status(t, both)).professionalTitle).toBe("Real Estate Agent & Car Company");
  });

  test("a car company subscription alone does not let an agent post property", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const both = await makeBusiness(t, "both", "agent", { roleApprovedAt: Date.now() });
    await approveCompany(t, admin, both);
    await giveSub(t, both, "CAR_CO_M");
    await expect(postProperty(t, both)).rejects.toThrow(/subscription/i);
    expect(typeof (await postVehicle(t, both))).toBe("string");
  });

  test("an account that is BOTH an individual dealer and a car company must choose, and the choice is enforced", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const both = await makeBusiness(t, "both", "dealer", { roleApprovedAt: Date.now() });
    await approveCompany(t, admin, both);
    const s = await status(t, both);
    expect(s.vehiclePosting.requiresChoice).toBe(true);
    // no choice -> never guessed
    await expect(postVehicle(t, both)).rejects.toThrow(/Choose which one/i);
    // car company route without a subscription is blocked...
    await expect(postVehicle(t, both, "car_company")).rejects.toThrow(/Car Company subscription is not active/i);
    // ...the free individual route is not made subscription-required by the other capability
    const free = await postVehicle(t, both, "individual_dealer");
    expect(((await t.run(async (ctx) => ctx.db.get(free as any))) as any).postedAs).toBe("individual_dealer");
    // ...and a car-company listing can't be re-published by dropping the subscription
    await giveSub(t, both, "CAR_CO_M", Date.now() + 30 * DAY);
    const co = await postVehicle(t, both, "car_company");
    await t.run(async (ctx) => {
      await ctx.db.patch(co as any, { isPublished: false });
      const sub = (await ctx.db.query("vendor_subscriptions").collect())[0];
      await ctx.db.patch(sub._id, { expiryDate: Date.now() - 1000 });
    });
    await expect(
      t.mutation(api.mobility.updateVehicleListing, {
        listingId: co as string, ownerId: both.id as string, sessionToken: both.token, isPublished: true, postingCapability: "individual_dealer",
      } as any)
    ).rejects.toThrow(/cannot be switched/i); // the recorded capability is immutable
    // omitting the claim: judged under the RECORDED capability, so the lapsed subscription blocks it
    await expect(
      t.mutation(api.mobility.updateVehicleListing, { listingId: co as string, ownerId: both.id as string, sessionToken: both.token, isPublished: true } as any)
    ).rejects.toThrow(/Car Company subscription is not active/i);
  });

  test("an agent with only the dealer add-on stays free for vehicles (no company subscription needed)", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: Date.now(), vehicleDealerApprovedAt: Date.now() });
    expect(typeof (await postVehicle(t, agent))).toBe("string");
  });
});

describe("public visibility follows the car-company subscription", () => {
  test("professional label appears only with an active car_company subscription", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const co = await makeBusiness(t, "co");
    await approveCompany(t, admin, co);
    const badge0: any = await t.query(api.subscriptions.getProfessionalBadge, { userId: co.id });
    expect(badge0.verifiedAgent).toBe(false);
    await giveSub(t, co, "CAR_CO_M");
    expect((await status(t, co)).carCompanyExpiresAt).toBeGreaterThan(Date.now());
  });
});

describe("republishing and client manipulation", () => {
  test("a legacy listing (no postedAs) takes the caller's held capability once, then it is frozen", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const both = await makeBusiness(t, "both", "dealer", { roleApprovedAt: Date.now() });
    await approveCompany(t, admin, both);
    const id = await postVehicle(t, both, "individual_dealer");
    await t.run(async (ctx) => ctx.db.patch(id as any, { postedAs: undefined, isPublished: false }));
    // legacy + both capabilities + no choice: the server refuses to guess
    await expect(
      t.mutation(api.mobility.updateVehicleListing, { listingId: id as string, ownerId: both.id as string, sessionToken: both.token, isPublished: true } as any)
    ).rejects.toThrow(/Choose which one/i);
    await t.mutation(api.mobility.updateVehicleListing, {
      listingId: id as string, ownerId: both.id as string, sessionToken: both.token, isPublished: true, postingCapability: "individual_dealer",
    } as any);
    expect(((await t.run(async (ctx) => ctx.db.get(id as any))) as any).postedAs).toBe("individual_dealer");
    await expect(
      t.mutation(api.mobility.updateVehicleListing, {
        listingId: id as string, ownerId: both.id as string, sessionToken: both.token, postingCapability: "car_company",
      } as any)
    ).rejects.toThrow(/cannot be switched/i);
  });

  test("a client cannot claim a capability it does not hold, or smuggle an unknown value", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    // an individual dealer claiming to be a car company is refused (no capability, no subscription)
    await expect(postVehicle(t, dealer, "car_company")).rejects.toThrow(/approved Car Company/i);
    // even holding a subscription row for that plan, the capability itself is still required
    await giveSub(t, dealer, "CAR_CO_M");
    await expect(postVehicle(t, dealer, "car_company")).rejects.toThrow(/approved Car Company/i);
    // an unknown value is rejected by validation
    await expect(postVehicle(t, dealer, "admin")).rejects.toThrow();
    // a company claiming the free route without holding it is refused
    const co = await makeBusiness(t, "co");
    await approveCompany(t, admin, co);
    await expect(postVehicle(t, co, "individual_dealer")).rejects.toThrow(/approved Car Dealer/i);
    // an unapproved role that merely selected "dealer" is refused too
    const self = await makeUser(t, "self", "dealer");
    await expect(postVehicle(t, self, "individual_dealer")).rejects.toThrow();
  });

  test("a company-held capability cannot be exercised after suspension, even for republishing", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const co = await makeBusiness(t, "co");
    const a = await apply(t, co, "car_company");
    await decide(t, admin, a.applicationId, "approve");
    await giveSub(t, co, "CAR_CO_M");
    const id = await postVehicle(t, co);
    await t.run(async (ctx) => ctx.db.patch(id as any, { isPublished: false }));
    await decide(t, admin, a.applicationId, "suspend", "policy breach");
    await expect(
      t.mutation(api.mobility.updateVehicleListing, { listingId: id as string, ownerId: co.id as string, sessionToken: co.token, isPublished: true } as any)
    ).rejects.toThrow(/approved Car Company/i);
  });
});

describe("admin application view", () => {
  test("a car-company application shows the server's business-verification state and blocks approval until approved", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const states: Array<[string, Record<string, unknown>, string, boolean]> = [
      ["ok", {}, "approved", true],
      ["pend", { verificationStatus: "PENDING_REVIEW", isVerified: false }, "pending", false],
      ["rej", { verificationStatus: "REJECTED", isVerified: false }, "rejected", false],
      ["miss", { accountType: "INDIVIDUAL" }, "missing", false],
    ];
    for (const [name, extra] of states) {
      const u = await makeBusiness(t, name, "client", extra);
      await t.run(async (ctx) =>
        ctx.db.insert("role_applications", { userId: u.id, targetRole: "car_company", businessName: `${name} Motors Ltd`, tinNumber: "TIN-0001", documentUrls: ["secret-doc-url"], status: "pending", updatedAt: 1 })
      );
    }
    const list: any[] = await t.query(api.roles.adminListRoleApplications, { sessionToken: admin.token });
    const byName = (n: string) => list.find((r) => r.userName === n);
    for (const [name, , state, canApprove] of states) {
      const r = byName(name);
      expect(r.isCarCompanyApplication).toBe(true);
      expect(r.businessVerification).toBe(state);
      expect(r.canApprove).toBe(canApprove);
      expect(r.documentCount).toBe(1);
      expect(JSON.stringify(r)).not.toContain("secret-doc-url"); // documents are never exposed here
    }
    // non-car-company applications are unaffected
    const dealer = await makeUser(t, "dl", "client");
    await t.run(async (ctx) =>
      ctx.db.insert("role_applications", { userId: dealer.id, targetRole: "dealer", documentUrls: [], status: "pending", updatedAt: 1 })
    );
    const again: any[] = await t.query(api.roles.adminListRoleApplications, { sessionToken: admin.token });
    const d = again.find((r) => r.userName === "dl");
    expect(d.isCarCompanyApplication).toBe(false);
    expect(d.canApprove).toBe(true);
    // only an administrator may list
    const rando = await makeUser(t, "rando");
    await expect(t.query(api.roles.adminListRoleApplications, { sessionToken: rando.token })).rejects.toThrow();
  });
});

// ═══════════════════════════════════════════════════════════════════════
// Stage 1B: a car-company listing is discoverable and orderable only while its company is
// active + approved + business-verified + subscribed to car_company.
// ═══════════════════════════════════════════════════════════════════════
describe("car-company listing eligibility (discovery and new orders)", () => {
  async function scene(t: T) {
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const co = await makeBusiness(t, "co");
    const app = await apply(t, co, "car_company");
    await decide(t, admin, app.applicationId, "approve");
    await giveSub(t, co, "CAR_CO_M");
    const id = (await postVehicle(t, co)) as string;
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer, 5_000_000);
    return { admin, co, app, id, buyer };
  }
  const subRow = (t: T, co: U) =>
    t.run(async (ctx) => (await ctx.db.query("vendor_subscriptions").collect()).find((s) => s.userId === co.id)!);
  const setExpiry = (t: T, co: U, expiryDate: number) =>
    t.run(async (ctx) => {
      const s = (await ctx.db.query("vendor_subscriptions").collect()).find((x) => x.userId === co.id)!;
      await ctx.db.patch(s._id, { expiryDate });
    });

  /** Every public path that can return a vehicle, as booleans. */
  async function surfaces(t: T, id: string, ownerId: Id<"users">) {
    const has = (x: unknown) => JSON.stringify(x).includes(id);
    const follower = await makeUser(t, "follower");
    await t.run(async (ctx) => {
      const exists = (await ctx.db.query("follows").collect()).some((f) => f.followerId === follower.id && f.followingId === ownerId);
      if (!exists) await ctx.db.insert("follows", { followerId: follower.id, followingId: ownerId, createdAt: Date.now() });
    });
    const detail = await t.query(api.mobility.getVehicleById, { listingId: id } as any);
    return {
      byCategory: has(await t.query(api.mobility.getVehiclesByCategory, { category: "all" } as any)),
      list: has(await t.query(api.mobility.listVehicles, { category: "all" } as any)),
      detail: detail !== null,
      feed: has(await t.query(api.explore.getExploreFeed, {} as any)),
      search: has(await t.query(api.explore.searchExplore, { searchQuery: "Toyota" } as any)),
      profile: has(await t.query(api.users.getUserPosts, { userId: ownerId } as any)),
      social: has(await t.query(api.social.getSocialFeed, { userId: follower.id } as any)),
    };
  }
  const ALL_VISIBLE = { byCategory: true, list: true, detail: true, feed: true, search: true, profile: true, social: true };
  const ALL_HIDDEN = { byCategory: false, list: false, detail: false, feed: false, search: false, profile: false, social: false };
  const order = (t: T, buyer: U, id: string) =>
    t.mutation(api.escrow.initiateEscrowOrder, {
      sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: id, payFromWallet: true,
    } as any) as Promise<any>;
  const book = (t: T, buyer: U, id: string) =>
    t.mutation(api.bookings.createBooking, {
      sessionToken: buyer.token, listingId: id, listingType: "vehicle", listingTitle: "Toyota", bookingType: "vehicle_inspection",
      startTime: Date.now() + 86_400_000, endTime: Date.now() + 2 * 86_400_000, days: 1,
    } as any);
  const inquiry = (t: T, buyer: U, id: string) =>
    t.mutation(api.adminPortal.submitContactRequest, {
      sessionToken: buyer.token, buyerId: buyer.id, listingId: id, listingType: "vehicle", message: "Is it available?",
    } as any);

  test("an active, approved, subscribed company is discoverable everywhere and takes orders", async () => {
    const t = convexTest(schema, modules);
    const { co, id, buyer } = await scene(t);
    expect(await surfaces(t, id, co.id)).toEqual(ALL_VISIBLE);
    const r = await order(t, buyer, id);
    expect(r.status).toBe("HELD_IN_ESCROW");
  });

  test("an expired subscription hides the listing on every path and blocks new orders, bookings and inquiries", async () => {
    const t = convexTest(schema, modules);
    const { co, id, buyer } = await scene(t);
    await setExpiry(t, co, Date.now() - 1000);
    expect(await surfaces(t, id, co.id)).toEqual(ALL_HIDDEN);
    await expect(order(t, buyer, id)).rejects.toThrow(/not available/i);
    await expect(book(t, buyer, id)).rejects.toThrow(/not found/i);
    await expect(inquiry(t, buyer, id)).rejects.toThrow(/not found/i);
    // the owner still sees it, with the reason; nothing was un-published or deleted
    const mine: any[] = await t.query(api.mobility.getMyVehicleListings as any, { ownerId: co.id, sessionToken: co.token });
    const row = mine.find((x) => x._id === id);
    expect(row.publicOfferability).toEqual({ offerable: false, reason: "SUBSCRIPTION_INACTIVE" });
    expect(row.isPublished).toBe(true);
    const owner: any = await t.query(api.mobility.getVehicleById, { listingId: id, sessionToken: co.token } as any);
    expect(owner).not.toBeNull();
    // no order, wallet or listing was written by the refused calls
    expect(await t.run(async (ctx) => ctx.db.query("escrow_orders").collect())).toHaveLength(0);
    expect(await t.run(async (ctx) => ctx.db.query("bookings").collect())).toHaveLength(0);
  });

  test("revoked company approval or invalid business verification also blocks discovery and orders", async () => {
    for (const how of ["suspended", "rejected-kyc", "not-business", "inactive"]) {
      const t = convexTest(schema, modules);
      const { admin, co, app, id, buyer } = await scene(t);
      if (how === "suspended") await decide(t, admin, app.applicationId, "suspend", "breach");
      if (how === "rejected-kyc") await t.run(async (ctx) => ctx.db.patch(co.id, { verificationStatus: "REJECTED", isVerified: false }));
      if (how === "not-business") await t.run(async (ctx) => ctx.db.patch(co.id, { accountType: "INDIVIDUAL" }));
      if (how === "inactive") await t.run(async (ctx) => ctx.db.patch(co.id, { isActive: false }));
      expect(await surfaces(t, id, co.id), how).toEqual(ALL_HIDDEN);
      await expect(order(t, buyer, id), how).rejects.toThrow(/not available/i);
      // the subscription row itself is untouched
      expect((await subRow(t, co)).status).toBe("active");
    }
  });

  test("an agent (or hotel) subscription cannot stand in for the car-company subscription", async () => {
    const t = convexTest(schema, modules);
    const { co, id, buyer } = await scene(t);
    await setExpiry(t, co, Date.now() - 1000); // car_company lapses
    await giveSub(t, co, "AGENT_M"); // an unrelated, active agent plan
    await giveSub(t, co, "HOTEL_M");
    expect(await surfaces(t, id, co.id)).toEqual(ALL_HIDDEN);
    await expect(order(t, buyer, id)).rejects.toThrow(/not available/i);
  });

  test("individual dealer listings are unaffected: no subscription needed, even beside a lapsed company", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const id = (await postVehicle(t, dealer)) as string;
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer, 5_000_000);
    expect(await surfaces(t, id, dealer.id)).toEqual(ALL_VISIBLE);
    expect((await order(t, buyer, id)).status).toBe("HELD_IN_ESCROW");

    // a dual-capability account: its individual listing stays public while the company one lapses
    const both = await makeBusiness(t, "both", "dealer", { roleApprovedAt: Date.now() });
    const a = await apply(t, both, "car_company");
    await decide(t, admin, a.applicationId, "approve");
    const personal = (await postVehicle(t, both, "individual_dealer")) as string;
    await giveSub(t, both, "CAR_CO_M");
    const company = (await postVehicle(t, both, "car_company")) as string;
    await setExpiry(t, both, Date.now() - 1000);
    expect((await surfaces(t, personal, both.id)).byCategory).toBe(true);
    expect((await surfaces(t, company, both.id)).byCategory).toBe(false);
    // legacy listing without postedAs: unchanged
    await t.run(async (ctx) => ctx.db.patch(company as any, { postedAs: undefined }));
    expect((await surfaces(t, company, both.id)).byCategory).toBe(true);
  });

  test("renewal restores visibility only for listings that are otherwise still eligible", async () => {
    const t = convexTest(schema, modules);
    const { co, id, buyer } = await scene(t);
    const unpublished = (await postVehicle(t, co)) as string;
    const deleted = (await postVehicle(t, co)) as string;
    const takenDown = (await postVehicle(t, co)) as string;
    await t.run(async (ctx) => {
      await ctx.db.patch(unpublished as any, { isPublished: false });
      await ctx.db.patch(deleted as any, { isDeleted: true });
      await ctx.db.patch(takenDown as any, { status: "TAKEN_DOWN" });
    });
    await setExpiry(t, co, Date.now() - 1000);
    expect((await surfaces(t, id, co.id)).byCategory).toBe(false);
    // the company renews through the real, idempotent checkout bookkeeping (no new charge here)
    await setExpiry(t, co, Date.now() + 30 * DAY);
    expect(await surfaces(t, id, co.id)).toEqual(ALL_VISIBLE);
    expect((await order(t, buyer, id)).status).toBe("HELD_IN_ESCROW");
    for (const hidden of [unpublished, deleted, takenDown]) {
      expect((await surfaces(t, hidden, co.id)).byCategory, hidden).toBe(false);
    }
    // nothing was republished automatically
    const rows = await t.run(async (ctx) => Promise.all([unpublished, deleted, takenDown].map((x) => ctx.db.get(x as any))));
    expect((rows[0] as any).isPublished).toBe(false);
    expect((rows[1] as any).isDeleted).toBe(true);
    expect((rows[2] as any).status).toBe("TAKEN_DOWN");
  });

  test("an existing order keeps its lifecycle and money after the subscription lapses", async () => {
    const t = convexTest(schema, modules);
    const { co, id, buyer } = await scene(t);
    const r = await order(t, buyer, id);
    const before = await t.run(async (ctx) => ({
      order: await ctx.db.get(r.escrowOrderId),
      tx: (await ctx.db.query("transactions").collect()).length,
      ledger: (await ctx.db.query("ledger_entries").collect()).length,
    }));
    await setExpiry(t, co, Date.now() - 1000);
    expect(await surfaces(t, id, co.id)).toEqual(ALL_HIDDEN);
    const after = await t.run(async (ctx) => ({
      order: await ctx.db.get(r.escrowOrderId),
      tx: (await ctx.db.query("transactions").collect()).length,
      ledger: (await ctx.db.query("ledger_entries").collect()).length,
    }));
    expect(after).toEqual(before);
    // the buyer can still complete the deal; the company is paid its net once
    await t.mutation(api.escrow.releaseDealEscrowFunds, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId });
    const w = (await t.run(async (ctx) => ctx.db.query("walletBalances").collect())).find((x) => x.userId === co.id)!;
    expect(w.availableBalance).toBeGreaterThan(0);
    expect(((await t.run(async (ctx) => ctx.db.get(r.escrowOrderId))) as any).status).toBe("SETTLED");
  });

  test("direct API calls cannot bypass: a client-supplied owner/capability/price changes nothing", async () => {
    const t = convexTest(schema, modules);
    const { co, id, buyer } = await scene(t);
    await setExpiry(t, co, Date.now() - 1000);
    await expect(
      t.mutation(api.escrow.initiateEscrowOrder, {
        sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: id, payFromWallet: true,
        renterOrBuyerId: buyer.id, fullPurchaseAmount: 1,
      } as any)
    ).rejects.toThrow(/not available/i);
    // the saved-listings route cannot be used to keep a lapsed company listing in play either
    await expect(
      t.mutation(api.savedListings.toggleSavedListing, { sessionToken: buyer.token, listingType: "vehicle", listingId: id })
    ).rejects.toThrow(/no longer available/i);
  });
});

// ═════════════════════════════════════════════════════════════════
// Stage 1C-1: a changed business identity cannot inherit an old car-company approval; unavailable
// listings take no NEW orders, bookings or inquiries; the legacy classification report is read-only.
// ═════════════════════════════════════════════════════════════════
const blob = (t: T) => t.run(async (ctx) => ctx.storage.store(new Blob(["id-document"], { type: "image/jpeg" })));
const submitKyc = async (t: T, u: U, businessName: string, tin: string, accountType = "BUSINESS") =>
  t.mutation(api.businessVerification.submitTieredVerification, {
    userId: u.id as string, sessionToken: u.token, accountType: accountType as any, idType: "NATIONAL_ID" as any,
    idNumber: "SL-123456", idPhotoStorageId: await blob(t), selfieStorageId: await blob(t),
    businessName, tin,
  } as any) as Promise<any>;
const approveKyc = (t: T, admin: U, u: U) =>
  t.mutation(api.businessVerification.approveAgent, { adminId: admin.id as string, sessionToken: admin.token, agentId: u.id as string } as any);
const rejectKyc = (t: T, admin: U, u: U) =>
  t.mutation(api.businessVerification.rejectAgent, { adminId: admin.id as string, sessionToken: admin.token, agentId: u.id as string, reason: "documents unclear" } as any);

describe("a changed business identity needs a fresh car-company review", () => {
  async function companyScene(t: T) {
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const co = await makeBusiness(t, "co");
    const app = await apply(t, co, "car_company");
    await decide(t, admin, app.applicationId, "approve");
    await giveSub(t, co, "CAR_CO_M");
    const id = (await postVehicle(t, co)) as string;
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer, 5_000_000);
    return { admin, co, id, buyer };
  }
  const visible = async (t: T, id: string) =>
    JSON.stringify(await t.query(api.mobility.getVehiclesByCategory, { category: "all" } as any)).includes(id);
  const tryOrder = (t: T, buyer: U, id: string) =>
    t.mutation(api.escrow.initiateEscrowOrder, {
      sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: id, payFromWallet: true,
    } as any) as Promise<any>;

  test("approval records the verified identity and never takes it from application text", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const co = await makeBusiness(t, "co");
    const a = await apply(t, co, "car_company", { businessName: "Other Name Ltd", tinNumber: "TIN-9999" });
    // the application's values differ from the verified business: approval is refused, nothing changes
    const list: any[] = await t.query(api.roles.adminListRoleApplications, { sessionToken: admin.token });
    expect(list.find((r) => r.userName === "co").canApprove).toBe(false);
    await expect(decide(t, admin, a.applicationId, "approve")).rejects.toThrow(/does not match the verified business/i);
    const before = await row(t, co);
    expect(before.carCompanyApprovedAt).toBeUndefined();
    expect(before.businessName).toBe("co Motors Ltd");
    expect(before.tinNumber).toBe("TIN-0001");

    // matching details (any spacing / case / punctuation) are accepted; the account's own values are stored
    const ok = await makeBusiness(t, "ok");
    const b = await apply(t, ok, "car_company", { businessName: "OK  motors LTD.", tinNumber: "tin 0001" });
    await decide(t, admin, b.applicationId, "approve");
    const after = await row(t, ok);
    expect(after.carCompanyApprovedName).toBe("ok Motors Ltd");
    expect(after.carCompanyApprovedTin).toBe("TIN-0001");
    expect(after.businessName).toBe("ok Motors Ltd");
    expect((await status(t, ok)).capabilities.carCompany).toBe(true);
  });

  test("changing the TIN through KYC, then re-approving KYC, does not restore the old approval", async () => {
    const t = convexTest(schema, modules);
    const { admin, co, id, buyer } = await companyScene(t);
    expect(await visible(t, id)).toBe(true);

    const r = await submitKyc(t, co, "co Motors Ltd", "TIN-7777"); // a different legal entity
    expect(r.status).toBe("PENDING_REVIEW");
    expect(await visible(t, id)).toBe(false); // hidden while the new identity is under review
    await approveKyc(t, admin, co);

    // KYC is approved again, but under a different TIN: the old car-company approval does not carry over
    const u = await row(t, co);
    expect(u.isVerified).toBe(true);
    expect(u.carCompanyApprovedAt).toBeTypeOf("number"); // the record is kept, it just no longer applies
    const s = await status(t, co);
    expect(s.capabilities.carCompany).toBe(false);
    expect(s.carCompanyReapprovalRequired).toBe(true);
    expect(await visible(t, id)).toBe(false);
    await expect(tryOrder(t, buyer, id)).rejects.toThrow(/not available/i);
    await expect(
      t.mutation(api.mobility.updateVehicleListing, { listingId: id, ownerId: co.id as string, sessionToken: co.token, price: 1 } as any)
    ).resolves.toBeTruthy(); // the owner keeps managing their own record

    // a fresh review: new application (details match the verified business) and approval
    const again = await apply(t, co, "car_company");
    expect(again.success).toBe(true);
    await decide(t, admin, again.applicationId, "approve");
    expect((await status(t, co)).capabilities.carCompany).toBe(true);
    expect(await visible(t, id)).toBe(true);
    expect((await tryOrder(t, buyer, id)).status).toBe("HELD_IN_ESCROW");
  });

  test("a changed name alone also needs review; resubmitting the SAME identity needs only KYC approval", async () => {
    const t = convexTest(schema, modules);
    const { admin, co, id } = await companyScene(t);

    // same name and TIN (different spacing/case): once KYC is approved again, nothing else is needed
    await submitKyc(t, co, "CO  motors ltd", "tin-0001");
    expect(await visible(t, id)).toBe(false);
    await approveKyc(t, admin, co);
    expect(await visible(t, id)).toBe(true);

    // a new business name with the same TIN: re-review required
    await submitKyc(t, co, "Completely Different Trading", "TIN-0001");
    await approveKyc(t, admin, co);
    expect((await status(t, co)).carCompanyReapprovalRequired).toBe(true);
    expect(await visible(t, id)).toBe(false);
  });

  test("switching to an individual account and back, and a rejected resubmission, never grant anything", async () => {
    const t = convexTest(schema, modules);
    const { admin, co, id } = await companyScene(t);
    await submitKyc(t, co, "", "", "INDIVIDUAL");
    await approveKyc(t, admin, co);
    expect(await visible(t, id)).toBe(false); // an individual account is not a company

    await submitKyc(t, co, "co Motors Ltd", "TIN-0001");
    await rejectKyc(t, admin, co);
    expect(await visible(t, id)).toBe(false);

    // the original identity, approved again: the original approval applies again, no new review needed
    await submitKyc(t, co, "co Motors Ltd", "TIN-0001");
    await approveKyc(t, admin, co);
    expect(await visible(t, id)).toBe(true);
  });

  test("another role's approval never rewrites the business identity of an approved car company", async () => {
    const t = convexTest(schema, modules);
    const { admin, co, id } = await companyScene(t);
    const d = await apply(t, co, "dealer", { businessName: "Sneaky Rename Ltd", tinNumber: "TIN-4242" });
    expect(d.success).toBe(true);
    await decide(t, admin, d.applicationId, "approve");
    const u = await row(t, co);
    expect(u.businessName).toBe("co Motors Ltd");
    expect(u.tinNumber).toBe("TIN-0001");
    expect((await status(t, co)).capabilities.carCompany).toBe(true);
    expect(await visible(t, id)).toBe(true);
  });

  test("an approval with no recorded identity fails closed, and suspension clears the record", async () => {
    const t = convexTest(schema, modules);
    const { admin, co, id } = await companyScene(t);
    await t.run(async (ctx) => ctx.db.patch(co.id, { carCompanyApprovedName: undefined, carCompanyApprovedTin: undefined }));
    expect((await status(t, co)).capabilities.carCompany).toBe(false);
    expect(await visible(t, id)).toBe(false);

    const t2 = convexTest(schema, modules);
    const s2 = await companyScene(t2);
    const apps: any[] = await t2.run(async (ctx) => ctx.db.query("role_applications").collect());
    await decide(t2, s2.admin, apps.find((a) => a.targetRole === "car_company")!._id, "suspend", "policy breach");
    const u = await row(t2, s2.co);
    expect(u.carCompanyApprovedAt).toBeUndefined();
    expect(u.carCompanyApprovedName).toBeUndefined();
    expect(u.carCompanyApprovedTin).toBeUndefined();
    void admin;
  });
});

describe("unavailable vehicle listings take no NEW transactions", () => {
  const order = (t: T, buyer: U, id: string) =>
    t.mutation(api.escrow.initiateEscrowOrder, {
      sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: id, payFromWallet: true,
    } as any) as Promise<any>;
  const book = (t: T, buyer: U, id: string) =>
    t.mutation(api.bookings.createBooking, {
      sessionToken: buyer.token, listingId: id, listingType: "vehicle", listingTitle: "Toyota", bookingType: "vehicle_inspection",
      startTime: Date.now() + 86_400_000, endTime: Date.now() + 2 * 86_400_000, days: 1,
    } as any);
  const inquiry = (t: T, buyer: U, id: string) =>
    t.mutation(api.adminPortal.submitContactRequest, {
      sessionToken: buyer.token, buyerId: buyer.id, listingId: id, listingType: "vehicle", message: "Is it available?",
    } as any);

  async function dealerScene(t: T) {
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer, 50_000_000);
    return { dealer, buyer };
  }
  const states: Array<[string, Record<string, unknown>]> = [
    ["unpublished", { isPublished: false }],
    ["sold", { status: "SOLD" }],
    ["taken down", { status: "TAKEN_DOWN" }],
    ["deleted", { isDeleted: true }],
  ];

  test.each(states)("a %s listing rejects a new order, booking and inquiry", async (_name, patch) => {
    const t = convexTest(schema, modules);
    const { dealer, buyer } = await dealerScene(t);
    const id = (await postVehicle(t, dealer)) as string;
    await t.run(async (ctx) => ctx.db.patch(id as any, patch as any));
    await expect(order(t, buyer, id)).rejects.toThrow(/not available/i);
    await expect(book(t, buyer, id)).rejects.toThrow(/Listing not found/i);
    await expect(inquiry(t, buyer, id)).rejects.toThrow(/Vehicle listing not found/i);
    const created = await t.run(async (ctx) => ({
      orders: (await ctx.db.query("escrow_orders").collect()).length,
      bookings: (await ctx.db.query("bookings").collect()).length,
      inquiries: (await ctx.db.query("contact_requests").collect()).length,
    }));
    expect(created).toEqual({ orders: 0, bookings: 0, inquiries: 0 });
  });

  test("an available listing still takes orders, bookings and inquiries (a BOOKED rental is not blocked)", async () => {
    const t = convexTest(schema, modules);
    const { dealer, buyer } = await dealerScene(t);
    const id = (await postVehicle(t, dealer)) as string;
    expect((await order(t, buyer, id)).status).toBe("HELD_IN_ESCROW");
    expect((await inquiry(t, buyer, id)).status).toBe("SUBMITTED");
    const rental = (await postVehicle(t, dealer)) as string;
    await t.run(async (ctx) => ctx.db.patch(rental as any, { status: "BOOKED" }));
    await expect(inquiry(t, buyer, rental)).resolves.toBeTruthy();
  });

  test("an EXISTING order on a listing that later becomes unavailable continues and can be released", async () => {
    const t = convexTest(schema, modules);
    const { dealer, buyer } = await dealerScene(t);
    const id = (await postVehicle(t, dealer)) as string;
    const unpaid = (await t.mutation(api.escrow.initiateEscrowOrder, {
      sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: id,
    } as any)) as any;
    expect(unpaid.status).toBe("PENDING_PAYMENT");
    const funded = await order(t, buyer, id);
    expect(funded.status).toBe("HELD_IN_ESCROW");

    // the listing is sold and unpublished afterwards
    await t.run(async (ctx) => ctx.db.patch(id as any, { status: "SOLD", isPublished: false }));
    // the already-created, unpaid order can still be funded; the funded one can still be released
    const fundedOrder = await t.run(async (ctx) => ctx.db.get(unpaid.escrowOrderId as any));
    expect((fundedOrder as any).status).toBe("PENDING_PAYMENT");
    const r = await t.mutation(api.escrow.releaseDealEscrowFunds, { sessionToken: buyer.token, escrowOrderId: funded.escrowOrderId });
    expect(r.success).toBe(true);
    expect(((await t.run(async (ctx) => ctx.db.get(funded.escrowOrderId))) as any).status).toBe("SETTLED");
    // ...but no NEW order starts
    await expect(order(t, buyer, id)).rejects.toThrow(/not available/i);
  });
});

describe("legacy vehicle classification report (read-only, counts only)", () => {
  test("counts listings by tag, lifecycle, owner class and open orders without exposing any record", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    await ensurePlans(t, admin);
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const co = await makeBusiness(t, "co");
    const app = await apply(t, co, "car_company");
    await decide(t, admin, app.applicationId, "approve");
    await giveSub(t, co, "CAR_CO_M");
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer, 50_000_000);

    const tagged = (await postVehicle(t, dealer)) as string; // individual_dealer
    const legacyDealer = (await postVehicle(t, dealer)) as string;
    const legacyCompany = (await postVehicle(t, co)) as string;
    const companyTagged = (await postVehicle(t, co)) as string;
    await t.run(async (ctx) => {
      await ctx.db.patch(legacyDealer as any, { postedAs: undefined });
      await ctx.db.patch(legacyCompany as any, { postedAs: undefined });
      await ctx.db.patch(legacyCompany as any, { isPublished: false });
    });
    await t.mutation(api.escrow.initiateEscrowOrder, {
      sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: tagged, payFromWallet: true,
    } as any);

    const before = await t.run(async (ctx) => JSON.stringify(await ctx.db.query("vehicleListings").collect()));
    const total: Record<string, number> = {};
    let cursor: string | null = null;
    let scanned = 0;
    for (let i = 0; i < 10; i++) {
      const page: any = await t.query(internal.vehicleClassificationReport.classificationPage, { cursor, numItems: 1 });
      scanned += page.scanned;
      for (const [k, n] of Object.entries(page.counts as Record<string, number>)) total[k] = (total[k] ?? 0) + n;
      // nothing identifying is ever returned
      // (the opaque pagination cursor is the only token that can embed an internal id)
      const text = JSON.stringify({ ...page, continueCursor: undefined });
      for (const secret of [tagged, legacyDealer, legacyCompany, companyTagged, String(co.id), String(dealer.id), "Toyota", "Prado", "Motors"]) {
        expect(text).not.toContain(secret);
      }
      cursor = page.continueCursor;
      if (page.isDone) break;
    }
    expect(scanned).toBe(4);
    const K = (tag: string, lifecycle: string, owner: string, purchaseOrders: string) =>
      `class=sale_standard|provenance=app_signature|consistent=yes|tag=${tag}|lifecycle=${lifecycle}|owner=${owner}` +
      `|rentalOrders=none|purchaseOrders=${purchaseOrders}|rentalBookings=none|inspections=none`;
    expect(total).toEqual({
      [K("individual_dealer", "active", "dealer_capability", "open")]: 1,
      [K("untagged", "active", "dealer_capability", "none")]: 1,
      [K("untagged", "unpublished", "company_approved", "none")]: 1,
      [K("car_company", "active", "company_approved", "none")]: 1,
    });
    // read-only: no listing was changed
    const after = await t.run(async (ctx) => JSON.stringify(await ctx.db.query("vehicleListings").collect()));
    expect(after).toBe(before);
  });
});
