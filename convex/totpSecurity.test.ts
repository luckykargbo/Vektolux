/// <reference types="vite/client" />
// 2FA management (setup / enable / disable) and the social sign-in second-factor gate.

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";
import { base32Decode, encryptTotpSecret, generateTotpSecret, hashBackupCode } from "./lib/totp";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
const PASSWORD = "Correct-Horse-9";
const KEY = "unit-test-totp-key-0123456789-abcdefghij";

beforeEach(() => {
  vi.stubEnv("TOTP_ENCRYPTION_KEY", KEY);
  vi.stubEnv("RESEND_API_KEY", "");
  vi.stubGlobal("fetch", async () => new Response("{}", { status: 599 }));
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

/** RFC 6238 SHA-1 / 6 digits / 30 s, independent of the server implementation. */
async function codeFor(secretBase32: string, offsetSteps = 0): Promise<string> {
  const step = Math.floor(Date.now() / 1000 / 30) + offsetSteps;
  const buf = new ArrayBuffer(8);
  new DataView(buf).setUint32(4, step);
  const key = await crypto.subtle.importKey("raw", base32Decode(secretBase32) as any, { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const h = new Uint8Array(await crypto.subtle.sign("HMAC", key, buf));
  const o = h[h.length - 1] & 0xf;
  const n = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return (n % 1_000_000).toString().padStart(6, "0");
}

async function makeAdmin(t: T, email = "boss@test.vektolux", phone = "+23276200001") {
  const r: any = await t.mutation(api.auth.registerUser, { name: "Boss", email, phone, password: PASSWORD, role: "client" });
  expect(r.success).toBe(true);
  await t.run(async (ctx) => ctx.db.patch(r.userId as Id<"users">, { role: "admin", activeRole: "admin" } as any));
  const login: any = await t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: email, password: PASSWORD });
  expect(login.success).toBe(true);
  return { userId: r.userId as Id<"users">, token: login.sessionToken as string, email };
}

/** Enrols 2FA through the real mutations; returns the secret and the SERVER-issued backup codes. */
async function enrol(t: T, token: string) {
  const s: any = await t.mutation(api.auth.setupTotp, { sessionToken: token, password: PASSWORD });
  expect(s.success).toBe(true);
  const e: any = await t.mutation(api.auth.enableTotp, { sessionToken: token, code: await codeFor(s.secret) });
  expect(e.success).toBe(true);
  return { secret: s.secret as string, backupCodes: s.backupCodes as string[] };
}

const userDoc = (t: T, id: Id<"users">) => t.run(async (ctx) => ctx.db.get(id));

describe("setupTotp", () => {
  test("a session token alone is not enough: wrong password is refused and nothing is staged", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    const r: any = await t.mutation(api.auth.setupTotp, { sessionToken: a.token, password: "not-the-password" });
    expect(r.success).toBe(false);
    const u: any = await userDoc(t, a.userId);
    expect(u.totpPendingSecretEncrypted).toBeUndefined();
  });

  test("first-time enrolment: server generates 10 backup codes, stores only hashes", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    const r: any = await t.mutation(api.auth.setupTotp, { sessionToken: a.token, password: PASSWORD });
    expect(r.success).toBe(true);
    expect(r.backupCodes).toHaveLength(10);
    const u: any = await userDoc(t, a.userId);
    expect(u.totpPendingBackupCodesHashed).toHaveLength(10);
    expect(JSON.stringify(u)).not.toContain(r.backupCodes[0]);
    expect(u.totpPendingBackupCodesHashed).toContain(await hashBackupCode(r.backupCodes[0]));
    expect(u.totpEnabled).toBeFalsy();
  });

  test("an already-active factor cannot be replaced with session + password only", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    const { secret } = await enrol(t, a.token);
    const before: any = await userDoc(t, a.userId);

    const noCode: any = await t.mutation(api.auth.setupTotp, { sessionToken: a.token, password: PASSWORD });
    expect(noCode.success).toBe(false);
    const badCode: any = await t.mutation(api.auth.setupTotp, { sessionToken: a.token, password: PASSWORD, code: "000000" });
    expect(badCode.success).toBe(false);

    const after: any = await userDoc(t, a.userId);
    expect(after.totpSecretEncrypted).toBe(before.totpSecretEncrypted);
    expect(after.totpPendingSecretEncrypted).toBeUndefined();

    // With the current code it IS allowed (legitimate device change).
    const ok: any = await t.mutation(api.auth.setupTotp, { sessionToken: a.token, password: PASSWORD, code: await codeFor(secret) });
    expect(ok.success).toBe(true);
  });

  test("fails closed when TOTP_ENCRYPTION_KEY is missing", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    vi.stubEnv("TOTP_ENCRYPTION_KEY", "");
    await expect(t.mutation(api.auth.setupTotp, { sessionToken: a.token, password: PASSWORD })).rejects.toThrow();
    const u: any = await userDoc(t, a.userId);
    expect(u.totpPendingSecretEncrypted).toBeUndefined();
  });

  test("non-admin sessions cannot enrol", async () => {
    const t = convexTest(schema, modules);
    const r: any = await t.mutation(api.auth.registerUser, { name: "C", email: "c@test.vektolux", phone: "+23276200002", password: PASSWORD, role: "client" });
    await expect(t.mutation(api.auth.setupTotp, { sessionToken: r.sessionToken, password: PASSWORD })).rejects.toThrow();
  });
});

