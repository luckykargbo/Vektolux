/// <reference types="vite/client" />
// Wallet ⇄ ledger invariants after a realistic mixed history. For every user and currency:
//   available + pending (reserved for withdrawals)  ==  Σ(CLIENT_AVAILABLE + OWNER_AVAILABLE) ledger net
//   escrowBalance                                   ==  Σ CLIENT_ESCROW_LOCKED ledger net
// no balance is ever negative; every ledger transaction balances (debits == credits); and money is
// conserved: Σ wallets (available + pending + escrow) + platform revenue + subscription revenue
// == total external deposits − completed withdrawals.

import { convexTest } from "convex-test";
import { afterEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { hashWalletPin } from "./lib/pin";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string };
const HOUR = 3600_000;
const PIN = "1234";
const r2 = (n: number) => Math.round(n * 100) / 100;
let seq = 0;

afterEach(() => vi.useRealTimers());

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", { email: `${name}${seq}@t.vx`, phone: `+2327600${2000 + seq}`, name, role: role as any, isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra } as any)
  );
  await t.run(async (ctx) => ctx.db.patch(id, { walletPinHash: await hashWalletPin(id, PIN) }));
  return { id, token };
}
const deposit = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });

async function checkInvariants(t: T, expect_: { deposits: number; completedWithdrawals: number }) {
  const { wallets, entries, ledgerTxs, txs } = await t.run(async (ctx) => ({
    wallets: await ctx.db.query("walletBalances").collect(),
    entries: await ctx.db.query("ledger_entries").collect(),
    ledgerTxs: await ctx.db.query("ledger_transactions").collect(),
    txs: await ctx.db.query("transactions").collect(),
  }));
  const net = (e: { direction: string; amount: number }) => (e.direction === "CREDIT" ? e.amount : -e.amount);

  // 1. no negative balances
  for (const w of wallets) {
    expect(w.availableBalance, "available").toBeGreaterThanOrEqual(0);
    expect(w.escrowBalance ?? 0, "escrow").toBeGreaterThanOrEqual(0);
    expect(w.pendingBalance, "pending").toBeGreaterThanOrEqual(0);
  }
  // 2. every ledger transaction balances, and has entries
  for (const lt of ledgerTxs) {
    const es = entries.filter((e) => e.transactionId === lt._id);
    expect(es.length, lt.transactionCode).toBeGreaterThan(0);
    const debit = es.filter((e) => e.direction === "DEBIT").reduce((s, e) => s + e.amount, 0);
    const credit = es.filter((e) => e.direction === "CREDIT").reduce((s, e) => s + e.amount, 0);
    expect(r2(debit), lt.transactionCode).toBe(r2(credit));
  }
  // 3. no orphan entries, and ledger transaction codes are unique (no duplicate postings)
  const ids = new Set(ledgerTxs.map((l) => l._id));
  for (const e of entries) expect(ids.has(e.transactionId)).toBe(true);
  const codes = ledgerTxs.map((l) => l.transactionCode);
  expect(new Set(codes).size).toBe(codes.length);
  // 4. per-user wallet == ledger
  for (const w of wallets) {
    const mine = entries.filter((e) => e.userId === w.userId);
    const avail = mine.filter((e) => e.accountType === "CLIENT_AVAILABLE" || e.accountType === "OWNER_AVAILABLE").reduce((s, e) => s + net(e), 0);
    const escrow = mine.filter((e) => e.accountType === "CLIENT_ESCROW_LOCKED").reduce((s, e) => s + net(e), 0);
    expect(r2(w.availableBalance + w.pendingBalance), `available+pending of ${w.userId}`).toBe(r2(avail));
    expect(r2(w.escrowBalance ?? 0), `escrow of ${w.userId}`).toBe(r2(escrow));
  }
  // 5. conservation of money
  const platform = entries.filter((e) => e.accountType === "PLATFORM_REVENUE_REALIZED" || e.accountType === "SUBSCRIPTION_REVENUE").reduce((s, e) => s + net(e), 0);
  const inWallets = wallets.reduce((s, w) => s + w.availableBalance + w.pendingBalance + (w.escrowBalance ?? 0), 0);
  expect(r2(inWallets + platform)).toBe(r2(expect_.deposits - expect_.completedWithdrawals));
  // 6. every escrow lock transaction row is still backed (locked ones by held escrow)
  const lockedTotal = txs.filter((x) => x.type === "escrow_lock" && x.escrowStatus === "locked").reduce((s, x) => s + x.amount, 0);
  expect(r2(lockedTotal)).toBe(r2(wallets.reduce((s, w) => s + (w.escrowBalance ?? 0), 0)));
}

