/// <reference types="vite/client" />
// Where the escrow bank-transfer destination comes from: owner env, or the admin-managed
// `bank_transfer` payment setting. Never silently from source, never a seeded placeholder.
import { convexTest } from "convex-test";
import { afterEach, describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
const ENV = ["ESCROW_BANK_NAME", "ESCROW_BANK_ACCOUNT_NAME", "ESCROW_BANK_ACCOUNT_NUMBER"] as const;
afterEach(() => { for (const k of ENV) delete process.env[k]; });

const details = (t: ReturnType<typeof convexTest>) => t.query(api.payments.getEscrowBankClearingDetails, {}) as Promise<any>;
const setBankRow = (t: ReturnType<typeof convexTest>, o: Record<string, unknown>) =>
  t.run(async (ctx) => ctx.db.insert("payment_settings", {
    providerId: "bank_transfer", displayName: "Test Bank", type: "BANK_TRANSFER", isEnabled: true, updatedAt: Date.now(), ...o,
  } as any));

describe("escrow bank account source", () => {
  test("nothing configured: not available (no account fields at all)", async () => {
    const t = convexTest(schema, modules);
    const d = await details(t);
    expect(d).toEqual({ available: false, message: expect.any(String) });
  });

  test("an admin-configured, enabled bank_transfer setting is used (no re-entry needed)", async () => {
    const t = convexTest(schema, modules);
    await setBankRow(t, { accountName: "Vektolux Test Escrow", accountNumber: "555000111222", instructions: "Use the reference." });
    const d = await details(t);
    expect(d.available).toBe(true);
    expect(d.accountNumber).toBe("555000111222");
    expect(d.accountName).toBe("Vektolux Test Escrow");
  });

  test.each([
    ["the seeded placeholder number", { accountName: "X", accountNumber: "0012345678" }],
    ["a disabled row", { accountName: "X", accountNumber: "555000111222", isEnabled: false }],
    ["a row without an account name", { accountNumber: "555000111222" }],
    ["a row without a number", { accountName: "X" }],
  ])("%s is NOT treated as configured", async (_n, row) => {
    const t = convexTest(schema, modules);
    await setBankRow(t, row);
    expect((await details(t)).available).toBe(false);
  });

  test("deployment env wins over the admin setting", async () => {
    const t = convexTest(schema, modules);
    await setBankRow(t, { accountName: "Row Name", accountNumber: "111111111111" });
    process.env.ESCROW_BANK_NAME = "Env Bank";
    process.env.ESCROW_BANK_ACCOUNT_NAME = "Env Name";
    process.env.ESCROW_BANK_ACCOUNT_NUMBER = "999888777666";
    expect((await details(t)).accountNumber).toBe("999888777666");
  });
});

describe("setEscrowBankAccount (owner-run)", () => {
  const good = { confirm: true, bankName: "Test Bank", accountName: "Vektolux Test Escrow", accountNumber: "555 000 111 222" };

  test("does nothing without explicit confirmation", async () => {
    const t = convexTest(schema, modules);
    const r: any = await t.mutation(internal.payments.setEscrowBankAccount, { ...good, confirm: false });
    expect(r.saved).toBe(false);
    expect((await details(t)).available).toBe(false);
  });

  test("with confirmation it stores what the owner passed in and the app uses it; the full number is never echoed", async () => {
    const t = convexTest(schema, modules);
    const r: any = await t.mutation(internal.payments.setEscrowBankAccount, good);
    expect(r).toEqual({ saved: true, accountEndsWith: "1222" });
    const d = await details(t);
    expect(d.available).toBe(true);
    expect(d.accountNumber).toBe("555000111222");
    expect(d.bankName).toBe("Test Bank");
  });

  test("malformed or placeholder numbers are refused", async () => {
    const t = convexTest(schema, modules);
    for (const accountNumber of ["12", "0012345678", "001", "has spaces!!"]) {
      const r: any = await t.mutation(internal.payments.setEscrowBankAccount, { ...good, accountNumber });
      expect(r.saved, accountNumber).toBe(false);
    }
    expect((await details(t)).available).toBe(false);
  });

  test("a placeholder row is replaced; a real one is never overwritten", async () => {
    const t = convexTest(schema, modules);
    await setBankRow(t, { accountName: "Seeded", accountNumber: "0012345678", isEnabled: false });
    expect(((await t.mutation(internal.payments.setEscrowBankAccount, good)) as any).saved).toBe(true);

    const t2 = convexTest(schema, modules);
    await setBankRow(t2, { accountName: "Owner Chosen", accountNumber: "777666555444" });
    const r: any = await t2.mutation(internal.payments.setEscrowBankAccount, good);
    expect(r).toEqual({ saved: false, reason: "already_configured" });
    expect((await details(t2)).accountNumber).toBe("777666555444");
  });
});

describe("seeded placeholder rows are not offered to customers", () => {
  test("an enabled row carrying the old seed's fake bank number is hidden and cannot take a claim", async () => {
    const t = convexTest(schema, modules);
    await t.run(async (ctx) => {
      await ctx.db.insert("payment_settings", { providerId: "bank_transfer", displayName: "Bank Transfer", type: "BANK_TRANSFER", isEnabled: true, accountName: "Seeded", accountNumber: "0012345678", updatedAt: 1 } as any);
      await ctx.db.insert("payment_settings", { providerId: "real_bank", displayName: "Real Bank", type: "BANK_TRANSFER", isEnabled: true, accountName: "Real", accountNumber: "555000111222", updatedAt: 1 } as any);
    });
    const active: any[] = await t.query(api.payments.getActivePaymentMethods, {});
    expect(active.map((m) => m.providerId)).toEqual(["real_bank"]);
  });
});
