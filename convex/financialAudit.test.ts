/// <reference types="vite/client" />
// Regression tests for the defects found in the financial-path audit: payment claims / Moneroo
// could mark orders "held" with no money held; claims and bank references could target another
// user's order; hosts/owners could pay themselves from deposits; hotel operators could release
// before the stay; anyone could file vehicle inspections; booking-dispute admin checks; legacy
// booking escrow stuck forever; recovery protection on escrow payments and subscriptions.

import { convexTest } from "convex-test";
import { afterEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { hashWalletPin } from "./lib/pin";
import type { Id } from "./_generated/dataModel";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts"]);
type T = ReturnType<typeof convexTest>;
type U = { id: Id<"users">; token: string };
const DAY = 24 * 60 * 60 * 1000;
const PIN = "1234";
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

const INSPECTION_TYPE = "PURCHASE_MECHANIC_INSPECTION" as const;
let seq = 0;

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

async function makeUser(t: T, name: string, role = "client", extra: Record<string, unknown> = {}): Promise<U> {
  seq += 1;
  const token = `sess_${name}_${seq}_0123456789abcdef`;
  const id: Id<"users"> = await t.run(async (ctx) =>
    ctx.db.insert("users", {
      email: `${name}${seq}@t.vx`, phone: `+2327900${1000 + seq}`, name, role: role as any,
      isVerified: false, isActive: true, sessionToken: token, updatedAt: Date.now(), ...extra,
    } as any)
  );
  await t.run(async (ctx) => ctx.db.patch(id, { walletPinHash: await hashWalletPin(id, PIN) }));
  return { id, token };
}
const fund = (t: T, userId: Id<"users">, amount: number) =>
  t.mutation(internal.walletCore.creditVerifiedDeposit, { userId, amount, provider: "TEST", providerReference: `f-${userId}-${seq++}` });
const wallet = async (t: T, userId: Id<"users">) =>
  (await t.run(async (ctx) => (await ctx.db.query("walletBalances").collect()).find((w) => w.userId === userId))) ??
  ({ availableBalance: 0, escrowBalance: 0, pendingBalance: 0 } as { availableBalance: number; escrowBalance?: number; pendingBalance: number });

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
/** A vehicle purchase order of 10,000 awaiting payment (not funded). */
async function pendingSale(t: T, buyer: U, owner: U) {
  const r: any = await t.mutation(api.escrow.initiateEscrowOrder, {
    sessionToken: buyer.token, orderType: "VEHICLE_PURCHASE", vehicleListingId: await vehicle(t, owner.id, 10_000, "total_sale"), payFromWallet: false,
  } as any);
  const order: any = await t.run(async (ctx) => ctx.db.get(r.escrowOrderId as Id<"escrow_orders">));
  expect(order.status).toBe("PENDING_PAYMENT");
  return order as { _id: Id<"escrow_orders">; grossEscrowAmount: number };
}
async function seedProviders(t: T, admin: U) {
  await t.mutation(api.payments.seedDefaultPaymentMethods, { sessionToken: admin.token });
}

// ─────────────────────────────────────────────────────────────────────
describe("payment claims never fake an escrow", () => {
  test("a claim cannot be linked to another user's order", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const victim = await makeUser(t, "victim");
    const attacker = await makeUser(t, "attacker");
    await seedProviders(t, admin);
    const order = await pendingSale(t, victim, owner);
    await expect(
      t.mutation(api.payments.submitManualPaymentClaim, {
        sessionToken: attacker.token, amount: 10_000, providerId: "qmoney_manual", transactionReference: "SMS-1", escrowOrderId: order._id,
      })
    ).rejects.toThrow(/not found/i);
  });

  test("admin approval credits the verified deposit and funds the order with REAL held money", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    await seedProviders(t, admin);
    const order = await pendingSale(t, buyer, owner);
    const { claimId }: any = await t.mutation(api.payments.submitManualPaymentClaim, {
      sessionToken: buyer.token, amount: order.grossEscrowAmount, providerId: "qmoney_manual", transactionReference: "SMS-OK", escrowOrderId: order._id,
    });
    // nothing happens until an admin approves
    expect((await wallet(t, buyer.id)).availableBalance).toBe(0);
    await expect(t.mutation(api.payments.approvePaymentClaim, { sessionToken: buyer.token, claimId })).rejects.toThrow(/administrator/i);

    const r: any = await t.mutation(api.payments.approvePaymentClaim, { sessionToken: admin.token, claimId });
    expect(r.escrowFunded).toBe(true);
    const w = await wallet(t, buyer.id);
    expect(w.escrowBalance).toBe(order.grossEscrowAmount); // genuinely held, not just a status
    expect(w.availableBalance).toBe(0);
    expect(((await t.run(async (ctx) => ctx.db.get(order._id))) as any).status).toBe("HELD_IN_ESCROW");
    await expect(t.mutation(api.payments.approvePaymentClaim, { sessionToken: admin.token, claimId })).rejects.toThrow(/status/i);
  });

  test("an underpaid approved claim does NOT mark the order held; the money stays in the wallet", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    await seedProviders(t, admin);
    const order = await pendingSale(t, buyer, owner);
    const { claimId }: any = await t.mutation(api.payments.submitManualPaymentClaim, {
      sessionToken: buyer.token, amount: 10, providerId: "qmoney_manual", transactionReference: "SMS-SMALL", escrowOrderId: order._id,
    });
    const r: any = await t.mutation(api.payments.resolveManualPaymentClaim, { sessionToken: admin.token, claimId, action: "APPROVE_DEPOSIT" });
    expect(r.escrowFunded).toBe(false);
    expect(((await t.run(async (ctx) => ctx.db.get(order._id))) as any).status).toBe("PENDING_PAYMENT");
    expect((await wallet(t, buyer.id)).availableBalance).toBe(10);
  });

  test("a legacy claim pointing at someone else's order cannot pull the victim's money into it", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const owner = await makeUser(t, "owner");
    const victim = await makeUser(t, "victim");
    const attacker = await makeUser(t, "attacker");
    await fund(t, victim.id, 20_000);
    const order = await pendingSale(t, victim, owner);
    const claimId = await t.run(async (ctx) =>
      ctx.db.insert("escrow_payment_claims", {
        userId: attacker.id, amount: 5, currency: "SLE", providerId: "qmoney_manual", paymentType: "MANUAL_CLAIM",
        transactionReference: "SMS-EVIL", status: "PENDING_APPROVAL", escrowOrderId: order._id, createdAt: Date.now(),
      } as any)
    );
    const r: any = await t.mutation(api.payments.approvePaymentClaim, { sessionToken: admin.token, claimId });
    expect(r.escrowFunded).toBe(false);
    expect((await wallet(t, victim.id)).availableBalance).toBe(20_000);
    expect(((await t.run(async (ctx) => ctx.db.get(order._id))) as any).status).toBe("PENDING_PAYMENT");
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("bank escrow references", () => {
  test("only the contract's own client can create one, and the amount is the contract's", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const client = await makeUser(t, "client");
    const attacker = await makeUser(t, "attacker");
    const c: any = await t.mutation(api.realEstateEscrow.initiateRealEstateEscrow, {
      sessionToken: client.token, contractType: "LAND_PURCHASE_MILESTONE", propertyListingId: await property(t, owner.id, "sale", 50_000), paymentRail: "BANK_TRANSFER",
    } as any);
    await expect(
      t.mutation(api.payments.generateBankEscrowReference, { sessionToken: attacker.token, orderType: "REAL_ESTATE", orderId: c.contractId, amount: 1 })
    ).rejects.toThrow(/not found/i);
    const r: any = await t.mutation(api.payments.generateBankEscrowReference, { sessionToken: client.token, orderType: "REAL_ESTATE", orderId: c.contractId, amount: 1 });
    expect(r.bankDetails.amount).toBe(c.grossEscrowAmount);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("deposits: the counterparty cannot pay themselves", () => {
  test("a stranger cannot file vehicle inspections on someone else's order", async () => {
    const t = convexTest(schema, modules);
    const owner = await makeUser(t, "owner");
    const buyer = await makeUser(t, "buyer");
    const stranger = await makeUser(t, "stranger");
    const order = await pendingSale(t, buyer, owner);
    const photo = "https://x/y.jpg";
    await expect(
      t.mutation(api.escrow.completeVehicleInspection, {
        sessionToken: stranger.token, escrowOrderId: order._id, inspectionType: INSPECTION_TYPE, odometerReadingKm: 1, fuelTankPercentage: 50,
        photoFrontUrl: photo, photoRearUrl: photo, photoLeftSideUrl: photo, photoRightSideUrl: photo, photoInteriorUrl: photo, photoDashboardOdometerUrl: photo,
        damagesDetected: ["fake dent"], qrTokenHash: "q",
      })
    ).rejects.toThrow(/not a party/i);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("hotel: the operator cannot release before the guest's window", () => {
  test("operator check-in + immediate release is refused; allowed 24h after check-out", async () => {
    const t = convexTest(schema, modules);
    const operator = await makeUser(t, "operator", "hotel_operator");
    const guest = await makeUser(t, "guest");
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
    await fund(t, guest.id, 1000);
    const checkOut = Date.now() + 2 * DAY;
    const res: any = await t.mutation(api.hotelBookings.createBookingWithEscrow, {
      sessionToken: guest.token, hotelId, roomId, guestName: "G", guestPhone: "+23276111111", bookingCategory: "nightly",
      checkInTimestamp: Date.now() + DAY, checkOutTimestamp: checkOut, numberOfGuests: 1, numberOfNights: 1,
    });
    await t.mutation(api.hotelBookings.confirmCheckIn, { sessionToken: operator.token, bookingId: res.bookingId });
    await expect(t.mutation(api.hotelBookings.releaseEscrowPayout, { sessionToken: operator.token, bookingId: res.bookingId })).rejects.toThrow(/24 hours after check-out/);
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date(checkOut + DAY - 60_000));
    await expect(t.mutation(api.hotelBookings.releaseEscrowPayout, { sessionToken: operator.token, bookingId: res.bookingId })).rejects.toThrow(/24 hours/);
    vi.setSystemTime(new Date(checkOut + DAY + 1));
    await t.mutation(api.hotelBookings.releaseEscrowPayout, { sessionToken: operator.token, bookingId: res.bookingId });
    expect((await wallet(t, operator.id)).availableBalance).toBe(900);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("booking disputes (admin)", () => {
  async function disputed(t: T) {
    const admin = await makeUser(t, "admin", "admin");
    const buyer = await makeUser(t, "buyer");
    const vendor = await makeUser(t, "vendor");
    const listingId = await t.run(async (ctx) =>
      ctx.db.insert("realEstateListings", {
        ownerId: vendor.id, title: "Stay", description: "d", category: "hourly_guesthouse", price: 100, hourlyRate: 100, currency: "SLE",
        address: "x", city: "Lumley", country: "Sierra Leone", latitude: 0, longitude: 0, geohash: "", imageUrls: [],
        availabilityStatus: "available", isFeatured: false, isPublished: true, viewCount: 0, updatedAt: Date.now(),
      } as any)
    );
    await fund(t, buyer.id, 1000);
    const start = Date.now() + DAY;
    const b: any = await t.mutation(api.bookings.createBooking, {
      sessionToken: buyer.token, listingId, listingType: "property", listingTitle: "Stay", bookingType: "hourly_guesthouse", startTime: start, endTime: start + 4 * 3600_000, hours: 4,
    });
    await t.mutation(api.payments.createEscrowPayment, { sessionToken: buyer.token, vendorId: vendor.id, amount: 420, referenceId: b.bookingId });
    await t.mutation(api.bookings.raiseBookingDispute, { sessionToken: buyer.token, bookingId: b.bookingId, reason: "host cancelled on arrival" });
    return { admin, buyer, vendor, bookingId: b.bookingId as string };
  }

  test("the list shows server amounts, the dispute and the full history; admins only", async () => {
    const t = convexTest(schema, modules);
    const { admin, buyer, bookingId } = await disputed(t);
    await expect(t.query(api.bookings.adminListBookingDisputes, { sessionToken: buyer.token })).rejects.toThrow(/administrator/i);
    const rows: any[] = await t.query(api.bookings.adminListBookingDisputes, { sessionToken: admin.token, view: "open" });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      id: bookingId, settlementStatus: "disputed", disputedBy: "buyer", disputeReason: "host cancelled on arrival", autoReleaseAt: null,
      escrow: { amountPaid: 420, heldAmount: 420, refundableAmount: 420, platformFee: 63, vendorAmount: 357, escrowStatus: "locked" },
      buyer: { name: "buyer" }, vendor: { name: "vendor" },
    });
    expect(rows[0].escrow.escrowTransactionCode).toMatch(/^TX-/);
    expect(rows[0].events.map((e: any) => e.action)).toEqual(["PAID", "DISPUTE_OPENED"]);
    expect(rows[0].events[0].ledgerCode).toMatch(/^ESC-LOCK-/);
  });

  test("the admin's confirmed amount must match the server's; resolution is final and fully recorded", async () => {
    const t = convexTest(schema, modules);
    const { admin, buyer, vendor, bookingId } = await disputed(t);
    await expect(
      t.mutation(api.bookings.adminResolveBookingDispute, { sessionToken: admin.token, bookingId, resolution: "refund_buyer", note: "host no-show confirmed", expectedAmount: 400 })
    ).rejects.toThrow(/changed/i);
    expect((await wallet(t, buyer.id)).escrowBalance).toBe(420);
    await t.mutation(api.bookings.adminResolveBookingDispute, { sessionToken: admin.token, bookingId, resolution: "refund_buyer", note: "host no-show confirmed", expectedAmount: 420 });
    expect((await wallet(t, buyer.id)).availableBalance).toBe(1000);
    // cannot be executed again, in either direction
    for (const resolution of ["refund_buyer", "release_to_vendor"] as const) {
      await expect(
        t.mutation(api.bookings.adminResolveBookingDispute, { sessionToken: admin.token, bookingId, resolution, note: "second attempt here" })
      ).rejects.toThrow(/no escrow/i);
    }
    expect((await wallet(t, vendor.id)).availableBalance).toBe(0);
    const rows: any[] = await t.query(api.bookings.adminListBookingDisputes, { sessionToken: admin.token, view: "resolved" });
    expect(rows[0].events.map((e: any) => e.action)).toEqual(["PAID", "DISPUTE_OPENED", "ADMIN_DECISION", "REFUNDED"]);
    const refunded = rows[0].events[3];
    expect(refunded).toMatchObject({ actorRole: "admin", actorName: "admin", amount: 420 });
    expect(refunded.transactionCode).toMatch(/^TX-/);
    expect(refunded.ledgerCode).toMatch(/^ESC-REF-/);
    expect(rows[0].audit).toHaveLength(1);
    expect(rows[0].audit[0]).toMatchObject({ action: "BOOKING_SETTLED", resolution: "refund_buyer", amount: 420, adminName: "admin" });
  });

  test("a booking paid before settlement tracking is backfilled, then released by the 24h job (not stuck)", async () => {
    const t = convexTest(schema, modules);
    const buyer = await makeUser(t, "buyer");
    const vendor = await makeUser(t, "vendor");
    await fund(t, buyer.id, 500);
    const bookingId = await t.run(async (ctx) =>
      ctx.db.insert("bookings", {
        listingId: "l", listingType: "property", listingTitle: "Old", buyerId: buyer.id as string, vendorId: vendor.id as string,
        bookingType: "hourly_guesthouse", status: "pending_payment", startTime: 1, endTime: 2, subtotal: 500, serviceFee: 0,
        totalAmount: 500, currency: "SLE", paymentStatus: "pending", updatedAt: Date.now(),
      })
    );
    await t.mutation(api.payments.createEscrowPayment, { sessionToken: buyer.token, vendorId: vendor.id, amount: 500, referenceId: bookingId });
    // simulate a booking paid by the previous code (no settlement fields)
    await t.run(async (ctx) => ctx.db.patch(bookingId, { settlementStatus: undefined, releaseEligibleAt: undefined }));
    expect(await t.mutation(internal.bookings.releaseDueBookings, {})).toMatchObject({ released: 0 });
    const r: any = await t.mutation(internal.bookings.backfillBookingSettlement, {});
    expect(r.fixed).toBe(1);
    expect((await t.mutation(internal.bookings.backfillBookingSettlement, {})).fixed).toBe(0); // idempotent
    expect(await t.mutation(internal.bookings.releaseDueBookings, {})).toMatchObject({ released: 1 });
    expect((await wallet(t, vendor.id)).availableBalance).toBe(425);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("recovery protection covers escrow payments and subscription charges too", () => {
  test("a recipient with an open recovery cannot spend the protected amount on a booking or a subscription", async () => {
    const t = convexTest(schema, modules);
    const admin = await makeUser(t, "admin", "admin");
    const vendor = await makeUser(t, "vendor");
    const payer = await makeUser(t, "payer");
    const host = await makeUser(t, "host");
    // vendor owes 300 on an open recovery case
    await t.run(async (ctx) => {
      const rel = await ctx.db.insert("walletBalances", { userId: payer.id, availableBalance: 0, pendingBalance: 0, escrowBalance: 0, currency: "SLE", updatedAt: Date.now() });
      const tx = await ctx.db.insert("transactions", {
        walletId: rel, userId: payer.id, counterpartyId: vendor.id, type: "escrow_release", amount: 300, currency: "SLE", status: "completed", updatedAt: Date.now(),
      } as any);
      await ctx.db.insert("payment_reversals", {
        releaseTransactionId: tx, buyerId: payer.id, recipientId: vendor.id, currency: "SLE", referenceType: "x", referenceId: "y",
        originalAmount: 300, platformFeeReversed: 0, recipientNetOwed: 300, recoveredFromRecipient: 0, platformCoveredAmount: 0, writtenOffAmount: 0,
        refundedToBuyer: 0, outstandingAmount: 300, status: "pending_recovery", withdrawalProtection: "active", reason: "test", createdBy: admin.id,
        createdAt: Date.now(), updatedAt: Date.now(),
      } as any);
    });
    await fund(t, vendor.id, 400); // 300 protected, 100 usable

    // escrow payment (booking) above the usable amount is refused
    const bookingId = await t.run(async (ctx) =>
      ctx.db.insert("bookings", {
        listingId: "l", listingType: "property", listingTitle: "S", buyerId: vendor.id as string, vendorId: host.id as string,
        bookingType: "hourly_guesthouse", status: "pending_payment", startTime: 1, endTime: 2, subtotal: 200, serviceFee: 0,
        totalAmount: 200, currency: "SLE", paymentStatus: "pending", updatedAt: Date.now(),
      })
    );
    await expect(
      t.mutation(api.payments.createEscrowPayment, { sessionToken: vendor.token, vendorId: host.id, amount: 200, referenceId: bookingId })
    ).rejects.toThrow(/RECOVERY_HOLD/);

    // subscription charge above the usable amount is refused
    await t.mutation(api.subscriptions.adminUpsertPlan, {
      sessionToken: admin.token, tierCode: "AGENT_M", name: "Agent Monthly", roleTarget: "agent", basePrice: 150, currency: "SLE",
      billingInterval: "monthly", intervalDays: 30, discountPercent: 0, isActive: true, features: [],
    });
    await t.run(async (ctx) => ctx.db.patch(vendor.id, { role: "agent" as any, roleApprovedAt: Date.now() }));
    await expect(
      t.mutation(api.subscriptions.subscribeWithWallet, { sessionToken: vendor.token, tierCode: "AGENT_M", pin: PIN, idempotencyKey: "sub-key-recovery-000001" })
    ).rejects.toThrow(/RECOVERY_HOLD/);
    expect((await wallet(t, vendor.id)).availableBalance).toBe(400);
  });
});

// ─────────────────────────────────────────────────────────────────────
describe("removed back doors stay removed", () => {
  test("no client-callable function can lock arbitrary escrow or create payment intents", async () => {
    const payments = (await import("./payments")) as Record<string, unknown>;
    for (const name of ["lockEscrowFunds", "createPaymentIntent", "processVerifiedPayment", "confirmPayment"]) {
      expect(name in payments, name).toBe(false);
    }
  });
});
