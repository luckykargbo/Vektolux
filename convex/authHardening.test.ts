/// <reference types="vite/client" />
// Login / password-reset / session hardening.

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
const PASSWORD = "Correct-Horse-9";

// No test may ever reach a real mail provider, whatever the developer's shell exports: the sender
// is disabled (no key) AND any outbound request is refused.
beforeEach(() => {
  vi.stubEnv("RESEND_API_KEY", "");
  vi.stubGlobal("fetch", async () => new Response("{}", { status: 599 }));
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

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

  // Policy (commit 4fa5c9d): per-account / per-identifier lockout applies ONLY to admin accounts, so an
  // attacker cannot lock ordinary customers out of their own accounts. Failed logins are additionally
  // counted per client IP, where the IP is the one the PLATFORM observed (ctx.meta) - never an `ip`
  // argument the caller chose. `t.withRequestMetadata` plays the role of the network connection.
  const IP_MAX = 20;
  const loginFrom = (t: T, ip: string, identifier: string, password: string, extra: Record<string, unknown> = {}) =>
    t.withRequestMetadata({ ip }).mutation(api.auth.loginWithPhoneOrEmail, { identifier, password, ...extra }) as Promise<any>;
  const failFrom = async (t: T, ip: string, identifier: string, n: number, extra: Record<string, unknown> = {}) => {
    for (let i = 0; i < n; i++) expect((await loginFrom(t, ip, identifier, `wrong-${i}-xx`, extra)).success).toBe(false);
  };
  const makeAdminUser = async (t: T, email: string, phone: string) => {
    const r = await register(t, email, phone);
    await t.run(async (ctx) => ctx.db.patch(r.userId as Id<"users">, { role: "admin", activeRole: "admin" } as any));
    return r;
  };

  test("a normal account is NOT locked by wrong passwords: the owner can still sign in", async () => {
    const t = convexTest(schema, modules);
    await register(t, "lock@test.vektolux", "+23276100002");
    for (let i = 0; i < 8; i++) expect((await login(t, "lock@test.vektolux", `wrong-${i}-xx`)).success).toBe(false);
    expect((await login(t, "lock@test.vektolux", PASSWORD)).success).toBe(true);
    const rows = await t.run(async (ctx) => ctx.db.query("auth_rate_limits").collect());
    expect(rows.some((r) => r.key.startsWith("login:id:") || r.key.startsWith("login:user:"))).toBe(false);
  });

  test("normal accounts: failures from one platform-observed IP block that IP for every identifier format", async () => {
    const t = convexTest(schema, modules);
    await register(t, "both@test.vektolux", "+23276100003");
    await failFrom(t, "203.0.113.7", "ghost@test.vektolux", IP_MAX); // Flutter-equivalent: no ip argument at all
    for (const identifier of ["both@test.vektolux", "BOTH@test.vektolux ", "+23276100003", "ghost@test.vektolux"]) {
      const blocked = await loginFrom(t, "203.0.113.7", identifier, PASSWORD);
      expect(blocked.success).toBe(false);
      expect(blocked.errorMessage).toMatch(/too many failed attempts/i);
    }
    // The block belongs to the address, not the account: the owner on another network signs in.
    expect((await loginFrom(t, "198.51.100.9", "both@test.vektolux", PASSWORD)).success).toBe(true);
  });

  test("the lock is the same, generic answer whether or not the account exists", async () => {
    const t = convexTest(schema, modules);
    await register(t, "real2@test.vektolux", "+23276100010");
    await failFrom(t, "203.0.113.20", "ghost@test.vektolux", IP_MAX);
    const real = await loginFrom(t, "203.0.113.20", "real2@test.vektolux", PASSWORD);
    const ghost = await loginFrom(t, "203.0.113.20", "ghost2@test.vektolux", PASSWORD);
    expect(real.errorMessage).toBe(ghost.errorMessage);
  });

  test("a fabricated or omitted `ip` argument cannot bypass the limit or move it onto someone else", async () => {
    const t = convexTest(schema, modules);
    await register(t, "bypass@test.vektolux", "+23276100011");
    // Attacker rotates made-up `ip` values every attempt; the platform still sees one address.
    for (let i = 0; i < IP_MAX; i++) {
      expect((await loginFrom(t, "203.0.113.30", "ghost@test.vektolux", `wrong-${i}-xx`, { ip: `10.9.9.${i}` })).success).toBe(false);
    }
    expect((await loginFrom(t, "203.0.113.30", "bypass@test.vektolux", PASSWORD, { ip: "10.1.1.1" })).success).toBe(false);
    expect((await loginFrom(t, "203.0.113.30", "bypass@test.vektolux", PASSWORD)).success).toBe(false);

    // And an attacker cannot pre-load the counter of a victim's address by claiming it in `ip`.
    await failFrom(t, "203.0.113.31", "ghost@test.vektolux", IP_MAX, { ip: "198.51.100.77" });
    expect((await loginFrom(t, "198.51.100.77", "bypass@test.vektolux", PASSWORD)).success).toBe(true);
  });

  test("a forwarded `ip` is honoured only with the shared proxy secret", async () => {
    vi.stubEnv("LOGIN_PROXY_SECRET", "proxy-secret-for-tests-0123456789");
    const t = convexTest(schema, modules);
    await register(t, "proxy@test.vektolux", "+23276100012");
    const proxy = { proxySecret: "proxy-secret-for-tests-0123456789" };
    // Dashboard server (one platform IP for everyone) forwards the real browser address.
    await failFrom(t, "192.0.2.1", "ghost@test.vektolux", IP_MAX, { ...proxy, ip: "203.0.113.40" });
    expect((await loginFrom(t, "192.0.2.1", "proxy@test.vektolux", PASSWORD, { ...proxy, ip: "203.0.113.40" })).success).toBe(false);
    // Another browser behind the same proxy is unaffected, and so is the proxy's own address.
    expect((await loginFrom(t, "192.0.2.1", "proxy@test.vektolux", PASSWORD, { ...proxy, ip: "203.0.113.41" })).success).toBe(true);
    // A wrong secret is ignored: the forwarded value is not used as the bucket.
    await failFrom(t, "203.0.113.50", "ghost@test.vektolux", IP_MAX, { proxySecret: "wrong-wrong-wrong-wrong", ip: "203.0.113.99" });
    expect((await loginFrom(t, "203.0.113.99", "proxy@test.vektolux", PASSWORD)).success).toBe(true);
    expect((await loginFrom(t, "203.0.113.50", "proxy@test.vektolux", PASSWORD)).success).toBe(false);
  });

  test("without LOGIN_PROXY_SECRET configured, a presented secret does nothing", async () => {
    vi.stubEnv("LOGIN_PROXY_SECRET", "");
    const t = convexTest(schema, modules);
    await register(t, "nosecret@test.vektolux", "+23276100013");
    await failFrom(t, "203.0.113.60", "ghost@test.vektolux", IP_MAX, { proxySecret: "", ip: "198.51.100.5" });
    expect((await loginFrom(t, "198.51.100.5", "nosecret@test.vektolux", PASSWORD)).success).toBe(true);
  });

  test("a successful login does not reset the IP counter (no guess-and-reset with an own account)", async () => {
    const t = convexTest(schema, modules);
    await register(t, "mine@test.vektolux", "+23276100014");
    await register(t, "target@test.vektolux", "+23276100015");
    await failFrom(t, "203.0.113.70", "ghost@test.vektolux", IP_MAX - 1);
    expect((await loginFrom(t, "203.0.113.70", "mine@test.vektolux", PASSWORD)).success).toBe(true);
    expect((await loginFrom(t, "203.0.113.70", "target@test.vektolux", "wrong-last-xx")).success).toBe(false);
    expect((await loginFrom(t, "203.0.113.70", "mine@test.vektolux", PASSWORD)).success).toBe(false);
  });

  test("one user's failed attempts never block another user, or the owner, at other addresses", async () => {
    const t = convexTest(schema, modules);
    await register(t, "alice@test.vektolux", "+23276100016");
    await register(t, "bob@test.vektolux", "+23276100017");
    // Below the IP limit: nobody is blocked, including Alice from the attacker's own address.
    await failFrom(t, "203.0.113.80", "ghost@test.vektolux", IP_MAX - 1);
    expect((await loginFrom(t, "203.0.113.80", "alice@test.vektolux", PASSWORD)).success).toBe(true);
    // At the limit the attacker's address is blocked; Alice and Bob elsewhere are not.
    await failFrom(t, "203.0.113.81", "ghost@test.vektolux", IP_MAX);
    expect((await loginFrom(t, "198.51.100.1", "alice@test.vektolux", PASSWORD)).success).toBe(true);
    expect((await loginFrom(t, "198.51.100.2", "bob@test.vektolux", PASSWORD)).success).toBe(true);
    // The block expires with its window: no permanent state remains on any account.
    const rows = await t.run(async (ctx) => ctx.db.query("auth_rate_limits").collect());
    expect(rows.every((r) => r.key.startsWith("login:ip:"))).toBe(true);
    await t.run(async (ctx) => {
      for (const r of rows) await ctx.db.patch(r._id, { lockedUntil: Date.now() - 1, windowStart: Date.now() - 16 * 60_000 });
    });
    expect((await loginFrom(t, "203.0.113.81", "alice@test.vektolux", PASSWORD)).success).toBe(true);
  });

  test("admin accounts ARE locked after 5 wrong passwords, even for the correct password", async () => {
    const t = convexTest(schema, modules);
    await makeAdminUser(t, "boss@test.vektolux", "+23276100008");
    for (let i = 0; i < 5; i++) expect((await login(t, "boss@test.vektolux", `wrong-${i}-xx`)).success).toBe(false);
    const locked = await login(t, "boss@test.vektolux", PASSWORD);
    expect(locked.success).toBe(false);
    expect(locked.errorMessage).toMatch(/too many failed attempts/i);
  });

  test("switching identifier format (email vs phone) does not bypass the ADMIN account lock", async () => {
    const t = convexTest(schema, modules);
    await makeAdminUser(t, "boss2@test.vektolux", "+23276100009");
    for (let i = 0; i < 5; i++) await login(t, "boss2@test.vektolux", `wrong-${i}-xx`);
    const viaPhone = await login(t, "+23276100009", PASSWORD);
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

  test("logout invalidates the session server-side: the same token cannot authenticate again", async () => {
    const t = convexTest(schema, modules);
    const a = await register(t, "out@test.vektolux", "+23276100041");
    const b = await register(t, "stay@test.vektolux", "+23276100042");

    // The token works before logout.
    expect(await t.query(api.auth.getUserSession, { userId: a.userId, sessionToken: a.sessionToken })).not.toBeNull();
    await expect(t.query(api.wallet.getUserBalance, { sessionToken: a.sessionToken })).resolves.toBeDefined();

    expect(await t.mutation(api.auth.logout, { sessionToken: a.sessionToken })).toBe(true);

    // Replaying the very same token no longer authenticates anywhere.
    expect(await t.query(api.auth.getUserSession, { userId: a.userId, sessionToken: a.sessionToken })).toBeNull();
    await expect(t.query(api.wallet.getUserBalance, { sessionToken: a.sessionToken })).rejects.toThrow(/Authentication required/i);
    await expect(
      t.mutation(api.users.updateUserProfile, { userId: a.userId, sessionToken: a.sessionToken, name: "Replay" })
    ).rejects.toThrow(/Authentication required/i);
    const u: any = await t.run(async (ctx) => ctx.db.get(a.userId as Id<"users">));
    expect(u.sessionToken).toBeUndefined();
    expect(u.sessionExpiresAt).toBeUndefined();

    // Idempotent: logging out again (or with junk / a too-short token) is a quiet no-op.
    expect(await t.mutation(api.auth.logout, { sessionToken: a.sessionToken })).toBe(false);
    expect(await t.mutation(api.auth.logout, { sessionToken: "short" })).toBe(false);
    expect(await t.mutation(api.auth.logout, { sessionToken: "x".repeat(64) })).toBe(false);

    // Another account's session is untouched.
    expect(await t.query(api.auth.getUserSession, { userId: b.userId, sessionToken: b.sessionToken })).not.toBeNull();

    // Signing in again issues a fresh, working token that differs from the revoked one.
    const again = await login(t, "out@test.vektolux", PASSWORD);
    expect(again.success).toBe(true);
    expect(again.sessionToken).not.toBe(a.sessionToken);
    expect(await t.query(api.auth.getUserSession, { userId: a.userId, sessionToken: again.sessionToken })).not.toBeNull();
    expect(await t.query(api.auth.getUserSession, { userId: a.userId, sessionToken: a.sessionToken })).toBeNull();
  });

  test("an administrator session is rejected by getAdminSession after logout", async () => {
    const t = convexTest(schema, modules);
    const r = await register(t, "adm-out@test.vektolux", "+23276100043");
    await t.run(async (ctx) => ctx.db.patch(r.userId as Id<"users">, { role: "admin", activeRole: "admin" } as any));
    const ok = await login(t, "adm-out@test.vektolux", PASSWORD);
    expect(ok.success).toBe(true);
    await expect(t.query(api.auth.getAdminSession, { sessionToken: ok.sessionToken })).resolves.toMatchObject({ role: "admin" });

    expect(await t.mutation(api.auth.logout, { sessionToken: ok.sessionToken })).toBe(true);
    await expect(t.query(api.auth.getAdminSession, { sessionToken: ok.sessionToken })).resolves.toBeNull();
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

describe("operator recovery of the admin account (CLI only)", () => {
  const reset = (t: T, email: string, newPassword: string) =>
    t.mutation(internal.auth.resetAdminCredentials, { email, newPassword }) as Promise<any>;

  async function makeAdmin(t: T) {
    const r = await register(t, "old-admin@test.vektolux", "+23276100900");
    await t.run(async (ctx) => ctx.db.patch(r.userId as Id<"users">, { role: "admin", activeRole: "admin" } as any));
    return r;
  }

  test("sets the admin email + password, signs the old session out, and nothing else changes", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeAdmin(t);
    const other = await register(t, "client@test.vektolux", "+23276100901");
    const out = await reset(t, "  New.Admin@Test.Vektolux ", "Temp-Pass-123");
    expect(out).toMatchObject({ success: true, email: "new.admin@test.vektolux" });

    expect((await login(t, "old-admin@test.vektolux", PASSWORD)).success).toBe(false);
    const ok = await login(t, "new.admin@test.vektolux", "Temp-Pass-123");
    expect(ok.success).toBe(true);
    expect(ok.role).toBe("admin");
    const u: any = await t.run(async (ctx) => ctx.db.get(admin.userId as Id<"users">));
    expect(u.sessionToken).not.toBe(admin.sessionToken); // the old session no longer works
    // another account is untouched
    expect((await login(t, "client@test.vektolux", PASSWORD)).success).toBe(true);
    const c: any = await t.run(async (ctx) => ctx.db.get(other.userId as Id<"users">));
    expect(c.role).toBe("client");
  });

  test("refuses an email another account uses, a short password, a bad email, or anything but exactly one admin", async () => {
    const t = convexTest(schema, modules);
    await expect(reset(t, "a@test.vektolux", "Temp-Pass-123")).rejects.toThrow(/exactly one administrator/);
    await makeAdmin(t);
    await register(t, "taken@test.vektolux", "+23276100902");
    await expect(reset(t, "taken@test.vektolux", "Temp-Pass-123")).rejects.toThrow(/already used/);
    await expect(reset(t, "fine@test.vektolux", "short")).rejects.toThrow(/at least 8/);
    await expect(reset(t, "not-an-email", "Temp-Pass-123")).rejects.toThrow(/valid email/);
    const second = await register(t, "second@test.vektolux", "+23276100903");
    await t.run(async (ctx) => ctx.db.patch(second.userId as Id<"users">, { role: "admin" } as any));
    await expect(reset(t, "fine@test.vektolux", "Temp-Pass-123")).rejects.toThrow(/exactly one administrator account, found 2/);
    expect((await login(t, "old-admin@test.vektolux", PASSWORD)).success).toBe(true); // nothing changed
  });
});

// ──────────────────────────────────────────────────────
// Phase 0 / Task 2: email ownership verification + no account enumeration
// ──────────────────────────────────────────────────────
/** Plants a verification challenge exactly as the server stores it (hashed), so tests know the plaintext. */
async function plantVerificationCode(
  t: T, userId: string, email: string, code: string, opts: { expiresAt?: number; isUsed?: boolean; attempts?: number } = {}
) {
  const codeHash = "v1:" + (await sha256Hex(`vektolux-emailverify:${userId}:${email}:${code}`));
  // retire whatever registration created so the planted row is the latest
  await t.run(async (ctx) => {
    for (const r of await ctx.db.query("email_verifications").collect()) {
      if (r.userId === (userId as any)) await ctx.db.patch(r._id, { isUsed: true });
    }
    await ctx.db.insert("email_verifications", {
      userId: userId as Id<"users">, email, codeHash, isUsed: opts.isUsed ?? false, attempts: opts.attempts ?? 0,
      expiresAt: opts.expiresAt ?? Date.now() + 600_000, createdAt: Date.now() + 1,
    });
  });
}
const verify = (t: T, sessionToken: string, code: string) => t.mutation(api.auth.verifyEmail, { sessionToken, code }) as Promise<any>;
const userDoc = (t: T, id: string) => t.run(async (ctx) => ctx.db.get(id as Id<"users">)) as Promise<any>;

describe("email verification", () => {
  test("registration creates an UNVERIFIED account and a hashed, expiring challenge", async () => {
    const t = convexTest(schema, modules);
    const r: any = await t.mutation(api.auth.registerUser, { name: "New", email: "new@test.vektolux", phone: "+23276100001", password: PASSWORD, role: "client" });
    expect(r.success).toBe(true);
    expect(r.emailVerified).toBe(false);
    expect(r.emailVerificationRequired).toBe(true);
    const u = await userDoc(t, r.userId);
    expect(u.emailVerifiedAt).toBeUndefined();
    const rows = await t.run(async (ctx) => ctx.db.query("email_verifications").collect());
    expect(rows).toHaveLength(1);
    expect(rows[0].userId).toBe(r.userId);
    expect(rows[0].email).toBe("new@test.vektolux");
    expect(rows[0].codeHash).toMatch(/^v1:[0-9a-f]{64}$/);
    expect(rows[0].isUsed).toBe(false);
    const ttl = rows[0].expiresAt - rows[0].createdAt;
    expect(ttl).toBeGreaterThan(9 * 60_000);
    expect(ttl).toBeLessThanOrEqual(10 * 60_000);
    const l = await login(t, "new@test.vektolux", PASSWORD);
    expect(l.success).toBe(true);
    expect(l.emailVerified).toBe(false); // limited access is preserved; nothing claims it is verified
  });

  test("a valid code verifies the email; the same code cannot be replayed", async () => {
    const t = convexTest(schema, modules);
    const u = await register(t, "ok@test.vektolux", "+23276100002");
    await plantVerificationCode(t, u.userId, "ok@test.vektolux", "123456");
    expect((await verify(t, u.sessionToken, "123456")).success).toBe(true);
    const verified = await userDoc(t, u.userId);
    expect(verified.emailVerifiedAt).toBeGreaterThan(0);
    const signedIn = await login(t, "ok@test.vektolux", PASSWORD); // rotates the (single) session
    expect(signedIn.emailVerified).toBe(true);
    // replay: even if the flag were cleared, the used challenge no longer works
    await t.run(async (ctx) => ctx.db.patch(u.userId as Id<"users">, { emailVerifiedAt: undefined }));
    const replay = await verify(t, signedIn.sessionToken, "123456");
    expect(replay.success).toBe(false);
    expect((await userDoc(t, u.userId)).emailVerifiedAt).toBeUndefined();
  });

  test("wrong, expired and malformed codes fail; wrong guesses burn the code", async () => {
    const t = convexTest(schema, modules);
    const u = await register(t, "bad@test.vektolux", "+23276100003");
    await plantVerificationCode(t, u.userId, "bad@test.vektolux", "111111", { expiresAt: Date.now() - 1000 });
    expect((await verify(t, u.sessionToken, "111111")).success).toBe(false); // expired

    await plantVerificationCode(t, u.userId, "bad@test.vektolux", "222222");
    expect((await verify(t, u.sessionToken, "12ab")).success).toBe(false); // malformed
    for (let i = 0; i < 5; i++) expect((await verify(t, u.sessionToken, "000000")).success).toBe(false);
    expect((await verify(t, u.sessionToken, "222222")).success).toBe(false); // burned: even the right code
    expect((await userDoc(t, u.userId)).emailVerifiedAt).toBeUndefined();
  });

  test("a code cannot verify, or change, another account", async () => {
    const t = convexTest(schema, modules);
    const a = await register(t, "a@test.vektolux", "+23276100004");
    const b = await register(t, "b@test.vektolux", "+23276100005");
    await plantVerificationCode(t, a.userId, "a@test.vektolux", "424242");
    // B's session + A's code
    expect((await verify(t, b.sessionToken, "424242")).success).toBe(false);
    expect((await userDoc(t, b.userId)).emailVerifiedAt).toBeUndefined();
    expect((await userDoc(t, a.userId)).emailVerifiedAt).toBeUndefined();
    // a code issued for an address the account no longer has is useless
    await t.run(async (ctx) => ctx.db.patch(a.userId as Id<"users">, { email: "changed@test.vektolux" }));
    expect((await verify(t, a.sessionToken, "424242")).success).toBe(false);
    // no session, no verification
    await expect(verify(t, "not-a-session-token-0123456789abcdef", "424242")).rejects.toThrow();
  });

  test("resend: retires the old code, issues a new one, and is throttled", async () => {
    const t = convexTest(schema, modules);
    const u = await register(t, "re@test.vektolux", "+23276100006");
    for (let i = 0; i < 3; i++) {
      const r: any = await t.mutation(api.auth.resendEmailVerification, { sessionToken: u.sessionToken });
      expect(r.success).toBe(true);
    }
    const r4: any = await t.mutation(api.auth.resendEmailVerification, { sessionToken: u.sessionToken });
    expect(r4.success).toBe(false);
    const rows = await t.run(async (ctx) => ctx.db.query("email_verifications").collect());
    expect(rows.filter((r) => !r.isUsed)).toHaveLength(1);
  });

  test("a successful password reset by email also proves ownership", async () => {
    const t = convexTest(schema, modules);
    const u = await register(t, "rv@test.vektolux", "+23276100007");
    await plantResetCode(t, "rv@test.vektolux", "654321");
    const r: any = await t.mutation(api.auth.verifyResetOtpAndSetPassword, { identifier: "rv@test.vektolux", otpCode: "654321", newPassword: "A-Brand-New-Pass-1" });
    expect(r.success).toBe(true);
    expect((await userDoc(t, u.userId)).emailVerifiedAt).toBeGreaterThan(0);
  });

  test("existing accounts (no emailVerifiedAt) can still sign in; they are not auto-verified", async () => {
    const t = convexTest(schema, modules);
    const u = await register(t, "old@test.vektolux", "+23276100008");
    await t.run(async (ctx) => ctx.db.patch(u.userId as Id<"users">, { emailVerifiedAt: undefined }));
    const l = await login(t, "old@test.vektolux", PASSWORD);
    expect(l.success).toBe(true);
    expect(l.emailVerified).toBe(false);
  });
});

describe("registration does not reveal which email or phone is registered", () => {
  test("an existing email, an existing phone and a brand-new pair answer identically", async () => {
    const t = convexTest(schema, modules);
    await register(t, "taken@test.vektolux", "+23276200001");
    const dupEmail: any = await t.mutation(api.auth.registerUser, { name: "X", email: "taken@test.vektolux", phone: "+23276200099", password: PASSWORD, role: "client" });
    const dupPhone: any = await t.mutation(api.auth.registerUser, { name: "X", email: "other@test.vektolux", phone: "+23276200001", password: PASSWORD, role: "client" });
    expect(dupEmail.success).toBe(false);
    expect(dupPhone.success).toBe(false);
    expect(dupEmail.errorMessage).toBe(dupPhone.errorMessage);
    expect(dupEmail.errorMessage).not.toMatch(/already exists|this email|this phone/i);
  });

  test("a short password gets the same answer whether or not the email exists", async () => {
    const t = convexTest(schema, modules);
    await register(t, "exists@test.vektolux", "+23276200002");
    const a: any = await t.mutation(api.auth.registerUser, { name: "X", email: "exists@test.vektolux", phone: "+23276200090", password: "short", role: "client" });
    const b: any = await t.mutation(api.auth.registerUser, { name: "X", email: "nobody@test.vektolux", phone: "+23276200091", password: "short", role: "client" });
    expect(a.errorMessage).toBe(b.errorMessage);
  });
});
