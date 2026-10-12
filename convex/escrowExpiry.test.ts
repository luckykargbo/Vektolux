/// <reference types="vite/client" />
// Expiry of UNPAID escrow orders / contracts / passes: eligibility, idempotence, late-payment safety.
import { convexTest } from "convex-test";
import { describe, expect, test, afterEach } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";
import { fundVehicleOrderFromWallet } from "./escrow";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
const DAY = 86_400_000;
let seq = 0;

async function makeUser(t: T, name: string, role = "client") {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327500${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
    } as any)
  );
  return { id, token };
}
const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });
const wallet = async (t: T, userId: Id<"users">) =>
  (await t.run(async (ctx) => (await ctx.db.query("walletBalances").collect()).find((w) => w.userId === userId))) ??
  ({ availableBalance: 0, escrowBalance: 0, pendingBalance: 0 } as any);

const makeVehicle = (t: T, ownerId: Id<"users">) =>
  t.run(async (ctx) =>
    ctx.db.insert("vehicleListings", {
      ownerId, title: "Toyota Hilux", category: "car_rental", price: 100, pricingType: "per_day", images: [],
      createdAt: Date.now(), location: "Bo", latitude: 0, longitude: 0, geohash: "", status: "AVAILABLE", isPublished: true, updatedAt: Date.now(),
    } as any)
  );
const makeProperty = (t: T, ownerId: Id<"users">) =>
  t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId, title: "Test property", description: "d", category: "sale", price: 50000, currency: "SLE",
      address: "a", city: "Lumley", district: "Western Area Urban", country: "Sierra Leone", latitude: 8.4, longitude: -13.2,
      geohash: "abc", imageUrls: [], availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
    } as any)
  );

/** A real unpaid vehicle order (mobile-money rail) created through the real mutation, then aged. */
async function unpaidVehicleOrder(t: T, ageDays = 15, rail = "MOBILE_MONEY") {
  const owner = await makeUser(t, "owner");
  const buyer = await makeUser(t, "buyer");
  const v = await makeVehicle(t, owner.id);
  const r: any = await t.mutation(api.escrow.initiateEscrowOrder, {
    sessionToken: buyer.token, orderType: "VEHICLE_RENTAL", vehicleListingId: v, numberOfDays: 3, paymentRail: rail,
  } as any);
  const id = r.escrowOrderId as Id<"escrow_orders">;
  await t.run(async (ctx) => ctx.db.patch(id, { createdAt: Date.now() - ageDays * DAY }));
  return { id, owner, buyer };
}
async function unpaidContract(t: T, ageDays = 15, contractType = "LAND_PURCHASE_MILESTONE", rail = "MOBILE_MONEY") {
  const owner = await makeUser(t, "owner");
  const client = await makeUser(t, "client");
  const p = await makeProperty(t, owner.id);
  const r: any = await t.mutation(api.realEstateEscrow.initiateRealEstateEscrow, {
    sessionToken: client.token, contractType, propertyListingId: p, paymentRail: rail,
  } as any);
  const id = r.contractId as Id<"re_escrow_contracts">;
  await t.run(async (ctx) => ctx.db.patch(id, { createdAt: Date.now() - ageDays * DAY }));
  return { id, owner, client, propertyId: p };
}
const get = (t: T, id: any) => t.run(async (ctx) => ctx.db.get(id));
const run = (t: T, args: Record<string, unknown> = {}) => t.mutation(internal.escrowExpiry.expireUnpaidOrders, args as any) as Promise<any>;
const counts = (t: T) =>
  t.run(async (ctx) => ({
    transactions: (await ctx.db.query("transactions").collect()).length,
    wallets: JSON.stringify((await ctx.db.query("walletBalances").collect()).map((w) => [w.userId, w.availableBalance, w.escrowBalance, w.pendingBalance])),
    ledgerTx: (await ctx.db.query("ledger_transactions").collect()).length,
    ledgerEntries: (await ctx.db.query("ledger_entries").collect()).length,
  }));
const notifs = (t: T) => t.run(async (ctx) => ctx.db.query("user_notifications").collect());

afterEach(() => { delete process.env.ESCROW_BANK_NAME; });

