/// <reference types="vite/client" />
// Vehicle escrow: server-side pricing, real funding (wallet / verified Monime / admin-confirmed bank),
// staged releases through the wallet core, no double payouts, admin dispute resolution.

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;

async function makeUser(t: T, name: string, role = "client") {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327400${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(),
    })
  );
  return { id, token };
}
const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });
const wallet = async (t: T, userId: Id<"users">) =>
  (await t.run(async (ctx) => (await ctx.db.query("walletBalances").collect()).find((w) => w.userId === userId))) ??
  ({ availableBalance: 0, escrowBalance: 0, pendingBalance: 0 } as { availableBalance: number; escrowBalance?: number; pendingBalance: number });

async function makeVehicle(t: T, ownerId: Id<"users">, price: number, pricingType: "per_day" | "total_sale") {
  return t.run(async (ctx) =>
    ctx.db.insert("vehicleListings", {
      ownerId, title: "Toyota Hilux", category: pricingType === "total_sale" ? "car_sale" : "car_rental", price, pricingType, images: [],
      createdAt: Date.now(), location: "Bo", latitude: 0, longitude: 0, geohash: "", status: "AVAILABLE", isPublished: true, updatedAt: Date.now(),
    } as any)
  );
}
const order = (t: T, id: any) => t.run(async (ctx) => ctx.db.get(id as Id<"escrow_orders">));
const initiate = (t: T, buyer: { token: string }, vehicleId: any, extra: Record<string, unknown> = {}) =>
  t.mutation(api.escrow.initiateEscrowOrder, {
    sessionToken: buyer.token, orderType: "VEHICLE_RENTAL", vehicleListingId: vehicleId, numberOfDays: 3, payFromWallet: true, ...extra,
  } as any);
const preTrip = (t: T, who: { token: string }, orderId: any) =>
  t.mutation(api.escrow.completeVehicleInspection, {
    sessionToken: who.token, escrowOrderId: orderId, inspectionType: "PRE_TRIP_RENTAL", odometerReadingKm: 1, fuelTankPercentage: 50,
    photoFrontUrl: "a", photoRearUrl: "a", photoLeftSideUrl: "a", photoRightSideUrl: "a", photoInteriorUrl: "a", photoDashboardOdometerUrl: "a", qrTokenHash: "q",
  } as any);

describe("funding & pricing", () => {
  test("the server prices the order; client amounts are ignored", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 5000);
    const v = await makeVehicle(t, owner.id, 100, "per_day");
    const r: any = await initiate(t, buyer, v, { baseRentalAmount: 1, refundableDepositAmount: 1, fullPurchaseAmount: 1 });
    expect(r.grossEscrowAmount).toBe(800); // 3 x 100 + deposit max(500, 99)
    expect(r.platformFeeAmount).toBe(45);
    expect(r.netMerchantExpected).toBe(255);
    expect(r.status).toBe("HELD_IN_ESCROW");
    const w = await wallet(t, buyer.id);
    expect(w.availableBalance).toBe(4200);
    expect(w.escrowBalance).toBe(800);
  });

  test("insufficient wallet funds: nothing is created and no balance moves", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 100);
    const v = await makeVehicle(t, owner.id, 100, "per_day");
    await expect(initiate(t, buyer, v)).rejects.toThrow(/INSUFFICIENT_FUNDS/);
    expect(await t.run(async (ctx) => ctx.db.query("escrow_orders").collect())).toHaveLength(0);
    expect((await wallet(t, buyer.id)).availableBalance).toBe(100);
  });

  test("a mobile-money order stays PENDING_PAYMENT and nothing can be released from it", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const v = await makeVehicle(t, owner.id, 100, "per_day");
    const r: any = await initiate(t, buyer, v, { payFromWallet: false, paymentRail: "MOBILE_MONEY" });
    expect(r.status).toBe("PENDING_PAYMENT");
    await expect(t.mutation(api.escrow.releaseMilestoneHandoff60, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId })).rejects.toThrow();
    expect((await wallet(t, buyer.id)).escrowBalance ?? 0).toBe(0);
  });

  test("rent/sale mismatch is refused (cannot buy a per-day rental for the daily price)", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 5000);
    const rental = await makeVehicle(t, owner.id, 100, "per_day");
    await expect(initiate(t, buyer, rental, { orderType: "VEHICLE_PURCHASE" })).rejects.toThrow(/for rent/);
    const forSale = await makeVehicle(t, owner.id, 1000, "total_sale");
    await expect(initiate(t, buyer, forSale)).rejects.toThrow(/for sale/);
  });
});

