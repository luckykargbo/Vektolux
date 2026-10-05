/// <reference types="vite/client" />
// Existing agents approved by the OLD admin flow keep their approval in the new architecture.
//
// The old flow (businessVerification.approveAgent) set isVerifiedAgent: true and marked the agent
// application "approved" but never changed users.role — so an agent who registered as a client was
// still role "client" and the current server classified them as a client (no workspace). The role is
// now restored from that stored evidence (backfill + login), never from the flag alone, and never for
// admins, other business roles, pending / rejected / suspended applications or KYC-only approvals.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";
import { legacyAgentGrace } from "./lib/permissions";
import { legacyAgentRestoreDecision } from "./lib/legacyRoles";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string; email: string };
const DAY = 24 * 60 * 60 * 1000;
const PASSWORD = "Correct-Horse-9";
let seq = 0;

/** A real registered account (registerUser), so login works exactly as in production. */
async function register(t: T, name: string): Promise<U> {
  seq += 1;
  const email = `${name}${seq}@legacy.vx`;
  const r: any = await t.mutation(api.auth.registerUser, { name, email, phone: `+2327710${1000 + seq}`, password: PASSWORD, role: "client" });
  expect(r.success).toBe(true);
  return { id: r.userId as Id<"users">, token: r.sessionToken, email };
}

