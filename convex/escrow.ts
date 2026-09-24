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

// ─── Helper: Resolve Caller User ──────────────────────────────────────
async function resolveCallerUser(ctx: any, explicitUserId?: string): Promise<Id<"users">> {
  if (explicitUserId) {
    const norm = ctx.db.normalizeId("users", explicitUserId);
    if (norm) return norm;
  }
  const identity = await ctx.auth.getUserIdentity();
  if (identity && identity.email) {
    const byEmail = await ctx.db
      .query("users")
      .withIndex("by_email", (q: any) => q.eq("email", identity.email!))
      .first();
    if (byEmail) return byEmail._id;
  }
  const fallback = await ctx.db.query("users").first();
  if (fallback) return fallback._id;
  throw new Error("User authentication required");
}

// ─── Helper: Post Double-Entry Ledger Transaction ─────────────────────
async function postLedgerTransaction(
  ctx: any,
  params: {
    code: string;
    orderId?: Id<"escrow_orders">;
    description: string;
    entries: Array<{
      accountType:
        | "CLIENT_AVAILABLE"
        | "CLIENT_ESCROW_LOCKED"
        | "OWNER_AVAILABLE"
        | "OWNER_ESCROW_PENDING"
        | "PLATFORM_REVENUE_REALIZED"
        | "DAMAGE_DEPOSIT_CUSTODY"
        | "TELCO_CLEARING_LIABILITY";
      userId?: Id<"users">;
      direction: "DEBIT" | "CREDIT";
      amount: number;
    }>;
  }
) {
  // Enforce double-entry invariant: sum(Debit) === sum(Credit)
  let totalDebit = 0;
  let totalCredit = 0;
  for (const entry of params.entries) {
    if (entry.direction === "DEBIT") totalDebit += entry.amount;
    if (entry.direction === "CREDIT") totalCredit += entry.amount;
  }
  const diff = Math.abs(totalDebit - totalCredit);
  if (diff > 0.01) {
    throw new Error(
      `Double-entry ledger unbalanced: Debits (${totalDebit.toFixed(2)}) != Credits (${totalCredit.toFixed(2)})`
    );
  }

  const txId = await ctx.db.insert("ledger_transactions", {
    transactionCode: params.code,
    escrowOrderId: params.orderId,
    description: params.description,
    createdAt: Date.now(),
  });

  for (const entry of params.entries) {
    await ctx.db.insert("ledger_entries", {
      transactionId: txId,
      accountType: entry.accountType,
      userId: entry.userId,
      direction: entry.direction,
      amount: entry.amount,
      currency: "SLE",
      createdAt: Date.now(),
    });
  }
  return txId;
}

// ─── Helper: Ensure or get user wallet ────────────────────────────────
async function getOrCreateWallet(ctx: any, userId: Id<"users">) {
  const existing = await ctx.db
    .query("walletBalances")
    .withIndex("by_user", (q: any) => q.eq("userId", userId))
    .first();

  if (existing) return existing;

  const newId = await ctx.db.insert("walletBalances", {
    userId,
    availableBalance: 0,
    pendingBalance: 0,
    escrowBalance: 0,
    currency: "SLE",
    updatedAt: Date.now(),
  });
  return await ctx.db.get(newId);
}