describe("enableTotp", () => {
  test("rejects when nothing is pending (cannot be used to plant a client-chosen state)", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    const r: any = await t.mutation(api.auth.enableTotp, { sessionToken: a.token, code: "123456", backupCodes: ["aaaa-bbbb"] });
    expect(r.success).toBe(false);
  });

  test("client-supplied backup codes are ignored: forged code never works, server codes do", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    const s: any = await t.mutation(api.auth.setupTotp, { sessionToken: a.token, password: PASSWORD });
    const e: any = await t.mutation(api.auth.enableTotp, {
      sessionToken: a.token, code: await codeFor(s.secret), backupCodes: ["aaaa-bbbb"],
    });
    expect(e.success).toBe(true);
    const u: any = await userDoc(t, a.userId);
    expect(u.totpBackupCodesHashed).not.toContain(await hashBackupCode("aaaa-bbbb"));

    const forged: any = await t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: a.email, password: PASSWORD, totpCode: "aaaa-bbbb" });
    expect(forged.success).toBe(false);
    const real: any = await t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: a.email, password: PASSWORD, totpCode: s.backupCodes[0] });
    expect(real.success).toBe(true);
    // single use
    const again: any = await t.mutation(api.auth.loginWithPhoneOrEmail, { identifier: a.email, password: PASSWORD, totpCode: s.backupCodes[0] });
    expect(again.success).toBe(false);
  });

  test("wrong code does not enable; correct code does and clears the staging fields", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    const s: any = await t.mutation(api.auth.setupTotp, { sessionToken: a.token, password: PASSWORD });
    const bad: any = await t.mutation(api.auth.enableTotp, { sessionToken: a.token, code: "000000" });
    expect(bad.success).toBe(false);
    expect(((await userDoc(t, a.userId)) as any).totpEnabled).toBeFalsy();
    const ok: any = await t.mutation(api.auth.enableTotp, { sessionToken: a.token, code: await codeFor(s.secret) });
    expect(ok.success).toBe(true);
    const u: any = await userDoc(t, a.userId);
    expect(u.totpEnabled).toBe(true);
    expect(u.totpPendingSecretEncrypted).toBeUndefined();
    expect(u.totpPendingBackupCodesHashed).toBeUndefined();
  });

  test("a pending secret staged without server backup codes (pre-fix state) cannot be promoted", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    const secret = generateTotpSecret();
    await t.run(async (ctx) => ctx.db.patch(a.userId, { totpPendingSecretEncrypted: await encryptTotpSecret(secret) }));
    const r: any = await t.mutation(api.auth.enableTotp, { sessionToken: a.token, code: await codeFor(secret), backupCodes: ["aaaa-bbbb"] });
    expect(r.success).toBe(false);
    expect(((await userDoc(t, a.userId)) as any).totpEnabled).toBeFalsy();
  });
});