async function makeAdmin(t: T): Promise<U> {
  seq += 1;
  const token = `sess_admin_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `admin${seq}@legacy.vx`, phone: `+2327720${1000 + seq}`, name: "Admin", role: "admin",
      isVerified: true, isActive: true, sessionToken: token, updatedAt: Date.now(),
    } as any)
  );
  return { id, token, email: `admin${seq}@legacy.vx` };
}

/** Exactly what the OLD businessVerification.approveAgent wrote (users.role untouched). */
async function oldFlowApproval(t: T, u: U, admin: U, appStatus: "approved" | "pending" | "rejected" | "suspended" = "approved") {
  await t.run(async (ctx) => {
    await ctx.db.insert("role_applications", {
      userId: u.id, targetRole: "agent", businessName: "Kargbo Homes", documentUrls: [], status: appStatus,
      reviewedBy: admin.id, reviewedAt: Date.now() - 30 * DAY, updatedAt: Date.now() - 30 * DAY,
    } as any);
    if (appStatus === "approved") {
      await ctx.db.patch(u.id, {
        verificationStatus: "approved", verificationBadge: "GREEN_TICK", isVerified: true, isVerifiedAgent: true,
        verifiedAt: Date.now() - 30 * DAY, verifiedBy: admin.id,
      } as any);
    }
  });
}

const status = (t: T, u: U) => t.query(api.subscriptions.getMyProfessionalStatus, { sessionToken: u.token }) as Promise<any>;
const userDoc = (t: T, u: U) => t.run(async (ctx) => ctx.db.get(u.id)) as Promise<any>;
const backfill = (t: T, dryRun = false) =>
  t.mutation(internal.legacyRoleMigration.backfillLegacyAgentRoles, dryRun ? { dryRun: true } : {}) as Promise<any>;
const login = (t: T, u: U) => t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: u.email, password: PASSWORD }) as Promise<any>;
const postProperty = (t: T, u: U) =>
  t.mutation(api.realEstate.createPropertyListing, {
    ownerId: u.id, sessionToken: u.token, title: "Villa", description: "Nice", category: "sale", price: 1, address: "x",
    city: "Lumley", imageStorageIds: [],
  });

async function subscribe(t: T, admin: U, u: U) {
  await t.mutation(api.subscriptions.adminUpsertPlan, {
    sessionToken: admin.token, tierCode: "AGENT_M", name: "Agent Monthly", roleTarget: "agent", basePrice: 100, currency: "SLE",
    billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
  });
  await t.run(async (ctx) => {
    const p = (await ctx.db.query("subscription_plans").collect()).find((x) => x.tierCode === "AGENT_M")!;
    await ctx.db.insert("vendor_subscriptions", {
      userId: u.id, planId: p._id, tierCode: "AGENT_M", status: "active", startDate: Date.now() - DAY, expiryDate: Date.now() + 30 * DAY,
      amountPaid: 100, currency: "SLE", paymentReference: `sub-${u.id}`, paymentMethod: "wallet", autoRenew: false, createdAt: Date.now(), updatedAt: Date.now(),
    });
  });
}

describe("legacy approved Real Estate Agents", () => {
  test("1. an old approved agent whose role is already 'agent' is an approved agent today (no migration needed)", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeAdmin(t);
    const agent = await register(t, "oldagent");
    // old registrations stored the role the person picked (registration no longer does)
    await t.run(async (ctx) => ctx.db.patch(agent.id, { role: "agent", activeRole: "agent" } as any));
    await oldFlowApproval(t, agent, admin);
    const s = await status(t, agent);
    expect(s).toMatchObject({ role: "real_estate_agent", roleApproved: true, professionalTitle: "Real Estate Agent" });
    expect(s.capabilities).toMatchObject({ client: true, realEstateAgent: true, carDealer: false, realEstateOwner: false, hotelOperator: false, admin: false });
    const before = await userDoc(t, agent);
    expect((await backfill(t)).restored).toEqual([]); // nothing to do
    const after = await userDoc(t, agent);
    expect(after.role).toBe("agent");
    expect(after.legacyRoleRestoredAt).toBeUndefined();
    expect(after.roleApprovedAt).toBe(before.roleApprovedAt);
  });

  test("2. an old-flow agent still stored as 'client' is restored by the backfill — idempotent, approval kept, legacy status kept", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeAdmin(t);
    const agent = await register(t, "lucky");
    await oldFlowApproval(t, agent, admin);

    // the problem: the current server sees a client
    let s = await status(t, agent);
    expect(s.role).toBe("client");
    expect(s.capabilities.realEstateAgent).toBe(false);

    // a dry run reports and writes nothing
    const dry = await backfill(t, true);
    expect(dry.wouldRestore).toEqual([agent.id]);
    expect((await userDoc(t, agent)).role).toBe("client");

    const run = await backfill(t);
    expect(run.restored).toEqual([agent.id]);
    expect(run.done).toBe(true);
    const u = await userDoc(t, agent);
    expect(u.role).toBe("agent");
    expect(u.activeRole).toBe("agent");
    expect(u.isVerifiedAgent).toBe(true); // the approval is kept
    expect(u.roleApprovedBy).toBe(admin.id); // who approved it (from the application)
    expect(typeof u.legacyRoleRestoredAt).toBe("number");
    expect(u.roleApprovedAt).toBeUndefined(); // still "approved by the old flow"

    s = await status(t, agent);
    expect(s).toMatchObject({ role: "real_estate_agent", roleApproved: true });
    expect(s.capabilities.realEstateAgent).toBe(true);
    // the legacy-agent subscription policy still treats the account as a legacy agent (path A)
    const launch = Date.UTC(2026, 9, 10);
    expect(legacyAgentGrace(u, launch + DAY, launch)).toMatchObject({ eligible: true, active: true });

    // running it again changes nothing
    const again = await backfill(t);
    expect(again.restored).toEqual([]);
    expect(again.skipped.already_has_business_role).toBe(1);
    expect((await userDoc(t, agent)).legacyRoleRestoredAt).toBe(u.legacyRoleRestoredAt);
  });

  test("2b. logging in restores the same account without any admin step, and the login response says 'agent'", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeAdmin(t);
    const agent = await register(t, "lucky");
    await oldFlowApproval(t, agent, admin);
    const r = await login(t, agent);
    expect(r.success).toBe(true);
    expect(r.role).toBe("agent");
    const s = await status(t, { ...agent, token: r.sessionToken });
    expect(s.capabilities.realEstateAgent).toBe(true);
    // a second login is a no-op
    const r2 = await login(t, agent);
    expect(r2.role).toBe("agent");
  });

  test("3. a normal client gets no agent capability (backfill and login change nothing)", async () => {
    const t = convexTest(schema, modules);
    const client = await register(t, "client");
    const r = await login(t, client);
    expect(r.role).toBe("client");
    const s = await status(t, { ...client, token: r.sessionToken });
    expect(s.role).toBe("client");
    expect(s.capabilities).toEqual({ client: true, realEstateAgent: false, realEstateOwner: false, hotelOperator: false, carDealer: false, admin: false });
    expect((await backfill(t)).restored).toEqual([]);
  });

  test("4. a pending agent application grants nothing — even next to an old identity-approval flag", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeAdmin(t);
    const pending = await register(t, "pending");
    await oldFlowApproval(t, pending, admin, "pending");
    // the old queue also approved identity (KYC) submissions with the same flag
    await t.run(async (ctx) => ctx.db.patch(pending.id, { isVerifiedAgent: true } as any));
    expect((await backfill(t)).restored).toEqual([]);
    const r = await login(t, pending);
    expect(r.role).toBe("client");
    expect((await status(t, { ...pending, token: r.sessionToken })).capabilities.realEstateAgent).toBe(false);
  });

  test("4b. the old flag alone (identity / KYC approval, no agent application) is never treated as an agent approval", async () => {
    const t = convexTest(schema, modules);
    const kyc = await register(t, "kyc");
    await t.run(async (ctx) => ctx.db.patch(kyc.id, { isVerifiedAgent: true, verificationStatus: "approved" } as any));
    expect((await login(t, kyc)).role).toBe("client");
    expect((await userDoc(t, kyc)).role).toBe("client");
    expect((await backfill(t, true)).wouldRestore).toEqual([]);
  });

  test("5. a suspended agent gets nothing back — new-flow suspension, and a later suspension over an old approval", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeAdmin(t);
    // new flow: approve, then suspend
    const a = await register(t, "suspended");
    const app: any = await t.mutation(api.users.applyRoleUpgrade, { sessionToken: a.token, userId: a.id, targetRole: "agent" });
    await t.mutation(api.roles.adminDecideRoleApplication, { sessionToken: admin.token, applicationId: app.applicationId, decision: "approve" });
    await t.mutation(api.roles.adminDecideRoleApplication, { sessionToken: admin.token, applicationId: app.applicationId, decision: "suspend", notes: "Complaints" });
    expect((await userDoc(t, a)).role).toBe("client");
    expect((await login(t, a)).role).toBe("client");

    // old flow approval, followed by a NEWER suspended application: the newest decision wins
    const b = await register(t, "oldsuspended");
    await oldFlowApproval(t, b, admin, "approved");
    await t.run(async (ctx) => {
      await ctx.db.insert("role_applications", { userId: b.id, targetRole: "agent", documentUrls: [], status: "suspended", updatedAt: Date.now() } as any);
    });
    expect((await backfill(t)).restored).toEqual([]);
    expect((await login(t, b)).role).toBe("client");

    // and a rejected / suspended verification blocks it too
    const c = await register(t, "rejectedverification");
    await oldFlowApproval(t, c, admin, "approved");
    await t.run(async (ctx) => ctx.db.patch(c.id, { verificationStatus: "rejected" } as any));
    expect((await login(t, c)).role).toBe("client");
  });

  test("admins and other business roles are never rewritten (the admin seed account carries the old flags)", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeAdmin(t);
    await t.run(async (ctx) => ctx.db.patch(admin.id, { isVerifiedAgent: true, isVerifiedMerchant: true } as any));
    await oldFlowApproval(t, { ...admin }, admin, "approved");
    const dealer = await register(t, "dealer");
    await t.run(async (ctx) => ctx.db.patch(dealer.id, { role: "dealer", roleApprovedAt: Date.now() } as any));
    await oldFlowApproval(t, dealer, admin, "approved");
    const run = await backfill(t);
    expect(run.restored).toEqual([]);
    expect((await userDoc(t, admin)).role).toBe("admin");
    expect((await userDoc(t, dealer)).role).toBe("dealer");
    // deactivated accounts are left for an administrator to look at
    const off = await register(t, "inactive");
    await oldFlowApproval(t, off, admin, "approved");
    await t.run(async (ctx) => ctx.db.patch(off.id, { isActive: false } as any));
    expect((await backfill(t)).skipped.inactive).toBe(1);
    expect((await userDoc(t, off)).role).toBe("client");
  });

  test("6 + 7. a restored legacy agent approved as Car Dealer holds BOTH capabilities; the dealer approval does not overwrite the agent role", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeAdmin(t);
    const agent = await register(t, "both");
    await oldFlowApproval(t, agent, admin);
    await backfill(t);
    const app: any = await t.mutation(api.users.applyRoleUpgrade, { sessionToken: agent.token, userId: agent.id, targetRole: "dealer" });
    expect(app.success).toBe(true);
    await t.mutation(api.roles.adminDecideRoleApplication, { sessionToken: admin.token, applicationId: app.applicationId, decision: "approve" });
    const u = await userDoc(t, agent);
    expect(u.role).toBe("agent");
    expect(typeof u.vehicleDealerApprovedAt).toBe("number");
    const s = await status(t, agent);
    expect(s.capabilities).toMatchObject({ realEstateAgent: true, carDealer: true });
    expect(s).toMatchObject({ role: "real_estate_agent", isCarDealer: true, canPostVehicle: true, professionalTitle: "Real Estate Agent & Car Dealer" });
  });

  test("8. without an active subscription the account is still an approved agent; only posting is refused", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeAdmin(t);
    const agent = await register(t, "unsubscribed");
    await oldFlowApproval(t, agent, admin);
    await backfill(t);
    let s = await status(t, agent);
    expect(s).toMatchObject({ role: "real_estate_agent", roleApproved: true, hasActiveSubscription: false, canPostProperty: false });
    expect(s.capabilities.realEstateAgent).toBe(true); // identity is not the subscription
    await expect(postProperty(t, agent)).rejects.toThrow(/subscription/i);
    await subscribe(t, admin, agent);
    s = await status(t, agent);
    expect(s).toMatchObject({ hasActiveSubscription: true, canPostProperty: true });
    await expect(postProperty(t, agent)).resolves.toBeTypeOf("string");
  });

  test("the decision function: exactly the stored evidence, nothing else", () => {
    const base = { role: "client" as const, isVerifiedAgent: true, isActive: true, verificationStatus: "approved" as const };
    const approved = [{ targetRole: "agent" as const, status: "approved" as const }];
    expect(legacyAgentRestoreDecision(base, approved)).toEqual({ restore: true });
    expect(legacyAgentRestoreDecision({ ...base, role: "buyer" as any }, approved)).toEqual({ restore: true });
    expect(legacyAgentRestoreDecision({ ...base, isVerifiedAgent: undefined }, approved)).toMatchObject({ reason: "not_legacy_flagged" });
    expect(legacyAgentRestoreDecision({ ...base, role: "agent" }, approved)).toMatchObject({ reason: "already_has_business_role" });
    expect(legacyAgentRestoreDecision({ ...base, role: "admin" }, approved)).toMatchObject({ reason: "already_has_business_role" });
    expect(legacyAgentRestoreDecision({ ...base, role: "hotel_operator" }, approved)).toMatchObject({ reason: "already_has_business_role" });
    expect(legacyAgentRestoreDecision({ ...base, isActive: false }, approved)).toMatchObject({ reason: "inactive" });
    expect(legacyAgentRestoreDecision({ ...base, verificationStatus: "suspended" }, approved)).toMatchObject({ reason: "verification_withdrawn" });
    expect(legacyAgentRestoreDecision(base, [])).toMatchObject({ reason: "no_agent_application" });
    expect(legacyAgentRestoreDecision(base, [{ targetRole: "dealer", status: "approved" }])).toMatchObject({ reason: "no_agent_application" });
    expect(legacyAgentRestoreDecision(base, [{ targetRole: "agent", status: "rejected" }, ...approved])).toMatchObject({ reason: "agent_application_not_approved" });
  });
});
