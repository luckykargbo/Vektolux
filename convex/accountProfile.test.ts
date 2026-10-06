/// <reference types="vite/client" />
// Account & Profile: verified name lock, PIN-protected phone change, 30-day deletion request.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;

async function makeUser(t: T, name: string, extra: Record<string, unknown> = {}) {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327600${1000 + seq}`, name, role: "client",
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
      ...extra,
    } as any)
  );
  return { id, token };
}

async function setPin(t: T, u: { id: Id<"users">; token: string }, pin = "4821") {
  await t.mutation(api.payments.setWalletPin, { sessionToken: u.token, pin });
}

describe("verified name", () => {
  test("a verified user cannot change their name; an unverified one can", async () => {
    const t = convexTest(schema, modules);
    const verified = await makeUser(t, "Verified", { isVerified: true });
    await expect(
      t.mutation(api.users.updateUserProfile, { sessionToken: verified.token, userId: verified.id, name: "Someone Else" })
    ).rejects.toThrow(/verified/);
    // re-sending the same name (e.g. a full-form save) is harmless
    await t.mutation(api.users.updateUserProfile, { sessionToken: verified.token, userId: verified.id, name: "Verified", bio: "hi" });
    const fresh = await makeUser(t, "Fresh");
    await t.mutation(api.users.updateUserProfile, { sessionToken: fresh.token, userId: fresh.id, name: "Fresh Name" });
    expect((await t.run((ctx) => ctx.db.get(fresh.id)))!.name).toBe("Fresh Name");
  });

  test("updateUserProfile no longer changes the phone number", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u");
    await expect(
      t.mutation(api.users.updateUserProfile, { sessionToken: u.token, userId: u.id, phone: "+23288000000" })
    ).rejects.toThrow();
  });

  test("the profile reports verified identity and member-since to the owner", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u", { kycStatus: "verified" });
    const p: any = await t.query(api.users.getUserProfile, { userId: u.id, sessionToken: u.token });
    expect(p.identityVerified).toBe(true);
    expect(typeof p.memberSince).toBe("number");
    const anon: any = await t.query(api.users.getUserProfile, { userId: u.id });
    expect(anon.memberSince).toBeUndefined();
  });
});

describe("phone change", () => {
  test("changing an existing number requires the PIN when one is set", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u");
    await setPin(t, u);
    const noPin: any = await t.mutation(api.users.linkPhoneNumber, { sessionToken: u.token, userId: u.id, phoneNumber: "077123456" });
    expect(noPin.success).toBe(false);
    expect(noPin.errorCode).toBe("REQUIRED");
    const badPin: any = await t.mutation(api.users.linkPhoneNumber, {
      sessionToken: u.token, userId: u.id, phoneNumber: "077123456", currentPin: "0000",
    });
    expect(badPin.errorCode).toBe("INVALID");
    const ok: any = await t.mutation(api.users.linkPhoneNumber, {
      sessionToken: u.token, userId: u.id, phoneNumber: "077123456", currentPin: "4821",
    });
    expect(ok).toMatchObject({ success: true, phoneNumber: "+23277123456" });
  });

  test("a number held by another account, or an invalid number, is refused", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "a", { phone: "+23277999888" });
    const b = await makeUser(t, "b");
    await expect(
      t.mutation(api.users.linkPhoneNumber, { sessionToken: b.token, userId: b.id, phoneNumber: "+232 77 999 888" })
    ).rejects.toThrow(/another account/);
    await expect(
      t.mutation(api.users.linkPhoneNumber, { sessionToken: b.token, userId: b.id, phoneNumber: "12" })
    ).rejects.toThrow(/valid/);
    expect((await t.run((ctx) => ctx.db.get(a.id)))!.phone).toBe("+23277999888");
  });

  test("first-time phone linking (no phone yet) still works without a PIN", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "social", { phone: "" });
    const r: any = await t.mutation(api.users.linkPhoneNumber, { sessionToken: u.token, userId: u.id, phoneNumber: "076555444" });
    expect(r.success).toBe(true);
  });

  test("nobody can change another user's number", async () => {
    const t = convexTest(schema, modules);
    const victim = await makeUser(t, "victim");
    const attacker = await makeUser(t, "attacker");
    await expect(
      t.mutation(api.users.linkPhoneNumber, { sessionToken: attacker.token, userId: victim.id, phoneNumber: "077000111" })
    ).rejects.toThrow(/Unauthorized/);
  });
});

describe("account deletion request", () => {
  test("marks the account pending for 30 days and signs it out, erasing nothing", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "Leaving");
    const before = Date.now();
    const r: any = await t.mutation(api.users.requestAccountDeletion, { sessionToken: u.token });
    expect(r.success).toBe(true);
    const doc: any = await t.run((ctx) => ctx.db.get(u.id));
    expect(doc.name).toBe("Leaving");
    expect(doc.isActive).toBe(true);
    expect(doc.sessionToken).toBeUndefined();
    expect(doc.deletionScheduledFor - doc.deletionRequestedAt).toBe(30 * 24 * 60 * 60 * 1000);
    expect(doc.deletionRequestedAt).toBeGreaterThanOrEqual(before);
    // the old session no longer works
    await expect(t.mutation(api.users.requestAccountDeletion, { sessionToken: u.token })).rejects.toThrow();
  });

  test("requires the PIN when one is set", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u");
    await setPin(t, u);
    const r: any = await t.mutation(api.users.requestAccountDeletion, { sessionToken: u.token, currentPin: "1111" });
    expect(r.success).toBe(false);
    expect((await t.run((ctx) => ctx.db.get(u.id)))!.deletionRequestedAt).toBeUndefined();
    const ok: any = await t.mutation(api.users.requestAccountDeletion, { sessionToken: u.token, currentPin: "4821" });
    expect(ok.success).toBe(true);
  });

  test("is refused while the wallet holds funds", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u");
    await t.run((ctx) =>
      ctx.db.insert("walletBalances", {
        userId: u.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 50, currency: "SLE", updatedAt: Date.now(),
      })
    );
    const r: any = await t.mutation(api.users.requestAccountDeletion, { sessionToken: u.token });
    expect(r).toMatchObject({ success: false, errorCode: "FUNDS_REMAINING" });
  });

  test("cannot target another user, and needs a session", async () => {
    const t = convexTest(schema, modules);
    const victim = await makeUser(t, "victim");
    const attacker = await makeUser(t, "attacker");
    await expect(
      t.mutation(api.users.requestAccountDeletion, { sessionToken: attacker.token, userId: victim.id })
    ).rejects.toThrow(/Unauthorized/);
    await expect(t.mutation(api.users.requestAccountDeletion, {})).rejects.toThrow();
    expect((await t.run((ctx) => ctx.db.get(victim.id)))!.deletionRequestedAt).toBeUndefined();
  });

  test("signing in again cancels the pending deletion", async () => {
    const t = convexTest(schema, modules);
    // legacy SHA-256 password record (still accepted at sign-in)
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode("correct-horse-1"));
    const passwordHash = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
    const u = await makeUser(t, "back", { passwordHash });
    await t.mutation(api.users.requestAccountDeletion, { sessionToken: u.token });
    const doc: any = await t.run((ctx) => ctx.db.get(u.id));
    const login: any = await t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: doc.email, password: "correct-horse-1" });
    expect(login.success).toBe(true);
    const after: any = await t.run((ctx) => ctx.db.get(u.id));
    expect(after.deletionRequestedAt).toBeUndefined();
    expect(after.deletionScheduledFor).toBeUndefined();
  });
});

describe("another user's session", () => {
  test("cannot change this user's name, PIN, phone or deletion state", async () => {
    const t = convexTest(schema, modules);
    const victim = await makeUser(t, "Victim");
    const attacker = await makeUser(t, "Attacker");
    await expect(
      t.mutation(api.users.updateUserProfile, { sessionToken: attacker.token, userId: victim.id, name: "Hijacked" })
    ).rejects.toThrow(/Unauthorized/);
    await expect(
      t.mutation(api.payments.setWalletPin, { sessionToken: attacker.token, userId: victim.id, pin: "1234" })
    ).rejects.toThrow(/Unauthorized/);
    await expect(
      t.mutation(api.users.linkPhoneNumber, { sessionToken: attacker.token, userId: victim.id, phoneNumber: "077000222" })
    ).rejects.toThrow(/Unauthorized/);
    await expect(
      t.mutation(api.users.requestAccountDeletion, { sessionToken: attacker.token, userId: victim.id })
    ).rejects.toThrow(/Unauthorized/);
    const doc: any = await t.run((ctx) => ctx.db.get(victim.id));
    expect(doc.name).toBe("Victim");
    expect(doc.walletPinHash).toBeUndefined();
    expect(doc.deletionRequestedAt).toBeUndefined();
  });
});

describe("Account PIN", () => {
  test("is stored only as a hash and never returned", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u");
    await setPin(t, u, "4821");
    const doc: any = await t.run((ctx) => ctx.db.get(u.id));
    expect(doc.walletPinHash).toMatch(/^0x[0-9a-f]{64}$/);
    expect(JSON.stringify(doc)).not.toContain('"4821"');
    const status: any = await t.query(api.payments.getUserSecurityPinStatus, { sessionToken: u.token });
    expect(status).toEqual({ hasPin: true, hasPassword: false });
  });

  test("wrong PINs on a phone change use the existing lockout (5 tries, then locked even for the right PIN)", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u");
    await setPin(t, u, "4821");
    const before: any = await t.run((ctx) => ctx.db.get(u.id));
    for (let i = 0; i < 4; i++) {
      const r: any = await t.mutation(api.users.linkPhoneNumber, {
        sessionToken: u.token, userId: u.id, phoneNumber: "077123456", currentPin: "0000",
      });
      expect(r.errorCode).toBe("INVALID");
    }
    const fifth: any = await t.mutation(api.users.linkPhoneNumber, {
      sessionToken: u.token, userId: u.id, phoneNumber: "077123456", currentPin: "0000",
    });
    expect(fifth.errorCode).toBe("LOCKED");
    const correct: any = await t.mutation(api.users.linkPhoneNumber, {
      sessionToken: u.token, userId: u.id, phoneNumber: "077123456", currentPin: "4821",
    });
    expect(correct.errorCode).toBe("LOCKED");
    const after: any = await t.run((ctx) => ctx.db.get(u.id));
    expect(after.phone).toBe(before.phone);
    expect(after.pinLockedUntil).toBeGreaterThan(Date.now());
  });
});

describe("social sign-in", () => {
  test("signing in with Apple/Google also cancels a pending deletion", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "social", { authProvider: "google", externalAuthId: "g-sub-1" });
    await t.mutation(api.users.requestAccountDeletion, { sessionToken: u.token });
    await t.mutation(internal.users.completeSocialSignIn, {
      provider: "google", sub: "g-sub-1", emailVerified: false,
    });
    const after: any = await t.run((ctx) => ctx.db.get(u.id));
    expect(after.deletionRequestedAt).toBeUndefined();
    expect(after.deletionScheduledFor).toBeUndefined();
  });
});
