// convex/escrow.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Production Vehicle Escrow & Settlement Engine
// Implements Vehicle Rentals (60/40 Split + Damage Deposit) and
// Vehicle Purchases (Earnest Fee + Mechanic QR + SLRSA Title Transfer)
// Standard: Sierra Leone New Leones (SLE)
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query, internalMutation } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import {
  escrowOrderType,
  escrowOrderStatus,
  inspectionTypeEnum,
} from "./schema";
import { detectSierraLeoneCarrier } from "./lib/paymentErrors";
import { requireSelf, requireParticipantOrAdmin, requireAdminSession } from "./lib/auth";
import { fundEscrowFromExternalPayment, holdFunds, releaseHeldFunds, refundHeldFunds } from "./walletCore";
import { FeeSnapshot, priceOrder } from "./lib/fees";

// ─── Helper: Resolve Caller User ──────────────────────────────────────
async function resolveCallerUser(ctx: any, explicitUserId?: string, sessionToken?: string): Promise<Id<"users">> {
  // Identity comes ONLY from the validated session (or JWT identity). A client-supplied
  // user id is merely checked for consistency; it is never a source of identity.
  const { userId } = await requireSelf(ctx, sessionToken, explicitUserId);
  return userId;
}

const round2 = (n: number) => Math.round(n * 100) / 100;

/** Escrow funds are held, released and refunded ONLY through walletCore (atomic, idempotent, double-entry). */
const REF = "vehicle_escrow";

/**
 * Moves the order's gross amount from the buyer's available wallet funds into escrow and marks the
 * order funded. `soft` (used when a verified provider payment has just been credited) reports a
 * reason instead of throwing, so the credit is never rolled back.
 */
export async function fundVehicleOrderFromWallet(
  ctx: { db: any },
  orderId: Id<"escrow_orders">,
  soft = false
): Promise<{ funded: boolean; reason?: string }> {
  const order = await ctx.db.get(orderId);
  if (!order || order.status !== "PENDING_PAYMENT") {
    return { funded: false, reason: "The order is not awaiting payment." };
  }
  if (soft) {
    const w = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q: any) => q.eq("userId", order.renterOrBuyerId).eq("currency", "SLE"))
      .first();
    if (!w || w.availableBalance < order.grossEscrowAmount) {
      return { funded: false, reason: "Available balance is lower than the escrow amount." };
    }
  }
  await holdFunds(ctx, {
    userId: order.renterOrBuyerId,
    amount: order.grossEscrowAmount,
    referenceType: REF,
    referenceId: order._id,
    idempotencyKey: `vesc:${order._id}:fund`,
    description: `Escrow funded for ${order.orderCode}`,
    counterpartyId: order.ownerOrSellerId,
  });
  const now = Date.now();
  await ctx.db.patch(order._id, { status: "HELD_IN_ESCROW", updatedAt: now });
  await ctx.db.insert("user_notifications", {
    userId: order.ownerOrSellerId as string,
    targetType: "single_user",
    title: "Deal escrow funded",
    body: `The buyer's payment for order ${order.orderCode} is secured in escrow. You can proceed with the handoff.`,
    read: false,
    createdAt: now,
  });
  return { funded: true };
}

/** A bank transfer confirmed by an admin funds the order directly (no wallet top-up). */
export async function fundVehicleOrderFromExternal(
  ctx: { db: any },
  orderId: Id<"escrow_orders">,
  provider: string,
  providerReference: string
): Promise<{ funded: boolean; reason?: string }> {
  const order = await ctx.db.get(orderId);
  if (!order || order.status !== "PENDING_PAYMENT") {
    return { funded: false, reason: "The order is not awaiting payment." };
  }
  await fundEscrowFromExternalPayment(ctx, {
    userId: order.renterOrBuyerId,
    amount: order.grossEscrowAmount,
    provider,
    providerReference,
    referenceType: REF,
    referenceId: order._id,
    counterpartyId: order.ownerOrSellerId,
  });
  const now = Date.now();
  await ctx.db.patch(order._id, { status: "HELD_IN_ESCROW", bankClearingStatus: "CLEARED", updatedAt: now });
  for (const uid of [order.renterOrBuyerId, order.ownerOrSellerId]) {
    await ctx.db.insert("user_notifications", {
      userId: uid as string,
      targetType: "single_user",
      title: "Escrow funded",
      body: `Payment for order ${order.orderCode} is confirmed and secured in escrow.`,
      read: false,
      createdAt: now,
    });
  }
  return { funded: true };
}

