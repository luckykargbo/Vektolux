/// <reference types="vite/client" />
// Login / password-reset / session hardening.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
const PASSWORD = "Correct-Horse-9";

async function register(t: T, email: string, phone: string) {
  const r: any = await t.mutation(api.auth.registerUser, { name: "User", email, phone, password: PASSWORD, role: "client" });
  expect(r.success).toBe(true);
  return r as { userId: string; sessionToken: string };
}
const login = (t: T, identifier: string, password: string) =>
  t.mutation(api.auth.loginWithPhoneOrEmail, { identifier, password }) as Promise<any>;

async function sha256Hex(s: string) {
  const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(b)).map((x) => x.toString(16).padStart(2, "0")).join("");
}
/** Plants a reset code exactly as the server stores it (hashed), so tests know the plaintext. */
async function plantResetCode(t: T, email: string, code: string, opts: { expiresAt?: number } = {}) {
  const hash = "h1:" + (await sha256Hex(`vektolux-reset:${email}:${code}`));
  await t.run(async (ctx) =>
    ctx.db.insert("password_resets", {
      identifier: email, deliveryChannel: "email", otpCode: hash, isUsed: false, attempts: 0,
      expiresAt: opts.expiresAt ?? Date.now() + 600_000, createdAt: Date.now(),
    })
  );
}

describe("login", () => {
  test("the response never reveals whether an account exists", async () => {
    const t = convexTest(schema, modules);
    await register(t, "real@test.vektolux", "+23276100001");
    const wrongPw = await login(t, "real@test.vektolux", "nope-nope-1");
    const noUser = await login(t, "ghost@test.vektolux", "nope-nope-1");
    expect(wrongPw.success).toBe(false);
    expect(noUser.errorMessage).toBe(wrongPw.errorMessage);
  });

  test("5 wrong passwords lock the account, even for the correct password", async () => {
    const t = convexTest(schema, modules);
    await register(t, "lock@test.vektolux", "+23276100002");
    for (let i = 0; i < 5; i++) expect((await login(t, "lock@test.vektolux", `wrong-${i}-xx`)).success).toBe(false);
    const locked = await login(t, "lock@test.vektolux", PASSWORD);
    expect(locked.success).toBe(false);
    expect(locked.errorMessage).toMatch(/too many failed attempts/i);
  });

  test("switching identifier format (email vs phone) does not bypass the account lock", async () => {
    const t = convexTest(schema, modules);
    await register(t, "both@test.vektolux", "+23276100003");
    for (let i = 0; i < 5; i++) await login(t, "both@test.vektolux", `wrong-${i}-xx`);
    const viaPhone = await login(t, "+23276100003", PASSWORD);
    expect(viaPhone.success).toBe(false);
    expect(viaPhone.errorMessage).toMatch(/too many failed attempts/i);
  });

  test("a correct login issues an expiring session and clears failures", async () => {
    const t = convexTest(schema, modules);
    const r = await register(t, "ok@test.vektolux", "+23276100004");
    await login(t, "ok@test.vektolux", "wrong-pw-1x");
    const ok = await login(t, "ok@test.vektolux", PASSWORD);
    expect(ok.success).toBe(true);
    const u = await t.run(async (ctx) => ctx.db.get(r.userId as Id<"users">));
    expect(u?.sessionExpiresAt).toBeGreaterThan(Date.now());
  });

  test("an expired session is rejected everywhere", async () => {
    const t = convexTest(schema, modules);
    const r = await register(t, "exp@test.vektolux", "+23276100005");
    await t.run(async (ctx) => ctx.db.patch(r.userId as Id<"users">, { sessionExpiresAt: Date.now() - 1 }));
    await expect(t.query(api.wallet.getUserBalance, { sessionToken: r.sessionToken })).rejects.toThrow(/expired/i);
    const s = await t.query(api.auth.getUserSession, { userId: r.userId, sessionToken: r.sessionToken });
    expect(s).toBeNull();
  });

  test("a legacy SHA-256 password works once and is upgraded; the stored hash itself is not a password", async () => {
    const t = convexTest(schema, modules);
    const legacy = await sha256Hex("old-password-1");
    const id = await t.run(async (ctx) =>
      ctx.db.insert("users", {
        email: "legacy@test.vektolux", phone: "+23276100006", name: "L", role: "client",
        isVerified: false, isActive: true, passwordHash: legacy, updatedAt: Date.now(),
      })
    );
    expect((await login(t, "legacy@test.vektolux", legacy)).success).toBe(false); // pass-the-hash refused
    expect((await login(t, "legacy@test.vektolux", "old-password-1")).success).toBe(true);
    const u = await t.run(async (ctx) => ctx.db.get(id));
    expect(u?.passwordHash).toContain(":"); // upgraded to salted PBKDF2
  });

  test("a phone-number suffix does not log you into someone else's account", async () => {
    const t = convexTest(schema, modules);
    await register(t, "suffix@test.vektolux", "+23276100007");
    expect((await login(t, "100007", PASSWORD)).success).toBe(false);
  });
});

