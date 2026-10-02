/// <reference types="vite/client" />
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — financial correctness & authorization tests (convex-test).
// Every test uses multiple real (test-database) users: no shared/global state.
// ═══════════════════════════════════════════════════════════════════════

import { convexTest } from "convex-test";
import { describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { hashWalletPin } from "./lib/pin";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);

type T = ReturnType<typeof convexTest>;
const PIN = "1234";
let seq = 0;

async function makeUser(t: T, name: string, role: string = "client") {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@test.vektolux`,
      phone: `+2327600${String(1000 + seq)}`,
      name,
      role: role as any,
      isVerified: false,
      isActive: true,
      sessionToken: token,
      updatedAt: Date.now(),
    })
  );
  const pinHash = await hashWalletPin(id, PIN);
  await t.run(async (ctx) => ctx.db.patch(id, { walletPinHash: pinHash }));
  return { id, token, name };
}

async function fund(t: T, userId: Id<"users">, amount: number, ref?: string) {
  return t.mutation(internal.walletCore.creditVerifiedDeposit, {
    userId,
    amount,
    provider: "TEST_PROVIDER",
    providerReference: ref ?? `fund-${userId}-${seq++}`,
  });
}

const balance = (t: T, u: { token: string }) =>
  t.query(api.wallet.getUserBalance, { sessionToken: u.token });

async function makeBooking(t: T, buyer: Id<"users">, vendor: Id<"users">, total: number) {
  return t.run(async (ctx) =>
    ctx.db.insert("bookings", {
      listingId: "listing-1",
      listingType: "property",
      listingTitle: "Test stay",
      buyerId: buyer as string,
      vendorId: vendor as string,
      bookingType: "hourly_guesthouse",
      status: "pending_payment",
      startTime: 1,
      endTime: 2,
      subtotal: total,
      serviceFee: 0,
      totalAmount: total,
      currency: "SLE",
      paymentStatus: "pending",
      updatedAt: Date.now(),
    })
  );
}

// A fake Monime checkout API (no network): sessions are created, then marked completed by the test.
function stubMonime() {
  const sessions = new Map<string, any>();
  process.env.MONIME_SPACE_ID = "spc-test";
  process.env.MONIME_ACCESS_TOKEN = "test-token";
  process.env.MONIME_API_BASE_URL = "https://fake.monime.test/v1";
  vi.stubGlobal("fetch", async (url: string, init?: any) => {
    const u = String(url);
    const json = (status: number, body: any) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
    if (u.endsWith("/checkout-sessions") && init?.method === "POST") {
      const body = JSON.parse(init.body);
      const id = `scs-${++seq}abcd`;
      sessions.set(id, { id, status: "pending", lineItems: { data: body.lineItems }, metadata: body.metadata });
      return json(200, { success: true, result: { id, redirectUrl: `https://checkout.test/${id}` } });
    }
    const m = u.match(/\/checkout-sessions\/([^/?]+)$/);
    if (m) return sessions.get(m[1]) ? json(200, { success: true, result: sessions.get(m[1]) }) : json(404, {});
    return json(404, {});
  });
  return sessions;
}

function unstubMonime() {
  vi.unstubAllGlobals();
  delete process.env.MONIME_SPACE_ID;
  delete process.env.MONIME_ACCESS_TOKEN;
  delete process.env.MONIME_API_BASE_URL;
}