describe("rental lifecycle", () => {
  test("handoff 60% then return 40% + deposit: exact balances, escrow back to zero, fee booked once", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 5000);
    const v = await makeVehicle(t, owner.id, 100, "per_day");
    const r: any = await initiate(t, buyer, v);
    await preTrip(t, owner, r.escrowOrderId);

    const a: any = await t.mutation(api.escrow.releaseMilestoneHandoff60, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId });
    expect(a.payoutToOwner60).toBe(153);
    expect((await wallet(t, owner.id)).availableBalance).toBe(153);
    // a second release of the same stage is refused
    await expect(t.mutation(api.escrow.releaseMilestoneHandoff60, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId })).rejects.toThrow();
    // releaseDealEscrowFunds must not pay a rental again (it used to)
    await expect(t.mutation(api.escrow.releaseDealEscrowFunds, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId })).rejects.toThrow(/purchases/);

    // The owner's damage claim does NOT pay the owner: it opens a dispute and the deposit stays held.
    const s: any = await t.mutation(api.escrow.settleVehicleReturn, { sessionToken: owner.token, escrowOrderId: r.escrowOrderId, damageDeductionCost: 100 });
    expect(s.status).toBe("DISPUTED");
    expect(s.damageDeducted).toBe(0);
    expect((await wallet(t, owner.id)).availableBalance).toBe(153);
    expect((await wallet(t, buyer.id)).escrowBalance).toBe(800 - 153 - 27);
    // An administrator decides: release the remaining 40% and award 100 of the 500 deposit.
    const admin = await makeUser(t, "admin", "admin");
    await expect(
      t.mutation(api.escrow.adminResolveEscrowDispute, { sessionToken: owner.token, escrowOrderId: r.escrowOrderId, resolution: "release_seller", notes: "award damage", damageAwardToOwner: 100 })
    ).rejects.toThrow(/administrator/i);
    await t.mutation(api.escrow.adminResolveEscrowDispute, {
      sessionToken: admin.token, escrowOrderId: r.escrowOrderId, resolution: "release_seller", notes: "photos confirm a dented door", damageAwardToOwner: 100,
    });
    expect((await wallet(t, owner.id)).availableBalance).toBe(153 + 102 + 100);
    const bw = await wallet(t, buyer.id);
    expect(bw.escrowBalance).toBe(0);
    expect(bw.availableBalance).toBe(5000 - 800 + 400);
    // can't settle twice
    await expect(t.mutation(api.escrow.settleVehicleReturn, { sessionToken: owner.token, escrowOrderId: r.escrowOrderId })).rejects.toThrow();

    const entries = await t.run(async (ctx) => ctx.db.query("ledger_entries").collect());
    const platform = entries.filter((e) => e.accountType === "PLATFORM_REVENUE_REALIZED").reduce((x, e) => x + e.amount, 0);
    expect(Math.round(platform * 100) / 100).toBe(45);
  });

  test("the buyer cannot set their own damage deduction; only the owner/admin settles", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const other = await makeUser(t, "other");
    await fund(t, buyer.id, 5000);
    const v = await makeVehicle(t, owner.id, 100, "per_day");
    const r: any = await initiate(t, buyer, v);
    await preTrip(t, owner, r.escrowOrderId);
    await t.mutation(api.escrow.releaseMilestoneHandoff60, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId });
    await expect(t.mutation(api.escrow.settleVehicleReturn, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId })).rejects.toThrow();
    await expect(t.mutation(api.escrow.settleVehicleReturn, { sessionToken: other.token, escrowOrderId: r.escrowOrderId })).rejects.toThrow();
  });
});

