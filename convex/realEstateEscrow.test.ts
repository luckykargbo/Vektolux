/// <reference types="vite/client" />
// Property escrow: server-side pricing, real funding, staged releases through the wallet core,
// OTP brute-force protection, no double payouts, and no leakage of the owner's contact/address.

import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
let seq = 0;
const SECRET_STREET = "17 Hidden Close";
const SECRET_PHONE = "+23277555999";

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}) {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327300${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    })
  );
  return { id, token };
}
const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });
const wallet = async (t: T, userId: Id<"users">) =>
  (await t.run(async (ctx) => (await ctx.db.query("walletBalances").collect()).find((w) => w.userId === userId))) ??
  ({ availableBalance: 0, escrowBalance: 0, pendingBalance: 0 } as { availableBalance: number; escrowBalance?: number; pendingBalance: number });

async function makeProperty(t: T, ownerId: Id<"users">, category: "sale" | "long_term_rent" | "hourly_guesthouse", price: number) {
  return t.run(async (ctx) =>
    ctx.db.insert("realEstateListings", {
      ownerId, title: "Test property", description: "d", category, price, currency: "SLE",
      address: SECRET_STREET, city: "Lumley", district: "Western Area Urban", country: "Sierra Leone",
      latitude: 8.4, longitude: -13.2, geohash: "abc", imageUrls: [], privateContactPhone: SECRET_PHONE,
      availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
    } as any)
  );
}
const contract = (t: T, id: any) => t.run(async (ctx) => ctx.db.get(id as Id<"re_escrow_contracts">));
const pass = (t: T, id: any) => t.run(async (ctx) => ctx.db.get(id as Id<"re_inspection_passes">));
const initContract = (t: T, client: { token: string }, propertyId: any, contractType: string, extra: Record<string, unknown> = {}) =>
  t.mutation(api.realEstateEscrow.initiateRealEstateEscrow, {
    sessionToken: client.token, contractType: contractType as any, propertyListingId: propertyId, paymentRail: "WALLET", ...extra,
  } as any);
const platformTotal = async (t: T) => {
  const entries = await t.run(async (ctx) => ctx.db.query("ledger_entries").collect());
  const sum = entries.filter((e) => e.accountType === "PLATFORM_REVENUE_REALIZED").reduce((x, e) => x + e.amount, 0);
  return Math.round(sum * 100) / 100;
};