// ═══════════════════════════════════════════════════════════════════════
// 1. INITIATE ESCROW ORDER
// ═══════════════════════════════════════════════════════════════════════
export const initiateEscrowOrder = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    orderType: escrowOrderType,
    vehicleListingId: v.id("vehicleListings"),
    renterOrBuyerId: v.optional(v.string()),
    rentalStartDate: v.optional(v.number()),
    rentalEndDate: v.optional(v.number()),
    numberOfDays: v.optional(v.number()),
    baseRentalAmount: v.optional(v.number()),
    refundableDepositAmount: v.optional(v.number()),
    earnestFeeAmount: v.optional(v.number()),
    fullPurchaseAmount: v.optional(v.number()),
    paymentRail: v.optional(v.string()), // "MOBILE_MONEY" | "BANK_TRANSFER" | "WALLET"
    paymentProvider: v.optional(v.string()), // "ORANGE_MONEY_SL" | "AFRICELL_AFRIMONEY_SL" | "MONIME" | "WALLET" | "BANK_TRANSFER"
    paymentPhone: v.optional(v.string()),
    bankEscrowReference: v.optional(v.string()),
    payFromWallet: v.optional(v.boolean()),
  },
  returns: v.object({
    escrowOrderId: v.string(),
    orderCode: v.string(),
    status: v.string(),
    grossEscrowAmount: v.number(),
    platformFeeAmount: v.number(),
    netMerchantExpected: v.number(),
    split60Amount: v.number(),
    split40Amount: v.number(),
    refundableDeposit: v.number(),
    buyerFeeAmount: v.optional(v.number()),
    bankEscrowReference: v.optional(v.string()),
    paymentRail: v.optional(v.string()),
    detectedCarrier: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    // 1. Caller identity comes from the session only
    const currentUserId = await resolveCallerUser(ctx, args.renterOrBuyerId, args.sessionToken);

    // 2. Listing must exist and be available
    const vehicle = await ctx.db.get(args.vehicleListingId);
    if (!vehicle || vehicle.isDeleted === true || vehicle.isPublished === false) {
      throw new Error("This vehicle listing is not available.");
    }
    if (vehicle.ownerId === currentUserId) {
      throw new Error("You cannot rent or purchase your own vehicle listing");
    }

    const now = Date.now();
    const orderCode = `VK-ESC-${now.toString().slice(-6)}-${Math.floor(1000 + Math.random() * 9000)}`;

    // 3. EVERY amount is computed here from the listing. Amounts sent by the app are ignored, so a
    //    client can never change what is paid or what the seller receives.
    let baseRental = 0;
    let refundableDeposit = 0;
    let earnestFee = 0;
    let fullPurchase = 0;
    let grossEscrow = 0;
    let platformFee = 0;
    let netMerchant = 0;
    let fees: FeeSnapshot;

    // Fees come from the Fee & Commission Engine (defaults = 15% rental / 5% sale, as before).
    // platformFee = everything the platform keeps (owner fee + any admin-enabled buyer fee);
    // netMerchant = what the owner receives. The rule used is snapshotted on the order.
    if (args.orderType === "VEHICLE_RENTAL") {
      if (vehicle.pricingType === "total_sale") throw new Error("This vehicle is listed for sale, not for rent.");
      const days = Math.floor(args.numberOfDays ?? 1);
      if (!(days >= 1 && days <= 365)) throw new Error("Rental period must be between 1 and 365 days.");
      baseRental = round2(vehicle.price * days);
      refundableDeposit = Math.max(500, Math.round(baseRental * 0.33));
      fees = await priceOrder(ctx, "vehicle_rental", baseRental, { hasAgent: false, now });
      grossEscrow = round2(fees.buyerTotal + refundableDeposit);
      platformFee = fees.platformTotal;
      netMerchant = fees.payeeNet;
    } else {
      if (vehicle.pricingType !== "total_sale") throw new Error("This vehicle is listed for rent, not for sale.");
      fullPurchase = round2(vehicle.price);
      earnestFee = Math.min(500, fullPurchase);
      fees = await priceOrder(ctx, "vehicle_sale", fullPurchase, { hasAgent: false, now });
      grossEscrow = fees.buyerTotal;
      platformFee = fees.platformTotal;
      netMerchant = fees.payeeNet;
    }
    if (!(grossEscrow > 0) || !Number.isFinite(grossEscrow)) throw new Error("This listing has no valid price.");

    const split60 = round2(netMerchant * 0.6);
    const split40 = round2(netMerchant - split60);

    // 4. Payment rail
    let resolvedRail = args.paymentRail;
    if (!resolvedRail) {
      if (args.payFromWallet || args.paymentProvider === "WALLET") resolvedRail = "WALLET";
      else if (args.paymentProvider === "BANK_TRANSFER") resolvedRail = "BANK_TRANSFER";
      else resolvedRail = "MOBILE_MONEY";
    }
    const payFromWallet = resolvedRail === "WALLET" || args.payFromWallet === true;

    let detectedCarrier: string | undefined;
    if (args.paymentPhone) {
      const carrier = detectSierraLeoneCarrier(args.paymentPhone);
      if (carrier !== "unknown") detectedCarrier = carrier;
    }

    let bankEscrowReference = args.bankEscrowReference;
    let bankClearingStatus: "PENDING_TRANSFER" | "CLEARED" | undefined;
    if (resolvedRail === "BANK_TRANSFER") {
      if (!bankEscrowReference) bankEscrowReference = `VKTLX-DEAL-${Math.floor(1000 + Math.random() * 9000)}`;
      bankClearingStatus = "PENDING_TRANSFER";
    }

    // 5. Create the order. It stays PENDING_PAYMENT until money is REALLY secured: from the wallet
    //    below, from a provider payment verified by Monime, or from a bank transfer confirmed by an admin.
    const escrowOrderId = await ctx.db.insert("escrow_orders", {
      orderCode,
      orderType: args.orderType,
      renterOrBuyerId: currentUserId,
      ownerOrSellerId: vehicle.ownerId,
      vehicleListingId: vehicle._id,
      currency: "SLE",
      baseRentalAmount: baseRental,
      refundableDepositAmount: refundableDeposit,
      earnestFeeAmount: earnestFee,
      fullPurchaseAmount: fullPurchase,
      grossEscrowAmount: grossEscrow,
      platformFeeAmount: platformFee,
      netMerchantExpected: netMerchant,
      split60ReleasedAmount: 0,
      split40ReleasedAmount: 0,
      depositRefundedAmount: 0,
      depositDamageDeductedAmount: 0,
      status: "PENDING_PAYMENT",
      purchaseStage: args.orderType === "VEHICLE_PURCHASE" ? "EARNEST_PENDING" : undefined,
      rentalStartDate: args.rentalStartDate,
      rentalEndDate: args.rentalEndDate,
      numberOfDays: args.numberOfDays,
      paymentProvider: args.paymentProvider ?? (payFromWallet ? "WALLET" : resolvedRail === "BANK_TRANSFER" ? "BANK_TRANSFER" : "MONIME"),
      paymentPhone: args.paymentPhone,
      paymentRail: resolvedRail,
      bankEscrowReference,
      bankClearingStatus,
      detectedCarrier,
      feeSnapshot: fees,
      createdAt: now,
      updatedAt: now,
    });

    let initialStatus = "PENDING_PAYMENT";
    if (payFromWallet) {
      // Throws INSUFFICIENT_FUNDS (and rolls the order back) if the wallet cannot cover it.
      await fundVehicleOrderFromWallet(ctx, escrowOrderId);
      initialStatus = "HELD_IN_ESCROW";
    }

    return {
      escrowOrderId: escrowOrderId as string,
      orderCode,
      status: initialStatus,
      grossEscrowAmount: grossEscrow,
      platformFeeAmount: platformFee,
      netMerchantExpected: netMerchant,
      split60Amount: split60,
      split40Amount: split40,
      refundableDeposit,
      buyerFeeAmount: fees.buyerFee,
      bankEscrowReference,
      paymentRail: resolvedRail,
      detectedCarrier,
    };
  },
});