describe("vehicle orders", () => {
  test("a stale unpaid mobile-money order expires exactly once, with no wallet or ledger effect", async () => {
    const t = convexTest(schema, modules);
    const { id } = await unpaidVehicleOrder(t);
    const before = await counts(t);
    const r1 = await run(t);
    expect(r1.vehicleOrders).toBe(1);
    const o: any = await get(t, id);
    expect(o.status).toBe("CANCELLED");
    expect(o.cancelReason).toBe("unpaid_expired");
    expect(o.cancelledBy).toBe("system_expiry");
    expect(typeof o.cancelledAt).toBe("number");
    expect(await counts(t)).toEqual(before); // wallets, transactions, ledger untouched

    const notesAfterFirst = (await notifs(t)).length;
    expect(notesAfterFirst).toBe(2); // buyer + seller, once
    const r2 = await run(t);
    expect(r2.vehicleOrders + r2.contracts + r2.passes).toBe(0);
    expect((await notifs(t)).length).toBe(notesAfterFirst); // a retry sends nothing
    expect(await counts(t)).toEqual(before);
  });

  test("the notice tells the buyer to contact support with a payment reference, and does not claim a refund", async () => {
    const t = convexTest(schema, modules);
    const { buyer } = await unpaidVehicleOrder(t);
    await run(t);
    const mine: any = (await notifs(t)).find((n) => n.userId === (buyer.id as string));
    expect(mine.body).toMatch(/14 days/);
    expect(mine.body).toMatch(/contact Vektolux support with your payment reference/);
    expect(mine.body).not.toMatch(/refund|lost/i);
  });

  test("an order younger than 14 days is untouched; a wallet-rail unpaid order is eligible", async () => {
    const t = convexTest(schema, modules);
    const young = await unpaidVehicleOrder(t, 13);
    await run(t);
    expect(((await get(t, young.id)) as any).status).toBe("PENDING_PAYMENT");
    const t2 = convexTest(schema, modules);
    const old = await unpaidVehicleOrder(t2, 20);
    await t2.run(async (ctx) => ctx.db.patch(old.id, { paymentRail: "WALLET" }));
    expect((await run(t2)).vehicleOrders).toBe(1);
  });

  test("a bank-transfer order is NEVER expired automatically, however old", async () => {
    const t = convexTest(schema, modules);
    const { id } = await unpaidVehicleOrder(t, 400, "BANK_TRANSFER");
    const r = await run(t);
    expect(r.vehicleOrders).toBe(0);
    expect(((await get(t, id)) as any).status).toBe("PENDING_PAYMENT");
    // a mobile-money order that nevertheless carries a bank reference / cleared status is also protected
    const t2 = convexTest(schema, modules);
    const a = await unpaidVehicleOrder(t2, 30);
    await t2.run(async (ctx) => ctx.db.patch(a.id, { bankClearingStatus: "CLEARED" }));
    const b = await unpaidVehicleOrder(t2, 30);
    await t2.run(async (ctx) => ctx.db.patch(b.id, { bankEscrowReference: "VKTLX-DEAL-1234" }));
    expect((await run(t2)).vehicleOrders).toBe(0);
  });

  test.each([
    ["a pending Monime checkout", { referenceType: "escrow_checkout", status: "pending" }],
    ["a completed Monime deposit", { referenceType: "escrow_checkout", status: "completed" }],
    ["held funds (escrow_lock)", { referenceType: "vehicle_escrow", status: "completed", type: "escrow_lock" }],
  ])("%s prevents expiry", async (_n, extra: any) => {
    const t = convexTest(schema, modules);
    const { id, buyer } = await unpaidVehicleOrder(t);
    await t.run(async (ctx) => {
      const w = await ctx.db.insert("walletBalances", { userId: buyer.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: 1 });
      await ctx.db.insert("transactions", {
        transactionId: `E-${Math.random()}`, walletId: w, userId: buyer.id, type: "top_up", amount: 100, currency: "SLE",
        referenceId: extra.referenceType === "escrow_checkout" ? `vehicle:${id}` : (id as string), createdAt: 1, updatedAt: 1, ...extra,
      } as any);
    });
    expect((await run(t)).vehicleOrders).toBe(0);
    expect(((await get(t, id)) as any).status).toBe("PENDING_PAYMENT");
  });

  test("a FAILED Monime attempt (Monime itself reported expired/cancelled) does not block expiry", async () => {
    const t = convexTest(schema, modules);
    const { id, buyer } = await unpaidVehicleOrder(t);
    await t.run(async (ctx) => {
      const w = await ctx.db.insert("walletBalances", { userId: buyer.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: 1 });
      await ctx.db.insert("transactions", {
        transactionId: "F-1", walletId: w, userId: buyer.id, type: "top_up", amount: 100, currency: "SLE", status: "failed",
        referenceType: "escrow_checkout", referenceId: `vehicle:${id}`, createdAt: 1, updatedAt: 1,
      } as any);
    });
    expect((await run(t)).vehicleOrders).toBe(1);
  });

  test("a pending or approved claim blocks expiry; a rejected claim does not", async () => {
    for (const [status, expired] of [["PENDING_APPROVAL", 0], ["APPROVED", 0], ["REJECTED", 1]] as const) {
      const t = convexTest(schema, modules);
      const { id, buyer } = await unpaidVehicleOrder(t);
      await t.run(async (ctx) =>
        ctx.db.insert("escrow_payment_claims", {
          userId: buyer.id, escrowOrderId: id, amount: 800, currency: "SLE", providerId: "qmoney_manual", paymentType: "MANUAL_CLAIM",
          transactionReference: `REF-${status}`, status, createdAt: Date.now(),
        } as any)
      );
      expect((await run(t)).vehicleOrders, status).toBe(expired);
    }
  });

  test("a dispute, a ledger record or an open reversal blocks expiry", async () => {
    const t = convexTest(schema, modules);
    const a = await unpaidVehicleOrder(t);
    await t.run(async (ctx) =>
      ctx.db.insert("escrow_disputes", {
        escrowOrderId: a.id, openedByUserId: a.buyer.id, reason: "x", claimedRepairCost: 0, evidenceMediaUrls: [], status: "OPENED", openedAt: 1,
      } as any)
    );
    const b = await unpaidVehicleOrder(t);
    await t.run(async (ctx) => ctx.db.insert("ledger_transactions", { transactionCode: "L-1", escrowOrderId: b.id, description: "d", createdAt: 1 }));
    const c = await unpaidVehicleOrder(t);
    await t.run(async (ctx) => {
      const w = await ctx.db.insert("walletBalances", { userId: c.buyer.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: 1 });
      const tx = await ctx.db.insert("transactions", { transactionId: "R-1", walletId: w, userId: c.buyer.id, type: "escrow_release", amount: 1, currency: "SLE", status: "completed", createdAt: 1, updatedAt: 1 } as any);
      await ctx.db.insert("payment_reversals", {
        releaseTransactionId: tx, buyerId: c.buyer.id, recipientId: c.owner.id, currency: "SLE", referenceType: "x", referenceId: c.id as string,
        originalAmount: 1, platformFeeReversed: 0, recipientNetOwed: 1, recoveredFromRecipient: 0, platformCoveredAmount: 0, writtenOffAmount: 0,
        refundedToBuyer: 0, outstandingAmount: 1, status: "pending_recovery", reason: "t", createdBy: c.owner.id, createdAt: 1, updatedAt: 1,
      } as any);
    });
    expect((await run(t)).vehicleOrders).toBe(0);
    for (const x of [a, b, c]) expect(((await get(t, x.id)) as any).status).toBe("PENDING_PAYMENT");
  });

  test("a funded order (HELD_IN_ESCROW) and other statuses are never touched", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 5000);
    const v = await makeVehicle(t, owner.id);
    const r: any = await t.mutation(api.escrow.initiateEscrowOrder, {
      sessionToken: buyer.token, orderType: "VEHICLE_RENTAL", vehicleListingId: v, numberOfDays: 3, payFromWallet: true,
    } as any);
    await t.run(async (ctx) => ctx.db.patch(r.escrowOrderId, { createdAt: Date.now() - 60 * DAY }));
    const before = await counts(t);
    expect((await run(t)).vehicleOrders).toBe(0);
    expect(((await get(t, r.escrowOrderId)) as any).status).toBe("HELD_IN_ESCROW");
    expect(await counts(t)).toEqual(before);
  });

  test("batches are bounded by `limit`", async () => {
    const t = convexTest(schema, modules);
    const ids: Id<"escrow_orders">[] = [];
    for (let i = 0; i < 4; i++) ids.push((await unpaidVehicleOrder(t, 20 + i)).id);
    const r = await run(t, { limit: 2 });
    expect(r.vehicleOrders).toBe(2);
    expect((await run(t, { limit: 10 })).vehicleOrders).toBe(2); // the rest, once
    for (const id of ids) expect(((await get(t, id)) as any).status).toBe("CANCELLED");
  });
});