describe("disableTotp", () => {
  test("needs password AND a valid code; stays enabled otherwise", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    const { secret } = await enrol(t, a.token);

    const badPw: any = await t.mutation(api.auth.disableTotp, { sessionToken: a.token, password: "nope-nope-1", code: await codeFor(secret) });
    expect(badPw.success).toBe(false);
    const badCode: any = await t.mutation(api.auth.disableTotp, { sessionToken: a.token, password: PASSWORD, code: "000000" });
    expect(badCode.success).toBe(false);
    expect(((await userDoc(t, a.userId)) as any).totpEnabled).toBe(true);

    const ok: any = await t.mutation(api.auth.disableTotp, { sessionToken: a.token, password: PASSWORD, code: await codeFor(secret) });
    expect(ok.success).toBe(true);
    expect(((await userDoc(t, a.userId)) as any).totpEnabled).toBeFalsy();
  });

  test("fails closed when 2FA is on but the secret is missing (no code check skipped)", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    await t.run(async (ctx) => ctx.db.patch(a.userId, { totpEnabled: true } as any));
    const r: any = await t.mutation(api.auth.disableTotp, { sessionToken: a.token, password: PASSWORD, code: "123456" });
    expect(r.success).toBe(false);
    expect(((await userDoc(t, a.userId)) as any).totpEnabled).toBe(true);
  });

  test("code guesses are rate limited", async () => {
    const t = convexTest(schema, modules);
    const a = await makeAdmin(t);
    const { secret } = await enrol(t, a.token);
    for (let i = 0; i < 5; i++) {
      await t.mutation(api.auth.disableTotp, { sessionToken: a.token, password: PASSWORD, code: "000000" });
    }
    const locked: any = await t.mutation(api.auth.disableTotp, { sessionToken: a.token, password: PASSWORD, code: await codeFor(secret) });
    expect(locked.success).toBe(false);
    expect(((await userDoc(t, a.userId)) as any).totpEnabled).toBe(true);
  });
});