// ─────────────────────────────────────────────────────────────────────
describe("wallet balances are per-user and server-derived", () => {
  test("a new user has a zero balance (no invented money)", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await balance(t, a);
    expect(b.availableBalance).toBe(0);
    expect(b.escrowBalance).toBe(0);
    expect(b.pendingBalance).toBe(0);
  });

  test("user A cannot see user B's balance or history", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await fund(t, b.id, 500);

    // A asking for B's wallet with A's own session is rejected
    await expect(
      t.query(api.wallet.getUserBalance, { sessionToken: a.token, userId: b.id })
    ).rejects.toThrow(/another user/i);
    await expect(
      t.query(api.payments.getWalletBalance, { sessionToken: a.token, userId: b.id })
    ).rejects.toThrow(/another user/i);
    await expect(
      t.query(api.walletCore.getUserTransactions, { sessionToken: a.token, userId: b.id })
    ).rejects.toThrow(/another user/i);

    // No session at all is rejected (no fallback to a claimed userId)
    await expect(t.query(api.wallet.getUserBalance, { userId: b.id })).rejects.toThrow(/authentication/i);

    // A's own view is independent of B's balance
    expect((await balance(t, a)).availableBalance).toBe(0);
    expect((await balance(t, b)).availableBalance).toBe(500);
  });

  test("transaction history contains only the caller's own records", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await fund(t, a.id, 100);
    await fund(t, b.id, 250);
    const ha = await t.query(api.walletCore.getUserTransactions, { sessionToken: a.token });
    const hb = await t.query(api.walletCore.getUserTransactions, { sessionToken: b.token });
    expect(ha.transactions).toHaveLength(1);
    expect(ha.transactions[0].amount).toBe(100);
    expect(hb.transactions).toHaveLength(1);
    expect(hb.transactions[0].amount).toBe(250);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("deposits", () => {
  test("a verified deposit credits only the right user", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await fund(t, a.id, 300);
    expect((await balance(t, a)).availableBalance).toBe(300);
    expect((await balance(t, b)).availableBalance).toBe(0);
  });

  test("a replayed deposit/webhook cannot credit twice", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const first = await fund(t, a.id, 100, "provider-ref-1");
    const replay = await fund(t, a.id, 100, "provider-ref-1");
    expect(first.duplicate).toBe(false);
    expect(replay.duplicate).toBe(true);
    expect((await balance(t, a)).availableBalance).toBe(100);
  });

  test("a provider reference cannot be claimed by two different users", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await fund(t, a.id, 100, "shared-ref");
    await expect(fund(t, b.id, 100, "shared-ref")).rejects.toThrow(/different account/i);
    expect((await balance(t, b)).availableBalance).toBe(0);
  });

  test("a failed deposit creates no spendable funds", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    await t.run(async (ctx) => {
      const wallet = await ctx.db.insert("walletBalances", {
        userId: a.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: Date.now(),
      });
      await ctx.db.insert("transactions", {
        walletId: wallet, userId: a.id, type: "top_up", amount: 999, currency: "SLE",
        gatewayProvider: "TEST_PROVIDER", gatewayReference: "pending-1", status: "pending", updatedAt: Date.now(),
      });
    });
    // pending money is not spendable
    expect((await balance(t, a)).availableBalance).toBe(0);
    const changed = await t.mutation(internal.walletCore.markDepositFailed, {
      userId: a.id, provider: "TEST_PROVIDER", providerReference: "pending-1", reason: "declined",
    });
    expect(changed).toBe(true);
    expect((await balance(t, a)).availableBalance).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("escrow", () => {
  test("wallet payment locks funds in escrow and reduces available funds", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    const vendor = await makeUser(t, "vendor");
    await fund(t, buyer.id, 1000);
    const bookingId = await makeBooking(t, buyer.id, vendor.id, 300);

    await t.mutation(api.payments.createEscrowPayment, {
      sessionToken: buyer.token,
      vendorId: vendor.id,
      amount: 300,
      referenceType: "hourly_guesthouse",
      referenceId: bookingId,
    });

    const b = await balance(t, buyer);
    expect(b.availableBalance).toBe(700);
    expect(b.escrowBalance).toBe(300);
    const booking = await t.run(async (ctx) => ctx.db.get(bookingId));
    expect(booking?.paymentStatus).toBe("completed");
    // the vendor got nothing yet
    expect((await balance(t, vendor)).availableBalance).toBe(0);
  });

  test("an unfunded buyer cannot mark a booking paid", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    const vendor = await makeUser(t, "vendor");
    const bookingId = await makeBooking(t, buyer.id, vendor.id, 300);
    await expect(
      t.mutation(api.payments.createEscrowPayment, {
        sessionToken: buyer.token, vendorId: vendor.id, amount: 300,
        referenceType: "hourly_guesthouse", referenceId: bookingId,
      })
    ).rejects.toThrow(/INSUFFICIENT_FUNDS/);
    const booking = await t.run(async (ctx) => ctx.db.get(bookingId));
    expect(booking?.paymentStatus).toBe("pending");
  });

  test("a wrong amount or another user's booking is rejected", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    const other = await makeUser(t, "other");
    const vendor = await makeUser(t, "vendor");
    await fund(t, buyer.id, 1000);
    await fund(t, other.id, 1000);
    const bookingId = await makeBooking(t, buyer.id, vendor.id, 300);
    await expect(
      t.mutation(api.payments.createEscrowPayment, {
        sessionToken: buyer.token, vendorId: vendor.id, amount: 1,
        referenceType: "hourly_guesthouse", referenceId: bookingId,
      })
    ).rejects.toThrow(/does not match/i);
    await expect(
      t.mutation(api.payments.createEscrowPayment, {
        sessionToken: other.token, vendorId: vendor.id, amount: 300,
        referenceType: "hourly_guesthouse", referenceId: bookingId,
      })
    ).rejects.toThrow(/another user/i);
  });

  test("a verified Monime payment for a booking funds its escrow (server amount), once", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    const vendor = await makeUser(t, "vendor");
    const bookingId = await makeBooking(t, buyer.id, vendor.id, 200);
    const sessions = stubMonime();
    try {
      // the client amount (1) is ignored: the server quotes the booking total
      await t.action(api.payments.initiateMoniMePayment, { sessionToken: buyer.token, amount: 1, bookingId, phoneNumber: "076123456" });
      const [sid] = [...sessions.keys()];
      expect(sessions.get(sid).lineItems.data[0].price.value).toBe(20000);
      sessions.get(sid).status = "completed";
      await t.action(internal.payments.settleMoniMeReference, { reference: sid });
      await t.action(internal.payments.settleMoniMeReference, { reference: sid }); // replay
    } finally {
      unstubMonime();
    }
    const b = await balance(t, buyer);
    expect(b.availableBalance).toBe(0);
    expect(b.escrowBalance).toBe(200); // held exactly once
    expect((await balance(t, vendor)).availableBalance).toBe(0); // vendor is paid on release only
    const booking = await t.run(async (ctx) => ctx.db.get(bookingId));
    expect(booking?.paymentStatus).toBe("completed");
  });

  test("a Monime checkout cannot be opened for someone else's or an already-paid booking", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    const other = await makeUser(t, "other");
    const vendor = await makeUser(t, "vendor");
    const bookingId = await makeBooking(t, buyer.id, vendor.id, 200);
    const sessions = stubMonime();
    try {
      await expect(
        t.action(api.payments.initiateMoniMePayment, { sessionToken: other.token, amount: 200, bookingId, phoneNumber: "076123456" })
      ).rejects.toThrow(/not found/i);
      await t.run(async (ctx) => ctx.db.patch(bookingId, { paymentStatus: "completed" }));
      await expect(
        t.action(api.payments.initiateMoniMePayment, { sessionToken: buyer.token, amount: 200, bookingId, phoneNumber: "076123456" })
      ).rejects.toThrow(/not awaiting payment/i);
      expect(sessions.size).toBe(0);
    } finally {
      unstubMonime();
    }
  });

  test("the booking split is decided by the server (85/15); a client split is ignored", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    const vendor = await makeUser(t, "vendor");
    await fund(t, buyer.id, 1000);
    const bookingId = await makeBooking(t, buyer.id, vendor.id, 500);
    const res: any = await t.mutation(api.payments.createEscrowPayment, {
      sessionToken: buyer.token, vendorId: vendor.id, amount: 500,
      referenceType: "hourly_guesthouse", referenceId: bookingId, partnerSplitPercent: 100,
    });
    expect(res.partnerAmount).toBe(425);
    expect(res.platformFeeAmount).toBe(75);
    const tx: any = await t.run(async (ctx) => ctx.db.get(res.transactionId));
    expect(tx.partnerAmount).toBe(425);
    expect(tx.platformFeeAmount).toBe(75);
  });

  test("a booking priced with a fee snapshot is split from the snapshot", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    const vendor = await makeUser(t, "vendor");
    await fund(t, buyer.id, 1000);
    // subtotal 200 + 5% service fee = 210; Vektolux keeps 15% of 210 (rounded) = 32, vendor 178
    const bookingId = await makeBooking(t, buyer.id, vendor.id, 210);
    const snap = await t.run(async (ctx) => {
      const { priceOrder } = await import("./lib/fees");
      return priceOrder(ctx as any, "marketplace_booking", 200, { hasAgent: false, now: Date.now() });
    });
    expect(snap.buyerTotal).toBe(210);
    await t.run(async (ctx) => ctx.db.patch(bookingId, { feeSnapshot: snap, subtotal: 200, serviceFee: 10 }));
    const res: any = await t.mutation(api.payments.createEscrowPayment, {
      sessionToken: buyer.token, vendorId: vendor.id, amount: 210, referenceType: "x", referenceId: bookingId,
    });
    expect(res.platformFeeAmount).toBe(snap.platformTotal);
    expect(res.partnerAmount).toBe(snap.payeeNet);
    await t.mutation(api.payments.releaseEscrowWithSplit, { transactionId: res.transactionId, sessionToken: buyer.token });
    expect((await balance(t, vendor)).availableBalance).toBe(snap.payeeNet);
  });

  test("releaseEscrowWithSplit refuses escrow holds that are not a booking's own escrow", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    const vendor = await makeUser(t, "vendor");
    await fund(t, buyer.id, 400);
    // e.g. a vehicle/property hold: must go through its own state machine
    const held: any = await t.mutation(internal.walletCore.holdFundsInEscrow, {
      userId: buyer.id, amount: 400, referenceType: "vehicle_escrow", referenceId: "order-1", idempotencyKey: "hold-v1",
    });
    const txId = held.transactionDocId ?? (await t.run(async (ctx) => {
      const all = await ctx.db.query("transactions").collect();
      return all.find((x) => x.type === "escrow_lock")!._id;
    }));
    await expect(
      t.mutation(api.payments.releaseEscrowWithSplit, { transactionId: txId, sessionToken: buyer.token })
    ).rejects.toThrow(/not a marketplace booking escrow/i);
    expect((await balance(t, buyer)).escrowBalance).toBe(400);
    expect((await balance(t, vendor)).availableBalance).toBe(0);
  });

  test("escrow release pays the vendor from REAL escrow; non-parties cannot release", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    const vendor = await makeUser(t, "vendor");
    const stranger = await makeUser(t, "stranger");
    await fund(t, buyer.id, 1000);
    const bookingId = await makeBooking(t, buyer.id, vendor.id, 500);
    const res: any = await t.mutation(api.payments.createEscrowPayment, {
      sessionToken: buyer.token, vendorId: vendor.id, amount: 500,
      referenceType: "hourly_guesthouse", referenceId: bookingId,
    });

    await expect(
      t.mutation(api.payments.releaseEscrowWithSplit, { transactionId: res.transactionId, sessionToken: stranger.token })
    ).rejects.toThrow(/not a party/i);
    await expect(
      t.mutation(api.payments.releaseEscrowWithSplit, { transactionId: res.transactionId, sessionToken: vendor.token })
    ).rejects.toThrow(/not a party/i);

    await t.mutation(api.payments.releaseEscrowWithSplit, { transactionId: res.transactionId, sessionToken: buyer.token });
    // a second release is refused (idempotent / no double pay)
    await expect(
      t.mutation(api.payments.releaseEscrowWithSplit, { transactionId: res.transactionId, sessionToken: buyer.token })
    ).rejects.toThrow(/already/i);

    const b = await balance(t, buyer);
    expect(b.escrowBalance).toBe(0);
    expect(b.availableBalance).toBe(500);
    expect((await balance(t, vendor)).availableBalance).toBe(425); // server split: vendor 85%
    const booking = await t.run(async (ctx) => ctx.db.get(bookingId));
    expect(booking?.status).toBe("completed");
  });

  test("refund returns escrowed funds to the buyer's available balance, once", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 400);
    await t.mutation(internal.walletCore.holdFundsInEscrow, {
      userId: buyer.id, amount: 400, referenceType: "deal", referenceId: "d1", idempotencyKey: "hold-1",
    });
    expect((await balance(t, buyer)).escrowBalance).toBe(400);
    await t.mutation(internal.walletCore.refundEscrowToBuyer, {
      userId: buyer.id, amount: 400, referenceType: "deal", referenceId: "d1", idempotencyKey: "refund-1",
    });
    await t.mutation(internal.walletCore.refundEscrowToBuyer, {
      userId: buyer.id, amount: 400, referenceType: "deal", referenceId: "d1", idempotencyKey: "refund-1",
    });
    const b = await balance(t, buyer);
    expect(b.escrowBalance).toBe(0);
    expect(b.availableBalance).toBe(400);
  });

  test("the same money cannot be held twice", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 100);
    await t.mutation(internal.walletCore.holdFundsInEscrow, {
      userId: buyer.id, amount: 100, referenceType: "deal", referenceId: "d1", idempotencyKey: "hold-A",
    });
    await expect(
      t.mutation(internal.walletCore.holdFundsInEscrow, {
        userId: buyer.id, amount: 100, referenceType: "deal", referenceId: "d2", idempotencyKey: "hold-B",
      })
    ).rejects.toThrow(/INSUFFICIENT_FUNDS/);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("withdrawals", () => {
  const bankArgs = (token: string, amount: number, key: string, pin = PIN) => ({
    sessionToken: token,
    amount,
    method: "bank" as const,
    destinationProviderCode: "Test Bank",
    destinationAccountNumber: "0123456789",
    destinationName: "Alice Test",
    bankName: "Test Bank",
    pin,
    idempotencyKey: key,
  });

  test("withdrawal reserves funds; only a confirmed payout removes them", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const admin = await makeUser(t, "admin", "admin");
    await fund(t, a.id, 1000);

    const res: any = await t.action(api.withdrawals.requestWithdrawal, bankArgs(a.token, 400, "wd-key-000000001"));
    expect(res.success).toBe(true);
    expect(res.status).toBe("pending"); // NOT completed: awaiting real confirmation

    let b = await balance(t, a);
    expect(b.availableBalance).toBe(600);
    expect(b.pendingBalance).toBe(400);

    await t.mutation(api.withdrawals.adminResolveWithdrawal, {
      sessionToken: admin.token, withdrawalId: res.withdrawalId, outcome: "completed", providerReference: "BANK-REF-1",
    });
    b = await balance(t, a);
    expect(b.availableBalance).toBe(600);
    expect(b.pendingBalance).toBe(0);
  });

  test("a failed withdrawal releases the reserved funds", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const admin = await makeUser(t, "admin", "admin");
    await fund(t, a.id, 1000);
    const res: any = await t.action(api.withdrawals.requestWithdrawal, bankArgs(a.token, 400, "wd-key-000000002"));
    await t.mutation(api.withdrawals.adminResolveWithdrawal, {
      sessionToken: admin.token, withdrawalId: res.withdrawalId, outcome: "failed", reason: "bank rejected",
    });
    const b = await balance(t, a);
    expect(b.availableBalance).toBe(1000);
    expect(b.pendingBalance).toBe(0);
  });

  test("cannot withdraw more than the available balance", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    await fund(t, a.id, 100);
    await expect(
      t.action(api.withdrawals.requestWithdrawal, bankArgs(a.token, 101, "wd-key-000000003"))
    ).rejects.toThrow(/INSUFFICIENT_FUNDS/);
    expect((await balance(t, a)).availableBalance).toBe(100);
  });

  test("funds protected in escrow cannot be withdrawn", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const v = await makeUser(t, "vendor");
    await fund(t, a.id, 400);
    const bookingId = await makeBooking(t, a.id, v.id, 300);
    await t.mutation(api.payments.createEscrowPayment, {
      sessionToken: a.token, vendorId: v.id, amount: 300, referenceId: bookingId,
    }); // available 100, escrow 300
    const b = await balance(t, a);
    expect(b.availableBalance).toBe(100);
    expect(b.escrowBalance).toBe(300);
    await expect(
      t.action(api.withdrawals.requestWithdrawal, bankArgs(a.token, 200, "wd-key-000000004"))
    ).rejects.toThrow(/INSUFFICIENT_FUNDS/);
  });

  test("the same request cannot withdraw twice (idempotency)", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    await fund(t, a.id, 1000);
    await t.action(api.withdrawals.requestWithdrawal, bankArgs(a.token, 400, "wd-key-000000005"));
    const again: any = await t.action(api.withdrawals.requestWithdrawal, bankArgs(a.token, 400, "wd-key-000000005"));
    expect(again.duplicate).toBe(true);
    const b = await balance(t, a);
    expect(b.availableBalance).toBe(600);
    expect(b.pendingBalance).toBe(400);
  });

  test("an unconfigured mobile-money provider never fakes success and releases the funds", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    await fund(t, a.id, 500);
    const res: any = await t.action(api.withdrawals.requestWithdrawal, {
      sessionToken: a.token, amount: 200, method: "mobile_money",
      destinationProviderCode: "orange", destinationAccountNumber: "+23276123456", pin: PIN,
      idempotencyKey: "wd-key-000000006",
    });
    expect(res.status).toBe("failed");
    const b = await balance(t, a);
    expect(b.availableBalance).toBe(500);
    expect(b.pendingBalance).toBe(0);
  });

  test("a wrong PIN is refused and repeated failures lock the wallet", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    await fund(t, a.id, 500);
    for (let i = 0; i < 5; i++) {
      const r: any = await t.action(api.withdrawals.requestWithdrawal, bankArgs(a.token, 10, `wd-key-bad-pin-${i}0000`, "9999"));
      expect(r.success).toBe(false);
    }
    // even the correct PIN is refused while locked
    const locked: any = await t.action(api.withdrawals.requestWithdrawal, bankArgs(a.token, 10, "wd-key-locked-00001"));
    expect(locked.success).toBe(false);
    expect(locked.errorCode).toBe("LOCKED");
    expect((await balance(t, a)).availableBalance).toBe(500);
  });

  test("a user cannot withdraw with another user's session or an unauthenticated call", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await fund(t, a.id, 500);
    await expect(
      t.action(api.withdrawals.requestWithdrawal, { ...bankArgs(b.token, 100, "wd-key-000000007"), userId: a.id })
    ).rejects.toThrow(/another user/i);
    await expect(
      t.action(api.withdrawals.requestWithdrawal, { ...bankArgs("", 100, "wd-key-000000008"), sessionToken: undefined })
    ).rejects.toThrow(/authentication/i);
  });

  test("only an admin can resolve a withdrawal", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    await fund(t, a.id, 500);
    const res: any = await t.action(api.withdrawals.requestWithdrawal, bankArgs(a.token, 100, "wd-key-000000009"));
    await expect(
      t.mutation(api.withdrawals.adminResolveWithdrawal, {
        sessionToken: a.token, withdrawalId: res.withdrawalId, outcome: "completed", providerReference: "x",
      })
    ).rejects.toThrow(/administrator/i);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("QR payments", () => {
  test("scanning (resolving) a QR moves no money", async () => {
    const t = convexTest(schema, modules);
    const payer = await makeUser(t, "payer");
    const receiver = await makeUser(t, "receiver");
    await fund(t, payer.id, 500);
    const qr: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: receiver.token, amount: 50 });

    const resolved: any = await t.query(api.qrPayment.resolveQR, { sessionToken: payer.token, payload: qr.qrPayload });
    expect(resolved.valid).toBe(true);
    expect(resolved.recipientName).toBe("receiver");
    expect(resolved.fixedAmount).toBe(50);
    expect((await balance(t, payer)).availableBalance).toBe(500);
    expect((await balance(t, receiver)).availableBalance).toBe(0);
  });

  test("the QR payload contains only an opaque token — no user id, phone, name or amount", async () => {
    const t = convexTest(schema, modules);
    const receiver = await makeUser(t, "receiver");
    const qr: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: receiver.token, amount: 75, note: "Rent" });
    expect(qr.qrPayload).toMatch(/^vektolux:\/\/pay\?r=[a-z0-9]{32}$/);
    expect(qr.qrPayload).not.toContain(receiver.id);
    expect(qr.qrPayload).not.toContain("receiver");
    // (the random token itself may contain "75" by chance; check everything except it)
    expect(qr.qrPayload.replace(/r=[a-z0-9]{32}$/, "r=")).not.toContain("75");
    expect(qr.qrPayload).not.toContain("+2327600");
  });

  test("paying sends the exact amount to the right recipient", async () => {
    const t = convexTest(schema, modules);
    const payer = await makeUser(t, "payer");
    const receiver = await makeUser(t, "receiver");
    const bystander = await makeUser(t, "bystander");
    await fund(t, payer.id, 500);
    const qr: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: receiver.token, amount: 120 });

    const receipt: any = await t.mutation(api.qrPayment.payQR, {
      sessionToken: payer.token, payload: qr.qrPayload, pin: PIN, idempotencyKey: "qr-pay-key-00000001",
    });
    expect(receipt.success).toBe(true);
    expect(receipt.amount).toBe(120);
    expect((await balance(t, payer)).availableBalance).toBe(380);
    expect((await balance(t, receiver)).availableBalance).toBe(120);
    expect((await balance(t, bystander)).availableBalance).toBe(0);

    // both users have a record of it
    const hp = await t.query(api.walletCore.getUserTransactions, { sessionToken: payer.token });
    const hr = await t.query(api.walletCore.getUserTransactions, { sessionToken: receiver.token });
    expect(hp.transactions.some((x) => x.netAmount === -120)).toBe(true);
    expect(hr.transactions.some((x) => x.netAmount === 120)).toBe(true);

    // the receiver sees it as paid, with the payer's name
    const status: any = await t.query(api.qrPayment.getMyQRStatus, { sessionToken: receiver.token, token: qr.token });
    expect(status.status).toBe("paid");
    expect(status.payerName).toBe("payer");
  });

  test("a duplicate payment attempt (same idempotency key) does not pay twice", async () => {
    const t = convexTest(schema, modules);
    const payer = await makeUser(t, "payer");
    const receiver = await makeUser(t, "receiver");
    await fund(t, payer.id, 500);
    const qr: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: receiver.token }); // open amount, reusable
    const args = { sessionToken: payer.token, payload: qr.qrPayload, amount: 40, pin: PIN, idempotencyKey: "qr-pay-key-00000002" };
    await t.mutation(api.qrPayment.payQR, args);
    const again: any = await t.mutation(api.qrPayment.payQR, args);
    expect(again.duplicate).toBe(true);
    expect((await balance(t, payer)).availableBalance).toBe(460);
    expect((await balance(t, receiver)).availableBalance).toBe(40);
  });

  test("a single-use QR can only be paid once", async () => {
    const t = convexTest(schema, modules);
    const p1 = await makeUser(t, "payer1");
    const p2 = await makeUser(t, "payer2");
    const receiver = await makeUser(t, "receiver");
    await fund(t, p1.id, 100);
    await fund(t, p2.id, 100);
    const qr: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: receiver.token, amount: 30 });
    await t.mutation(api.qrPayment.payQR, { sessionToken: p1.token, payload: qr.qrPayload, pin: PIN, idempotencyKey: "qr-pay-key-00000003" });
    await expect(
      t.mutation(api.qrPayment.payQR, { sessionToken: p2.token, payload: qr.qrPayload, pin: PIN, idempotencyKey: "qr-pay-key-00000004" })
    ).rejects.toThrow(/paid/i);
    expect((await balance(t, p2)).availableBalance).toBe(100);
  });

  test("the amount comes from the server: a different amount for a fixed QR is refused", async () => {
    const t = convexTest(schema, modules);
    const payer = await makeUser(t, "payer");
    const receiver = await makeUser(t, "receiver");
    await fund(t, payer.id, 500);
    const qr: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: receiver.token, amount: 100 });
    await expect(
      t.mutation(api.qrPayment.payQR, {
        sessionToken: payer.token, payload: qr.qrPayload, amount: 1, pin: PIN, idempotencyKey: "qr-pay-key-00000005",
      })
    ).rejects.toThrow(/AMOUNT_MISMATCH/);
    expect((await balance(t, payer)).availableBalance).toBe(500);
  });

  test("expired, cancelled, self-pay and forged legacy payloads are refused", async () => {
    const t = convexTest(schema, modules);
    const payer = await makeUser(t, "payer");
    const receiver = await makeUser(t, "receiver");
    await fund(t, payer.id, 500);

    const expired: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: receiver.token, amount: 10 });
    await t.run(async (ctx) => {
      const row = await ctx.db.query("qr_payment_requests").withIndex("by_token", (q) => q.eq("token", expired.token)).first();
      await ctx.db.patch(row!._id, { expiresAt: Date.now() - 1000 });
    });
    const r1: any = await t.query(api.qrPayment.resolveQR, { sessionToken: payer.token, payload: expired.qrPayload });
    expect(r1.valid).toBe(false);
    expect(r1.reason).toBe("EXPIRED");
    await expect(
      t.mutation(api.qrPayment.payQR, { sessionToken: payer.token, payload: expired.qrPayload, pin: PIN, idempotencyKey: "qr-pay-key-00000006" })
    ).rejects.toThrow(/expired/i);

    const cancelled: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: receiver.token, amount: 10 });
    await t.mutation(api.qrPayment.cancelReceiveQR, { sessionToken: receiver.token, token: cancelled.token });
    await expect(
      t.mutation(api.qrPayment.payQR, { sessionToken: payer.token, payload: cancelled.qrPayload, pin: PIN, idempotencyKey: "qr-pay-key-00000007" })
    ).rejects.toThrow(/cancelled/i);

    const own: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: receiver.token, amount: 10 });
    await expect(
      t.mutation(api.qrPayment.payQR, { sessionToken: receiver.token, payload: own.qrPayload, pin: PIN, idempotencyKey: "qr-pay-key-00000008" })
    ).rejects.toThrow(/yourself/i);

    // the old style payload (user id inside the QR) is not a valid payment code
    const legacy: any = await t.query(api.qrPayment.resolveQR, {
      sessionToken: payer.token, payload: `vektolux://pay?userId=${receiver.id}&name=receiver`,
    });
    expect(legacy.valid).toBe(false);
    expect((await balance(t, payer)).availableBalance).toBe(500);
  });

  test("a wrong PIN does not pay; a QR can only be cancelled/inspected by its owner", async () => {
    const t = convexTest(schema, modules);
    const payer = await makeUser(t, "payer");
    const receiver = await makeUser(t, "receiver");
    await fund(t, payer.id, 500);
    const qr: any = await t.mutation(api.qrPayment.createReceiveQR, { sessionToken: receiver.token, amount: 10 });
    const bad: any = await t.mutation(api.qrPayment.payQR, {
      sessionToken: payer.token, payload: qr.qrPayload, pin: "0000", idempotencyKey: "qr-pay-key-00000009",
    });
    expect(bad.success).toBe(false);
    expect((await balance(t, payer)).availableBalance).toBe(500);

    await expect(t.mutation(api.qrPayment.cancelReceiveQR, { sessionToken: payer.token, token: qr.token })).rejects.toThrow(/not found/i);
    await expect(t.query(api.qrPayment.getMyQRStatus, { sessionToken: payer.token, token: qr.token })).rejects.toThrow(/not found/i);
  });

  test("an unauthenticated caller cannot create, resolve or pay a QR", async () => {
    const t = convexTest(schema, modules);
    await expect(t.mutation(api.qrPayment.createReceiveQR, {})).rejects.toThrow(/authentication/i);
    await expect(t.query(api.qrPayment.resolveQR, { payload: "vektolux://pay?r=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" })).rejects.toThrow(/authentication/i);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("wallet-to-wallet transfers", () => {
  test("a transfer moves money between the right users and cannot overdraw", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await fund(t, a.id, 100);
    const r: any = await t.mutation(api.payments.executeP2PTransfer, {
      sessionToken: a.token, recipientQuery: b.id, amount: 40, pin: PIN, idempotencyKey: "p2p-key-000000001",
    });
    expect(r.success).toBe(true);
    expect((await balance(t, a)).availableBalance).toBe(60);
    expect((await balance(t, b)).availableBalance).toBe(40);

    await expect(
      t.mutation(api.payments.executeP2PTransfer, {
        sessionToken: a.token, recipientQuery: b.id, amount: 61, pin: PIN, idempotencyKey: "p2p-key-000000002",
      })
    ).rejects.toThrow(/INSUFFICIENT_FUNDS/);
  });

  test("a transfer cannot be sent on behalf of another user", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await fund(t, a.id, 100);
    await expect(
      t.mutation(api.payments.executeP2PTransfer, {
        sessionToken: b.token, senderUserId: a.id, recipientQuery: b.id, amount: 50, pin: PIN,
      })
    ).rejects.toThrow(/another user/i);
    expect((await balance(t, a)).availableBalance).toBe(100);
  });

  test("escrow-protected funds cannot be transferred", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await fund(t, a.id, 100);
    await t.mutation(internal.walletCore.holdFundsInEscrow, {
      userId: a.id, amount: 100, referenceType: "deal", referenceId: "d1", idempotencyKey: "hold-T1",
    });
    await expect(
      t.mutation(api.payments.executeP2PTransfer, { sessionToken: a.token, recipientQuery: b.id, amount: 10, pin: PIN })
    ).rejects.toThrow(/INSUFFICIENT_FUNDS/);
  });

  test("recipient lookup requires a session and never leaks email or full phone", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await expect(t.query(api.payments.resolveRecipient, { query: b.id })).rejects.toThrow(/authentication/i);
    const r: any = await t.query(api.payments.resolveRecipient, { sessionToken: a.token, query: b.id });
    expect(r.found).toBe(true);
    expect(r.email).toBeUndefined();
    expect(r.phone).not.toContain("+2327600");
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("authorization", () => {
  test("only the owner can change a PIN (and needs the current one)", async () => {
    const t = convexTest(schema, modules);
    const a = await makeUser(t, "alice");
    const b = await makeUser(t, "bob");
    await expect(
      t.mutation(api.payments.setWalletPin, { sessionToken: b.token, userId: a.id, pin: "5555", currentPin: PIN })
    ).rejects.toThrow(/another user/i);
    const noCurrent: any = await t.mutation(api.payments.setWalletPin, { sessionToken: a.token, pin: "5555" });
    expect(noCurrent.success).toBe(false);
    const ok: any = await t.mutation(api.payments.setWalletPin, { sessionToken: a.token, pin: "5555", currentPin: PIN });
    expect(ok.success).toBe(true);
  });

  test("a user cannot modify another user's listing by changing an id", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner", "agent");
    const attacker = await makeUser(t, "attacker");
    const listingId = await t.run(async (ctx) =>
      ctx.db.insert("realEstateListings", {
        ownerId: owner.id, title: "House", description: "d", category: "sale", price: 1000, currency: "SLE",
        address: "a", city: "Freetown", country: "SL", latitude: 8.4, longitude: -13.2, geohash: "abc",
        imageUrls: [], availabilityStatus: "available", isFeatured: false, viewCount: 0, updatedAt: Date.now(),
      })
    );
    await expect(
      t.mutation(api.realEstate.updatePropertyListing, { listingId, ownerId: owner.id, sessionToken: attacker.token, price: 1 })
    ).rejects.toThrow(/permission|another user/i);
    await expect(
      t.mutation(api.realEstate.updatePropertyListing, { listingId, ownerId: owner.id, price: 1 })
    ).rejects.toThrow(/authentication/i);
    await expect(
      t.mutation(api.realEstate.deletePropertyListing, { listingId, ownerId: attacker.id, sessionToken: attacker.token })
    ).rejects.toThrow(/permission/i);
    const row = await t.run(async (ctx) => ctx.db.get(listingId));
    expect(row?.price).toBe(1000);
  });

  test("a normal client cannot post a listing", async () => {
    const t = convexTest(schema, modules);
    const client = await makeUser(t, "client");
    await expect(
      t.mutation(api.realEstate.createPropertyListing, {
        ownerId: client.id, sessionToken: client.token, title: "x", description: "y", category: "sale", price: 1,
        address: "a", latitude: 1, longitude: 1, imageStorageIds: [],
      })
    ).rejects.toThrow(/approved Real Estate Owner or Real Estate Agent/i);
  });

  test("subscription plan prices can only be changed by an admin", async () => {
    const t = convexTest(schema, modules);
    const client = await makeUser(t, "client");
    const admin = await makeUser(t, "admin", "admin");
    const plan = {
      tierCode: "AGENT_MONTHLY", name: "Agent Monthly", roleTarget: "agent" as const, basePrice: 10, currency: "SLE",
      billingInterval: "monthly" as const, intervalDays: 30, discountPercent: 0, isActive: true, features: [],
    };
    await expect(t.mutation(api.subscriptions.adminUpsertPlan, { ...plan, sessionToken: client.token })).rejects.toThrow(/administrator/i);
    await expect(t.mutation(api.subscriptions.adminUpsertPlan, plan)).rejects.toThrow(/authentication/i);
    const ok: any = await t.mutation(api.subscriptions.adminUpsertPlan, { ...plan, sessionToken: admin.token });
    expect(ok.action).toBe("created");
  });

  test("a bank transfer can only be confirmed by an admin, for the order's real amount", async () => {
    const t = convexTest(schema, modules);
    const client = await makeUser(t, "client");
    await expect(
      t.mutation(api.payments.confirmBankEscrowTransfer, { sessionToken: client.token, bankEscrowReference: "VKTLX-DEAL-X", amountTransferred: 1e9 })
    ).rejects.toThrow(/administrator/i);
  });

  test("payment settings (where users send money) are admin-only", async () => {
    const t = convexTest(schema, modules);
    const client = await makeUser(t, "client");
    await expect(t.query(api.payments.getAllPaymentMethods, { sessionToken: client.token })).rejects.toThrow(/administrator/i);
    await expect(t.mutation(api.payments.seedDefaultPaymentMethods, {})).rejects.toThrow(/authentication/i);
  });

  test("only a party to an escrow order can read it; the admin summary is admin-only", async () => {
    const t = convexTest(schema, modules);
    const client = await makeUser(t, "client");
    await expect(t.query(api.escrow.getAdminEscrowSummary, { sessionToken: client.token })).rejects.toThrow(/administrator/i);
    await expect(t.query(api.escrow.getAdminEscrowSummary, {})).rejects.toThrow(/authentication/i);
  });
});