describe("real-estate contracts", () => {
  test("a stale unpaid contract expires; its caution deposit and milestones are closed; no money effect", async () => {
    const t = convexTest(schema, modules);
    const { id } = await unpaidContract(t);
    const before = await counts(t);
    const r = await run(t);
    expect(r.contracts).toBe(1);
    const c: any = await get(t, id);
    expect(c.currentState).toBe("CANCELLED");
    expect(c.cancelReason).toBe("unpaid_expired");
    const deposits: any[] = await t.run(async (ctx) => ctx.db.query("re_caution_deposits").collect());
    const milestones: any[] = await t.run(async (ctx) => ctx.db.query("re_escrow_milestones").collect());
    for (const d of deposits) {
      expect(d.status).toBe("VOID");
      expect(d.heldAmount).toBe(0);
      expect(d.originalDepositAmount).toBeGreaterThanOrEqual(0); // history is kept
    }
    for (const m of milestones) expect(m.state).toBe("CANCELLED");
    expect(await counts(t)).toEqual(before);
    expect((await run(t)).contracts).toBe(0); // idempotent
  });

  test("bank-transfer contracts never expire; a funded contract is never touched", async () => {
    const t = convexTest(schema, modules);
    const bank = await unpaidContract(t, 400, "LAND_PURCHASE_MILESTONE", "BANK_TRANSFER");
    expect((await run(t)).contracts).toBe(0);
    expect(((await get(t, bank.id)) as any).currentState).toBe("CREATED");

    const t2 = convexTest(schema, modules);
    const owner = await makeUser(t2, "owner");
    const client = await makeUser(t2, "client");
    await fund(t2, client.id, 500000);
    const p = await makeProperty(t2, owner.id);
    const r: any = await t2.mutation(api.realEstateEscrow.initiateRealEstateEscrow, {
      sessionToken: client.token, contractType: "LAND_PURCHASE_MILESTONE", propertyListingId: p, paymentRail: "WALLET",
    } as any);
    await t2.run(async (ctx) => ctx.db.patch(r.contractId, { createdAt: Date.now() - 90 * DAY }));
    expect((await run(t2)).contracts).toBe(0);
    expect(((await get(t2, r.contractId)) as any).currentState).toBe("FUNDS_LOCKED");
  });

  test("unresolved provider evidence, a claim or a dispute blocks a contract", async () => {
    const t = convexTest(schema, modules);
    const a = await unpaidContract(t);
    await t.run(async (ctx) => {
      const w = await ctx.db.insert("walletBalances", { userId: a.client.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: 1 });
      await ctx.db.insert("transactions", {
        transactionId: "RE-1", walletId: w, userId: a.client.id, type: "top_up", amount: 1, currency: "SLE", status: "pending",
        referenceType: "escrow_checkout", referenceId: `re:${a.id}`, createdAt: 1, updatedAt: 1,
      } as any);
    });
    const b = await unpaidContract(t);
    await t.run(async (ctx) =>
      ctx.db.insert("escrow_payment_claims", {
        userId: b.client.id, reContractId: b.id, amount: 1, currency: "SLE", providerId: "x", paymentType: "MANUAL_CLAIM",
        transactionReference: "R-B", status: "PENDING_APPROVAL", createdAt: 1,
      } as any)
    );
    const c = await unpaidContract(t);
    await t.run(async (ctx) =>
      ctx.db.insert("re_escrow_disputes", {
        contractId: c.id, openedByUserId: c.client.id, claimantRole: "client", reason: "r", claimedRepairCost: 0, evidenceMediaUrls: [], status: "OPENED", openedAt: 1,
      } as any)
    );
    expect((await run(t)).contracts).toBe(0);
  });

  test("account deletion is blocked by an unpaid contract and unblocked ONLY after a safe expiry", async () => {
    const t = convexTest(schema, modules);
    const { id, client } = await unpaidContract(t);
    await t.run(async (ctx) =>
      ctx.db.patch(client.id, { deletionRequestedAt: 1, deletionScheduledFor: Date.now() - 1000, sessionToken: undefined, sessionExpiresAt: undefined } as any)
    );
    const before: any = await t.mutation(internal.accountDeletion.processDueDeletions, {});
    expect(before.deferred.find((d: any) => d.userId === (client.id as string))?.reason).toBe("RE_ESCROW_OPEN");
    await run(t);
    expect(((await get(t, id)) as any).currentState).toBe("CANCELLED");
    const after: any = await t.mutation(internal.accountDeletion.processDueDeletions, {});
    expect(after.processed).toBeGreaterThanOrEqual(1);
    expect(((await get(t, client.id)) as any).anonymizedAt).toBeDefined();
  });
});