// (confirmEscrowFunding was removed: it credited escrow balances from an unauthenticated "webhook"
// without any verified payment. Escrow is funded only via walletCore holds or verified provider
// payments - see payments.ts / walletCore.fundEscrowFromExternalPayment.)


// ═══════════════════════════════════════════════════════════════════════
// 3. COMPLETE VEHICLE INSPECTION (Pre-trip, Post-trip, or Mechanic)
// ═══════════════════════════════════════════════════════════════════════
export const completeVehicleInspection = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    escrowOrderId: v.id("escrow_orders"),
    inspectorId: v.optional(v.string()),
    inspectionType: inspectionTypeEnum,
    odometerReadingKm: v.number(),
    fuelTankPercentage: v.number(),
    photoFrontUrl: v.string(),
    photoRearUrl: v.string(),
    photoLeftSideUrl: v.string(),
    photoRightSideUrl: v.string(),
    photoInteriorUrl: v.string(),
    photoDashboardOdometerUrl: v.string(),
    additionalPhotos: v.optional(v.array(v.string())),
    damagesDetected: v.optional(v.array(v.string())),
    notes: v.optional(v.string()),
    qrTokenHash: v.string(),
    counterpartySignatureUrl: v.optional(v.string()),
  },
  returns: v.object({
    inspectionId: v.string(),
    status: v.string(),
    canReleaseMilestone: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");
    // Only a party to the order (or an admin) can record an inspection: these records are the
    // evidence in damage disputes.
    const who = await requireParticipantOrAdmin(ctx, args.sessionToken, [order.renterOrBuyerId, order.ownerOrSellerId]);
    const inspectorId = who.userId;

    const now = Date.now();
    const hasDamages = args.damagesDetected && args.damagesDetected.length > 0;
    const inspectionStatus = hasDamages ? "COMPLETED_WITH_DAMAGE" : "COMPLETED_CLEAN";

    const inspectionId = await ctx.db.insert("vehicle_inspections", {
      escrowOrderId: order._id,
      inspectorId,
      inspectionType: args.inspectionType,
      odometerReadingKm: args.odometerReadingKm,
      fuelTankPercentage: args.fuelTankPercentage,
      photoFrontUrl: args.photoFrontUrl,
      photoRearUrl: args.photoRearUrl,
      photoLeftSideUrl: args.photoLeftSideUrl,
      photoRightSideUrl: args.photoRightSideUrl,
      photoInteriorUrl: args.photoInteriorUrl,
      photoDashboardOdometerUrl: args.photoDashboardOdometerUrl,
      additionalPhotos: args.additionalPhotos,
      damagesDetected: args.damagesDetected,
      notes: args.notes,
      qrTokenHash: args.qrTokenHash,
      counterpartySignatureUrl: args.counterpartySignatureUrl,
      status: inspectionStatus,
      createdAt: now,
      completedAt: now,
    });

    return {
      inspectionId: inspectionId as string,
      status: inspectionStatus,
      canReleaseMilestone: true,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 4. RELEASE 60% HANDOFF MILESTONE (Owner Handoff / Trip Start)
// ═══════════════════════════════════════════════════════════════════════
export const releaseMilestoneHandoff60 = mutation({
  args: {
    escrowOrderId: v.id("escrow_orders"),
    sessionToken: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    status: v.string(),
    payoutToOwner60: v.number(),
    platformFeeRealized60: v.number(),
  }),
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");

    // Only the paying renter/buyer (confirming handoff) or an admin may release the buyer's funds.
    await requireParticipantOrAdmin(ctx, args.sessionToken, [order.renterOrBuyerId]);

    if (order.status !== "HELD_IN_ESCROW") {
      throw new Error(`Cannot release 60% milestone when order is in status ${order.status}`);
    }

    if (order.orderType !== "VEHICLE_RENTAL") {
      throw new Error("The 60% handoff release only applies to rentals.");
    }

    // Verify pre-trip inspection completed
    const preTrip = await ctx.db
      .query("vehicle_inspections")
      .withIndex("by_order_type", (q: any) =>
        q.eq("escrowOrderId", order._id).eq("inspectionType", "PRE_TRIP_RENTAL")
      )
      .first();

    if (!preTrip) {
      throw new Error("Pre-trip inspection must be submitted and signed before releasing handoff funds");
    }

    const now = Date.now();
    const payoutToOwner60 = round2(order.netMerchantExpected * 0.6);
    const platformFeeRealized60 = round2(order.platformFeeAmount * 0.6);

    // Escrow -> owner (net) + platform fee, atomically, with transactions and ledger entries.
    await releaseHeldFunds(ctx, {
      buyerId: order.renterOrBuyerId,
      recipientId: order.ownerOrSellerId,
      amount: round2(payoutToOwner60 + platformFeeRealized60),
      platformFee: platformFeeRealized60,
      referenceType: REF,
      referenceId: order._id,
      idempotencyKey: `vesc:${order._id}:rel60`,
    });

    await ctx.db.patch(order._id, {
      status: "PARTIALLY_RELEASED",
      split60ReleasedAmount: payoutToOwner60,
      updatedAt: now,
    });

    return {
      success: true,
      status: "PARTIALLY_RELEASED",
      payoutToOwner60,
      platformFeeRealized60,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 5. SETTLE VEHICLE RETURN (40% Owner Release + 100% Deposit Refund)
// ═══════════════════════════════════════════════════════════════════════
export const settleVehicleReturn = mutation({
  args: {
    escrowOrderId: v.id("escrow_orders"),
    damageDeductionCost: v.optional(v.number()),
    sessionToken: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    status: v.string(),
    payoutToOwner40: v.number(),
    damageDeducted: v.number(),
    depositRefundedToRenter: v.number(),
  }),
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");

    // The owner or an admin settles the return. The OWNER cannot pay themselves out of the renter's
    // deposit: a damage claim (> 0) opens a dispute and an administrator decides the amount
    // (adminResolveEscrowDispute damageAwardToOwner). A clean return settles at once.
    const who = await requireParticipantOrAdmin(ctx, args.sessionToken, [order.ownerOrSellerId]);
    if (args.damageDeductionCost !== undefined && (!(args.damageDeductionCost >= 0) || !Number.isFinite(args.damageDeductionCost))) {
      throw new Error("Invalid damage deduction amount.");
    }

    if (order.orderType !== "VEHICLE_RENTAL") {
      throw new Error("Return settlement only applies to rentals.");
    }
    if (order.status !== "PARTIALLY_RELEASED" && order.status !== "POST_INSPECTION_PENDING") {
      throw new Error(`Order cannot be settled in status ${order.status}`);
    }

    const now = Date.now();

    // Remaining base = what the 60% release has not already paid (so rounding never leaks).
    const fee60 = order.split60ReleasedAmount > 0 ? round2(order.platformFeeAmount * 0.6) : 0;
    const payoutToOwner40 = round2(order.netMerchantExpected - order.split60ReleasedAmount);
    const platformFeeRealized40 = round2(order.platformFeeAmount - fee60);

    const requestedDamage = args.damageDeductionCost ?? 0;
    if (!who.isAdmin && requestedDamage > 0) {
      await ctx.db.insert("escrow_disputes", {
        escrowOrderId: order._id,
        openedByUserId: who.userId,
        reason: "Damage claim on vehicle return (owner).",
        claimedRepairCost: round2(Math.min(requestedDamage, order.refundableDepositAmount)),
        evidenceMediaUrls: [],
        status: "OPENED",
        openedAt: now,
      });
      await ctx.db.patch(order._id, { status: "DISPUTED", updatedAt: now });
      await ctx.db.insert("user_notifications", {
        userId: order.renterOrBuyerId as string,
        targetType: "single_user",
        title: "Damage claim opened",
        body: `The owner claimed damage on ${order.orderCode}. Your deposit stays protected until Vektolux decides.`,
        read: false,
        createdAt: now,
      });
      return { success: true, status: "DISPUTED", payoutToOwner40: 0, damageDeducted: 0, depositRefundedToRenter: 0 };
    }
    const actualDamageDeduction = round2(Math.min(requestedDamage, order.refundableDepositAmount));
    const depositRefundToRenter = round2(order.refundableDepositAmount - actualDamageDeduction);

    // Owner: remaining 40% + awarded damage compensation. Platform: its remaining fee.
    await releaseHeldFunds(ctx, {
      buyerId: order.renterOrBuyerId,
      recipientId: order.ownerOrSellerId,
      amount: round2(payoutToOwner40 + platformFeeRealized40 + actualDamageDeduction),
      platformFee: platformFeeRealized40,
      referenceType: REF,
      referenceId: order._id,
      idempotencyKey: `vesc:${order._id}:settle`,
    });
    // Renter: the rest of the deposit goes back to AVAILABLE funds.
    if (depositRefundToRenter > 0) {
      await refundHeldFunds(ctx, {
        userId: order.renterOrBuyerId,
        amount: depositRefundToRenter,
        referenceType: REF,
        referenceId: order._id,
        idempotencyKey: `vesc:${order._id}:deposit`,
      });
    }

    await ctx.db.patch(order._id, {
      status: "SETTLED",
      split40ReleasedAmount: payoutToOwner40,
      depositRefundedAmount: depositRefundToRenter,
      depositDamageDeductedAmount: actualDamageDeduction,
      updatedAt: now,
    });

    return {
      success: true,
      status: "SETTLED",
      payoutToOwner40,
      damageDeducted: actualDamageDeduction,
      depositRefundedToRenter: depositRefundToRenter,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 6. UPLOAD SLRSA OWNERSHIP DOCUMENTS (Vehicle Purchase)
// ═══════════════════════════════════════════════════════════════════════
export const uploadSlrsaDocuments = mutation({
  args: {
    escrowOrderId: v.id("escrow_orders"),
    vehicleVinOrChassis: v.string(),
    slrsaLicensePlate: v.string(),
    logbookBlueBookFrontUrl: v.string(),
    logbookBlueBookEndorsementUrl: v.string(),
    slrsaFormCUrl: v.string(),
    buyerNationalIdUrl: v.string(),
    sellerNationalIdUrl: v.string(),
    sessionToken: v.optional(v.string()),
  },
  returns: v.string(),
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");
    await requireParticipantOrAdmin(ctx, args.sessionToken, [order.renterOrBuyerId, order.ownerOrSellerId]);

    const now = Date.now();
    const recordId = await ctx.db.insert("slrsa_transfer_records", {
      escrowOrderId: order._id,
      vehicleVinOrChassis: args.vehicleVinOrChassis,
      slrsaLicensePlate: args.slrsaLicensePlate,
      logbookBlueBookFrontUrl: args.logbookBlueBookFrontUrl,
      logbookBlueBookEndorsementUrl: args.logbookBlueBookEndorsementUrl,
      slrsaFormCUrl: args.slrsaFormCUrl,
      buyerNationalIdUrl: args.buyerNationalIdUrl,
      sellerNationalIdUrl: args.sellerNationalIdUrl,
      isVerified: false,
      submittedAt: now,
    });

    await ctx.db.patch(order._id, {
      purchaseStage: "SLRSA_DOCS_SUBMITTED",
      updatedAt: now,
    });

    return recordId as string;
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 7. CONFIRM SLRSA TRANSFER & DISBURSE SALE PROCEEDS (Admin Only)
// ═══════════════════════════════════════════════════════════════════════
export const confirmSlrsaTransfer = mutation({
  args: {
    escrowOrderId: v.id("escrow_orders"),
    verificationNotes: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    // 0. Verify admin authorization
    const callerId = await resolveCallerUser(ctx, undefined, args.sessionToken);
    const caller = await ctx.db.get(callerId);
    if (!caller || caller.role !== "admin") {
      throw new Error("Unauthorized: Only platform administrators can confirm SLRSA vehicle transfers.");
    }

    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");
    if (order.orderType !== "VEHICLE_PURCHASE") {
      throw new Error("SLRSA transfer verification only applies to Vehicle Purchases");
    }

    if (order.status !== "HELD_IN_ESCROW" && order.status !== "ESCROW_LOCKED") {
      throw new Error(`Sale proceeds cannot be released for an order in status ${order.status}.`);
    }

    const slrsaRecord = await ctx.db
      .query("slrsa_transfer_records")
      .withIndex("by_order", (q: any) => q.eq("escrowOrderId", order._id))
      .first();

    if (!slrsaRecord) throw new Error("No SLRSA records submitted for this order");

    const now = Date.now();
    await ctx.db.patch(slrsaRecord._id, {
      isVerified: true,
      verificationNotes: args.verificationNotes,
      verifiedAt: now,
    });

    // Buyer escrow -> seller (net) + platform fee. Idempotent: the same sale can never pay twice.
    await releaseHeldFunds(ctx, {
      buyerId: order.renterOrBuyerId,
      recipientId: order.ownerOrSellerId,
      amount: order.grossEscrowAmount,
      platformFee: order.platformFeeAmount,
      referenceType: REF,
      referenceId: order._id,
      idempotencyKey: `vesc:${order._id}:sale`,
    });

    await ctx.db.patch(order._id, { status: "SETTLED", purchaseStage: "SETTLED", updatedAt: now });
    return true;
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 7B. BUYER INSPECTION APPROVAL & DEAL ESCROW RELEASE
// ═══════════════════════════════════════════════════════════════════════
export const releaseDealEscrowFunds = mutation({
  args: {
    escrowOrderId: v.id("escrow_orders"),
    buyerPinOrConfirmation: v.optional(v.string()),
    notes: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    status: v.string(),
    amountReleased: v.number(),
    platformFee: v.number(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    const currentUserId = await resolveCallerUser(ctx, undefined, args.sessionToken);
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");

    // Only buyer or admin can release funds
    if (order.renterOrBuyerId !== currentUserId) {
      const user = await ctx.db.get(currentUserId);
      if (user?.role !== "admin") {
        throw new Error("Only the buyer or an admin can approve inspection and release deal funds.");
      }
    }

    // Vehicle PURCHASES only. (Rentals pay out in two stages — handoff and return — and releasing
    // a rental here after the 60% payout would have paid the owner twice.)
    if (order.orderType !== "VEHICLE_PURCHASE") {
      throw new Error("This release applies to vehicle purchases. Rentals are released at handoff and return.");
    }
    if (order.status !== "HELD_IN_ESCROW" && order.status !== "ESCROW_LOCKED") {
      throw new Error(`Cannot release funds for order currently in status: ${order.status}`);
    }

    const now = Date.now();
    const releaseAmount = order.netMerchantExpected;

    await releaseHeldFunds(ctx, {
      buyerId: order.renterOrBuyerId,
      recipientId: order.ownerOrSellerId,
      amount: order.grossEscrowAmount,
      platformFee: order.platformFeeAmount,
      referenceType: REF,
      referenceId: order._id,
      idempotencyKey: `vesc:${order._id}:sale`,
    });

    await ctx.db.patch(order._id, {
      status: "SETTLED",
      purchaseStage: "SETTLED",
      split60ReleasedAmount: releaseAmount,
      updatedAt: now,
    });

    await ctx.db.insert("user_notifications", {
      userId: order.ownerOrSellerId as string,
      targetType: "single_user",
      title: "Escrow payment released",
      body: `The buyer approved ${order.orderCode}. SLE ${releaseAmount.toFixed(2)} was credited to your available balance.`,
      read: false,
      createdAt: now,
    });
    await ctx.db.insert("user_notifications", {
      userId: order.renterOrBuyerId as string,
      targetType: "single_user",
      title: "Escrow settled",
      body: `You approved and released payment for ${order.orderCode}.`,
      read: false,
      createdAt: now,
    });

    return {
      success: true,
      status: "SETTLED",
      amountReleased: releaseAmount,
      platformFee: order.platformFeeAmount,
      message: "Deal escrow funds successfully released to seller.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 8. RAISE ESCROW DISPUTE
// ═══════════════════════════════════════════════════════════════════════
export const raiseEscrowDispute = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    escrowOrderId: v.id("escrow_orders"),
    reason: v.string(),
    claimedRepairCost: v.number(),
    evidenceMediaUrls: v.array(v.string()),
  },
  returns: v.string(),
  handler: async (ctx, args) => {
    const currentUserId = await resolveCallerUser(ctx, undefined, args.sessionToken);

    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");
    if (order.renterOrBuyerId !== currentUserId && order.ownerOrSellerId !== currentUserId) {
      throw new Error("Unauthorized: You are not a party to this order.");
    }
    if (order.status !== "HELD_IN_ESCROW" && order.status !== "ESCROW_LOCKED" && order.status !== "PARTIALLY_RELEASED") {
      throw new Error(`A dispute cannot be opened for an order in status ${order.status}.`);
    }

    const now = Date.now();
    const disputeId = await ctx.db.insert("escrow_disputes", {
      escrowOrderId: order._id,
      openedByUserId: currentUserId,
      reason: args.reason,
      claimedRepairCost: args.claimedRepairCost,
      evidenceMediaUrls: args.evidenceMediaUrls,
      status: "OPENED",
      openedAt: now,
    });

    await ctx.db.patch(order._id, {
      status: "DISPUTED",
      updatedAt: now,
    });

    return disputeId as string;
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 8B. ADMIN DISPUTE RESOLUTION (refund buyer / release seller) — audited
// ═══════════════════════════════════════════════════════════════════════
export const adminResolveEscrowDispute = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    escrowOrderId: v.id("escrow_orders"),
    resolution: v.union(v.literal("refund_buyer"), v.literal("release_seller")),
    notes: v.string(),
    // Rentals, release_seller only: part of the refundable deposit awarded to the owner for damage
    // (capped at the deposit; the rest of the deposit goes back to the renter).
    damageAwardToOwner: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    if (args.notes.trim().length < 5) throw new Error("Resolution notes are required.");
    if (args.damageAwardToOwner !== undefined && !(Number.isFinite(args.damageAwardToOwner) && args.damageAwardToOwner >= 0)) {
      throw new Error("Invalid damage award.");
    }
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");
    if (order.status !== "DISPUTED") throw new Error("Only a disputed order can be resolved here.");

    // What is still held for this order: gross minus whatever the 60% handoff already paid out.
    const paid60 = order.split60ReleasedAmount > 0
      ? round2(order.split60ReleasedAmount + order.platformFeeAmount * 0.6)
      : 0;
    const remaining = round2(order.grossEscrowAmount - (order.orderType === "VEHICLE_RENTAL" ? paid60 : 0));
    if (!(remaining > 0)) throw new Error("Nothing is held for this order.");
    const now = Date.now();
    const deposit = order.orderType === "VEHICLE_RENTAL" ? order.refundableDepositAmount : 0;
    if ((args.damageAwardToOwner ?? 0) > 0 && (args.resolution !== "release_seller" || deposit <= 0)) {
      throw new Error("A damage award applies only when releasing a rental to the owner.");
    }
    const award = round2(Math.min(args.damageAwardToOwner ?? 0, deposit));

    if (args.resolution === "refund_buyer") {
      await refundHeldFunds(ctx, {
        userId: order.renterOrBuyerId,
        amount: remaining,
        referenceType: REF,
        referenceId: order._id,
        idempotencyKey: `vesc:${order._id}:dispute-refund`,
      });
    } else {
      const baseRemaining = round2(remaining - deposit);
      const fee = order.orderType === "VEHICLE_RENTAL"
        ? round2(order.platformFeeAmount - (paid60 > 0 ? round2(order.platformFeeAmount * 0.6) : 0))
        : order.platformFeeAmount;
      if (round2(baseRemaining + award) > 0) {
        await releaseHeldFunds(ctx, {
          buyerId: order.renterOrBuyerId,
          recipientId: order.ownerOrSellerId,
          amount: round2(baseRemaining + award),
          platformFee: Math.min(fee, Math.max(0, baseRemaining)),
          referenceType: REF,
          referenceId: order._id,
          idempotencyKey: `vesc:${order._id}:dispute-release`,
        });
      }
      if (round2(deposit - award) > 0) {
        await refundHeldFunds(ctx, {
          userId: order.renterOrBuyerId,
          amount: round2(deposit - award),
          referenceType: REF,
          referenceId: order._id,
          idempotencyKey: `vesc:${order._id}:dispute-deposit`,
        });
      }
    }

    await ctx.db.patch(order._id, {
      status: args.resolution === "refund_buyer" ? "REFUNDED" : "SETTLED",
      updatedAt: now,
    });
    const disputes = await ctx.db
      .query("escrow_disputes")
      .withIndex("by_order", (q: any) => q.eq("escrowOrderId", order._id))
      .collect();
    for (const d of disputes) {
      if (d.status === "OPENED" || d.status === "UNDER_REVIEW") {
        await ctx.db.patch(d._id, {
          status: "RESOLVED_ADJUDICATED",
          approvedRepairCost: award,
          adjudicatedByAdminId: adminId,
          adjudicationNotes: args.notes.trim().slice(0, 1000),
          resolvedAt: now,
        });
      }
    }
    for (const uid of [order.renterOrBuyerId, order.ownerOrSellerId]) {
      await ctx.db.insert("user_notifications", {
        userId: uid as string,
        targetType: "single_user",
        title: "Dispute resolved",
        body: `The dispute on ${order.orderCode} was resolved by an administrator (${args.resolution === "refund_buyer" ? "buyer refunded" : "released to seller"}).`,
        read: false,
        createdAt: now,
      });
    }
    return { success: true, status: args.resolution === "refund_buyer" ? "REFUNDED" : "SETTLED", amount: remaining };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 9. QUERIES: REAL-TIME ESCROW ORDER TRACKING & ADMIN OVERSIGHT
// ═══════════════════════════════════════════════════════════════════════
export const getMyEscrowOrders = query({
  args: {
    sessionToken: v.optional(v.string()),
    userId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = await resolveCallerUser(ctx, args.userId, args.sessionToken);

    // Orders where user is renter/buyer or owner/seller
    const asRenter = await ctx.db
      .query("escrow_orders")
      .withIndex("by_renter_or_buyer", (q: any) => q.eq("renterOrBuyerId", userId))
      .collect();

    const asOwner = await ctx.db
      .query("escrow_orders")
      .withIndex("by_owner_or_seller", (q: any) => q.eq("ownerOrSellerId", userId))
      .collect();

    // Merge and sort newest first
    const map = new Map();
    for (const o of [...asRenter, ...asOwner]) {
      map.set(o._id, o);
    }
    const all = Array.from(map.values()).sort((a, b) => b.createdAt - a.createdAt);

    // Hydrate vehicle details
    const result = [];
    for (const o of all) {
      const veh: any = await ctx.db.get(o.vehicleListingId);
      result.push({
        ...o,
        vehicleTitle: veh?.title ?? "Commercial Vehicle",
        vehicleCategory: veh?.category ?? "commercial",
        vehicleImage: veh?.images?.[0] ?? "",
        isOwner: o.ownerOrSellerId === userId,
      });
    }
    return result;
  },
});

export const getEscrowOrderById = query({
  args: { escrowOrderId: v.id("escrow_orders"), sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) return null;
    await requireParticipantOrAdmin(ctx, args.sessionToken, [order.renterOrBuyerId, order.ownerOrSellerId]);

    const vehicle: any = await ctx.db.get(order.vehicleListingId);
    const renter = await ctx.db.get(order.renterOrBuyerId);
    const owner = await ctx.db.get(order.ownerOrSellerId);

    const inspections = await ctx.db
      .query("vehicle_inspections")
      .withIndex("by_order", (q: any) => q.eq("escrowOrderId", order._id))
      .collect();

    const slrsa = await ctx.db
      .query("slrsa_transfer_records")
      .withIndex("by_order", (q: any) => q.eq("escrowOrderId", order._id))
      .first();

    const disputes = await ctx.db
      .query("escrow_disputes")
      .withIndex("by_order", (q: any) => q.eq("escrowOrderId", order._id))
      .collect();

    const ledger = await ctx.db
      .query("ledger_transactions")
      .withIndex("by_order", (q: any) => q.eq("escrowOrderId", order._id))
      .collect();

    return {
      order,
      vehicle,
      renterName: renter?.name ?? "Client",
      renterPhone: renter?.phone ?? "",
      ownerName: owner?.name ?? "Merchant",
      ownerPhone: owner?.phone ?? "",
      inspections,
      slrsa,
      disputes,
      ledgerCount: ledger.length,
    };
  },
});

export const getAdminEscrowSummary = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const allOrders = await ctx.db.query("escrow_orders").collect();

    let totalInEscrow = 0;
    let totalSettledVolume = 0;
    let activeRentalCount = 0;
    let pendingInspectionCount = 0;
    let disputedCount = 0;

    for (const o of allOrders) {
      if (o.status === "HELD_IN_ESCROW" || o.status === "PARTIALLY_RELEASED") {
        totalInEscrow += o.grossEscrowAmount - o.split60ReleasedAmount;
        activeRentalCount++;
      } else if (o.status === "SETTLED") {
        totalSettledVolume += o.grossEscrowAmount;
      } else if (o.status === "DISPUTED") {
        disputedCount++;
      } else if (o.status === "POST_INSPECTION_PENDING") {
        pendingInspectionCount++;
      }
    }

    return {
      totalOrders: allOrders.length,
      totalInEscrow,
      totalSettledVolume,
      activeRentalCount,
      pendingInspectionCount,
      disputedCount,
      // Admin-only (this query requires an admin session): most recent orders for the dashboard.
      recentOrders: allOrders.slice(-50).reverse(),
    };
  },
});
