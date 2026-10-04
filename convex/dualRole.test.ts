/// <reference types="vite/client" />
// Real Estate Agent and Car Dealer are separate, admin-approved authorisations. An agent never
// gets vehicle rights by being an agent; a separately approved Car Dealer application ADDS them to
// the same account (one profile: "Real Estate Agent & Car Dealer"); suspending one keeps the other.
// Nobody can grant themselves a role.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
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
      email: `${name}${seq}@t.vx`, phone: `+2327900${1000 + seq}`, name, role: role as any,
      isVerified: true, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    } as any)
  );
  return { id, token };
}

async function subscribe(t: T, admin: U, user: U) {
  const plans = await t.run(async (ctx) => ctx.db.query("subscription_plans").collect());
  if (!plans.some((p) => p.tierCode === "AGENT_M")) {
    await t.mutation(api.subscriptions.adminUpsertPlan, {
      sessionToken: admin.token, tierCode: "AGENT_M", name: "Agent Monthly", roleTarget: "agent", basePrice: 100, currency: "SLE",
      billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
    });
  }
  await t.run(async (ctx) => {
    const p = (await ctx.db.query("subscription_plans").collect()).find((x) => x.tierCode === "AGENT_M")!;
    await ctx.db.insert("vendor_subscriptions", {
      userId: user.id, planId: p._id, tierCode: "AGENT_M", status: "active", startDate: Date.now() - DAY, expiryDate: Date.now() + 30 * DAY,
      amountPaid: 100, currency: "SLE", paymentReference: `sub-${user.id}`, paymentMethod: "wallet", autoRenew: false, createdAt: Date.now(), updatedAt: Date.now(),
    });
  });
}

const status = (t: T, u: U) => t.query(api.subscriptions.getMyProfessionalStatus, { sessionToken: u.token }) as Promise<any>;
const apply = (t: T, u: U, targetRole: "agent" | "dealer") =>
  t.mutation(api.users.applyRoleUpgrade, { sessionToken: u.token, userId: u.id, targetRole }) as Promise<any>;
const decide = (t: T, admin: U, applicationId: string, decision: "approve" | "reject" | "suspend", notes?: string) =>
  t.mutation(api.roles.adminDecideRoleApplication, {
    sessionToken: admin.token, applicationId: applicationId as Id<"role_applications">, decision, ...(notes ? { notes } : {}),
  });
const postVehicle = (t: T, u: U) =>
  t.mutation(api.mobility.createVehicleListing, {
    ownerId: u.id, sessionToken: u.token, make: "Toyota", model: "Prado", year: 2022, salePrice: 900000, imageStorageIds: [],
    category: "car_sale", listingIntent: "sale",
  } as any);
const postProperty = (t: T, u: U) =>
  t.mutation(api.realEstate.createPropertyListing, {
    ownerId: u.id, sessionToken: u.token, title: "Villa", description: "Nice", category: "sale", price: 1, address: "x",
    city: "Lumley", imageStorageIds: [],
  });
const user = (t: T, u: U) => t.run(async (ctx) => ctx.db.get(u.id)) as Promise<any>;