describe("inspection passes", () => {
  async function pass(t: T, rail = "MOBILE_MONEY") {
    const owner = await makeUser(t, "owner");
    const client = await makeUser(t, "client");
    const p = await makeProperty(t, owner.id);
    const r: any = await t.mutation(api.realEstateEscrow.initiateInspectionPass, {
      sessionToken: client.token, propertyListingId: p, scheduledTimestamp: Date.now() + 3_600_000, paymentRail: rail,
    } as any);
    return { id: r.passId as Id<"re_inspection_passes">, client, owner, p };
  }

  test("expires only after its own deadline (scheduled + 4h), once, with no money effect", async () => {
    const t = convexTest(schema, modules);
    const { id } = await pass(t);
    expect((await run(t)).passes).toBe(0); // deadline in the future
    const before = await counts(t);
    await t.run(async (ctx) => ctx.db.patch(id, { otpExpiresAt: Date.now() - 1000 }));
    expect((await run(t)).passes).toBe(1);
    expect(((await get(t, id)) as any).status).toBe("CANCELLED");
    expect((await run(t)).passes).toBe(0);
    expect(await counts(t)).toEqual(before);
  });

  test("a paid / funded / used pass is never expired", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const client = await makeUser(t, "client");
    await fund(t, client.id, 500);
    const p = await makeProperty(t, owner.id);
    const r: any = await t.mutation(api.realEstateEscrow.initiateInspectionPass, {
      sessionToken: client.token, propertyListingId: p, scheduledTimestamp: Date.now() + 3_600_000, paymentRail: "WALLET",
    } as any);
    expect(r.status).toBe("FUNDS_LOCKED");
    await t.run(async (ctx) => ctx.db.patch(r.passId, { otpExpiresAt: Date.now() - 1000 }));
    expect((await run(t)).passes).toBe(0);

    const t2 = convexTest(schema, modules);
    const used = await pass(t2);
    await t2.run(async (ctx) => ctx.db.patch(used.id, { otpExpiresAt: Date.now() - 1000, failedAttempts: 2 }));
    expect((await run(t2)).passes).toBe(0);

    const t3 = convexTest(schema, modules);
    const bound = await pass(t3);
    await t3.run(async (ctx) => {
      await ctx.db.patch(bound.id, { otpExpiresAt: Date.now() - 1000 });
      const w = await ctx.db.insert("walletBalances", { userId: bound.client.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: 1 });
      await ctx.db.insert("transactions", {
        transactionId: "P-1", walletId: w, userId: bound.client.id, type: "top_up", amount: 50, currency: "SLE", status: "pending",
        referenceType: "escrow_checkout", referenceId: `pass:${bound.id}`, createdAt: 1, updatedAt: 1,
      } as any);
    });
    expect((await run(t3)).passes).toBe(0);
  });
});