describe("wallet ⇄ ledger invariants after a mixed history", () => {
  test("deposit, booking release, cancel, dispute, reversal with partial recovery, withdrawal, QR, subscription", async () => {
    const t = convexTest(schema, modules);
    const T0 = Date.UTC(2026, 10, 3, 9);
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(T0));

    const admin = await makeUser(t, "admin", "admin");
    const buyer = await makeUser(t, "buyer");
    const vendor = await makeUser(t, "vendor");
    const friend = await makeUser(t, "friend");
    const agent = await makeUser(t, "agent", "agent", { roleApprovedAt: Date.now() });
    let deposits = 0;
    let withdrawn = 0;
    const dep = async (u: U, n: number) => {
      await deposit(t, u.id, n);
      deposits += n;
    };

    await dep(buyer, 3000);
    await dep(agent, 500);
    const listingId = await t.run(async (ctx) =>
      ctx.db.insert("realEstateListings", {
        ownerId: vendor.id, title: "Stay", description: "d", category: "hourly_guesthouse", price: 100, hourlyRate: 100, currency: "SLE",
        address: "x", city: "Lumley", country: "Sierra Leone", latitude: 0, longitude: 0, geohash: "", imageUrls: [],
        availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
      } as any)
    );
    const book = async (dayOffset: number) => {
      const start = Date.now() + dayOffset * 24 * HOUR;
      const b: any = await t.mutation(api.bookings.createBooking, { sessionToken: buyer.token, listingId, listingType: "property", listingTitle: "Stay", bookingType: "hourly_guesthouse", startTime: start, endTime: start + 4 * HOUR, hours: 4 });
      await t.mutation(api.payments.createEscrowPayment, { sessionToken: buyer.token, vendorId: vendor.id, amount: b.totalAmount, referenceId: b.bookingId });
      return { id: b.bookingId as Id<"bookings">, start };
    };
    await checkInvariants(t, { deposits, completedWithdrawals: 0 });

    // booking 1: buyer confirms after the start → released 357 / fee 63
    const b1 = await book(1);
    await checkInvariants(t, { deposits, completedWithdrawals: 0 });
    vi.setSystemTime(new Date(b1.start + HOUR));
    await t.mutation(api.bookings.confirmBookingCompletion, { sessionToken: buyer.token, bookingId: b1.id });
    await checkInvariants(t, { deposits, completedWithdrawals: 0 });

    // booking 2: cancelled before the start → full refund
    const b2 = await book(2);
    await t.mutation(api.bookings.cancelBooking, { sessionToken: buyer.token, bookingId: b2.id, userId: buyer.id, reason: "changed plans" });
    await checkInvariants(t, { deposits, completedWithdrawals: 0 });

    // booking 3: disputed → admin releases to the vendor
    const b3 = await book(3);
    await t.mutation(api.bookings.raiseBookingDispute, { sessionToken: buyer.token, bookingId: b3.id, reason: "late arrival by host" });
    await t.mutation(api.bookings.adminResolveBookingDispute, { sessionToken: admin.token, bookingId: b3.id, resolution: "release_to_vendor", note: "stay took place" });
    await checkInvariants(t, { deposits, completedWithdrawals: 0 });

    // booking 4: auto-released 24h after the end
    const b4 = await book(4);
    vi.setSystemTime(new Date(b4.start + 4 * HOUR + 24 * HOUR + 1000));
    await t.mutation(internal.bookings.releaseDueBookings, {});
    await checkInvariants(t, { deposits, completedWithdrawals: 0 });

    // vendor withdraws part (pending), the admin completes it, then another is left pending
    const wd = async (amount: number) =>
      (await t.action(api.withdrawals.requestWithdrawal, { sessionToken: vendor.token, amount, method: "bank", destinationProviderCode: "Test Bank", destinationAccountNumber: "0123456789", destinationName: "Vendor Test", bankName: "Test Bank", pin: PIN, idempotencyKey: `wd-req-${seq++}-0123456789abcdef` } as any)) as any;
    const w1 = await wd(600);
    await checkInvariants(t, { deposits, completedWithdrawals: 0 }); // reserved, not yet completed
    await t.mutation(api.withdrawals.adminResolveWithdrawal, { sessionToken: admin.token, withdrawalId: w1.withdrawalId, outcome: "completed", providerReference: "BANK-1" });
    withdrawn += 600;
    const w2 = await wd(100);
    await checkInvariants(t, { deposits, completedWithdrawals: withdrawn });
    await t.mutation(api.withdrawals.adminResolveWithdrawal, { sessionToken: admin.token, withdrawalId: w2.withdrawalId, outcome: "failed", reason: "bank rejected" });
    await checkInvariants(t, { deposits, completedWithdrawals: withdrawn });

    // reverse booking 1's payout: vendor has less than owed → partial recovery, open case, protected funds
    const release = await t.run(async (ctx) =>
      (await ctx.db.query("transactions").collect()).find((x) => x.type === "escrow_release" && x.referenceId === (b1.id as string))!
    );
    const rev: any = await t.mutation(api.reversals.adminReverseRelease, { sessionToken: admin.token, releaseTransactionId: release._id, reason: "service not delivered" });
    await checkInvariants(t, { deposits, completedWithdrawals: withdrawn });
    await dep(vendor, 200);
    if (rev.status === "pending_recovery") {
      await t.mutation(api.reversals.adminRetryRecovery, { sessionToken: admin.token, reversalId: rev.reversalId });
      await checkInvariants(t, { deposits, completedWithdrawals: withdrawn });
    }

    // QR payment between users
    const qr: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: friend.token, amount: 40 });
    await t.mutation(api.qrPayment.payQR, { sessionToken: buyer.token, payload: qr.qrPayload, pin: PIN, idempotencyKey: `qr-pay-${seq++}-0123456789abcdef` });
    await checkInvariants(t, { deposits, completedWithdrawals: withdrawn });

    // subscription charge (platform subscription revenue)
    await t.mutation(api.subscriptions.adminUpsertPlan, { sessionToken: admin.token, tierCode: "AGENT_M", name: "Agent Monthly", roleTarget: "agent", basePrice: 100, currency: "SLE", billingInterval: "monthly", intervalDays: 30, discountPercent: 10, isActive: true, features: [] });
    await t.mutation(api.subscriptions.subscribeWithWallet, { sessionToken: agent.token, tierCode: "AGENT_M", pin: PIN, idempotencyKey: `sub-req-${seq++}-0123456789abcdef` });
    await checkInvariants(t, { deposits, completedWithdrawals: withdrawn });
  });
});
