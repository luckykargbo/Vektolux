/// <reference types="vite/client" />
// Fee & Commission Engine, end to end: immutable per-order snapshots, admin-only versioned rules,
// changes that affect only NEW orders, scheduling/cancellation, and buyer/owner fees flowing
// correctly through escrow, payouts and refunds.

import { convexTest } from "convex-test";
import { afterEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
const DAY = 24 * 60 * 60 * 1000;
let seq = 0;

afterEach(() => vi.useRealTimers());

async function makeUser(t: T, name: string, role = "client") {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327100${1000 + seq}`, name, role: role as any,
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
const platformRevenue = async (t: T) => {
  const e = await t.run(async (ctx) => ctx.db.query("ledger_entries").collect());
  return Math.round(e.filter((x) => x.accountType === "PLATFORM_REVENUE_REALIZED").reduce((s, x) => s + (x.direction === "CREDIT" ? x.amount : -x.amount), 0) * 100) / 100;
};

const vehicle = (t: T, ownerId: Id<"users">, price: number, pricingType: "per_day" | "total_sale") =>
  t.run(async (ctx) =>
    ctx.db.insert("vehicleListings", {
      ownerId, title: "Car", category: pricingType === "total_sale" ? "car_sale" : "car_rental", price, pricingType, images: [],
      createdAt: Date.now(), location: "Bo", latitude: 0, longitude: 0, geohash: "", status: "AVAILABLE", isPublished: true, updatedAt: Date.now(),
    } as any)
  );
const property = (t: T, ownerId: Id<"users">, category: string, price: number) =>
  t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId, title: "P", description: "d", category, price, currency: "SLE", address: "x", city: "Lumley", country: "Sierra Leone",
      latitude: 0, longitude: 0, geohash: "", imageUrls: [], availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
    } as any)
  );

/** An approved, subscribed agent whom the owner authorised (and who accepted) for this listing. */
async function authorisedAgent(t: T, admin: { token: string }, owner: { token: string }, propertyId: Id<"realEstateListings">) {
  const agent = await makeUser(t, "agent", "agent");
  await t.mutation(api.subscriptions.adminUpsertPlan, {
    sessionToken: admin.token, tierCode: "AGENT_M", name: "Agent Monthly", roleTarget: "agent", basePrice: 100, currency: "SLE",
    billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
  });
  await t.run(async (ctx) => {
    await ctx.db.patch(agent.id, { roleApprovedAt: Date.now() });
    const p = (await ctx.db.query("subscription_plans").collect()).find((x) => x.tierCode === "AGENT_M")!;
    await ctx.db.insert("vendor_subscriptions", {
      userId: agent.id, planId: p._id, tierCode: "AGENT_M", status: "active", startDate: Date.now() - DAY, expiryDate: Date.now() + 30 * DAY,
      amountPaid: 100, currency: "SLE", paymentReference: `sub-${agent.id}`, paymentMethod: "wallet", autoRenew: false, createdAt: Date.now(), updatedAt: Date.now(),
    });
  });
  const inv = await t.mutation(api.listingAgents.authorizeListingAgent, { sessionToken: owner.token, listingType: "property", listingId: propertyId, agentUserId: agent.id });
  await t.mutation(api.listingAgents.respondToListingAgentInvitation, { sessionToken: agent.token, authorizationId: inv.authorizationId as Id<"listing_agent_authorizations">, accept: true });
  return agent;
}

/** A hotel operator who may take bookings: approved role + an ACTIVE paid subscription. */
async function makeEligible(ctx: any, operatorId: Id<"users">) {
  const now = Date.now();
  await ctx.db.patch(operatorId, { role: "hotel_operator", roleApprovedAt: now });
  const planId = await ctx.db.insert("subscription_plans", {
    name: "Hotel", tierCode: `HOTEL_T_${operatorId}`, roleTarget: "hotel_operator", basePrice: 1, currency: "SLE", billingInterval: "monthly",
    intervalDays: 30, discountPercent: 0, isActive: true, features: [], createdAt: now, updatedAt: now,
  });
  await ctx.db.insert("vendor_subscriptions", {
    userId: operatorId, planId, tierCode: `HOTEL_T_${operatorId}`, status: "active", startDate: now - 1000, expiryDate: now + 365 * 24 * 3600 * 1000,
    amountPaid: 1, currency: "SLE", paymentReference: `t-${operatorId}`, paymentMethod: "wallet", autoRenew: false, createdAt: now, updatedAt: now,
  });
}

const setRule = (t: T, admin: { token: string }, vertical: string, r: Partial<Record<string, any>> = {}) =>
  t.mutation(api.feeRules.adminSetFeeRule, {
    sessionToken: admin.token, vertical, ownerFeeBps: 0, buyerFeeBps: 0, agentCommissionBps: 0, agentCommissionPayer: "buyer",
    platformShareOfAgentCommissionBps: 0, note: "test rule change", ...r,
  } as any);

// ─────────────────────────────────────────────────────────────────────
describe("snapshots on every order type", () => {
  test("with no configured rules, every order snapshots the DEFAULT rule and its stored amounts match", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 200_000);

    const rent: any = await t.mutation(api.escrow.initiateEscrowOrder, { sessionToken: buyer.token, orderType: "VEHICLE_RENTAL", vehicleListingId: await vehicle(t, owner.id, 100, "per_day"), numberOfDays: 3, payFromWallet: true });
    const sale: any = await t.mutation(api.escrow.initiateEscrowOrder, { sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: await vehicle(t, owner.id, 10_000, "total_sale"), payFromWallet: true });
    const stay: any = await t.mutation(api.realEstateEscrow.initiateRealEstateEscrow, { sessionToken: buyer.token, contractType: "SHORT_STAY_BOOKING", propertyListingId: await property(t, owner.id, "hourly_guesthouse", 100), nightsCount: 2, paymentRail: "WALLET" } as any);
    const lease: any = await t.mutation(api.realEstateEscrow.initiateRealEstateEscrow, { sessionToken: buyer.token, contractType: "LONG_TERM_LEASE", propertyListingId: await property(t, owner.id, "long_term_rent", 12_000), leaseDurationMonths: 12, paymentRail: "WALLET" } as any);
    const land: any = await t.mutation(api.realEstateEscrow.initiateRealEstateEscrow, { sessionToken: buyer.token, contractType: "LAND_PURCHASE_MILESTONE", propertyListingId: await property(t, owner.id, "sale", 50_000), paymentRail: "WALLET" } as any);
    const pass: any = await t.mutation(api.realEstateEscrow.initiateInspectionPass, { sessionToken: buyer.token, propertyListingId: await property(t, owner.id, "sale", 50_000), scheduledTimestamp: Date.now() + 3600_000, paymentRail: "WALLET" } as any);

    const o1: any = await t.run(async (ctx) => ctx.db.get(rent.escrowOrderId as Id<"escrow_orders">));
    expect(o1.feeSnapshot).toMatchObject({ vertical: "vehicle_rental", ruleSource: "default", ruleVersion: 0, ownerFeeBps: 1500, buyerFeeBps: 0, baseAmount: 300, platformTotal: 45, payeeNet: 255 });
    expect(o1.platformFeeAmount).toBe(o1.feeSnapshot.platformTotal);
    const o2: any = await t.run(async (ctx) => ctx.db.get(sale.escrowOrderId as Id<"escrow_orders">));
    expect(o2.feeSnapshot).toMatchObject({ vertical: "vehicle_sale", ownerFeeBps: 500, platformTotal: 500, payeeNet: 9500, buyerTotal: 10_000 });
    const c1: any = await t.run(async (ctx) => ctx.db.get(stay.contractId as Id<"re_escrow_contracts">));
    expect(c1.feeSnapshot).toMatchObject({ vertical: "re_short_stay", platformTotal: 20, payeeNet: 180 });
    const c2: any = await t.run(async (ctx) => ctx.db.get(lease.contractId as Id<"re_escrow_contracts">));
    // no owner-authorised agent on this listing → no agent commission
    expect(c2.feeSnapshot).toMatchObject({ vertical: "re_lease", agentApplied: false, agentCommissionGross: 0, platformAgentShare: 0, agentCommissionNet: 0, payeeNet: 12_000, buyerTotal: 12_000 });
    const c3: any = await t.run(async (ctx) => ctx.db.get(land.contractId as Id<"re_escrow_contracts">));
    expect(c3.feeSnapshot).toMatchObject({ vertical: "re_land_purchase", platformTotal: 2500, payeeNet: 47_500 });
    const p: any = await t.run(async (ctx) => ctx.db.get(pass.passId as Id<"re_inspection_passes">));
    expect(p.feeSnapshot).toMatchObject({ vertical: "re_viewing_pass", platformTotal: 7.5, payeeNet: 42.5, buyerTotal: 50 });
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("admin rules: admin-only, validated, versioned, audited", () => {
  test("only an admin can change fees; every change is validated and audited; versions increase", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const user = await makeUser(t, "user");
    await expect(setRule(t, user, "vehicle_sale", { ownerFeeBps: 100 })).rejects.toThrow();
    await expect(setRule(t, admin, "vehicle_sale", { ownerFeeBps: 5001 })).rejects.toThrow(/basis points/);
    await expect(setRule(t, admin, "vehicle_sale", { ownerFeeBps: 12.5 })).rejects.toThrow(/basis points/);
    await expect(setRule(t, admin, "vehicle_sale", { ownerFeeBps: -1 })).rejects.toThrow(/basis points/);
    await expect(setRule(t, admin, "vehicle_sale", { agentCommissionBps: 100 })).rejects.toThrow(/agent commissions/);
    await expect(setRule(t, admin, "vehicle_sale", { ownerFeeBps: 100, note: "x" })).rejects.toThrow(/note/);
    await expect(setRule(t, admin, "vehicle_sale", { ownerFeeBps: 100, effectiveFrom: Date.now() - DAY })).rejects.toThrow(/backdated/);

    const r1: any = await setRule(t, admin, "vehicle_sale", { ownerFeeBps: 600 });
    const r2: any = await setRule(t, admin, "vehicle_sale", { ownerFeeBps: 700 });
    expect([r1.version, r2.version]).toEqual([1, 2]);
    const logs = await t.run(async (ctx) => ctx.db.query("audit_logs").collect());
    const changes = logs.filter((l) => l.action === "FEE_RULE_CHANGED");
    expect(changes).toHaveLength(2);
    expect(JSON.parse(changes[0].snapshot).previous).toMatchObject({ ownerFeeBps: 500, source: "default" });
    expect(JSON.parse(changes[1].snapshot).next).toMatchObject({ ownerFeeBps: 700 });

    const list: any = await t.query(api.feeRules.adminListFeeRules, { sessionToken: admin.token });
    const vs = list.verticals.find((x: any) => x.vertical === "vehicle_sale");
    expect(vs.current).toMatchObject({ ownerFeeBps: 700, version: 2, source: "configured" });
    expect(vs.defaults.ownerFeeBps).toBe(500);
    await expect(t.query(api.feeRules.adminListFeeRules, { sessionToken: user.token })).rejects.toThrow();
  });

  test("a scheduled rule applies only from its effective time and can be cancelled only before then", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const T0 = Date.UTC(2026, 10, 1);
    vi.setSystemTime(new Date(T0));
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 100_000);
    const car = await vehicle(t, owner.id, 10_000, "total_sale");
    const buy = async () => (await t.mutation(api.escrow.initiateEscrowOrder, { sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: car, payFromWallet: true })) as any;

    const future: any = await setRule(t, admin, "vehicle_sale", { ownerFeeBps: 1000, effectiveFrom: T0 + 2 * DAY });
    expect((await buy()).platformFeeAmount).toBe(500); // still the default 5%
    vi.setSystemTime(new Date(T0 + 2 * DAY));
    expect((await buy()).platformFeeAmount).toBe(1000); // now 10%
    await expect(
      t.mutation(api.feeRules.adminCancelScheduledFeeRule, { sessionToken: admin.token, ruleId: future.ruleId, reason: "too late now" })
    ).rejects.toThrow(/already in effect/);

    const later: any = await setRule(t, admin, "vehicle_sale", { ownerFeeBps: 200, effectiveFrom: T0 + 5 * DAY });
    await t.mutation(api.feeRules.adminCancelScheduledFeeRule, { sessionToken: admin.token, ruleId: later.ruleId, reason: "changed our mind" });
    vi.setSystemTime(new Date(T0 + 6 * DAY));
    expect((await buy()).platformFeeAmount).toBe(1000); // the cancelled rule never applied
    const logs = await t.run(async (ctx) => ctx.db.query("audit_logs").collect());
    expect(logs.some((l) => l.action === "FEE_RULE_CANCELLED")).toBe(true);

    // what the admin Fees & Commissions page shows
    await expect(t.query(api.feeRules.adminListFeeRules, { sessionToken: owner.token })).rejects.toThrow(/administrator/i);
    const list: any = await t.query(api.feeRules.adminListFeeRules, { sessionToken: admin.token });
    const vs = list.verticals.find((x: any) => x.vertical === "vehicle_sale");
    expect(vs.current).toMatchObject({ source: "configured", version: 1, ownerFeeBps: 1000 });
    expect(vs.example).toMatchObject({ buyerTotal: 1000, payeeNet: 900, platformTotal: 100 });
    const v2 = vs.history.find((r: any) => r.version === 2);
    expect(v2).toMatchObject({ status: "cancelled", cancelReason: "changed our mind", createdByName: "admin", cancelledByName: "admin", inEffect: false });
    expect(vs.history.find((r: any) => r.version === 1).inEffect).toBe(true);
    expect(list.audit.map((a: any) => [a.action, a.version])).toEqual([
      ["FEE_RULE_CANCELLED", 2], ["FEE_RULE_CHANGED", 2], ["FEE_RULE_CHANGED", 1],
    ]);
    expect(list.audit[2]).toMatchObject({ adminName: "admin", vertical: "vehicle_sale", next: { ownerFeeBps: 1000 }, previous: { ownerFeeBps: 500 } });
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("changes affect only new orders; existing orders follow their snapshot", () => {
  test("an order priced at 5% still pays out at 5% after the admin raises the fee to 8% + a 2% buyer fee", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const seller = await makeUser(t, "seller");
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 100_000);
    const car = await vehicle(t, seller.id, 10_000, "total_sale");
    const before: any = await t.mutation(api.escrow.initiateEscrowOrder, { sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: car, payFromWallet: true });
    const snapBefore = (await t.run(async (ctx) => ctx.db.get(before.escrowOrderId as Id<"escrow_orders">)))!.feeSnapshot;

    await setRule(t, admin, "vehicle_sale", { ownerFeeBps: 800, buyerFeeBps: 200 });
    const after: any = await t.mutation(api.escrow.initiateEscrowOrder, { sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: car, payFromWallet: true });
    expect(after.grossEscrowAmount).toBe(10_200); // buyer pays price + 2%
    expect(after.buyerFeeAmount).toBe(200);
    expect(after.netMerchantExpected).toBe(9_200); // seller keeps 92%

    // the old order's snapshot did not change
    const snapAfter = (await t.run(async (ctx) => ctx.db.get(before.escrowOrderId as Id<"escrow_orders">)))!.feeSnapshot;
    expect(snapAfter).toEqual(snapBefore);

    await t.mutation(api.escrow.releaseDealEscrowFunds, { sessionToken: buyer.token, escrowOrderId: before.escrowOrderId });
    expect((await wallet(t, seller.id)).availableBalance).toBe(9_500); // old terms
    await t.mutation(api.escrow.releaseDealEscrowFunds, { sessionToken: buyer.token, escrowOrderId: after.escrowOrderId });
    expect((await wallet(t, seller.id)).availableBalance).toBe(9_500 + 9_200); // new terms
    expect(await platformRevenue(t)).toBe(500 + 1_000); // 5% ; 8% + 2%
    const bw = await wallet(t, buyer.id);
    expect(bw.escrowBalance).toBe(0);
    expect(bw.availableBalance).toBe(100_000 - 10_000 - 10_200);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("buyer and owner fees through payouts and refunds", () => {
  test("a full refund returns the buyer's fee too", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const seller = await makeUser(t, "seller");
    const buyer = await makeUser(t, "buyer");
    await fund(t, buyer.id, 50_000);
    await setRule(t, admin, "vehicle_sale", { ownerFeeBps: 500, buyerFeeBps: 500 });
    const o: any = await t.mutation(api.escrow.initiateEscrowOrder, { sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: await vehicle(t, seller.id, 10_000, "total_sale"), payFromWallet: true });
    expect(o.grossEscrowAmount).toBe(10_500);
    await t.mutation(api.escrow.raiseEscrowDispute, { sessionToken: buyer.token, escrowOrderId: o.escrowOrderId, reason: "x", claimedRepairCost: 0, evidenceMediaUrls: [] });
    await t.mutation(api.escrow.adminResolveEscrowDispute, { sessionToken: admin.token, escrowOrderId: o.escrowOrderId, resolution: "refund_buyer", notes: "seller withdrew" });
    const bw = await wallet(t, buyer.id);
    expect(bw.availableBalance).toBe(50_000);
    expect(bw.escrowBalance).toBe(0);
    expect(await platformRevenue(t)).toBe(0);
  });

  test("vehicle rental with a buyer fee: 60/40 releases plus deposit refund leave escrow at exactly zero", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const renter = await makeUser(t, "renter");
    await fund(t, renter.id, 5_000);
    await setRule(t, admin, "vehicle_rental", { ownerFeeBps: 1500, buyerFeeBps: 300 });
    const o: any = await t.mutation(api.escrow.initiateEscrowOrder, { sessionToken: renter.token, orderType: "VEHICLE_RENTAL", vehicleListingId: await vehicle(t, owner.id, 100, "per_day"), numberOfDays: 3, payFromWallet: true });
    expect(o.grossEscrowAmount).toBe(809); // 300 + 9 buyer fee + 500 deposit
    await t.mutation(api.escrow.completeVehicleInspection, {
      sessionToken: owner.token, escrowOrderId: o.escrowOrderId, inspectionType: "PRE_TRIP_RENTAL", odometerReadingKm: 1, fuelTankPercentage: 50,
      photoFrontUrl: "a", photoRearUrl: "a", photoLeftSideUrl: "a", photoRightSideUrl: "a", photoInteriorUrl: "a", photoDashboardOdometerUrl: "a", qrTokenHash: "q",
    } as any);
    await t.mutation(api.escrow.releaseMilestoneHandoff60, { sessionToken: renter.token, escrowOrderId: o.escrowOrderId });
    await t.mutation(api.escrow.settleVehicleReturn, { sessionToken: owner.token, escrowOrderId: o.escrowOrderId });
    expect((await wallet(t, owner.id)).availableBalance).toBe(255); // 300 - 15%
    expect(await platformRevenue(t)).toBe(54); // 45 owner fee + 9 buyer fee
    const rw = await wallet(t, renter.id);
    expect(rw.escrowBalance).toBe(0);
    expect(rw.availableBalance).toBe(5_000 - 809 + 500);
  });

  test("lease with owner + buyer fees and commission paid by the OWNER: every leone accounted for", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const landlord = await makeUser(t, "landlord");
    const tenant = await makeUser(t, "tenant");
    await fund(t, tenant.id, 50_000);
    await setRule(t, admin, "re_lease", { ownerFeeBps: 200, buyerFeeBps: 100, agentCommissionBps: 1000, agentCommissionPayer: "owner", platformShareOfAgentCommissionBps: 1500 });
    const propertyId = await property(t, landlord.id, "long_term_rent", 12_000);
    const agent = await authorisedAgent(t, admin, landlord, propertyId);
    const c: any = await t.mutation(api.realEstateEscrow.initiateRealEstateEscrow, { sessionToken: tenant.token, contractType: "LONG_TERM_LEASE", propertyListingId: propertyId, leaseDurationMonths: 12, paymentRail: "WALLET" } as any);
    // base 12,000; buyer fee 120; owner fee 240; commission 1,200 deducted from the owner (platform 180, agent 1,020)
    expect(c.grossEscrowAmount).toBe(12_000 + 120 + 1_000); // + caution 1,000
    await t.mutation(api.realEstateEscrow.checkInShortStay, { sessionToken: tenant.token, contractId: c.contractId });
    await t.run(async (ctx) => ctx.db.patch(c.contractId as Id<"re_escrow_contracts">, { stay24hAutoReleaseTimestamp: Date.now() - 1 }));
    await t.mutation(api.realEstateEscrow.releaseShortStayPayout24h, { sessionToken: tenant.token, contractId: c.contractId });
    await t.mutation(api.realEstateEscrow.refundCautionDeposit, { sessionToken: landlord.token, contractId: c.contractId, inspectionPassedClean: true });
    // landlord: 12,000 - 240 owner fee - 1,200 commission; the owner-authorised agent: 1,020
    expect((await wallet(t, landlord.id)).availableBalance).toBe(12_000 - 240 - 1_200);
    expect((await wallet(t, agent.id)).availableBalance).toBe(1_020);
    expect(await platformRevenue(t)).toBe(240 + 120 + 180);
    const tw = await wallet(t, tenant.id);
    expect(tw.escrowBalance).toBe(0);
    expect(tw.availableBalance).toBe(50_000 - 12_120);
  });

  test("hotel booking with a buyer fee: the guest's total is held; the platform keeps commission + buyer fee", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const operator = await makeUser(t, "operator", "hotel_operator");
    const guest = await makeUser(t, "guest");
    await fund(t, guest.id, 5_000);
    await setRule(t, admin, "hotel_booking", { ownerFeeBps: 1000, buyerFeeBps: 500 });
    const { hotelId, roomId } = await t.run(async (ctx) => {
      await makeEligible(ctx, operator.id);
      const hotelId = await ctx.db.insert("hotel_profiles", {
        userId: operator.id, businessName: "H", operationalType: "hotel", isVerified: true, verificationStatus: "verified", address: "a", city: "Freetown",
        phone: "+23276000000", amenities: [], mediaUrls: [], description: "d", supportsHourlyStays: false, updatedAt: Date.now(),
      } as any);
      const roomId = await ctx.db.insert("hotel_rooms", {
        hotelId, name: "R", roomType: "Standard", pricePerNight: 1000, supportsHourly: false, capacityGuests: 2, bedConfiguration: "1",
        amenities: [], images: [], isAvailable: true, totalRoomUnits: 1, createdAt: Date.now(), updatedAt: Date.now(),
      } as any);
      return { hotelId, roomId };
    });
    const res: any = await t.mutation(api.hotelBookings.createBookingWithEscrow, {
      sessionToken: guest.token, hotelId, roomId, guestName: "G", guestPhone: "+23276111111", bookingCategory: "nightly",
      checkInTimestamp: Date.now() + DAY, checkOutTimestamp: Date.now() + 2 * DAY, numberOfGuests: 1, numberOfNights: 1,
    });
    expect(res.subtotalAmount).toBe(1000);
    expect(res.guestTotalAmount).toBe(1050);
    expect((await wallet(t, guest.id)).escrowBalance).toBe(1050);
    await t.mutation(api.hotelBookings.confirmCheckIn, { sessionToken: guest.token, bookingId: res.bookingId });
    await t.mutation(api.hotelBookings.releaseEscrowPayout, { sessionToken: guest.token, bookingId: res.bookingId });
    expect((await wallet(t, operator.id)).availableBalance).toBe(900);
    expect(await platformRevenue(t)).toBe(150);
    expect((await wallet(t, guest.id)).escrowBalance).toBe(0);
  });
});