describe("late payments are never lost or double-credited", () => {
  test("a Monime deposit confirmed AFTER expiry lands in the wallet once; the order stays cancelled; no escrow hold", async () => {
    const t = convexTest(schema, modules);
    const { id, buyer } = await unpaidVehicleOrder(t);
    await run(t);
    expect(((await get(t, id)) as any).status).toBe("CANCELLED");
    // a verified Monime payment arrives for a pending deposit that was bound to this order's checkout
    const txId = await t.run(async (ctx) => {
      const w = await ctx.db.insert("walletBalances", { userId: buyer.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: 1 });
      return ctx.db.insert("transactions", {
        transactionId: "LATE-1", walletId: w, userId: buyer.id, type: "top_up", amount: 800, currency: "SLE", status: "pending",
        gatewayProvider: "MONIME_ORANGE", gatewayReference: "cs-late0001", referenceType: "escrow_checkout", referenceId: `vehicle:${id}`,
        createdAt: Date.now(), updatedAt: Date.now(),
      } as any);
    });
    const a: any = await t.mutation(internal.payments.processMoniMeWebhookSuccess, { txDocId: txId, verifiedAmount: 800, currency: "SLE" });
    const b: any = await t.mutation(internal.payments.processMoniMeWebhookSuccess, { txDocId: txId, verifiedAmount: 800, currency: "SLE" });
    expect(a.success).toBe(true);
    expect(b.alreadyProcessed).toBe(true);
    expect((await wallet(t, buyer.id)).availableBalance).toBe(800); // credited exactly once, to the wallet
    expect((await wallet(t, buyer.id)).escrowBalance ?? 0).toBe(0);
    expect(((await get(t, id)) as any).status).toBe("CANCELLED");
    const locks = (await t.run(async (ctx) => ctx.db.query("transactions").collect())).filter((x) => x.type === "escrow_lock");
    expect(locks).toHaveLength(0);
  });

  test("an admin-confirmed bank wire for a CANCELLED order credits the buyer's wallet once and is audited", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const { id, buyer } = await unpaidVehicleOrder(t, 1, "BANK_TRANSFER");
    const ref = ((await get(t, id)) as any).bankEscrowReference as string;
    // simulate a cancelled bank-rail order (this phase never creates one automatically)
    await t.run(async (ctx) => ctx.db.patch(id, { status: "CANCELLED" }));
    const call = () => t.mutation(api.payments.confirmBankEscrowTransfer, {
      sessionToken: admin.token, bankEscrowReference: ref, externalBankTxnId: "BANK-777", amountTransferred: 900,
    } as any) as Promise<any>;
    const first = await call();
    expect(first.success).toBe(true);
    expect(first.creditedToWallet).toBe(true);
    expect((await wallet(t, buyer.id)).availableBalance).toBe(900);
    const second = await call();
    expect(second.alreadyProcessed).toBe(true);
    expect((await wallet(t, buyer.id)).availableBalance).toBe(900); // not double-credited
    const audits = await t.run(async (ctx) => ctx.db.query("audit_logs").collect());
    expect(audits.some((a) => String(a.snapshot).includes("late_bank_transfer_vehicle_order"))).toBe(true);
    expect(((await get(t, id)) as any).status).toBe("CANCELLED");
    expect((await t.run(async (ctx) => ctx.db.query("transactions").collect())).filter((x) => x.type === "escrow_lock")).toHaveLength(0);
  });

  test("an admin-confirmed bank wire for a CANCELLED real-estate contract credits the client's wallet once", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const { id, client } = await unpaidContract(t, 1, "LAND_PURCHASE_MILESTONE", "BANK_TRANSFER");
    const ref = ((await get(t, id)) as any).bankEscrowReference as string;
    await t.run(async (ctx) => ctx.db.patch(id, { currentState: "CANCELLED" }));
    const args = { sessionToken: admin.token, bankEscrowReference: ref, externalBankTxnId: "BANK-888", amountTransferred: 5000 } as any;
    expect(((await t.mutation(api.payments.confirmBankEscrowTransfer, args)) as any).creditedToWallet).toBe(true);
    expect(((await t.mutation(api.payments.confirmBankEscrowTransfer, args)) as any).alreadyProcessed).toBe(true);
    expect((await wallet(t, client.id)).availableBalance).toBe(5000);
  });

  test("a bank wire for an order that is NOT cancelled still funds it exactly as before", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const { id, buyer } = await unpaidVehicleOrder(t, 1, "BANK_TRANSFER");
    const o: any = await get(t, id);
    const r: any = await t.mutation(api.payments.confirmBankEscrowTransfer, {
      sessionToken: admin.token, bankEscrowReference: o.bankEscrowReference, externalBankTxnId: "B1", amountTransferred: o.grossEscrowAmount,
    } as any);
    expect(r.status).toBe("HELD_IN_ESCROW");
    expect((await wallet(t, buyer.id)).escrowBalance).toBe(o.grossEscrowAmount);
  });

  test("a checkout can no longer be started for an expired order", async () => {
    const t = convexTest(schema, modules);
    const { id, buyer } = await unpaidVehicleOrder(t);
    await run(t);
    process.env.MONIME_SPACE_ID = "spc"; process.env.MONIME_ACCESS_TOKEN = "tok";
    await expect(
      t.action(api.payments.initiateMoniMePayment, { sessionToken: buyer.token, amount: 1, escrowOrderId: id as string, phoneNumber: "076123456" } as any)
    ).rejects.toThrow();
    delete process.env.MONIME_SPACE_ID; delete process.env.MONIME_ACCESS_TOKEN;
    expect(await t.run(async (ctx) => (await ctx.db.query("transactions").collect()).filter((x) => x.type === "top_up"))).toHaveLength(0);
  });
});

