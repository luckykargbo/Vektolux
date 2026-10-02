/// <reference types="vite/client" />
// The admin financial overview reports real records, keeps categories separate, and is admin-only.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { hashWalletPin } from "./lib/pin";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}) {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327900${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    })
  );
  await t.run(async (ctx) => ctx.db.patch(id, { walletPinHash: await hashWalletPin(id, "1234") }));
  return { id, token };
}

describe("admin financial overview", () => {
  test("is admin-only", async () => {
    const t = convexTest(schema, modules);
    const u = await makeUser(t, "u");
    await expect(t.query(api.adminFinance.getFinancialOverview, { sessionToken: u.token })).rejects.toThrow();
    await expect(t.query(api.adminFinance.getFinancialOverview, {})).rejects.toThrow();
  });

  test("an empty platform reports zeros, not invented figures", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const o = await t.query(api.adminFinance.getFinancialOverview, { sessionToken: admin.token });
    expect(o.userFunds).toEqual({});
    expect(o.subscriptionRevenue).toEqual({});
    expect(o.platformFees).toEqual({});
    expect(o.activeSubscriptions).toBe(0);
  });

  test("user funds, escrow and subscription revenue are reported separately", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const a = await makeUser(t, "agent", "agent", { roleApprovedAt: Date.now() });
    const b = await makeUser(t, "buyer");
    await t.mutation(internal.walletCore.creditVerifiedDeposit, { userId: a.id, amount: 300, provider: "TEST", providerReference: "d1" });
    await t.mutation(internal.walletCore.creditVerifiedDeposit, { userId: b.id, amount: 200, provider: "TEST", providerReference: "d2" });
    await t.mutation(api.subscriptions.adminUpsertPlan, {
      sessionToken: admin.token, tierCode: "AGENT_M", name: "Agent Monthly", roleTarget: "agent", basePrice: 100, currency: "SLE",
      billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
    });
    await t.mutation(api.subscriptions.subscribeWithWallet, { sessionToken: a.token, tierCode: "AGENT_M", pin: "1234", idempotencyKey: "k-0123456789abcdef" });
    const o = await t.query(api.adminFinance.getFinancialOverview, { sessionToken: admin.token });
    expect(o.subscriptionRevenue.SLE.amount).toBe(100);
    // user funds = 300 + 200 deposited − 100 paid for the subscription; revenue is NOT counted as user funds
    expect(round(o.userFunds.SLE.available)).toBe(400);
    expect(o.userFunds.SLE.escrow).toBe(0);
    expect(o.depositsSettled.SLE.amount).toBe(500);
    expect(o.activeSubscriptions).toBe(1);
  });
});
const round = (n: number) => Math.round(n * 100) / 100;