describe("purchase lifecycle", () => {
  async function purchase(t: T) {
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const admin = await makeUser(t, "admin", "admin");
    await fund(t, buyer.id, 20000);
    const v = await makeVehicle(t, owner.id, 10000, "total_sale");
    const r: any = await initiate(t, buyer, v, { orderType: "VEHICLE_PURCHASE" });
    return { owner, buyer, admin, r };
  }

  test("buyer approval pays the seller net once; replays and the SLRSA path cannot pay again", async () => {
    const t = convexTest(schema, modules);
    const { owner, buyer, admin, r } = await purchase(t);
    expect(r.grossEscrowAmount).toBe(10000);
    await t.mutation(api.escrow.releaseDealEscrowFunds, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId });
    expect((await wallet(t, owner.id)).availableBalance).toBe(9500);
    expect((await wallet(t, buyer.id)).escrowBalance).toBe(0);
    await expect(t.mutation(api.escrow.releaseDealEscrowFunds, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId })).rejects.toThrow();
    await expect(t.mutation(api.escrow.confirmSlrsaTransfer, { sessionToken: admin.token, escrowOrderId: r.escrowOrderId })).rejects.toThrow();
    expect((await wallet(t, owner.id)).availableBalance).toBe(9500);
  });

  test("a stranger can neither release nor dispute someone else's order", async () => {
    const t = convexTest(schema, modules);
    const { r } = await purchase(t);
    const stranger = await makeUser(t, "stranger");
    await expect(t.mutation(api.escrow.releaseDealEscrowFunds, { sessionToken: stranger.token, escrowOrderId: r.escrowOrderId })).rejects.toThrow();
    await expect(
      t.mutation(api.escrow.raiseEscrowDispute, { sessionToken: stranger.token, escrowOrderId: r.escrowOrderId, reason: "x", claimedRepairCost: 1, evidenceMediaUrls: [] })
    ).rejects.toThrow(/not a party/);
  });

  test("dispute freezes the order; only an admin resolves it, and a refund returns the full amount", async () => {
    const t = convexTest(schema, modules);
    const { owner, buyer, admin, r } = await purchase(t);
    await t.mutation(api.escrow.raiseEscrowDispute, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId, reason: "bad car", claimedRepairCost: 0, evidenceMediaUrls: [] });
    await expect(t.mutation(api.escrow.releaseDealEscrowFunds, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId })).rejects.toThrow();
    await expect(
      t.mutation(api.escrow.adminResolveEscrowDispute, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId, resolution: "refund_buyer", notes: "refund me" })
    ).rejects.toThrow();
    await t.mutation(api.escrow.adminResolveEscrowDispute, { sessionToken: admin.token, escrowOrderId: r.escrowOrderId, resolution: "refund_buyer", notes: "seller misrepresented" });
    const bw = await wallet(t, buyer.id);
    expect(bw.availableBalance).toBe(20000);
    expect(bw.escrowBalance).toBe(0);
    expect((await wallet(t, owner.id)).availableBalance).toBe(0);
    expect((await order(t, r.escrowOrderId))?.status).toBe("REFUNDED");
  });
});