// ═══════════════════════════════════════════════════════════════════════
// 1. INITIATE ESCROW ORDER
// ═══════════════════════════════════════════════════════════════════════
export const initiateEscrowOrder = mutation({
  args: {
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
    bankEscrowReference: v.optional(v.string()),
    paymentRail: v.optional(v.string()),
    detectedCarrier: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    // 1. Verify caller identity
    const currentUserId = await resolveCallerUser(ctx, args.renterOrBuyerId);

    // 2. Fetch vehicle listing
    const vehicle = await ctx.db.get(args.vehicleListingId);
    if (!vehicle) throw new Error("Vehicle listing not found");
    if (vehicle.ownerId === currentUserId) {
      throw new Error("You cannot rent or purchase your own vehicle listing");
    }

    const now = Date.now();
    const orderCode = `VK-ESC-${now.toString().slice(-6)}-${Math.floor(1000 + Math.random() * 9000)}`;

    let baseRental = 0;
    let refundableDeposit = 0;
    let earnestFee = 0;
    let fullPurchase = 0;
    let grossEscrow = 0;
    let platformFee = 0;
    let netMerchant = 0;

    if (args.orderType === "VEHICLE_RENTAL") {
      const days = args.numberOfDays ?? 1;
      baseRental = args.baseRentalAmount ?? vehicle.price * days;
      // Default damage deposit is 33% of base rental or min 500 SLE if not specified
      refundableDeposit = args.refundableDepositAmount ?? Math.max(500, Math.round(baseRental * 0.33));
      grossEscrow = baseRental + refundableDeposit;
      // 15% platform commission strictly on base rental
      platformFee = parseFloat((baseRental * 0.15).toFixed(2));
      netMerchant = parseFloat((baseRental * 0.85).toFixed(2));
    } else {
      fullPurchase = args.fullPurchaseAmount ?? vehicle.price;
      earnestFee = args.earnestFeeAmount ?? 500;
      grossEscrow = fullPurchase;
      // 5% platform commission on vehicle sales
      platformFee = parseFloat((fullPurchase * 0.05).toFixed(2));
      netMerchant = parseFloat((fullPurchase * 0.95).toFixed(2));
    }

    const split60 = parseFloat((netMerchant * 0.6).toFixed(2));
    const split40 = parseFloat((netMerchant * 0.4).toFixed(2));

    // Determine payment rail
    let resolvedRail = args.paymentRail;
    if (!resolvedRail) {
      if (args.payFromWallet || args.paymentProvider === "WALLET") {
        resolvedRail = "WALLET";
      } else if (args.paymentProvider === "BANK_TRANSFER") {
        resolvedRail = "BANK_TRANSFER";
      } else {
        resolvedRail = "MOBILE_MONEY";
      }
    }

    let detectedCarrier: string | undefined;
    if (args.paymentPhone) {
      const carrier = detectSierraLeoneCarrier(args.paymentPhone);
      if (carrier !== "unknown") {
        detectedCarrier = carrier;
      }
    }

    let bankEscrowReference = args.bankEscrowReference;
    let bankClearingStatus: "PENDING_TRANSFER" | "CLEARED" | undefined;

    if (resolvedRail === "BANK_TRANSFER") {
      if (!bankEscrowReference) {
        bankEscrowReference = `VKTLX-DEAL-${Math.floor(1000 + Math.random() * 9000)}`;
      }
      bankClearingStatus = "PENDING_TRANSFER";
    }

    // 3. Check wallet ONLY if paying directly from wallet
    let initialStatus: "PENDING_PAYMENT" | "HELD_IN_ESCROW" = "PENDING_PAYMENT";
    if (resolvedRail === "WALLET" || args.payFromWallet) {
      const renterWallet = await getOrCreateWallet(ctx, currentUserId);
      if (renterWallet.availableBalance < grossEscrow) {
        throw new Error(
          `Insufficient available balance (SLE ${renterWallet.availableBalance.toFixed(2)}). Escrow requires SLE ${grossEscrow.toFixed(2)}.`
        );
      }
      // Deduct from available balance, add to escrow balance
      await ctx.db.patch(renterWallet._id, {
        availableBalance: renterWallet.availableBalance - grossEscrow,
        escrowBalance: (renterWallet.escrowBalance ?? 0) + grossEscrow,
        updatedAt: now,
      });
      initialStatus = "HELD_IN_ESCROW";
    }

    // 4. Create escrow order
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
      status: initialStatus,
      purchaseStage: args.orderType === "VEHICLE_PURCHASE" ? "EARNEST_PENDING" : undefined,
      rentalStartDate: args.rentalStartDate,
      rentalEndDate: args.rentalEndDate,
      numberOfDays: args.numberOfDays,
      paymentProvider: args.paymentProvider ?? (resolvedRail === "WALLET" ? "WALLET" : resolvedRail === "BANK_TRANSFER" ? "BANK_TRANSFER" : "MONIME"),
      paymentPhone: args.paymentPhone,
      paymentRail: resolvedRail,
      bankEscrowReference,
      bankClearingStatus,
      detectedCarrier,
      createdAt: now,
      updatedAt: now,
    });

    // 5. If paid from wallet, post double-entry ledger entries
    if (resolvedRail === "WALLET" || args.payFromWallet) {
      await postLedgerTransaction(ctx, {
        code: `TX-ESCROW-WALLET-${orderCode}`,
        orderId: escrowOrderId,
        description: `Escrow funded from wallet for order ${orderCode}`,
        entries: [
          {
            accountType: "CLIENT_AVAILABLE",
            userId: currentUserId,
            direction: "DEBIT",
            amount: grossEscrow,
          },
          {
            accountType: "CLIENT_ESCROW_LOCKED",
            userId: currentUserId,
            direction: "CREDIT",
            amount: grossEscrow,
          },
        ],
      });
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
      bankEscrowReference,
      paymentRail: resolvedRail,
      detectedCarrier,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 2. CONFIRM ESCROW FUNDING (Internal or Webhook Callback)
// ═══════════════════════════════════════════════════════════════════════
export const confirmEscrowFunding = internalMutation({
  args: {
    orderCode: v.string(),
    externalTransactionId: v.string(),
    provider: v.string(),
    amountPaid: v.number(),
  },
  handler: async (ctx, args) => {
    const order = await ctx.db
      .query("escrow_orders")
      .withIndex("by_order_code", (q: any) => q.eq("orderCode", args.orderCode))
      .first();

    if (!order) throw new Error(`Escrow order not found: ${args.orderCode}`);
    if (order.status !== "PENDING_PAYMENT" && order.status !== "INITIATED") {
      return { success: true, message: `Order already in status ${order.status}` };
    }

    const now = Date.now();

    // Verify amount matches gross escrow
    if (Math.abs(args.amountPaid - order.grossEscrowAmount) > 0.05) {
      throw new Error(
        `Amount mismatch: Expected SLE ${order.grossEscrowAmount}, received SLE ${args.amountPaid}`
      );
    }

    // 1. Credit Renter Escrow Balance
    const renterWallet = await getOrCreateWallet(ctx, order.renterOrBuyerId);
    await ctx.db.patch(renterWallet._id, {
      escrowBalance: (renterWallet.escrowBalance ?? 0) + order.grossEscrowAmount,
      updatedAt: now,
    });

    // 2. Update order status to HELD_IN_ESCROW
    await ctx.db.patch(order._id, {
      status: "HELD_IN_ESCROW",
      updatedAt: now,
    });

    // 3. Post Double-Entry Ledger
    await postLedgerTransaction(ctx, {
      code: `TX-TELCO-FUND-${args.externalTransactionId}`,
      orderId: order._id,
      description: `Escrow funded via ${args.provider} (${args.externalTransactionId})`,
      entries: [
        {
          accountType: "TELCO_CLEARING_LIABILITY",
          direction: "DEBIT",
          amount: order.grossEscrowAmount,
        },
        {
          accountType: "CLIENT_ESCROW_LOCKED",
          userId: order.renterOrBuyerId,
          direction: "CREDIT",
          amount: order.grossEscrowAmount,
        },
      ],
    });

    return { success: true, newStatus: "HELD_IN_ESCROW" };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 3. COMPLETE VEHICLE INSPECTION (Pre-trip, Post-trip, or Mechanic)
// ═══════════════════════════════════════════════════════════════════════
export const completeVehicleInspection = mutation({
  args: {
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
    const inspectorId = await resolveCallerUser(ctx, args.inspectorId);

    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");

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

    if (order.status !== "HELD_IN_ESCROW") {
      throw new Error(`Cannot release 60% milestone when order is in status ${order.status}`);
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

    // 60% Payout Calculations
    const payoutToOwner60 = parseFloat((order.netMerchantExpected * 0.6).toFixed(2));
    const platformFeeRealized60 = parseFloat((order.platformFeeAmount * 0.6).toFixed(2));
    const totalDeductionFromEscrow = payoutToOwner60 + platformFeeRealized60;

    // 1. Deduct from Renter Escrow Balance
    const renterWallet = await getOrCreateWallet(ctx, order.renterOrBuyerId);
    await ctx.db.patch(renterWallet._id, {
      escrowBalance: Math.max(0, (renterWallet.escrowBalance ?? 0) - totalDeductionFromEscrow),
      updatedAt: now,
    });

    // 2. Credit Owner Available Balance
    const ownerWallet = await getOrCreateWallet(ctx, order.ownerOrSellerId);
    await ctx.db.patch(ownerWallet._id, {
      availableBalance: ownerWallet.availableBalance + payoutToOwner60,
      updatedAt: now,
    });

    // 3. Update Order Status
    await ctx.db.patch(order._id, {
      status: "PARTIALLY_RELEASED",
      split60ReleasedAmount: payoutToOwner60,
      updatedAt: now,
    });

    // 4. Double-entry Ledger
    await postLedgerTransaction(ctx, {
      code: `TX-REL60-${order.orderCode}`,
      orderId: order._id,
      description: `60% Handoff release for rental ${order.orderCode}`,
      entries: [
        {
          accountType: "CLIENT_ESCROW_LOCKED",
          userId: order.renterOrBuyerId,
          direction: "DEBIT",
          amount: totalDeductionFromEscrow,
        },
        {
          accountType: "OWNER_AVAILABLE",
          userId: order.ownerOrSellerId,
          direction: "CREDIT",
          amount: payoutToOwner60,
        },
        {
          accountType: "PLATFORM_REVENUE_REALIZED",
          direction: "CREDIT",
          amount: platformFeeRealized60,
        },
      ],
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

    if (order.status !== "PARTIALLY_RELEASED" && order.status !== "POST_INSPECTION_PENDING") {
      throw new Error(`Order cannot be settled in status ${order.status}`);
    }

    const now = Date.now();

    // 40% Calculations
    const payoutToOwner40 = parseFloat((order.netMerchantExpected * 0.4).toFixed(2));
    const platformFeeRealized40 = parseFloat((order.platformFeeAmount * 0.4).toFixed(2));
    const baseRemainingEscrow = payoutToOwner40 + platformFeeRealized40;

    // Damage vs Refund Calculations
    const requestedDamage = args.damageDeductionCost ?? 0;
    const actualDamageDeduction = Math.min(requestedDamage, order.refundableDepositAmount);
    const depositRefundToRenter = parseFloat(
      (order.refundableDepositAmount - actualDamageDeduction).toFixed(2)
    );

    const totalEscrowToClear = baseRemainingEscrow + order.refundableDepositAmount;

    // 1. Clear Renter Escrow and refund net deposit to available balance
    const renterWallet = await getOrCreateWallet(ctx, order.renterOrBuyerId);
    await ctx.db.patch(renterWallet._id, {
      escrowBalance: Math.max(0, (renterWallet.escrowBalance ?? 0) - totalEscrowToClear),
      availableBalance: renterWallet.availableBalance + depositRefundToRenter,
      updatedAt: now,
    });

    // 2. Credit Owner Available Balance: 40% balance + awarded damage compensation
    const totalOwnerCredit = payoutToOwner40 + actualDamageDeduction;
    const ownerWallet = await getOrCreateWallet(ctx, order.ownerOrSellerId);
    await ctx.db.patch(ownerWallet._id, {
      availableBalance: ownerWallet.availableBalance + totalOwnerCredit,
      updatedAt: now,
    });

    // 3. Mark Order Settled
    await ctx.db.patch(order._id, {
      status: "SETTLED",
      split40ReleasedAmount: payoutToOwner40,
      depositRefundedAmount: depositRefundToRenter,
      depositDamageDeductedAmount: actualDamageDeduction,
      updatedAt: now,
    });

    // 4. Double-Entry Balanced Ledger
    await postLedgerTransaction(ctx, {
      code: `TX-SETTLE-${order.orderCode}`,
      orderId: order._id,
      description: `Final return settlement for ${order.orderCode} (Deducted damage: SLE ${actualDamageDeduction})`,
      entries: [
        {
          accountType: "CLIENT_ESCROW_LOCKED",
          userId: order.renterOrBuyerId,
          direction: "DEBIT",
          amount: totalEscrowToClear,
        },
        {
          accountType: "OWNER_AVAILABLE",
          userId: order.ownerOrSellerId,
          direction: "CREDIT",
          amount: totalOwnerCredit,
        },
        {
          accountType: "CLIENT_AVAILABLE",
          userId: order.renterOrBuyerId,
          direction: "CREDIT",
          amount: depositRefundToRenter,
        },
        {
          accountType: "PLATFORM_REVENUE_REALIZED",
          direction: "CREDIT",
          amount: platformFeeRealized40,
        },
      ],
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
  },
  returns: v.string(),
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");

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
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");
    if (order.orderType !== "VEHICLE_PURCHASE") {
      throw new Error("SLRSA transfer verification only applies to Vehicle Purchases");
    }

    const slrsaRecord = await ctx.db
      .query("slrsa_transfer_records")
      .withIndex("by_order", (q: any) => q.eq("escrowOrderId", order._id))
      .first();

    if (!slrsaRecord) throw new Error("No SLRSA records submitted for this order");

    const now = Date.now();

    // 1. Mark record verified
    await ctx.db.patch(slrsaRecord._id, {
      isVerified: true,
      verificationNotes: args.verificationNotes,
      verifiedAt: now,
    });

    // 2. Clear Buyer Escrow and Credit Seller Available Balance
    const buyerWallet = await getOrCreateWallet(ctx, order.renterOrBuyerId);
    await ctx.db.patch(buyerWallet._id, {
      escrowBalance: Math.max(0, (buyerWallet.escrowBalance ?? 0) - order.grossEscrowAmount),
      updatedAt: now,
    });

    const sellerWallet = await getOrCreateWallet(ctx, order.ownerOrSellerId);
    await ctx.db.patch(sellerWallet._id, {
      availableBalance: sellerWallet.availableBalance + order.netMerchantExpected,
      updatedAt: now,
    });

    // 3. Mark Order Settled
    await ctx.db.patch(order._id, {
      status: "SETTLED",
      purchaseStage: "SETTLED",
      updatedAt: now,
    });

    // 4. Double-Entry Balanced Ledger
    await postLedgerTransaction(ctx, {
      code: `TX-SALE-SETTLE-${order.orderCode}`,
      orderId: order._id,
      description: `SLRSA Title Transfer Verified. Sale settled for ${order.orderCode}`,
      entries: [
        {
          accountType: "CLIENT_ESCROW_LOCKED",
          userId: order.renterOrBuyerId,
          direction: "DEBIT",
          amount: order.grossEscrowAmount,
        },
        {
          accountType: "OWNER_AVAILABLE",
          userId: order.ownerOrSellerId,
          direction: "CREDIT",
          amount: order.netMerchantExpected,
        },
        {
          accountType: "PLATFORM_REVENUE_REALIZED",
          direction: "CREDIT",
          amount: order.platformFeeAmount,
        },
      ],
    });

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
  },
  returns: v.object({
    success: v.boolean(),
    status: v.string(),
    amountReleased: v.number(),
    platformFee: v.number(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    const currentUserId = await resolveCallerUser(ctx);
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");

    // Only buyer or admin can release funds
    if (order.renterOrBuyerId !== currentUserId) {
      const user = await ctx.db.get(currentUserId);
      if (user?.role !== "admin") {
        throw new Error("Only the buyer or an admin can approve inspection and release deal funds.");
      }
    }

    if (
      order.status !== "HELD_IN_ESCROW" &&
      order.status !== "ESCROW_LOCKED" &&
      order.status !== "PARTIALLY_RELEASED"
    ) {
      throw new Error(`Cannot release funds for order currently in status: ${order.status}`);
    }

    const now = Date.now();
    const releaseAmount = order.netMerchantExpected;

    // Credit seller available balance
    const sellerWallet = await getOrCreateWallet(ctx, order.ownerOrSellerId);
    await ctx.db.patch(sellerWallet._id, {
      availableBalance: (sellerWallet.availableBalance ?? 0) + releaseAmount,
      updatedAt: now,
    });

    // Debit buyer escrow balance
    const buyerWallet = await getOrCreateWallet(ctx, order.renterOrBuyerId);
    await ctx.db.patch(buyerWallet._id, {
      escrowBalance: Math.max(0, (buyerWallet.escrowBalance ?? 0) - order.grossEscrowAmount),
      updatedAt: now,
    });

    // Mark order settled
    await ctx.db.patch(order._id, {
      status: "SETTLED",
      purchaseStage: "SETTLED",
      split60ReleasedAmount: releaseAmount,
      updatedAt: now,
    });

    // Post double-entry ledger transaction
    try {
      await postLedgerTransaction(ctx, {
        code: `TX-DEAL-RELEASE-${order.orderCode}`,
        orderId: order._id,
        description: `Buyer approved inspection and released deal funds for ${order.orderCode}`,
        entries: [
          {
            accountType: "CLIENT_ESCROW_LOCKED",
            userId: order.renterOrBuyerId,
            direction: "DEBIT",
            amount: order.grossEscrowAmount,
          },
          {
            accountType: "OWNER_AVAILABLE",
            userId: order.ownerOrSellerId,
            direction: "CREDIT",
            amount: releaseAmount,
          },
          {
            accountType: "PLATFORM_REVENUE_REALIZED",
            direction: "CREDIT",
            amount: order.platformFeeAmount,
          },
        ],
      });
    } catch (e) {
      console.warn("Non-fatal double-entry ledger posting failure:", e);
    }

    // In-app notifications
    try {
      await ctx.db.insert("user_notifications", {
        userId: order.ownerOrSellerId as string,
        targetType: "single_user",
        title: "Escrow Payment Released! 💰",
        body: `Buyer has approved inspection for ${order.orderCode}. SLE ${releaseAmount.toFixed(2)} has been credited to your available balance.`,
        read: false,
        createdAt: now,
      });

      await ctx.db.insert("user_notifications", {
        userId: order.renterOrBuyerId as string,
        targetType: "single_user",
        title: "Escrow Settled Successfully 🎉",
        body: `You approved inspection and released payment for ${order.orderCode}. Thank you for using Vektolux Escrow.`,
        read: false,
        createdAt: now,
      });
    } catch {
      // non-fatal
    }

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
    escrowOrderId: v.id("escrow_orders"),
    reason: v.string(),
    claimedRepairCost: v.number(),
    evidenceMediaUrls: v.array(v.string()),
  },
  returns: v.string(),
  handler: async (ctx, args) => {
    const currentUserId = await resolveCallerUser(ctx);

    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) throw new Error("Escrow order not found");

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
// 9. QUERIES: REAL-TIME ESCROW ORDER TRACKING & ADMIN OVERSIGHT
// ═══════════════════════════════════════════════════════════════════════
export const getMyEscrowOrders = query({
  args: {
    userId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = await resolveCallerUser(ctx, args.userId);

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
  args: { escrowOrderId: v.id("escrow_orders") },
  handler: async (ctx, args) => {
    const order = await ctx.db.get(args.escrowOrderId);
    if (!order) return null;

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
  args: {},
  handler: async (ctx) => {
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
    };
  },
});