describe("password reset", () => {
  test("requesting a reset never reveals whether the account exists", async () => {
    const t = convexTest(schema, modules);
    await register(t, "r1@test.vektolux", "+23276200001");
    const a: any = await t.mutation(api.auth.sendPasswordResetOtp, { identifier: "r1@test.vektolux", deliveryChannel: "email" });
    const b: any = await t.mutation(api.auth.sendPasswordResetOtp, { identifier: "nobody@test.vektolux", deliveryChannel: "email" });
    expect(a.message).toBe(b.message);
    expect(a.success).toBe(b.success);
  });

  test("the reset code is never stored in plain text", async () => {
    const t = convexTest(schema, modules);
    await register(t, "r2@test.vektolux", "+23276200002");
    await t.mutation(api.auth.sendPasswordResetOtp, { identifier: "r2@test.vektolux", deliveryChannel: "email" });
    const rows = await t.run(async (ctx) => ctx.db.query("password_resets").collect());
    expect(rows).toHaveLength(1);
    expect(rows[0].otpCode).toMatch(/^h1:[0-9a-f]{64}$/);
  });

  test("repeated reset requests are throttled", async () => {
    const t = convexTest(schema, modules);
    await register(t, "r3@test.vektolux", "+23276200003");
    const send = () => t.mutation(api.auth.sendPasswordResetOtp, { identifier: "r3@test.vektolux", deliveryChannel: "email" }) as Promise<any>;
    for (let i = 0; i < 3; i++) expect((await send()).success).toBe(true);
    const fourth = await send();
    expect(fourth.success).toBe(false);
    expect(fourth.message).toMatch(/too many/i);
  });

  test("wrong codes burn the code after 5 guesses (no brute force)", async () => {
    const t = convexTest(schema, modules);
    await register(t, "r4@test.vektolux", "+23276200004");
    await plantResetCode(t, "r4@test.vektolux", "424242");
    const tryCode = (c: string) =>
      t.mutation(api.auth.verifyResetOtpAndSetPassword, { identifier: "r4@test.vektolux", otpCode: c, newPassword: "Brand-New-Pass1" }) as Promise<any>;
    for (let i = 0; i < 5; i++) expect((await tryCode(String(100000 + i))).success).toBe(false);
    const right = await tryCode("424242"); // correct code, but already burned
    expect(right.success).toBe(false);
  });

  test("a correct code resets once; it cannot be reused, and old sessions die", async () => {
    const t = convexTest(schema, modules);
    const r = await register(t, "r5@test.vektolux", "+23276200005");
    await plantResetCode(t, "r5@test.vektolux", "135790");
    const ok: any = await t.mutation(api.auth.verifyResetOtpAndSetPassword, { identifier: "r5@test.vektolux", otpCode: "135790", newPassword: "Brand-New-Pass1" });
    expect(ok.success).toBe(true);
    const again: any = await t.mutation(api.auth.verifyResetOtpAndSetPassword, { identifier: "r5@test.vektolux", otpCode: "135790", newPassword: "Other-Pass-22" });
    expect(again.success).toBe(false);
    await expect(t.query(api.wallet.getUserBalance, { sessionToken: r.sessionToken })).rejects.toThrow(/authentication/i);
    expect((await login(t, "r5@test.vektolux", "Brand-New-Pass1")).success).toBe(true);
  });

  test("an expired code is refused", async () => {
    const t = convexTest(schema, modules);
    await register(t, "r6@test.vektolux", "+23276200006");
    await plantResetCode(t, "r6@test.vektolux", "246802", { expiresAt: Date.now() - 1 });
    const r: any = await t.mutation(api.auth.verifyResetOtpAndSetPassword, { identifier: "r6@test.vektolux", otpCode: "246802", newPassword: "Brand-New-Pass1" });
    expect(r.success).toBe(false);
  });

  test("short passwords are refused at registration and reset", async () => {
    const t = convexTest(schema, modules);
    const r: any = await t.mutation(api.auth.registerUser, { name: "S", email: "short@test.vektolux", phone: "+23276200007", password: "abc12", role: "client" });
    expect(r.success).toBe(false);
  });
});