describe("direct provider & bank funding", () => {
  const sessions = new Map<string, any>();
  beforeEach(() => {
    sessions.clear();
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
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    delete process.env.MONIME_SPACE_ID;
    delete process.env.MONIME_ACCESS_TOKEN;
    delete process.env.MONIME_API_BASE_URL;
  });

  test("Model B: the server quotes the escrow amount; Monime-confirmed payment funds escrow without a top-up", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const v = await makeVehicle(t, owner.id, 100, "per_day");
    const r: any = await initiate(t, buyer, v, { payFromWallet: false, paymentRail: "MOBILE_MONEY" });
    expect(r.status).toBe("PENDING_PAYMENT");

    await t.action(api.payments.initiateMoniMePayment, { sessionToken: buyer.token, amount: 1, escrowOrderId: r.escrowOrderId, phoneNumber: "076123456" });
    const [sid] = [...sessions.keys()];
    expect(sessions.get(sid).lineItems.data[0].price.value).toBe(80000); // 800.00 SLE, not the client's "1"

    await t.action(internal.payments.settleMoniMeReference, { reference: sid });
    expect((await order(t, r.escrowOrderId))?.status).toBe("PENDING_PAYMENT"); // not paid yet
    sessions.get(sid).status = "completed";
    await t.action(internal.payments.settleMoniMeReference, { reference: sid });
    await t.action(internal.payments.settleMoniMeReference, { reference: sid }); // replay
    expect((await order(t, r.escrowOrderId))?.status).toBe("HELD_IN_ESCROW");
    const w = await wallet(t, buyer.id);
    expect(w.escrowBalance).toBe(800);
    expect(w.availableBalance).toBe(0);
  });

  test("a stranger cannot start (or quote) a checkout for someone else's order", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const stranger = await makeUser(t, "stranger");
    const v = await makeVehicle(t, owner.id, 100, "per_day");
    const r: any = await initiate(t, buyer, v, { payFromWallet: false, paymentRail: "MOBILE_MONEY" });
    await expect(
      t.action(api.payments.initiateMoniMePayment, { sessionToken: stranger.token, amount: 1, escrowOrderId: r.escrowOrderId, phoneNumber: "076123456" })
    ).rejects.toThrow(/not found/i);
    expect(sessions.size).toBe(0);
  });

  test("bank transfer: admin-only, exact amount, funds escrow once", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const admin = await makeUser(t, "admin", "admin");
    const v = await makeVehicle(t, owner.id, 100, "per_day");
    const r: any = await initiate(t, buyer, v, { payFromWallet: false, paymentRail: "BANK_TRANSFER", bankEscrowReference: "VKTLX-DEAL-1234" });
    expect(r.status).toBe("PENDING_PAYMENT");

    await expect(t.mutation(api.payments.confirmBankEscrowTransfer, { sessionToken: buyer.token, bankEscrowReference: "VKTLX-DEAL-1234", amountTransferred: 800 })).rejects.toThrow();
    await expect(t.mutation(api.payments.confirmBankEscrowTransfer, { sessionToken: admin.token, bankEscrowReference: "VKTLX-DEAL-1234", amountTransferred: 100 })).rejects.toThrow(/AMOUNT_MISMATCH/);
    await t.mutation(api.payments.confirmBankEscrowTransfer, { sessionToken: admin.token, bankEscrowReference: "VKTLX-DEAL-1234", amountTransferred: 800, externalBankTxnId: "B1" });
    const again: any = await t.mutation(api.payments.confirmBankEscrowTransfer, { sessionToken: admin.token, bankEscrowReference: "VKTLX-DEAL-1234", amountTransferred: 800, externalBankTxnId: "B1" });
    expect(again.alreadyProcessed).toBe(true);
    const w = await wallet(t, buyer.id);
    expect(w.escrowBalance).toBe(800);
    expect((await order(t, r.escrowOrderId))?.status).toBe("HELD_IN_ESCROW");
    // the money then flows through the normal releases
    await preTrip(t, owner, r.escrowOrderId);
    await t.mutation(api.escrow.releaseMilestoneHandoff60, { sessionToken: buyer.token, escrowOrderId: r.escrowOrderId });
    expect((await wallet(t, owner.id)).availableBalance).toBe(153);
  });
});
