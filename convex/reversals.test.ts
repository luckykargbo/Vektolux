/// <reference types="vite/client" />
// Refunds AFTER payout: reversal entries (the original release is never modified), no negative
// balances, no fake refunds, and a controlled recovery state for admins.

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { hashWalletPin } from "./lib/pin";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string };
const PIN = "1234";
let seq = 0;

async function makeUser(t: T, name: string, role = "client"): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327500${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
    } as any)
  );
  await t.run(async (ctx) => ctx.db.patch(id, { walletPinHash: await hashWalletPin(id, PIN) }));
  return { id, token };
}
const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });
const bal = async (t: T, u: U) => t.query(api.wallet.getUserBalance, { sessionToken: u.token });
const platformRevenue = async (t: T) => {
  const e = await t.run(async (ctx) => ctx.db.query("ledger_entries").collect());
  const r = e.filter((x) => x.accountType === "PLATFORM_REVENUE_REALIZED").reduce((s, x) => s + (x.direction === "CREDIT" ? x.amount : -x.amount), 0);
  return Math.round(r * 100) / 100;
};

/** A booking paid (500) and released: vendor 425, platform 75. Returns the buyer-side release row. */
async function paidOut(t: T) {
  const admin = await makeUser(t, "admin", "admin");
  const buyer = await makeUser(t, "buyer");
  const vendor = await makeUser(t, "vendor");
  await fund(t, buyer.id, 500);
  const bookingId = await t.run(async (ctx) =>
    ctx.db.insert("bookings", {
      listingId: "l1", listingType: "property", listingTitle: "Stay", buyerId: buyer.id as string, vendorId: vendor.id as string,
      bookingType: "hourly_guesthouse", status: "pending_payment", startTime: 1, endTime: 2, subtotal: 500, serviceFee: 0,
      totalAmount: 500, currency: "SLE", paymentStatus: "pending", updatedAt: Date.now(),
    })
  );
  const lock: any = await t.mutation(api.payments.createEscrowPayment, { sessionToken: buyer.token, vendorId: vendor.id, amount: 500, referenceId: bookingId });
  await t.mutation(api.payments.releaseEscrowWithSplit, { transactionId: lock.transactionId, sessionToken: buyer.token });
  const release = await t.run(async (ctx) =>
    (await ctx.db.query("transactions").collect()).find((x) => x.type === "escrow_release" && x.userId === buyer.id)!
  );
  return { admin, buyer, vendor, release, lockTxId: lock.transactionId as Id<"transactions"> };
}

async function vendorWithdraws(t: T, admin: U, vendor: U, amount: number) {
  const res: any = await t.action(api.withdrawals.requestWithdrawal, {
    sessionToken: vendor.token, amount, method: "bank", destinationProviderCode: "Test Bank", destinationAccountNumber: "0123456789",
    destinationName: "Vendor", bankName: "Test Bank", pin: PIN, idempotencyKey: `wd-${seq++}-0123456789`,
  } as any);
  await t.mutation(api.withdrawals.adminResolveWithdrawal, { sessionToken: admin.token, withdrawalId: res.withdrawalId, outcome: "completed", providerReference: `B-${seq++}` });
}

const reverse = (t: T, admin: U, releaseTransactionId: Id<"transactions">, reason = "service not delivered") =>
  t.mutation(api.reversals.adminReverseRelease, { sessionToken: admin.token, releaseTransactionId, reason }) as Promise<any>;

