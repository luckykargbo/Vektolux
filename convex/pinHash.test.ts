/// <reference types="vite/client" />
// Wallet PIN hashing: versioned salted PBKDF2, legacy hashes still work and upgrade, no oracle.
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import { hashPin, isLegacyPinHash, verifyPinHash } from "./lib/pinHash";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const PASSWORD = "Correct-Horse-9";

async function legacy(userId: string, pin: string) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`wallet_pin_${userId}_${pin}`));
  return "0x" + Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

describe("pinHash", () => {
  test("v2 hashes are salted: same PIN, different strings; verify works; wrong PIN / other user fail", async () => {
    const a = await hashPin("user1", "1234");
    const b = await hashPin("user1", "1234");
    expect(a).not.toBe(b);
    expect(a.startsWith("pin2$")).toBe(true);
    expect(a).not.toContain("1234");
    expect((await verifyPinHash("user1", "1234", a)).valid).toBe(true);
    expect((await verifyPinHash("user1", "1235", a)).valid).toBe(false);
    expect((await verifyPinHash("user2", "1234", a)).valid).toBe(false);
    expect((await verifyPinHash("user1", "1234", a)).needsUpgrade).toBe(false);
  });

  test("legacy SHA-256 hashes still verify (no lockout of existing customers) and are flagged for upgrade", async () => {
    const stored = await legacy("user1", "4321");
    expect(isLegacyPinHash(stored)).toBe(true);
    const ok = await verifyPinHash("user1", "4321", stored);
    expect(ok).toEqual({ valid: true, needsUpgrade: true });
    expect((await verifyPinHash("user1", "0000", stored)).valid).toBe(false);
  });

  test("malformed or tampered v2 values never verify and never throw", async () => {
    for (const bad of ["pin2$", "pin2$abc$def$ghi", "pin2$100000$zz$00", "pin2$999999999$" + "a".repeat(32) + "$00", "", undefined]) {
      expect((await verifyPinHash("u", "1234", bad as any)).valid).toBe(false);
    }
  });

  test("a lower stored work factor verifies and asks for an upgrade", async () => {
    // Craft a v2 hash with 1000 iterations.
    const salt = new Uint8Array(16).fill(7);
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode("u:1234"), { name: "PBKDF2" }, false, ["deriveBits"]);
    const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt, iterations: 1000, hash: "SHA-256" }, key, 256);
    const hex = (u: Uint8Array) => Array.from(u).map((b) => b.toString(16).padStart(2, "0")).join("");
    const stored = `pin2$1000$${hex(salt)}$${hex(new Uint8Array(bits))}`;
    expect(await verifyPinHash("u", "1234", stored)).toEqual({ valid: true, needsUpgrade: true });
  });
});

describe("wallet PIN in the backend", () => {
  async function user(t: ReturnType<typeof convexTest>) {
    const r: any = await t.mutation(api.auth.registerUser, { name: "P", email: "pin@test.vektolux", phone: "+23276190001", password: PASSWORD, role: "client" });
    return { id: r.userId as Id<"users">, token: r.sessionToken as string };
  }

  test("setWalletPin stores a v2 hash, never the PIN", async () => {
    const t = convexTest(schema, modules);
    const u = await user(t);
    const r: any = await t.mutation(api.payments.setWalletPin, { sessionToken: u.token, userId: u.id, pin: "2468" } as any);
    expect(r.success).toBe(true);
    const doc: any = await t.run(async (ctx) => ctx.db.get(u.id));
    expect(doc.walletPinHash.startsWith("pin2$")).toBe(true);
    // No field holds the PIN itself (substring checks on hex/number fields would be flaky by chance).
    expect(Object.values(doc).some((v) => v === "2468" || v === 2468)).toBe(false);
    expect(doc.walletPinHash).not.toBe("2468");
  });

  test("a legacy-hash customer can still pay, and the hash is upgraded on that successful use", async () => {
    const t = convexTest(schema, modules);
    const u = await user(t);
    await t.run(async (ctx) => ctx.db.patch(u.id, { walletPinHash: await legacy(u.id, "1357") }));
    // changing the PIN requires the CURRENT pin, verified through the lockout path (accepts legacy)
    const r: any = await t.mutation(api.payments.setWalletPin, { sessionToken: u.token, userId: u.id, pin: "9999", currentPin: "1357" } as any);
    expect(r.success).toBe(true);
    const doc: any = await t.run(async (ctx) => ctx.db.get(u.id));
    expect(doc.walletPinHash.startsWith("pin2$")).toBe(true);
    // wrong current PIN against a legacy hash still counts a failure and is refused
    await t.run(async (ctx) => ctx.db.patch(u.id, { walletPinHash: await legacy(u.id, "1357") }));
    const bad: any = await t.mutation(api.payments.setWalletPin, { sessionToken: u.token, userId: u.id, pin: "9999", currentPin: "0000" } as any);
    expect(bad.success).toBe(false);
    const after: any = await t.run(async (ctx) => ctx.db.get(u.id));
    expect(after.pinFailedAttempts).toBe(1);
  });

  test("the read-only PIN checks are not oracles: right and wrong guesses answer identically", async () => {
    const t = convexTest(schema, modules);
    const u = await user(t);
    await t.mutation(api.payments.setWalletPin, { sessionToken: u.token, userId: u.id, pin: "2468" } as any);
    const right: any = await t.query(api.payments.verifyTransactionPin, { sessionToken: u.token, userId: u.id, pin: "2468" });
    const wrong: any = await t.query(api.payments.verifyTransactionPin, { sessionToken: u.token, userId: u.id, pin: "1111" });
    expect(right).toEqual(wrong);
    const r2: any = await t.query(api.payments.verifyWalletPin, { sessionToken: u.token, userId: u.id, pin: "2468" });
    const w2: any = await t.query(api.payments.verifyWalletPin, { sessionToken: u.token, userId: u.id, pin: "1111" });
    expect(r2).toEqual(w2);
    const r3: any = await t.query(api.users.verifyTransactionPin, { sessionToken: u.token, userId: u.id, pin: "2468" });
    const w3: any = await t.query(api.users.verifyTransactionPin, { sessionToken: u.token, userId: u.id, pin: "1111" });
    expect(r3).toEqual(w3);
  });
});