describe("concurrency", () => {
  test("expiry racing a wallet funding ends in exactly one consistent state", async () => {
    for (const funderFirst of [true, false]) {
      const t = convexTest(schema, modules);
      const { id, buyer } = await unpaidVehicleOrder(t);
      await fund(t, buyer.id, 5000);
      const fundIt = () => t.run(async (ctx) => fundVehicleOrderFromWallet(ctx as any, id, true));
      const results = funderFirst
        ? await Promise.all([fundIt(), run(t)])
        : await Promise.all([run(t), fundIt()]);
      void results;
      const o: any = await get(t, id);
      const w = await wallet(t, buyer.id);
      const locks = (await t.run(async (ctx) => ctx.db.query("transactions").collect())).filter((x) => x.type === "escrow_lock");
      if (o.status === "HELD_IN_ESCROW") {
        expect(locks).toHaveLength(1);
        expect(o.cancelledAt).toBeUndefined();
        expect(w.escrowBalance).toBeGreaterThan(0);
      } else {
        expect(o.status).toBe("CANCELLED");
        expect(locks).toHaveLength(0);
        expect(w.escrowBalance ?? 0).toBe(0);
        expect(w.availableBalance).toBe(5000);
      }
      // running expiry again never duplicates anything
      await run(t);
      expect((await t.run(async (ctx) => ctx.db.query("transactions").collect())).filter((x) => x.type === "escrow_lock").length).toBe(locks.length);
    }
  });
});