// ─────────────────────────────────────────────────────────────────────
describe("reversal of a settled payout", () => {
  test("recipient has the funds: full refund, original release untouched, own tx/ledger ids, audited", async () => {
    const t = convexTest(schema, modules);
    const { admin, buyer, vendor, release } = await paidOut(t);
    expect((await bal(t, vendor)).availableBalance).toBe(425);
    expect(await platformRevenue(t)).toBe(75);
    const ledgerBefore = await t.run(async (ctx) => ctx.db.query("ledger_entries").collect());

    const r = await reverse(t, admin, release._id);
    expect(r).toMatchObject({ duplicate: false, refundedToBuyer: 500, outstanding: 0, status: "completed" });
    expect((await bal(t, buyer)).availableBalance).toBe(500);
    expect((await bal(t, vendor)).availableBalance).toBe(0);
    expect(await platformRevenue(t)).toBe(0);

    // the original release row and its ledger entries are unchanged
    const relAfter = await t.run(async (ctx) => ctx.db.get(release._id));
    expect(relAfter).toEqual(release);
    const ledgerAfter = await t.run(async (ctx) => ctx.db.query("ledger_entries").collect());
    for (const e of ledgerBefore) expect(ledgerAfter.find((x) => x._id === e._id)).toEqual(e);

    // the reversal has its own transaction code and ledger transaction, and the ledger balances
    const rev: any = (await t.query(api.reversals.adminListReversals, { sessionToken: admin.token }))[0];
    expect(rev.events).toHaveLength(1);
    expect(rev.events[0].transactionCode).not.toBe(release.transactionId);
    expect(rev.events[0].ledgerCode).toMatch(/^REV-/);
    const lt = await t.run(async (ctx) => (await ctx.db.query("ledger_transactions").collect()).find((x) => x.transactionCode === rev.events[0].ledgerCode)!);
    const entries = ledgerAfter.filter((e) => e.transactionId === lt._id);
    const sum = (d: string) => entries.filter((e) => e.direction === d).reduce((s, e) => s + e.amount, 0);
    expect(sum("DEBIT")).toBe(500);
    expect(sum("CREDIT")).toBe(500);

    const audits = await t.run(async (ctx) => (await ctx.db.query("audit_logs").collect()).filter((a) => a.action === "PAYMENT_REVERSED"));
    expect(audits).toHaveLength(1);
    expect(audits[0].adminUserId).toBe(admin.id);
  });

  test("a repeated reversal moves nothing", async () => {
    const t = convexTest(schema, modules);
    const { admin, buyer, release } = await paidOut(t);
    await reverse(t, admin, release._id);
    const again = await reverse(t, admin, release._id);
    expect(again.duplicate).toBe(true);
    expect((await bal(t, buyer)).availableBalance).toBe(500);
  });

  test("only admins can reverse, and only a completed escrow release", async () => {
    const t = convexTest(schema, modules);
    const { admin, buyer, vendor, release, lockTxId } = await paidOut(t);
    await expect(reverse(t, buyer, release._id)).rejects.toThrow(/administrator/i);
    await expect(reverse(t, vendor, release._id)).rejects.toThrow(/administrator/i);
    await expect(reverse(t, admin, lockTxId)).rejects.toThrow(/only a completed escrow release/i);
    await expect(reverse(t, admin, release._id, "x")).rejects.toThrow(/reason/i);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("recipient lacks funds: controlled recovery, never negative, never fake", () => {
  test("partial recovery opens a case; the buyer gets only what was really recovered", async () => {
    const t = convexTest(schema, modules);
    const { admin, buyer, vendor, release } = await paidOut(t);
    await vendorWithdraws(t, admin, vendor, 325); // vendor keeps 100
    expect((await bal(t, vendor)).availableBalance).toBe(100);

    const r = await reverse(t, admin, release._id);
    expect(r).toMatchObject({ refundedToBuyer: 175, outstanding: 325, status: "pending_recovery" }); // 75 fee + 100 recovered
    expect((await bal(t, buyer)).availableBalance).toBe(175);
    expect((await bal(t, vendor)).availableBalance).toBe(0); // not negative

    // nothing to take yet
    const none: any = await t.mutation(api.reversals.adminRetryRecovery, { sessionToken: admin.token, reversalId: r.reversalId });
    expect(none.recovered).toBe(0);

    // the vendor receives new money → the admin recovers it
    await fund(t, vendor.id, 200);
    const r1: any = await t.mutation(api.reversals.adminRetryRecovery, { sessionToken: admin.token, reversalId: r.reversalId, note: "vendor topped up" });
    expect(r1).toMatchObject({ recovered: 200, outstanding: 125, status: "pending_recovery" });
    await fund(t, vendor.id, 1000);
    const r2: any = await t.mutation(api.reversals.adminRetryRecovery, { sessionToken: admin.token, reversalId: r.reversalId });
    expect(r2).toMatchObject({ recovered: 125, outstanding: 0, status: "recovered" });
    expect((await bal(t, buyer)).availableBalance).toBe(500);
    expect((await bal(t, vendor)).availableBalance).toBe(875);
    await expect(t.mutation(api.reversals.adminRetryRecovery, { sessionToken: admin.token, reversalId: r.reversalId })).rejects.toThrow(/recovered/);

    const rev: any = (await t.query(api.reversals.adminListReversals, { sessionToken: admin.token, status: "recovered" }))[0];
    expect(rev.events.map((e: any) => [e.action, e.amount])).toEqual([["REVERSED", 175], ["RECOVERED", 200], ["RECOVERED", 125]]);
    expect(new Set(rev.events.map((e: any) => e.ledgerCode)).size).toBe(3); // each step its own ledger transaction
  });

  test("the platform can cover the shortfall (recorded), or it can be written off without crediting the buyer", async () => {
    const t = convexTest(schema, modules);
    const a = await paidOut(t);
    await vendorWithdraws(t, a.admin, a.vendor, 425);
    const r = await reverse(t, a.admin, a.release._id);
    expect(r).toMatchObject({ refundedToBuyer: 75, outstanding: 425, status: "pending_recovery" });
    await expect(
      t.mutation(api.reversals.adminCloseRecovery, { sessionToken: a.buyer.token, reversalId: r.reversalId, resolution: "platform_covered", note: "goodwill refund" })
    ).rejects.toThrow(/administrator/i);
    const c: any = await t.mutation(api.reversals.adminCloseRecovery, { sessionToken: a.admin.token, reversalId: r.reversalId, resolution: "platform_covered", note: "goodwill refund" });
    expect(c).toMatchObject({ status: "platform_covered", amount: 425 });
    expect((await bal(t, a.buyer)).availableBalance).toBe(500);
    expect((await bal(t, a.vendor)).availableBalance).toBe(0);
    expect(await platformRevenue(t)).toBe(-425); // the platform absorbed the loss, on the ledger

    const t2 = convexTest(schema, modules);
    const b = await paidOut(t2);
    await vendorWithdraws(t2, b.admin, b.vendor, 425);
    const r2 = await reverse(t2, b.admin, b.release._id);
    const w: any = await t2.mutation(api.reversals.adminCloseRecovery, { sessionToken: b.admin.token, reversalId: r2.reversalId, resolution: "written_off", note: "vendor unreachable; legal referral" });
    expect(w).toMatchObject({ status: "written_off", amount: 425 });
    expect((await bal(t2, b.buyer)).availableBalance).toBe(75); // only what was really refunded
    const rev: any = (await t2.query(api.reversals.adminListReversals, { sessionToken: b.admin.token }))[0];
    expect(rev).toMatchObject({ status: "written_off", writtenOffAmount: 425, outstandingAmount: 0, closeNote: "vendor unreachable; legal referral" });
    await expect(
      t2.mutation(api.reversals.adminCloseRecovery, { sessionToken: b.admin.token, reversalId: r2.reversalId, resolution: "platform_covered", note: "changed mind" })
    ).rejects.toThrow(/not open/);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("an open recovery protects the owed amount from the recipient's own debits", () => {
  async function openCase(t: T) {
    const a = await paidOut(t);
    await vendorWithdraws(t, a.admin, a.vendor, 425); // the vendor took everything out
    const r = await reverse(t, a.admin, a.release._id); // 425 outstanding, protected
    return { ...a, reversalId: r.reversalId as Id<"payment_reversals"> };
  }
  const withdraw = (t: T, u: U, amount: number) =>
    t.action(api.withdrawals.requestWithdrawal, {
      sessionToken: u.token, amount, method: "bank", destinationProviderCode: "Test Bank", destinationAccountNumber: "0123456789",
      destinationName: "Vendor", bankName: "Test Bank", pin: PIN, idempotencyKey: `wd-${seq++}-0123456789`,
    } as any);

  test("only funds above the protected amount can be withdrawn or sent by QR", async () => {
    const t = convexTest(schema, modules);
    const { vendor, buyer } = await openCase(t);
    await fund(t, vendor.id, 500); // new money arrives: 425 of it is reserved for the recovery
    await expect(withdraw(t, vendor, 100)).rejects.toThrow(/RECOVERY_HOLD/);
    const ok: any = await withdraw(t, vendor, 75); // 500 - 425
    expect(ok.success).toBe(true);
    // QR payment (a transfer) is protected the same way
    const qr: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: buyer.token, amount: 10 });
    await expect(
      t.mutation(api.qrPayment.payQR, { sessionToken: vendor.token, payload: qr.qrPayload, pin: PIN, idempotencyKey: `qr-${seq++}-0123456789` })
    ).rejects.toThrow(/RECOVERY_HOLD/);
    expect((await bal(t, vendor)).availableBalance).toBe(425);
  });

  test("an admin can lift (and restore) the protection with a note; closing the case ends it", async () => {
    const t = convexTest(schema, modules);
    const { admin, vendor, buyer, reversalId } = await openCase(t);
    await fund(t, vendor.id, 100);
    await expect(withdraw(t, vendor, 50)).rejects.toThrow(/RECOVERY_HOLD/);
    await expect(
      t.mutation(api.reversals.adminSetRecoveryProtection, { sessionToken: vendor.token, reversalId, lifted: true, note: "please let me" })
    ).rejects.toThrow(/administrator/i);
    await expect(t.mutation(api.reversals.adminSetRecoveryProtection, { sessionToken: admin.token, reversalId, lifted: true, note: "x" })).rejects.toThrow(/note/i);
    await t.mutation(api.reversals.adminSetRecoveryProtection, { sessionToken: admin.token, reversalId, lifted: true, note: "repayment plan agreed in writing" });
    expect((await withdraw(t, vendor, 50)).success).toBe(true);
    await t.mutation(api.reversals.adminSetRecoveryProtection, { sessionToken: admin.token, reversalId, lifted: false, note: "repayment plan breached" });
    await expect(withdraw(t, vendor, 50)).rejects.toThrow(/RECOVERY_HOLD/);

    await t.mutation(api.reversals.adminCloseRecovery, { sessionToken: admin.token, reversalId, resolution: "written_off", note: "uncollectable after 90 days" });
    expect((await withdraw(t, vendor, 50)).success).toBe(true);

    const rev: any = (await t.query(api.reversals.adminListReversals, { sessionToken: admin.token }))[0];
    expect(rev.events.map((e: any) => e.action)).toEqual(["REVERSED", "PROTECTION_LIFTED", "PROTECTION_RESTORED", "WRITTEN_OFF"]);
    expect(rev.recipient.name).toBe("vendor");
    expect(rev.buyer.name).toBe("buyer");
    expect(rev.originalRelease).toMatchObject({ amount: 500, platformFee: 75 });
    expect(rev.protectionActive).toBe(false);
    const audits = await t.run(async (ctx) => (await ctx.db.query("audit_logs").collect()).filter((a) => a.action === "RECOVERY_PROTECTION_CHANGED"));
    expect(audits).toHaveLength(2);
    void buyer;
  });

  test("recent releases are listed for admins with their reversal link", async () => {
    const t = convexTest(schema, modules);
    const { admin, buyer, release } = await paidOut(t);
    await expect(t.query(api.reversals.adminListRecentReleases, { sessionToken: buyer.token })).rejects.toThrow(/administrator/i);
    let rows: any[] = await t.query(api.reversals.adminListRecentReleases, { sessionToken: admin.token });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ id: release._id, amount: 500, platformFee: 75, reversalId: null, recipientName: "vendor" });
    const r = await reverse(t, admin, release._id);
    rows = await t.query(api.reversals.adminListRecentReleases, { sessionToken: admin.token });
    expect(rows[0].reversalId).toBe(r.reversalId);
  });
});