describe("Real Estate Agent and Car Dealer stay separate", () => {
  test("an approved, subscribed agent cannot post cars", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: Date.now() });
    await subscribe(t, admin, agent);
    const s = await status(t, agent);
    expect(s).toMatchObject({ canPostProperty: true, canPostVehicle: false, isCarDealer: false, professionalTitle: "Real Estate Agent" });
    await expect(postVehicle(t, agent)).rejects.toThrow(/Car Dealer/i);
  });

  test("a separately approved Car Dealer application adds car rights to the same agent account", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: Date.now() });
    await subscribe(t, admin, agent);
    const app = await apply(t, agent, "dealer");
    expect(app.success).toBe(true);
    // a pending application grants nothing
    expect((await status(t, agent)).canPostVehicle).toBe(false);
    await decide(t, admin, app.applicationId, "approve");

    const u = await user(t, agent);
    expect(u.role).toBe("agent"); // the agent role (and workspace) is kept
    expect(typeof u.vehicleDealerApprovedAt).toBe("number");
    const s = await status(t, agent);
    expect(s).toMatchObject({
      role: "real_estate_agent", canPostProperty: true, canPostVehicle: true, isCarDealer: true,
      professionalTitle: "Real Estate Agent & Car Dealer",
    });
    await expect(postVehicle(t, agent)).resolves.toBeTypeOf("string");
    await expect(postProperty(t, agent)).resolves.toBeTypeOf("string");
    // applying again for what the account already holds is refused
    expect((await apply(t, agent, "dealer")).errorCode).toBe("ALREADY_GRANTED");
    // the public profile shows the combined title (nothing private)
    const viewer = await makeUser(t, "viewer");
    const profile: any = await t.query(api.users.getUserProfile, { userId: agent.id, sessionToken: viewer.token });
    expect(profile.professionalTitle).toBe("Real Estate Agent & Car Dealer");
    expect(profile.email).toBeUndefined();
    expect(profile.phone).toBeUndefined();
  });

  test("suspending the Car Dealer add-on keeps the agent role; suspending the agent role keeps the dealer role", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: Date.now() });
    await subscribe(t, admin, agent);
    const dealerApp = await apply(t, agent, "dealer");
    await decide(t, admin, dealerApp.applicationId, "approve");
    await decide(t, admin, dealerApp.applicationId, "suspend", "Unpaid vehicle fees");
    let s = await status(t, agent);
    expect(s).toMatchObject({ role: "real_estate_agent", canPostProperty: true, canPostVehicle: false, isCarDealer: false });

    // a dealer who becomes an agent too, then loses the agent role
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() - DAY });
    const agentApp = await apply(t, dealer, "agent");
    await decide(t, admin, agentApp.applicationId, "approve");
    s = await status(t, dealer);
    expect(s).toMatchObject({ role: "real_estate_agent", canPostVehicle: true, isCarDealer: true, canPostProperty: false });
    await subscribe(t, admin, dealer);
    expect((await status(t, dealer)).canPostProperty).toBe(true);
    await decide(t, admin, agentApp.applicationId, "suspend", "Licence expired");
    s = await status(t, dealer);
    expect(s).toMatchObject({ role: "vehicle_dealer", canPostVehicle: true, canPostProperty: false, professionalTitle: "Car Dealer" });
  });

  test("a car dealer gets no property rights", async () => {
    const t = convexTest(schema, modules);
    const dealer = await makeUser(t, "dealer", "dealer", { roleApprovedAt: Date.now() });
    const s = await status(t, dealer);
    expect(s).toMatchObject({ canPostVehicle: true, canPostProperty: false, isCarDealer: true });
    await expect(postProperty(t, dealer)).rejects.toThrow(/Real Estate/i);
  });
});

describe("nobody grants themselves a role", () => {
  test("a client's application is only pending; switching the active role grants nothing; admin decisions are admin-only", async () => {
    const t = convexTest(schema, modules);
    const client = await makeUser(t, "client");
    for (const role of ["agent", "dealer"] as const) {
      const c2 = await makeUser(t, `client_${role}`);
      const app = await apply(t, c2, role);
      expect(app.success).toBe(true);
      const s = await status(t, c2);
      expect(s).toMatchObject({ canPostProperty: false, canPostVehicle: false, isCarDealer: false });
      await expect(decide(t, c2, app.applicationId, "approve")).rejects.toThrow(/administrator/i);
    }
    const switched: any = await t.mutation(api.users.switchActiveRole, { sessionToken: client.token, userId: client.id, targetRole: "agent" });
    expect(switched.success).toBe(false);
    await expect(postProperty(t, client)).rejects.toThrow();
    await expect(postVehicle(t, client)).rejects.toThrow();
    // the profile cannot be used to change the role either (no such field)
    await expect(
      t.mutation(api.users.updateUserProfile, { sessionToken: client.token, userId: client.id, role: "agent" } as any)
    ).rejects.toThrow();
    expect((await user(t, client)).role).toBe("client");
  });
});