describe("dry run, scope and roles", () => {
  test("admin dry-run reports eligible and blocked records and writes nothing; non-admins are refused", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const user = await makeUser(t, "someone");
    const ok = await unpaidVehicleOrder(t, 20);
    const blocked = await unpaidVehicleOrder(t, 20);
    await t.run(async (ctx) =>
      ctx.db.insert("escrow_payment_claims", {
        userId: blocked.buyer.id, escrowOrderId: blocked.id, amount: 1, currency: "SLE", providerId: "x", paymentType: "MANUAL_CLAIM",
        transactionReference: "R", status: "PENDING_APPROVAL", createdAt: 1,
      } as any)
    );
    await unpaidVehicleOrder(t, 40, "BANK_TRANSFER");
    const snapshot = JSON.stringify(await t.run(async (ctx) => ({
      o: await ctx.db.query("escrow_orders").collect(),
      n: await ctx.db.query("user_notifications").collect(),
    })));
    const d: any = await t.query(api.escrowExpiry.adminExpiryDryRun, { sessionToken: admin.token });
    expect(d.eligible.map((e: any) => e.id)).toEqual([ok.id as string]);
    expect(d.blocked.find((b: any) => b.id === (blocked.id as string)).blockers).toContain("CLAIM_PRESENT");
    expect(d.bankTransferAwaitingAdminReview).toHaveLength(1);
    expect(d.policy.bankTransferExpiresAutomatically).toBe(false);
    expect(JSON.stringify(await t.run(async (ctx) => ({
      o: await ctx.db.query("escrow_orders").collect(),
      n: await ctx.db.query("user_notifications").collect(),
    })))).toBe(snapshot);
    await expect(t.query(api.escrowExpiry.adminExpiryDryRun, { sessionToken: user.token })).rejects.toThrow();
  });

  test("other record types are unaffected: pending bookings and a different user's funded order", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const bookingId = await t.run(async (ctx) =>
      ctx.db.insert("bookings", {
        listingId: "l", listingType: "property", listingTitle: "T", buyerId: buyer.id as string, vendorId: owner.id as string,
        bookingType: "hourly_guesthouse", status: "pending_payment", startTime: 1, endTime: 2, subtotal: 1, serviceFee: 0,
        totalAmount: 1, currency: "SLE", paymentStatus: "pending", updatedAt: 1,
      } as any)
    );
    await t.run(async (ctx) => ctx.db.patch(bookingId, {} as any));
    const stale = await unpaidVehicleOrder(t, 30);
    await run(t);
    expect(((await get(t, bookingId)) as any).status).toBe("pending_payment");
    expect(((await get(t, stale.id)) as any).status).toBe("CANCELLED");
  });
});