// ─────────────────────────────────────────────────────────────────────
describe("inspection pass", () => {
  async function setup(t: T) {
    const owner = await makeUser(t, "owner");
    const client = await makeUser(t, "client");
    const propertyId = await makeProperty(t, owner.id, "sale", 50000);
    await fund(t, client.id, 500);
    const book = (extra: Record<string, unknown> = {}) =>
      t.mutation(api.realEstateEscrow.initiateInspectionPass, {
        sessionToken: client.token, propertyListingId: propertyId, scheduledTimestamp: Date.now() + 3600_000, paymentRail: "WALLET", ...extra,
      } as any);
    return { owner, client, propertyId, book };
  }

  test("the fee is one of the server tiers and is really held; the response has no contact details", async () => {
    const t = convexTest(schema, modules);
    const { client, book } = await setup(t);
    const r: any = await book({ tourFee: 0.01 });
    expect(r.tourFee).toBe(50); // an arbitrary client fee is replaced by the default tier
    expect(r.status).toBe("FUNDS_LOCKED");
    expect(r.qrHash).toMatch(/^VK-TOUR-[0-9a-f]{24}$/);
    expect(r.otpCode).toMatch(/^\d{4}$/);
    const w = await wallet(t, client.id);
    expect(w.availableBalance).toBe(450);
    expect(w.escrowBalance).toBe(50);
    const json = JSON.stringify(r);
    expect(json).not.toContain(SECRET_PHONE);
    expect(json).not.toContain(SECRET_STREET);
    expect(r.maskedNeighborhood).toContain("Inside");
  });

  test("insufficient funds creates nothing (no free pass, no minted payout)", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const poor = await makeUser(t, "poor");
    const propertyId = await makeProperty(t, owner.id, "sale", 50000);
    await expect(
      t.mutation(api.realEstateEscrow.initiateInspectionPass, { sessionToken: poor.token, propertyListingId: propertyId, scheduledTimestamp: Date.now() + 3600_000, paymentRail: "WALLET" } as any)
    ).rejects.toThrow(/INSUFFICIENT_FUNDS/);
    expect(await t.run(async (ctx) => ctx.db.query("re_inspection_passes").collect())).toHaveLength(0);
  });

  test("an unpaid (mobile-money) pass cannot be verified", async () => {
    const t = convexTest(schema, modules);
    const { owner, book } = await setup(t);
    const r: any = await book({ paymentRail: "orange" });
    expect(r.status).toBe("CREATED");
    const v: any = await t.mutation(api.realEstateEscrow.verifyInspectionPass, { sessionToken: owner.token, passId: r.passId, enteredOtp: r.otpCode });
    expect(v.success).toBe(false);
    expect(v.errorCode).toBe("PASS_NOT_FUNDED");
  });

  test("the agent verifies with the OTP: 85/15 split, no owner phone/address returned, no second payout", async () => {
    const t = convexTest(schema, modules);
    const { owner, client, book } = await setup(t);
    const r: any = await book();
    // the client cannot verify their own pass; strangers cannot either
    await expect(t.mutation(api.realEstateEscrow.verifyInspectionPass, { sessionToken: client.token, passId: r.passId, enteredOtp: r.otpCode })).rejects.toThrow();
    const v: any = await t.mutation(api.realEstateEscrow.verifyInspectionPass, { sessionToken: owner.token, passId: r.passId, enteredOtp: r.otpCode });
    expect(v.success).toBe(true);
    expect(v.agentNetPaid).toBe(42.5);
    const json = JSON.stringify(v);
    expect(json).not.toContain(SECRET_PHONE);
    expect(json).not.toContain(SECRET_STREET);
    expect(json).not.toMatch(/unmasked/i);
    expect((await wallet(t, owner.id)).availableBalance).toBe(42.5);
    expect((await wallet(t, client.id)).escrowBalance).toBe(0);
    expect(await platformTotal(t)).toBe(7.5);
    await expect(t.mutation(api.realEstateEscrow.verifyInspectionPass, { sessionToken: owner.token, passId: r.passId, enteredOtp: r.otpCode })).rejects.toThrow(/already/);
    expect((await wallet(t, owner.id)).availableBalance).toBe(42.5);
  });

  test("wrong codes are counted (and the count survives); five failures lock the pass", async () => {
    const t = convexTest(schema, modules);
    const { owner, book } = await setup(t);
    const r: any = await book();
    const wrong = r.otpCode === "0000" ? "1111" : "0000";
    for (let i = 0; i < 5; i++) {
      const v: any = await t.mutation(api.realEstateEscrow.verifyInspectionPass, { sessionToken: owner.token, passId: r.passId, enteredOtp: wrong });
      expect(v.success).toBe(false);
    }
    expect(((await pass(t, r.passId)) as any).failedAttempts).toBe(5);
    const locked: any = await t.mutation(api.realEstateEscrow.verifyInspectionPass, { sessionToken: owner.token, passId: r.passId, enteredOtp: r.otpCode });
    expect(locked.errorCode).toBe("PASS_LOCKED");
    expect((await wallet(t, owner.id)).availableBalance).toBe(0);
  });

  test("an unused pass is refunded to the client after it expires (or by an admin), never twice", async () => {
    const t = convexTest(schema, modules);
    const { client, book } = await setup(t);
    const admin = await makeUser(t, "admin", "admin");
    const r: any = await book();
    await expect(t.mutation(api.realEstateEscrow.refundInspectionPass, { sessionToken: client.token, passId: r.passId })).rejects.toThrow(/still valid/);
    await t.run(async (ctx) => ctx.db.patch(r.passId as Id<"re_inspection_passes">, { otpExpiresAt: Date.now() - 48 * 3600_000 }));
    await t.mutation(api.realEstateEscrow.refundInspectionPass, { sessionToken: client.token, passId: r.passId });
    expect((await wallet(t, client.id)).availableBalance).toBe(500);
    await expect(t.mutation(api.realEstateEscrow.refundInspectionPass, { sessionToken: admin.token, passId: r.passId })).rejects.toThrow();
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("short stay", () => {
  async function setup(t: T) {
    const owner = await makeUser(t, "host");
    const guest = await makeUser(t, "guest");
    const admin = await makeUser(t, "admin", "admin");
    const propertyId = await makeProperty(t, owner.id, "hourly_guesthouse", 100);
    await fund(t, guest.id, 2000);
    return { owner, guest, admin, propertyId };
  }

  test("priced on the server (client amounts ignored) and funded from the wallet", async () => {
    const t = convexTest(schema, modules);
    const { guest, propertyId } = await setup(t);
    const r: any = await initContract(t, guest, propertyId, "SHORT_STAY_BOOKING", { nightsCount: 2, baseAmount: 1, cautionDepositAmount: 1 });
    expect(r.grossEscrowAmount).toBe(500); // 200 stay + caution clamp(50, 300..5000) = 300
    expect(r.cautionDeposit).toBe(300);
    expect(r.platformFee).toBe(20);
    expect(r.netBeneficiaryExpected).toBe(180);
    expect(r.status).toBe("FUNDS_LOCKED");
    const w = await wallet(t, guest.id);
    expect(w.availableBalance).toBe(1500);
    expect(w.escrowBalance).toBe(500);
  });

  test("full lifecycle: check-in, 24h payout, caution claim; exact balances, fee booked once", async () => {
    const t = convexTest(schema, modules);
    const { owner, guest, propertyId } = await setup(t);
    const r: any = await initContract(t, guest, propertyId, "SHORT_STAY_BOOKING", { nightsCount: 2 });
    await expect(t.mutation(api.realEstateEscrow.releaseShortStayPayout24h, { sessionToken: owner.token, contractId: r.contractId })).rejects.toThrow(/CHECKED_IN/);
    // only the guest checks in
    await expect(t.mutation(api.realEstateEscrow.checkInShortStay, { sessionToken: owner.token, contractId: r.contractId })).rejects.toThrow();
    await t.mutation(api.realEstateEscrow.checkInShortStay, { sessionToken: guest.token, contractId: r.contractId });
    await expect(t.mutation(api.realEstateEscrow.releaseShortStayPayout24h, { sessionToken: owner.token, contractId: r.contractId })).rejects.toThrow(/24-hour/);
    await t.run(async (ctx) => ctx.db.patch(r.contractId as Id<"re_escrow_contracts">, { stay24hAutoReleaseTimestamp: Date.now() - 1000 }));
    await t.mutation(api.realEstateEscrow.releaseShortStayPayout24h, { sessionToken: owner.token, contractId: r.contractId });
    expect((await wallet(t, owner.id)).availableBalance).toBe(180);
    expect(await platformTotal(t)).toBe(20);
    await expect(t.mutation(api.realEstateEscrow.releaseShortStayPayout24h, { sessionToken: owner.token, contractId: r.contractId })).rejects.toThrow();

    // The host's damage claim does NOT pay the host: the deposit stays held for an admin decision.
    const claim: any = await t.mutation(api.realEstateEscrow.refundCautionDeposit, {
      sessionToken: owner.token, contractId: r.contractId, inspectionPassedClean: false, damageDeductionAmount: 100,
    });
    expect(claim).toMatchObject({ status: "CAUTION_CLAIM_PENDING", deductedToHost: 0, refundedToClient: 0 });
    expect((await wallet(t, owner.id)).availableBalance).toBe(180);
    expect((await wallet(t, guest.id)).escrowBalance).toBe(300);
    await expect(
      t.mutation(api.realEstateEscrow.refundCautionDeposit, { sessionToken: owner.token, contractId: r.contractId, inspectionPassedClean: true })
    ).rejects.toThrow(/awaiting an administrator/);
    const admin = await makeUser(t, "admin", "admin");
    const c: any = await t.mutation(api.realEstateEscrow.refundCautionDeposit, {
      sessionToken: admin.token, contractId: r.contractId, inspectionPassedClean: false, damageDeductionAmount: 100,
    });
    expect(c.deductedToHost).toBe(100);
    expect(c.refundedToClient).toBe(200);
    expect(c.status).toBe("FULLY_SETTLED");
    expect((await wallet(t, owner.id)).availableBalance).toBe(280);
    const gw = await wallet(t, guest.id);
    expect(gw.escrowBalance).toBe(0);
    expect(gw.availableBalance).toBe(1500 + 200);
    await expect(
      t.mutation(api.realEstateEscrow.refundCautionDeposit, { sessionToken: owner.token, contractId: r.contractId, inspectionPassedClean: true })
    ).rejects.toThrow();
  });

  test("a stranger cannot freeze a contract; a party can, and only an admin resolves it", async () => {
    const t = convexTest(schema, modules);
    const { owner, guest, admin, propertyId } = await setup(t);
    const stranger = await makeUser(t, "stranger");
    const r: any = await initContract(t, guest, propertyId, "SHORT_STAY_BOOKING", { nightsCount: 1 });
    const args = { contractId: r.contractId, claimantRole: "CLIENT", reason: "dirty", claimedRepairCost: 0, evidenceMediaUrls: [] };
    await expect(t.mutation(api.realEstateEscrow.raiseRealEstateDispute, { sessionToken: stranger.token, ...args })).rejects.toThrow(/not a party/);
    await t.mutation(api.realEstateEscrow.raiseRealEstateDispute, { sessionToken: guest.token, ...args });
    await expect(
      t.mutation(api.realEstateEscrow.adminResolveRealEstateDispute, { sessionToken: owner.token, contractId: r.contractId, resolution: "release_beneficiary", notes: "pay me please" })
    ).rejects.toThrow();
    await t.mutation(api.realEstateEscrow.adminResolveRealEstateDispute, { sessionToken: admin.token, contractId: r.contractId, resolution: "refund_client", notes: "host did not deliver" });
    const gw = await wallet(t, guest.id);
    expect(gw.availableBalance).toBe(2000);
    expect(gw.escrowBalance).toBe(0);
    expect((await wallet(t, owner.id)).availableBalance).toBe(0);
    expect((await contract(t, r.contractId))?.currentState).toBe("REFUNDED");
  });

  test("admin can release a disputed stay to the host (caution goes back to the guest)", async () => {
    const t = convexTest(schema, modules);
    const { owner, guest, admin, propertyId } = await setup(t);
    const r: any = await initContract(t, guest, propertyId, "SHORT_STAY_BOOKING", { nightsCount: 2 });
    await t.mutation(api.realEstateEscrow.raiseRealEstateDispute, { sessionToken: owner.token, contractId: r.contractId, claimantRole: "HOST", reason: "x", claimedRepairCost: 0, evidenceMediaUrls: [] });
    await t.mutation(api.realEstateEscrow.adminResolveRealEstateDispute, { sessionToken: admin.token, contractId: r.contractId, resolution: "release_beneficiary", notes: "guest stayed as agreed" });
    expect((await wallet(t, owner.id)).availableBalance).toBe(180);
    const gw = await wallet(t, guest.id);
    expect(gw.escrowBalance).toBe(0);
    expect(gw.availableBalance).toBe(1500 + 300);
    expect(await platformTotal(t)).toBe(20);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("long-term lease", () => {
  test("without an owner-authorised agent: rent to the landlord, NO agent commission, caution refunded", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "landlord");
    const tenant = await makeUser(t, "tenant");
    const propertyId = await makeProperty(t, owner.id, "long_term_rent", 12000);
    await fund(t, tenant.id, 20000);
    const r: any = await initContract(t, tenant, propertyId, "LONG_TERM_LEASE", { leaseDurationMonths: 12 });
    expect(r.grossEscrowAmount).toBe(13000); // 12000 rent + 1000 caution (no commission: no authorised agent)
    expect(r.platformFee).toBe(0);
    expect(r.agentCommission).toBe(0);
    await t.mutation(api.realEstateEscrow.checkInShortStay, { sessionToken: tenant.token, contractId: r.contractId });
    await t.run(async (ctx) => ctx.db.patch(r.contractId as Id<"re_escrow_contracts">, { stay24hAutoReleaseTimestamp: Date.now() - 1 }));
    await t.mutation(api.realEstateEscrow.releaseShortStayPayout24h, { sessionToken: tenant.token, contractId: r.contractId });
    expect((await wallet(t, owner.id)).availableBalance).toBe(12000);
    expect(await platformTotal(t)).toBe(0);
    await t.mutation(api.realEstateEscrow.refundCautionDeposit, { sessionToken: owner.token, contractId: r.contractId, inspectionPassedClean: true });
    const tw = await wallet(t, tenant.id);
    expect(tw.escrowBalance).toBe(0);
    expect(tw.availableBalance).toBe(20000 - 13000 + 1000);
  });
  // (lease WITH an authorised agent: listingAgents.test.ts)
});

// ─────────────────────────────────────────────────────────────────────
describe("land purchase milestones", () => {
  test("10/40/50 release in order, admin only; the 5% fee is collected pro-rata; exact totals", async () => {
    const t = convexTest(schema, modules);
    const seller = await makeUser(t, "seller");
    const buyer = await makeUser(t, "buyer");
    const admin = await makeUser(t, "admin", "admin");
    const propertyId = await makeProperty(t, seller.id, "sale", 100000);
    await fund(t, buyer.id, 100000);
    const r: any = await initContract(t, buyer, propertyId, "LAND_PURCHASE_MILESTONE");
    expect(r.grossEscrowAmount).toBe(100000);
    expect(r.platformFee).toBe(5000);

    const rel = (token: string, i: number) =>
      t.mutation(api.realEstateEscrow.verifyAndReleaseLandMilestone, { sessionToken: token, contractId: r.contractId, milestoneIndex: i, proofDocumentUrls: ["doc"] });
    await expect(rel(buyer.token, 1)).rejects.toThrow(); // buyer cannot verify their own milestone
    await expect(rel(seller.token, 1)).rejects.toThrow();
    await expect(rel(admin.token, 2)).rejects.toThrow(/before Milestone 1/);
    await rel(admin.token, 1);
    expect((await wallet(t, seller.id)).availableBalance).toBe(9500);
    await expect(rel(admin.token, 1)).rejects.toThrow(/already/);
    await rel(admin.token, 2);
    const last: any = await rel(admin.token, 3);
    expect(last.contractState).toBe("FULLY_SETTLED");
    expect((await wallet(t, seller.id)).availableBalance).toBe(95000);
    expect(await platformTotal(t)).toBe(5000);
    const bw = await wallet(t, buyer.id);
    expect(bw.escrowBalance).toBe(0);
    expect(bw.availableBalance).toBe(0);
  });

  test("an unfunded contract cannot be released", async () => {
    const t = convexTest(schema, modules);
    const seller = await makeUser(t, "seller");
    const buyer = await makeUser(t, "buyer");
    const admin = await makeUser(t, "admin", "admin");
    const propertyId = await makeProperty(t, seller.id, "sale", 100000);
    const r: any = await initContract(t, buyer, propertyId, "LAND_PURCHASE_MILESTONE", { paymentRail: "BANK_TRANSFER" });
    expect(r.status).toBe("CREATED");
    await expect(
      t.mutation(api.realEstateEscrow.verifyAndReleaseLandMilestone, { sessionToken: admin.token, contractId: r.contractId, milestoneIndex: 1, proofDocumentUrls: [] })
    ).rejects.toThrow(/funded/);
    expect((await wallet(t, seller.id)).availableBalance).toBe(0);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("validation & privacy", () => {
  test("category mismatch, own property and out-of-range durations are refused", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const user = await makeUser(t, "user");
    await fund(t, user.id, 10000);
    const rent = await makeProperty(t, owner.id, "long_term_rent", 12000);
    await expect(initContract(t, user, rent, "SHORT_STAY_BOOKING")).rejects.toThrow(/short stays/);
    await expect(initContract(t, user, rent, "LAND_PURCHASE_MILESTONE")).rejects.toThrow(/not for sale/);
    await expect(initContract(t, user, rent, "LONG_TERM_LEASE", { leaseDurationMonths: 600 })).rejects.toThrow(/months/);
    await fund(t, owner.id, 10000);
    await expect(initContract(t, owner, rent, "LONG_TERM_LEASE")).rejects.toThrow(/own property/);
  });

  test("the client's contract view never contains the street address, coordinates or phone numbers", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const guest = await makeUser(t, "guest");
    const admin = await makeUser(t, "admin", "admin");
    const propertyId = await makeProperty(t, owner.id, "hourly_guesthouse", 100);
    await fund(t, guest.id, 2000);
    const r: any = await initContract(t, guest, propertyId, "SHORT_STAY_BOOKING", { nightsCount: 1 });

    const asGuest: any = await t.query(api.realEstateEscrow.getRealEstateEscrowById, { sessionToken: guest.token, contractId: r.contractId });
    const json = JSON.stringify(asGuest);
    expect(json).not.toContain(SECRET_STREET);
    expect(json).not.toContain(SECRET_PHONE);
    expect(json).not.toMatch(/latitude|longitude|geohash|privateContactPhone|Phone"/i);
    expect(asGuest.property.city).toBe("Inside Lumley, Sierra Leone");

    const asOwner: any = await t.query(api.realEstateEscrow.getRealEstateEscrowById, { sessionToken: owner.token, contractId: r.contractId });
    expect(asOwner.property.address).toBe(SECRET_STREET); // the owner sees their own data
    const asAdmin: any = await t.query(api.realEstateEscrow.getRealEstateEscrowById, { sessionToken: admin.token, contractId: r.contractId });
    expect(asAdmin.property.address).toBe(SECRET_STREET);

    const mine: any = await t.query(api.realEstateEscrow.getMyRealEstateEscrows, { sessionToken: guest.token });
    expect(JSON.stringify(mine)).not.toContain(SECRET_STREET);
    expect(mine.contracts[0].propertyCity).toBe("Inside Lumley, Sierra Leone");
  });

  test("the agent never sees the client's OTP/QR in 'my escrows'", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const client = await makeUser(t, "client");
    const propertyId = await makeProperty(t, owner.id, "sale", 50000);
    await fund(t, client.id, 500);
    const r: any = await t.mutation(api.realEstateEscrow.initiateInspectionPass, {
      sessionToken: client.token, propertyListingId: propertyId, scheduledTimestamp: Date.now() + 3600_000, paymentRail: "WALLET",
    } as any);
    const asAgent: any = await t.query(api.realEstateEscrow.getMyRealEstateEscrows, { sessionToken: owner.token });
    const p = asAgent.inspectionPasses[0];
    expect(p.otpCode).toBeUndefined();
    expect(p.qrHash).toBeUndefined();
    const asClient: any = await t.query(api.realEstateEscrow.getMyRealEstateEscrows, { sessionToken: client.token });
    expect(asClient.inspectionPasses[0].otpCode).toBe(r.otpCode);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("direct Monime payment funds property escrow", () => {
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

  test("contract: server-quoted amount, confirmed by Monime, held in escrow with no top-up", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "host");
    const guest = await makeUser(t, "guest");
    const propertyId = await makeProperty(t, owner.id, "hourly_guesthouse", 100);
    const r: any = await initContract(t, guest, propertyId, "SHORT_STAY_BOOKING", { paymentRail: "MOBILE_MONEY", nightsCount: 2 });
    expect(r.status).toBe("CREATED");
    await t.action(api.payments.initiateMoniMePayment, { sessionToken: guest.token, amount: 1, reContractId: r.contractId, phoneNumber: "076123456" });
    const [sid] = [...sessions.keys()];
    expect(sessions.get(sid).lineItems.data[0].price.value).toBe(50000);
    sessions.get(sid).status = "completed";
    await t.action(internal.payments.settleMoniMeReference, { reference: sid });
    await t.action(internal.payments.settleMoniMeReference, { reference: sid });
    expect((await contract(t, r.contractId))?.currentState).toBe("FUNDS_LOCKED");
    const w = await wallet(t, guest.id);
    expect(w.escrowBalance).toBe(500);
    expect(w.availableBalance).toBe(0);
  });

  test("inspection pass: Monime payment activates the pass", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const client = await makeUser(t, "client");
    const propertyId = await makeProperty(t, owner.id, "sale", 50000);
    const r: any = await t.mutation(api.realEstateEscrow.initiateInspectionPass, {
      sessionToken: client.token, propertyListingId: propertyId, scheduledTimestamp: Date.now() + 3600_000, paymentRail: "orange",
    } as any);
    expect(r.status).toBe("CREATED");
    await t.action(api.payments.initiateMoniMePayment, { sessionToken: client.token, amount: 1, inspectionPassId: r.passId, phoneNumber: "076123456" });
    const [sid] = [...sessions.keys()];
    expect(sessions.get(sid).lineItems.data[0].price.value).toBe(5000);
    sessions.get(sid).status = "completed";
    await t.action(internal.payments.settleMoniMeReference, { reference: sid });
    expect(((await pass(t, r.passId)) as any).status).toBe("FUNDS_LOCKED");
    expect((await wallet(t, client.id)).escrowBalance).toBe(50);
    // and the verification now works
    const v: any = await t.mutation(api.realEstateEscrow.verifyInspectionPass, { sessionToken: owner.token, passId: r.passId, enteredOtp: r.otpCode });
    expect(v.success).toBe(true);
  });
});