describe("social sign-in second factor (challenge flow)", () => {
  const exp = () => Date.now() + 3_600_000;
  let n = 0;

  /** A linked Google account with a chosen role / 2FA state, signed out. */
  async function linked(t: T, opts: { role: "admin" | "client"; totp: boolean }) {
    const sub = `g-${++n}`;
    const first: any = await t.mutation(internal.users.completeSocialSignIn, {
      provider: "google", sub, emailVerified: false, tokenHash: `h-first-${n}`, tokenExpiresAt: exp(),
    });
    const id = first.userId as Id<"users">;
    const secret = generateTotpSecret();
    await t.run(async (ctx) =>
      ctx.db.patch(id, {
        role: opts.role,
        ...(opts.totp ? { totpEnabled: true, totpSecretEncrypted: await encryptTotpSecret(secret) } : {}),
        sessionToken: undefined, sessionExpiresAt: undefined,
      } as any)
    );
    return { id, sub, secret };
  }
  let h = 0;
  const signIn = (t: T, sub: string, tokenHash = `h-${++h}-${Math.random()}`) =>
    t.mutation(internal.users.completeSocialSignIn, {
      provider: "google", sub, emailVerified: false, tokenHash, tokenExpiresAt: exp(),
    }) as Promise<any>;
  const complete = (t: T, challengeToken: string, totpCode: string) =>
    t.mutation(api.users.completeSocialMfa, { challengeToken, totpCode }) as Promise<any>;
  const sessionOf = async (t: T, id: Id<"users">) => ((await userDoc(t, id)) as any).sessionToken;

  test("admin with 2FA: sign-in returns only a challenge, never a session", async () => {
    const t = convexTest(schema, modules);
    const a = await linked(t, { role: "admin", totp: true });
    const r = await signIn(t, a.sub);
    expect(r.blocked).toBe(true);
    expect(r.code).toBe("MFA_REQUIRED");
    expect(r.sessionToken).toBeUndefined();
    expect(r.mfaChallengeToken).toMatch(/^[0-9a-f]{64}$/);
    expect(await sessionOf(t, a.id)).toBeUndefined();
    // only a hash of the challenge token is stored
    const rows: any[] = await t.run(async (ctx) => ctx.db.query("mfa_challenges").collect());
    expect(JSON.stringify(rows)).not.toContain(r.mfaChallengeToken);
  });

  test("valid code completes the challenge and issues the 8-hour admin session, once", async () => {
    const t = convexTest(schema, modules);
    const a = await linked(t, { role: "admin", totp: true });
    const ch = await signIn(t, a.sub);
    const ok = await complete(t, ch.mfaChallengeToken, await codeFor(a.secret));
    expect(ok.blocked).toBeUndefined();
    expect(ok.sessionToken).toBeTruthy();
    expect(ok.user.role).toBe("admin");
    const u: any = await userDoc(t, a.id);
    expect(u.sessionExpiresAt - Date.now()).toBeLessThanOrEqual(8 * 3_600_000 + 5_000);
    // replay of the same challenge fails
    const replay = await complete(t, ch.mfaChallengeToken, await codeFor(a.secret));
    expect(replay.blocked).toBe(true);
    expect(replay.code).toBe("MFA_CHALLENGE_INVALID");
  });

  test("the provider token is consumed when the challenge is issued (cannot be replayed)", async () => {
    const t = convexTest(schema, modules);
    const a = await linked(t, { role: "admin", totp: true });
    await signIn(t, a.sub, "same-token");
    await expect(signIn(t, a.sub, "same-token")).rejects.toThrow();
  });

  test("wrong code: no session; five wrong codes burn the challenge even for a later valid code", async () => {
    const t = convexTest(schema, modules);
    const a = await linked(t, { role: "admin", totp: true });
    const ch = await signIn(t, a.sub);
    for (let i = 0; i < 4; i++) {
      const bad = await complete(t, ch.mfaChallengeToken, "000000");
      expect(bad.code).toBe("MFA_INVALID");
    }
    await complete(t, ch.mfaChallengeToken, "000000"); // 5th: burned
    const after = await complete(t, ch.mfaChallengeToken, await codeFor(a.secret));
    expect(after.blocked).toBe(true);
    expect(await sessionOf(t, a.id)).toBeUndefined();
  });

  test("expired challenge is refused", async () => {
    const t = convexTest(schema, modules);
    const a = await linked(t, { role: "admin", totp: true });
    const ch = await signIn(t, a.sub);
    await t.run(async (ctx) => {
      const row = await ctx.db.query("mfa_challenges").first();
      await ctx.db.patch(row!._id, { expiresAt: Date.now() - 1 });
    });
    const r = await complete(t, ch.mfaChallengeToken, await codeFor(a.secret));
    expect(r.code).toBe("MFA_CHALLENGE_INVALID");
    expect(await sessionOf(t, a.id)).toBeUndefined();
  });

  test("cancelling burns the challenge", async () => {
    const t = convexTest(schema, modules);
    const a = await linked(t, { role: "admin", totp: true });
    const ch = await signIn(t, a.sub);
    await t.mutation(api.users.cancelSocialMfa, { challengeToken: ch.mfaChallengeToken });
    const r = await complete(t, ch.mfaChallengeToken, await codeFor(a.secret));
    expect(r.code).toBe("MFA_CHALLENGE_INVALID");
  });

  test("unknown / malformed challenge tokens are refused identically and write nothing", async () => {
    const t = convexTest(schema, modules);
    const r1 = await complete(t, "f".repeat(64), "123456");
    const r2 = await complete(t, "not-hex", "123456");
    expect(r1.code).toBe("MFA_CHALLENGE_INVALID");
    expect(r2).toEqual(r1);
  });

  test("2FA disabled mid-challenge, or account deactivated, voids the challenge", async () => {
    const t = convexTest(schema, modules);
    const a = await linked(t, { role: "admin", totp: true });
    const ch = await signIn(t, a.sub);
    await t.run(async (ctx) => ctx.db.patch(a.id, { isActive: false } as any));
    const r = await complete(t, ch.mfaChallengeToken, await codeFor(a.secret));
    expect(r.code).toBe("MFA_CHALLENGE_INVALID");
  });

  test("a challenge cannot be completed with another account's code", async () => {
    const t = convexTest(schema, modules);
    const a = await linked(t, { role: "admin", totp: true });
    const b = await linked(t, { role: "admin", totp: true });
    const ch = await signIn(t, a.sub);
    const r = await complete(t, ch.mfaChallengeToken, await codeFor(b.secret));
    expect(r.blocked).toBe(true);
    expect(await sessionOf(t, a.id)).toBeUndefined();
    expect(await sessionOf(t, b.id)).toBeUndefined();
  });

  test("customer social sign-in is unaffected (2FA disabled)", async () => {
    const t = convexTest(schema, modules);
    const c = await linked(t, { role: "client", totp: false });
    const ok = await signIn(t, c.sub);
    expect(ok.blocked).toBeUndefined();
    expect(ok.sessionToken).toBeTruthy();
  });

  test("admin without 2FA enabled signs in as before (parity with password login)", async () => {
    const t = convexTest(schema, modules);
    const a = await linked(t, { role: "admin", totp: false });
    expect((await signIn(t, a.sub)).sessionToken).toBeTruthy();
  });

  test("any account with 2FA enabled is gated, regardless of role", async () => {
    const t = convexTest(schema, modules);
    const c = await linked(t, { role: "client", totp: true });
    expect((await signIn(t, c.sub)).code).toBe("MFA_REQUIRED");
  });

  test("a backup code completes the challenge once", async () => {
    const t = convexTest(schema, modules);
    const a = await linked(t, { role: "admin", totp: true });
    const code = "abcd-1234";
    await t.run(async (ctx) => ctx.db.patch(a.id, { totpBackupCodesHashed: [await hashBackupCode(code)] } as any));
    const ch = await signIn(t, a.sub);
    expect((await complete(t, ch.mfaChallengeToken, code)).sessionToken).toBeTruthy();
    const ch2 = await signIn(t, a.sub);
    expect((await complete(t, ch2.mfaChallengeToken, code)).blocked).toBe(true);
  });
});
