/// <reference types="vite/client" />
// Identity verification (KYC): owner-only submission, admin-only review with a real admin session,
// identity approval is separate from business-role approval, documents are never exposed to others.

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
      email: `${name}${seq}@t.vx`, phone: `+2327600${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
    })
  );
  return { id, token };
}
const blob = (t: T) => t.run(async (ctx) => ctx.storage.store(new Blob(["id-document"], { type: "image/jpeg" })));

async function submit(t: T, u: { id: Id<"users">; token?: string }, asUserId?: Id<"users">) {
  const idPhoto = await blob(t);
  const selfie = await blob(t);
  return t.mutation(api.businessVerification.submitTieredVerification, {
    userId: (asUserId ?? u.id) as string,
    sessionToken: u.token,
    accountType: "INDIVIDUAL" as any,
    idType: "NATIONAL_ID" as any,
    idNumber: "SL-123456",
    idPhotoStorageId: idPhoto,
    selfieStorageId: selfie,
    livenessPassed: true,
    faceMatchPassed: true,
  });
}

describe("KYC submission", () => {
  test("requires the user's own session", async () => {
    const t = convexTest(schema, modules);
    const victim = await makeUser(t, "victim");
    const attacker = await makeUser(t, "attacker");
    await expect(submit(t, { id: victim.id })).rejects.toThrow(/Authentication required/);
    await expect(submit(t, attacker, victim.id)).rejects.toThrow();
    const r = await submit(t, victim);
    expect(r.status).toBe("PENDING_REVIEW");
    const u = await t.run(async (ctx) => ctx.db.get(victim.id));
    expect(u?.isVerified).toBe(false); // nothing granted before admin review
  });

  test("status is readable only by the owner", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "a");
    const b = await makeUser(t, "b");
    await expect(
      t.query(api.businessVerification.getMyVerificationStatus, { userId: a.id, sessionToken: b.token })
    ).rejects.toThrow();
    await expect(t.query(api.businessVerification.getMyVerificationStatus, { userId: a.id })).rejects.toThrow();
  });
});

describe("client-asserted biometrics decide nothing", () => {
  test("claimed liveness/face-match results and scores are ignored: every submission is pending manual review", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "a");
    const b = await makeUser(t, "b");
    const base = async (u: { id: Id<"users">; token: string }, extra: Record<string, unknown>) =>
      t.mutation(api.businessVerification.submitTieredVerification, {
        userId: u.id as string, sessionToken: u.token, accountType: "INDIVIDUAL" as any, idType: "NATIONAL_ID" as any,
        idNumber: "SL-123456", idPhotoStorageId: await blob(t), selfieStorageId: await blob(t), ...extra,
      } as any);
    // a client claiming perfect scores is NOT verified
    const claimedPass: any = await base(a, { livenessPassed: true, faceMatchPassed: true, livenessScore: 99.9, faceMatchScore: 99.9 });
    expect(claimedPass.status).toBe("PENDING_REVIEW");
    // a client claiming failure is not auto-rejected either (no real check ran)
    const claimedFail: any = await base(b, { livenessPassed: false, faceMatchPassed: false });
    expect(claimedFail.status).toBe("PENDING_REVIEW");
    for (const id of [a.id, b.id]) {
      const u = await t.run(async (ctx) => ctx.db.get(id));
      expect(u?.isVerified).toBe(false);
      expect(u?.verificationBadge ?? "NONE").toBe("NONE");
    }
    // new app builds send no biometric fields at all
    const c = await makeUser(t, "c");
    expect(((await base(c, {})) as any).status).toBe("PENDING_REVIEW");
  });
});

describe("KYC admin review", () => {
  test("an admin id without the admin's session cannot read the queue, documents or decide", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const user = await makeUser(t, "user");
    await submit(t, user);
    const docId = await blob(t);

    await expect(t.query(api.businessVerification.getVerificationQueue, { adminId: admin.id })).rejects.toThrow();
    await expect(
      t.query(api.businessVerification.getVerificationQueue, { adminId: admin.id, sessionToken: user.token })
    ).rejects.toThrow();
    await expect(
      t.query(api.businessVerification.getSignedDocumentUrl, { adminId: admin.id, storageId: docId })
    ).rejects.toThrow();
    await expect(
      t.mutation(api.businessVerification.approveAgent, { adminId: admin.id, agentId: user.id })
    ).rejects.toThrow();
    // self-approval with the user's own session
    await expect(
      t.mutation(api.businessVerification.approveAgent, { adminId: admin.id, sessionToken: user.token, agentId: user.id })
    ).rejects.toThrow();
    expect((await t.run(async (ctx) => ctx.db.get(user.id)))?.isVerified).toBe(false);
  });

  test("approval verifies IDENTITY only — no business role, no agent flag — and is audited", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const user = await makeUser(t, "user");
    await submit(t, user);
    const queue = await t.query(api.businessVerification.getVerificationQueue, { adminId: admin.id, sessionToken: admin.token });
    expect(queue.length).toBeGreaterThan(0);

    const r = await t.mutation(api.businessVerification.approveAgent, { adminId: admin.id, sessionToken: admin.token, agentId: user.id });
    expect(r.success).toBe(true);
    const u = await t.run(async (ctx) => ctx.db.get(user.id));
    expect(u?.isVerified).toBe(true);
    expect(u?.verificationStatus).toBe("approved");
    expect(u?.role).toBe("client");
    expect(u?.isVerifiedAgent).not.toBe(true);
    const logs = await t.run(async (ctx) => ctx.db.query("audit_logs").collect());
    expect(logs.some((l) => l.action === "VERIFICATION_DECISION")).toBe(true);
  });
});
