/// <reference types="vite/client" />
// Authorization sweep: private data and actions require the owner's / admin's real session.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;

async function makeUser(t: T, name: string, role = "client") {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327500${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
    })
  );
  return { id, token };
}

describe("admin portal functions need the admin's own session", () => {
  test("an admin id alone (or a non-admin session) is refused", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const user = await makeUser(t, "user");
    await expect(t.query(api.adminPortal.getFinancialSummary as any, { adminId: admin.id })).rejects.toThrow();
    await expect(t.query(api.adminPortal.getFinancialSummary as any, { adminId: admin.id, sessionToken: user.token })).rejects.toThrow();
    await expect(t.query(api.admin.getAllUsers as any, { adminId: admin.id })).rejects.toThrow();
  });
});

describe("admin portal: omitting adminId must not skip authorization", () => {
  test("analytics, gateway health, key masks and the probe all need an admin session", async () => {
    const t = convexTest(schema, modules);
    const user = await makeUser(t, "user");
    const admin = await makeUser(t, "admin", "admin");
    await expect(t.query(api.adminPortal.getAdminAnalytics as any, {})).rejects.toThrow();
    await expect(t.query(api.adminPortal.getApiGatewayHealthPanel as any, {})).rejects.toThrow();
    await expect(t.query(api.adminPortal.getApiGatewayHealthPanel as any, { sessionToken: user.token })).rejects.toThrow();
    await expect(
      t.mutation(api.adminPortal.updateGatewayKeyMask as any, { serviceId: "monime", keyName: "k", newMaskedValue: "****" })
    ).rejects.toThrow();
    await expect(t.action(api.adminPortal.testApiGatewayPing as any, { serviceId: "monime" })).rejects.toThrow();
    await expect(t.action(api.adminPortal.testApiGatewayPing as any, { serviceId: "monime", sessionToken: user.token })).rejects.toThrow();
    // an admin session works, and an unsupported service is reported honestly (no invented result)
    const r: any = await t.action(api.adminPortal.testApiGatewayPing as any, { serviceId: "orange_money_sl", sessionToken: admin.token });
    expect(r.status).toBe("not_checked");
    expect(r.success).toBe(false);
    await expect(t.query(api.adminPortal.getAdminAnalytics as any, { sessionToken: admin.token })).resolves.toBeTruthy();
  });
});

describe("private profile and listing data", () => {
  test("email/phone of a profile are visible only to its owner", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const other = await makeUser(t, "other");
    const anon: any = await t.query(api.users.getUserProfile, { userId: owner.id });
    expect(anon.email).toBeUndefined();
    expect(anon.phone).toBeUndefined();
    const asOther: any = await t.query(api.users.getUserProfile, { userId: owner.id, sessionToken: other.token });
    expect(asOther.email).toBeUndefined();
    const asOwner: any = await t.query(api.users.getUserProfile, { userId: owner.id, sessionToken: owner.token });
    expect(asOwner.email).toContain("@t.vx");
  });

  test("'my listings' (private fields) require the owner's session", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const other = await makeUser(t, "other");
    await expect(t.query(api.realEstate.getMyPropertyListings, { ownerId: owner.id })).rejects.toThrow();
    await expect(t.query(api.realEstate.getMyPropertyListings, { ownerId: owner.id, sessionToken: other.token })).rejects.toThrow();
    await expect(t.query(api.mobility.getMyVehicleListings, { ownerId: owner.id, sessionToken: other.token })).rejects.toThrow();
    await expect(t.query(api.realEstate.getMyPropertyListings, { ownerId: owner.id, sessionToken: owner.token })).resolves.toEqual([]);
  });

  test("bio and follow need the matching session", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "a");
    const b = await makeUser(t, "b");
    await expect(t.mutation(api.users.updateBio, { userId: a.id, bio: "hi", sessionToken: b.token })).rejects.toThrow();
    await expect(t.mutation(api.users.updateBio, { userId: a.id, bio: "hi" })).rejects.toThrow();
    await expect(
      t.mutation(api.social.toggleFollow, { currentUserId: a.id, targetUserId: b.id, sessionToken: b.token })
    ).rejects.toThrow();
    await t.mutation(api.users.updateBio, { userId: a.id, bio: "hi", sessionToken: a.token });
    await t.mutation(api.social.toggleFollow, { currentUserId: a.id, targetUserId: b.id, sessionToken: a.token });
  });

  test("an expired session no longer authorises anything", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "a");
    await t.run(async (ctx) => ctx.db.patch(a.id, { sessionExpiresAt: Date.now() - 1000 }));
    await expect(t.mutation(api.users.updateBio, { userId: a.id, bio: "hi", sessionToken: a.token })).rejects.toThrow(/expired/i);
  });
});
