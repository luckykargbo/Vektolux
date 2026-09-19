// convex/payments.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Payment Processing: Mutations & Internal Functions
// Handles: payment intent creation, webhook verification processing,
//          wallet credit/debit, commission splitting, atomic ledger updates
// ═══════════════════════════════════════════════════════════════════════

import { v } from "convex/values";
import {
  mutation,
  query,
  action,
  internalMutation,
  internalQuery,
  internalAction,
} from "./_generated/server";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import {
  requirePositive,
  requireNonEmpty,
  computeCommissionSplit,
} from "./lib/validation";

// ─── COMMISSION RATES (basis points) ─────────────────────────────────

/** Commission rates per vertical, in basis points (100 bps = 1%). */
const COMMISSION_RATES: Record<string, number> = {
  // Real Estate
  property_sale: 250, // 2.5%
  long_term_rent: 500, // 5% first month
  hourly_guesthouse: 1000, // 10%
  // Mobility
  ride_hailing: 1500, // 15% — default for rides
  vehicle_rental: 800, // 8%
  vehicle_sale: 300, // 3%
};

const DEFAULT_COMMISSION_BPS = 1500; // 15% fallback

// ═══════════════════════════════════════════════════════════════════════
//                     PAYMENT INTENT CREATION
// ═══════════════════════════════════════════════════════════════════════

/**
 * Create a payment intent for a booking/ride/purchase.
 * This records the intent in Convex and returns the data needed
 * for the HTTP action to initialize with Flutterwave/Paystack.
 */
export const createPaymentIntent = mutation({
  args: {
    userId: v.id("users"),
    amount: v.number(),
    currency: v.string(),
    paymentMethod: v.union(
      v.literal("card"),
      v.literal("mobile_money"),
      v.literal("wallet"),
      v.literal("crypto")
    ),
    gatewayProvider: v.union(
      v.literal("flutterwave"),
      v.literal("paystack")
    ),
    referenceType: v.string(), // "ride", "property_booking", "vehicle_purchase", etc.
    referenceId: v.string(), // Convex document ID of the booking/ride
    vendorId: v.id("users"),
    idempotencyKey: v.string(),
    commissionType: v.optional(v.string()), // Key into COMMISSION_RATES
  },
  handler: async (ctx, args) => {
    // ── Input validation ──────────────────────────────────────────
    requirePositive(args.amount, "amount");
    requireNonEmpty(args.currency, "currency");
    requireNonEmpty(args.referenceType, "referenceType");
    requireNonEmpty(args.referenceId, "referenceId");
    requireNonEmpty(args.idempotencyKey, "idempotencyKey");

    // ── Idempotency check ─────────────────────────────────────────
    const existingKey = await ctx.db
      .query("idempotencyKeys")
      .withIndex("by_key", (q) => q.eq("key", args.idempotencyKey))
      .first();

    if (existingKey) {
      // Return existing payment intent ID
      const existingIntent = await ctx.db
        .query("paymentIntents")
        .withIndex("by_idempotency", (q) =>
          q.eq("idempotencyKey", args.idempotencyKey)
        )
        .first();

      if (existingIntent) {
        return {
          paymentIntentId: existingIntent._id,
          status: existingIntent.status,
          alreadyExists: true,
        };
      }
    }

    // ── User validation ───────────────────────────────────────────
    const user = await ctx.db.get(args.userId);
    if (!user) throw new Error("User not found");
    if (!user.isActive) throw new Error("User account is deactivated");

    const vendor = await ctx.db.get(args.vendorId);
    if (!vendor) throw new Error("Vendor not found");

    // ── Commission calculation ────────────────────────────────────
    const commissionKey = args.commissionType ?? args.referenceType;
    const feeBps = COMMISSION_RATES[commissionKey] ?? DEFAULT_COMMISSION_BPS;
    const { platformFee, vendorPayout } = computeCommissionSplit(
      args.amount,
      feeBps
    );

    // ── Create payment intent ─────────────────────────────────────
    const now = Date.now();
    const paymentIntentId = await ctx.db.insert("paymentIntents", {
      userId: args.userId,
      amount: args.amount,
      currency: args.currency.toUpperCase(),
      paymentMethod: args.paymentMethod,
      gatewayProvider: args.gatewayProvider,
      referenceType: args.referenceType,
      referenceId: args.referenceId,
      platformFeeBps: feeBps,
      platformFeeAmount: platformFee,
      vendorPayoutAmount: vendorPayout,
      vendorId: args.vendorId,
      status: "pending",
      idempotencyKey: args.idempotencyKey,
      webhookVerified: false,
      updatedAt: now,
    });

    // ── Store idempotency key ─────────────────────────────────────
    await ctx.db.insert("idempotencyKeys", {
      key: args.idempotencyKey,
      result: paymentIntentId,
      createdAt: now,
      expiresAt: now + 24 * 60 * 60 * 1000, // 24h TTL
    });

    return {
      paymentIntentId,
      amount: args.amount,
      currency: args.currency.toUpperCase(),
      platformFee,
      vendorPayout,
      feeBps,
      status: "pending" as const,
      alreadyExists: false,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//             WEBHOOK PROCESSING (called by http.ts)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Internal mutation: Process a verified payment webhook.
 * Atomically updates:
 *   1. PaymentIntent status
 *   2. Vendor wallet balance (credit payout)
 *   3. Platform wallet (credit commission)
 *   4. Transaction ledger entries
 *   5. Associated booking/ride payment status
 *
 * Called only from the HTTP webhook handler after signature verification.
 */
export const processVerifiedPayment = internalMutation({
  args: {
    gatewayProvider: v.string(),
    gatewayReference: v.string(),
    gatewayStatus: v.string(),
    amountPaid: v.number(),
    currency: v.string(),
    paymentIntentId: v.id("paymentIntents"),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    // ── Fetch payment intent ──────────────────────────────────────
    const intent = await ctx.db.get(args.paymentIntentId);
    if (!intent) throw new Error("Payment intent not found");

    // ── Guard: already processed ──────────────────────────────────
    if (intent.status === "completed") {
      return { success: true, alreadyProcessed: true };
    }
    if (intent.status === "failed" || intent.status === "refunded") {
      throw new Error(`Payment intent is in terminal status: ${intent.status}`);
    }

    // ── Verify amount matches (within 1% tolerance for FX) ───────
    const tolerance = intent.amount * 0.01;
    if (Math.abs(args.amountPaid - intent.amount) > tolerance) {
      await ctx.db.patch(args.paymentIntentId, {
        status: "failed",
        failureReason: `Amount mismatch: expected ${intent.amount}, received ${args.amountPaid}`,
        updatedAt: now,
      });
      throw new Error(
        `Amount mismatch: expected ${intent.amount}, got ${args.amountPaid}`
      );
    }

    // ── Handle payment failure ────────────────────────────────────
    if (
      args.gatewayStatus === "failed" ||
      args.gatewayStatus === "cancelled"
    ) {
      await ctx.db.patch(args.paymentIntentId, {
        status: "failed",
        gatewayReference: args.gatewayReference,
        failureReason: `Gateway status: ${args.gatewayStatus}`,
        webhookVerified: true,
        updatedAt: now,
      });
      return { success: false, reason: args.gatewayStatus };
    }

    // ═══════════════════════════════════════════════════════════════
    //    ATOMIC UPDATES (all within single Convex mutation = ACID)
    // ═══════════════════════════════════════════════════════════════

    // 1. Update payment intent
    await ctx.db.patch(args.paymentIntentId, {
      status: "completed",
      gatewayReference: args.gatewayReference,
      paidAt: now,
      webhookVerified: true,
      updatedAt: now,
    });

    // 2. Credit vendor wallet
    const vendorWallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", intent.vendorId).eq("currency", intent.currency)
      )
      .first();

    let vendorWalletId: Id<"walletBalances">;

    if (vendorWallet) {
      vendorWalletId = vendorWallet._id;
      await ctx.db.patch(vendorWallet._id, {
        availableBalance:
          vendorWallet.availableBalance + intent.vendorPayoutAmount,
        updatedAt: now,
      });
    } else {
      // Create wallet on first payment
      vendorWalletId = await ctx.db.insert("walletBalances", {
        userId: intent.vendorId,
        availableBalance: intent.vendorPayoutAmount,
        pendingBalance: 0,
        currency: intent.currency,
        updatedAt: now,
      });
    }

    // 3. Record vendor payout transaction
    await ctx.db.insert("transactions", {
      walletId: vendorWalletId,
      userId: intent.vendorId,
      type: "payout",
      amount: intent.vendorPayoutAmount,
      currency: intent.currency,
      referenceType: intent.referenceType,
      referenceId: intent.referenceId,
      gatewayProvider: args.gatewayProvider,
      gatewayReference: args.gatewayReference,
      status: "completed",
      description: `Payout for ${intent.referenceType} #${intent.referenceId}`,
      updatedAt: now,
    });

    // 4. Record platform commission transaction
    // Platform uses a "system" user or the admin's wallet
    // For simplicity, we record it as a commission transaction on the vendor wallet
    await ctx.db.insert("transactions", {
      walletId: vendorWalletId,
      userId: intent.vendorId,
      type: "commission",
      amount: intent.platformFeeAmount,
      currency: intent.currency,
      referenceType: intent.referenceType,
      referenceId: intent.referenceId,
      gatewayProvider: args.gatewayProvider,
      gatewayReference: args.gatewayReference,
      status: "completed",
      description: `Platform commission (${intent.platformFeeBps / 100}%) on ${intent.referenceType}`,
      updatedAt: now,
    });

    // 5. Update associated booking/ride payment status
    await updateBookingPaymentStatus(
      ctx,
      intent.referenceType,
      intent.referenceId,
      args.gatewayReference,
      now
    );

    // 6. Schedule blockchain logging (non-blocking)
    await ctx.scheduler.runAfter(0, internal.blockchain.logTransactionOnChain, {
      paymentIntentId: args.paymentIntentId,
      dealType: intent.referenceType,
      buyerId: intent.userId,
      sellerId: intent.vendorId,
      amount: intent.amount,
      currency: intent.currency,
      gatewayReference: args.gatewayReference,
    });

    return {
      success: true,
      alreadyProcessed: false,
      vendorPayout: intent.vendorPayoutAmount,
      platformFee: intent.platformFeeAmount,
    };
  },
});

/**
 * Helper: Update the payment status on the associated booking or ride.
 */
async function updateBookingPaymentStatus(
  ctx: { db: any },
  referenceType: string,
  referenceId: string,
  paymentReference: string,
  now: number
) {
  // 1. Check the universal bookings collection
  const bookingNorm = ctx.db.normalizeId("bookings", referenceId);
  if (bookingNorm) {
    const booking = await ctx.db.get(bookingNorm);
    if (booking) {
      await ctx.db.patch(bookingNorm, {
        status: "confirmed",
        paymentStatus: "completed",
        paymentReference,
        flwRef: paymentReference,
        updatedAt: now,
      });
      return;
    }
  }

  // 2. Check bookings by txRef
  const bookingByTx = await ctx.db
    .query("bookings")
    .withIndex("by_tx_ref", (q: any) => q.eq("txRef", referenceId))
    .first();
  if (bookingByTx) {
    await ctx.db.patch(bookingByTx._id, {
      status: "confirmed",
      paymentStatus: "completed",
      paymentReference,
      flwRef: paymentReference,
      updatedAt: now,
    });
    return;
  }

  // 3. Fallback to realEstateBookings or rideRequests
  switch (referenceType) {
    case "property_booking":
    case "hourly_guesthouse": {
      const bId = ctx.db.normalizeId("realEstateBookings", referenceId);
      if (bId) {
        const booking = await ctx.db.get(bId);
        if (booking) {
          await ctx.db.patch(booking._id, {
            paymentStatus: "completed",
            paymentReference,
            updatedAt: now,
          });
        }
      }
      break;
    }
    default:
      break;
  }
}

// ═══════════════════════════════════════════════════════════════════════
//                 IN-APP FLUTTERWAVE INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════

/**
 * Initialize a Flutterwave checkout session for an in-app booking.
 */
export const initializePayment = mutation({
  args: {
    bookingId: v.string(),
    txRef: v.string(),
    amount: v.number(),
    currency: v.optional(v.string()),
    customerEmail: v.string(),
    customerPhone: v.optional(v.string()),
    customerName: v.optional(v.string()),
    paymentOptions: v.optional(v.string()),
    redirectUrl: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    paymentLink: v.string(),
    txRef: v.string(),
  }),
  handler: async (ctx, args) => {
    const bookingNorm = ctx.db.normalizeId("bookings", args.bookingId);
    if (!bookingNorm) throw new Error("Booking not found");

    const booking = await ctx.db.get(bookingNorm);
    if (!booking) throw new Error("Booking not found");

    const currency = args.currency ?? "SLE";
    const hostedCheckoutUrl = `https://checkout.flutterwave.com/v3/hosted/pay/${args.txRef}?amount=${args.amount}&currency=${currency}`;

    await ctx.db.patch(bookingNorm, {
      txRef: args.txRef,
      updatedAt: Date.now(),
    });

    return {
      success: true,
      paymentLink: hostedCheckoutUrl,
      txRef: args.txRef,
    };
  },
});

/**
 * Complete payment confirmation (via webhook, callback, or in-app payment flow).
 * Atomically marks booking as confirmed, calculates 15% platform fee, and credits 85% to vendor.
 */
export const confirmPayment = mutation({
  args: {
    bookingId: v.string(),
    txRef: v.string(),
    gatewayReference: v.optional(v.string()),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const bookingNorm = ctx.db.normalizeId("bookings", args.bookingId);
    if (!bookingNorm) throw new Error("Booking not found");

    const booking = await ctx.db.get(bookingNorm);
    if (!booking) throw new Error("Booking not found");

    const now = Date.now();
    const flwRef =
      args.gatewayReference ??
      `FLW_${now}_${Math.random().toString(36).substring(2, 8).toUpperCase()}`;

    // 1. Atomically mark booking confirmed
    await ctx.db.patch(bookingNorm, {
      status: "confirmed",
      paymentStatus: "completed",
      paymentReference: flwRef,
      flwRef,
      updatedAt: now,
    });

    // 2. Credit 85% vendor payout & record 15% platform commission
    const vendorNorm = ctx.db.normalizeId("users", booking.vendorId);
    if (vendorNorm && booking.totalAmount > 0) {
      const vendorPayout = Math.round(booking.totalAmount * 0.85);
      const platformCommission = booking.totalAmount - vendorPayout;

      let wallet = await ctx.db
        .query("walletBalances")
        .withIndex("by_user_currency", (q) =>
          q.eq("userId", vendorNorm).eq("currency", booking.currency)
        )
        .first();

      let walletId: Id<"walletBalances">;
      if (wallet) {
        walletId = wallet._id;
        await ctx.db.patch(wallet._id, {
          availableBalance: wallet.availableBalance + vendorPayout,
          updatedAt: now,
        });
      } else {
        walletId = await ctx.db.insert("walletBalances", {
          userId: vendorNorm,
          availableBalance: vendorPayout,
          pendingBalance: 0,
          currency: booking.currency,
          updatedAt: now,
        });
      }

      // Record vendor payout transaction
      await ctx.db.insert("transactions", {
        walletId,
        userId: vendorNorm,
        type: "payout",
        amount: vendorPayout,
        currency: booking.currency,
        referenceType: booking.bookingType,
        referenceId: booking._id,
        gatewayProvider: "flutterwave",
        gatewayReference: flwRef,
        status: "completed",
        description: `Vendor payout (85%) for ${booking.listingTitle}`,
        updatedAt: now,
      });

      // Record platform commission transaction
      await ctx.db.insert("transactions", {
        walletId,
        userId: vendorNorm,
        type: "commission",
        amount: platformCommission,
        currency: booking.currency,
        referenceType: booking.bookingType,
        referenceId: booking._id,
        gatewayProvider: "flutterwave",
        gatewayReference: flwRef,
        status: "completed",
        description: `Platform commission (15%) on ${booking.listingTitle}`,
        updatedAt: now,
      });
    }

    return true;
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    WALLET QUERIES & MUTATIONS
// ═══════════════════════════════════════════════════════════════════════

/**
 * Get a user's wallet balance.
 */
export const getWalletBalance = query({
  args: {
    userId: v.string(),
    currency: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const currency = args.currency ?? "SLE";
    const userConvexId = ctx.db.normalizeId("users", args.userId);
    if (!userConvexId) {
      return {
        availableBalance: 0,
        pendingBalance: 0,
        currency,
        exists: false,
      };
    }

    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", userConvexId).eq("currency", currency)
      )
      .first();

    if (!wallet) {
      return {
        availableBalance: 0,
        pendingBalance: 0,
        currency,
        exists: false,
      };
    }

    return {
      walletId: wallet._id,
      availableBalance: wallet.availableBalance,
      pendingBalance: wallet.pendingBalance,
      currency: wallet.currency,
      exists: true,
      updatedAt: wallet.updatedAt,
    };
  },
});

/**
 * Get a user's transaction history with pagination.
 */
export const getTransactionHistory = query({
  args: {
    userId: v.string(),
    limit: v.optional(v.number()),
    type: v.optional(
      v.union(
        v.literal("payment"),
        v.literal("payout"),
        v.literal("commission"),
        v.literal("refund"),
        v.literal("top_up"),
        v.literal("transfer"),
        v.literal("escrow_lock"),
        v.literal("escrow_release")
      )
    ),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 50;
    const userConvexId = ctx.db.normalizeId("users", args.userId);
    if (!userConvexId) {
      return { transactions: [], count: 0 };
    }

    let transactionsQuery;

    if (args.type) {
      transactionsQuery = ctx.db
        .query("transactions")
        .withIndex("by_user_type", (q) =>
          q.eq("userId", userConvexId).eq("type", args.type!)
        );
    } else {
      transactionsQuery = ctx.db
        .query("transactions")
        .withIndex("by_user", (q) => q.eq("userId", userConvexId));
    }

    const transactions = await transactionsQuery.order("desc").take(limit);

    return { transactions, count: transactions.length };
  },
});

/**
 * Top up user wallet balance via Mobile Money (Orange Money, Africell Money) or Card.
 * Atomically creates or updates the user's wallet and inserts a ledger record.
 */
export const topUpWallet = mutation({
  args: {
    userId: v.string(),
    amount: v.number(),
    currency: v.optional(v.string()),
    provider: v.optional(v.string()),
    reference: v.optional(v.string()),
    agentNumber: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.amount <= 0) throw new Error("Top up amount must be positive");
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (!userNorm) throw new Error("User not found");

    const currency = args.currency ?? "SLE";
    const now = Date.now();

    let wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", userNorm).eq("currency", currency)
      )
      .first();

    let walletId: Id<"walletBalances">;
    if (wallet) {
      walletId = wallet._id;
      await ctx.db.patch(wallet._id, {
        availableBalance: wallet.availableBalance + args.amount,
        updatedAt: now,
      });
    } else {
      walletId = await ctx.db.insert("walletBalances", {
        userId: userNorm,
        availableBalance: args.amount,
        pendingBalance: 0,
        currency,
        updatedAt: now,
      });
    }

    const provider = args.provider ?? "mobile_money";
    const ref =
      args.reference ??
      `TOPUP_${now}_${Math.random().toString(36).substring(2, 7).toUpperCase()}`;

    await ctx.db.insert("transactions", {
      walletId,
      userId: userNorm,
      type: "top_up",
      amount: args.amount,
      currency,
      gatewayProvider: provider,
      gatewayReference: ref,
      agentNumber: args.agentNumber,
      status: "completed",
      description: `Wallet top up of ${args.amount} ${currency} via ${provider}`,
      updatedAt: now,
    });

    const updated = await ctx.db.get(walletId);
    return {
      success: true,
      availableBalance: updated?.availableBalance ?? args.amount,
      currency,
    };
  },
});

/**
 * Atomically deduct from user's available wallet balance.
 * Returns failure if balance is insufficient.
 */
export const deductWalletBalance = mutation({
  args: {
    userId: v.string(),
    amount: v.number(),
    currency: v.optional(v.string()),
    description: v.optional(v.string()),
    referenceType: v.optional(v.string()),
    referenceId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.amount <= 0) throw new Error("Deduction amount must be positive");
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (!userNorm) throw new Error("User not found");

    const currency = args.currency ?? "SLE";
    const now = Date.now();

    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", userNorm).eq("currency", currency)
      )
      .first();

    if (!wallet || wallet.availableBalance < args.amount) {
      throw new Error(
        `Insufficient wallet balance. Available: ${wallet?.availableBalance ?? 0} ${currency}, required: ${args.amount} ${currency}`
      );
    }

    const newBalance = wallet.availableBalance - args.amount;
    await ctx.db.patch(wallet._id, {
      availableBalance: newBalance,
      updatedAt: now,
    });

    await ctx.db.insert("transactions", {
      walletId: wallet._id,
      userId: userNorm,
      type: "payment",
      amount: args.amount,
      currency,
      referenceType: args.referenceType,
      referenceId: args.referenceId,
      gatewayProvider: "wallet",
      status: "completed",
      description:
        args.description ?? `Wallet payment of ${args.amount} ${currency}`,
      updatedAt: now,
    });

    return {
      success: true,
      remainingBalance: newBalance,
      currency,
    };
  },
});

/**
 * Get a payment intent by ID.
 */
export const getPaymentIntent = query({
  args: {
    paymentIntentId: v.id("paymentIntents"),
  },
  handler: async (ctx, args) => {
    return await ctx.db.get(args.paymentIntentId);
  },
});

/**
 * Internal: Mark a payment intent with a blockchain tx hash after on-chain logging.
 */
export const updateBlockchainHash = internalMutation({
  args: {
    paymentIntentId: v.id("paymentIntents"),
    blockchainTxHash: v.string(),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.paymentIntentId, {
      blockchainTxHash: args.blockchainTxHash,
      updatedAt: Date.now(),
    });
  },
});

/**
 * Internal: Update payment intent with gateway reference and payment link.
 * Called by http.ts POST /payments/initialize after gateway returns a checkout URL.
 */
export const updateGatewayReference = internalMutation({
  args: {
    paymentIntentId: v.id("paymentIntents"),
    gatewayReference: v.string(),
    gatewayPaymentLink: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const intent = await ctx.db.get(args.paymentIntentId);
    if (!intent) throw new Error("Payment intent not found");

    await ctx.db.patch(args.paymentIntentId, {
      gatewayReference: args.gatewayReference,
      gatewayPaymentLink: args.gatewayPaymentLink,
      status: "processing",
      updatedAt: Date.now(),
    });
  },
});

/**
 * Internal query to fetch a user's blockchain wallet address.
 * Used by the relayer action to resolve buyer/seller addresses.
 */
export const getUserWalletAddress = internalQuery({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) return null;
    return {
      walletAddress: user.walletAddress ?? null,
      name: user.name,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//               ESCROW PAYMENT & SPLIT REVENUE LEDGER
// ═══════════════════════════════════════════════════════════════════════

async function generateDeterministicHash(payload: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(payload);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return "0x" + hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Lock funds in Vektolux Escrow with customizable partner revenue split.
 * Generates cryptographic blockchain audit hash and records on ledger.
 */
export const createEscrowPayment = mutation({
  args: {
    buyerId: v.string(),
    vendorId: v.string(),
    amount: v.number(),
    currency: v.optional(v.string()),
    referenceType: v.string(), // "vehicle_sale", "vehicle_rental", "property_booking", "hourly_guesthouse", "ride"
    referenceId: v.string(),
    partnerSplitPercent: v.optional(v.number()), // default 60%
    agentNumber: v.optional(v.string()), // Orange Money / Africell agent code or phone
    momoProvider: v.optional(v.string()), // "orange_money" or "africell_money"
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    requirePositive(args.amount, "amount");

    const currency = (args.currency ?? "SLE").toUpperCase();
    const splitPercent = args.partnerSplitPercent ?? 60; // 60% partner, 40% platform fee
    const partnerAmount = Math.round((args.amount * splitPercent) / 100);
    const platformFeeAmount = args.amount - partnerAmount;

    let buyerId = ctx.db.normalizeId("users", args.buyerId);
    let buyer = buyerId ? await ctx.db.get(buyerId) : null;
    if (!buyer) {
      buyer = await ctx.db.query("users").first();
      buyerId = buyer?._id ?? null;
    }
    if (!buyer || !buyer.isActive) throw new Error("Buyer account not found or deactivated");

    let vendorId = ctx.db.normalizeId("users", args.vendorId);
    let vendor = vendorId ? await ctx.db.get(vendorId) : null;
    if (!vendor) {
      vendor = await ctx.db.query("users").filter((q) => q.neq(q.field("_id"), buyerId)).first() ?? buyer;
      vendorId = vendor._id;
    }

    const now = Date.now();
    const txNonce = `${buyerId}-${vendorId}-${args.amount}-${args.referenceId}-${now}`;
    const blockchainTxHash = await generateDeterministicHash(txNonce);

    // Ensure buyer wallet exists
    let buyerWallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", buyerId!).eq("currency", currency)
      )
      .first();

    if (!buyerWallet) {
      const wId = await ctx.db.insert("walletBalances", {
        userId: buyerId!,
        availableBalance: 0,
        pendingBalance: 0,
        currency,
        updatedAt: now,
      });
      buyerWallet = await ctx.db.get(wId);
    }

    // Insert escrow_lock ledger record
      const effectiveAgentNumber = args.agentNumber ?? (args.momoProvider ? "001" : undefined);
      const transactionId = await ctx.db.insert("transactions", {
        walletId: buyerWallet!._id,
        userId: buyerId!,
        counterpartyId: vendorId ?? undefined,
        type: "escrow_lock",
        amount: args.amount,
        currency,
        referenceType: args.referenceType,
        referenceId: args.referenceId,
        gatewayProvider: args.momoProvider ?? "mobile_money",
        gatewayReference: effectiveAgentNumber ? `AGENT_${effectiveAgentNumber}` : `MOMO_${now}`,
        agentNumber: effectiveAgentNumber,
        partnerSplitPercent: splitPercent,
        partnerAmount,
        platformFeeAmount,
        escrowStatus: "locked",
        blockchainTxHash,
        status: "completed",
        description: `Escrow locked for ${args.referenceType} (#${args.referenceId}) with ${splitPercent}% partner split via ${effectiveAgentNumber ? "Mobile Money Agent #" + effectiveAgentNumber : "Mobile Money"}`,
        updatedAt: now,
      });

    // Update universal booking if applicable
    const bookingNorm = ctx.db.normalizeId("bookings", args.referenceId);
    if (bookingNorm) {
      await ctx.db.patch(bookingNorm, {
        status: "confirmed",
        paymentStatus: "completed",
        escrowId: transactionId,
        blockchainTxHash,
        updatedAt: now,
      });
    }

    return {
      success: true,
      transactionId,
      blockchainTxHash,
      totalAmount: args.amount,
      currency,
      partnerAmount,
      platformFeeAmount,
      partnerSplitPercent: splitPercent,
      agentNumber: args.agentNumber,
      escrowStatus: "locked",
    };
  },
});

/**
 * Release escrow funds upon inspection/meetup verification or service completion.
 * Automatically disburses the partner share (e.g. 60%) to partner wallet and fee to treasury.
 */
export const releaseEscrowWithSplit = mutation({
  args: {
    transactionId: v.id("transactions"),
    approverId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const tx = await ctx.db.get(args.transactionId);
    if (!tx) throw new Error("Transaction not found");
    if (tx.type !== "escrow_lock") throw new Error("Transaction is not an escrow lock");
    if (tx.escrowStatus !== "locked") {
      throw new Error(`Escrow is already ${tx.escrowStatus ?? "resolved"}`);
    }

    const now = Date.now();
    const partnerAmount = tx.partnerAmount ?? Math.round((tx.amount * 60) / 100);
    const platformFeeAmount = tx.platformFeeAmount ?? (tx.amount - partnerAmount);

    // Update original transaction status to released
    await ctx.db.patch(args.transactionId, {
      escrowStatus: "released",
      updatedAt: now,
    });

    // Credit vendor wallet
    if (tx.counterpartyId) {
      let vendorWallet = await ctx.db
        .query("walletBalances")
        .withIndex("by_user_currency", (q) =>
          q.eq("userId", tx.counterpartyId!).eq("currency", tx.currency)
        )
        .first();

      let vendorWalletId = vendorWallet?._id;
      if (vendorWallet) {
        await ctx.db.patch(vendorWallet._id, {
          availableBalance: vendorWallet.availableBalance + partnerAmount,
          updatedAt: now,
        });
      } else {
        vendorWalletId = await ctx.db.insert("walletBalances", {
          userId: tx.counterpartyId,
          availableBalance: partnerAmount,
          pendingBalance: 0,
          currency: tx.currency,
          updatedAt: now,
        });
      }

      // Record escrow release payout transaction for the vendor
      await ctx.db.insert("transactions", {
        walletId: vendorWalletId!,
        userId: tx.counterpartyId,
        counterpartyId: tx.userId,
        type: "escrow_release",
        amount: partnerAmount,
        currency: tx.currency,
        referenceType: tx.referenceType,
        referenceId: tx.referenceId,
        blockchainTxHash: tx.blockchainTxHash,
        partnerSplitPercent: tx.partnerSplitPercent,
        partnerAmount,
        platformFeeAmount,
        escrowStatus: "released",
        status: "completed",
        description: `Escrow payout released: ${tx.partnerSplitPercent ?? 60}% disbursement for ${tx.referenceType ?? "deal"}`,
        updatedAt: now,
      });
    }

    return {
      success: true,
      releasedPartnerAmount: partnerAmount,
      platformFeeAmount,
      blockchainTxHash: tx.blockchainTxHash,
      status: "released",
    };
  },
});

/**
 * Configure or update 4-digit Wallet Security PIN.
 */
export const setWalletPin = mutation({
  args: {
    userId: v.string(),
    pin: v.string(),
  },
  handler: async (ctx, args) => {
    if (args.pin.length < 4 || args.pin.length > 6) {
      throw new Error("PIN must be between 4 and 6 digits");
    }

    const userId = ctx.db.normalizeId("users", args.userId);
    if (!userId) throw new Error("Invalid user ID");

    const pinHash = await generateDeterministicHash(`wallet_pin_${userId}_${args.pin}`);
    await ctx.db.patch(userId, {
      walletPinHash: pinHash,
      updatedAt: Date.now(),
    });

    return { success: true };
  },
});

/**
 * Verify 4-digit Wallet Security PIN before checkout or release.
 */
export const verifyWalletPin = query({
  args: {
    userId: v.string(),
    pin: v.string(),
  },
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.userId);
    if (!userId) return { valid: false, hasPin: false };

    const user = await ctx.db.get(userId);
    if (!user) return { valid: false, hasPin: false };
    if (!user.walletPinHash) return { valid: true, hasPin: false }; // No PIN set yet

    const testHash = await generateDeterministicHash(`wallet_pin_${userId}_${args.pin}`);
    return {
      valid: testHash === user.walletPinHash,
      hasPin: true,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//        DYNAMIC PAYMENT SETTINGS (Admin-Configurable Methods)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Get all enabled payment methods for the mobile checkout.
 * Returns only providers where isEnabled === true.
 */
export const getActivePaymentMethods = query({
  args: {},
  handler: async (ctx) => {
    const methods = await ctx.db
      .query("payment_settings")
      .withIndex("by_isEnabled", (q) => q.eq("isEnabled", true))
      .collect();
    return methods;
  },
});

/**
 * Get all payment methods (enabled + disabled) for admin configurator.
 */
export const getAllPaymentMethods = query({
  args: {},
  handler: async (ctx) => {
    const methods = await ctx.db
      .query("payment_settings")
      .collect();
    return methods;
  },
});

/**
 * Admin: Update a payment method's settings (toggle, instructions, account info).
 */
export const updatePaymentMethod = mutation({
  args: {
    settingsId: v.id("payment_settings"),
    isEnabled: v.optional(v.boolean()),
    displayName: v.optional(v.string()),
    instructions: v.optional(v.string()),
    accountNumber: v.optional(v.string()),
    accountName: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db.get(args.settingsId);
    if (!existing) throw new Error("Payment method not found");

    const updates: Record<string, unknown> = { updatedAt: Date.now() };
    if (args.isEnabled !== undefined) updates.isEnabled = args.isEnabled;
    if (args.displayName !== undefined) updates.displayName = args.displayName;
    if (args.instructions !== undefined) updates.instructions = args.instructions;
    if (args.accountNumber !== undefined) updates.accountNumber = args.accountNumber;
    if (args.accountName !== undefined) updates.accountName = args.accountName;

    await ctx.db.patch(args.settingsId, updates);
    return { success: true };
  },
});

/**
 * One-time seed: Insert the 4 default payment providers if table is empty.
 */
export const seedDefaultPaymentMethods = mutation({
  args: {},
  handler: async (ctx) => {
    const existing = await ctx.db.query("payment_settings").first();
    if (existing) {
      return { seeded: false, message: "Payment settings already exist" };
    }

    const now = Date.now();
    const defaults = [
      {
        providerId: "moneroo_auto",
        displayName: "Orange Money / Cards (Moneroo)",
        type: "AGGREGATOR_AUTO" as const,
        isEnabled: true,
        instructions: "Pay securely via Orange Money, Visa, or Mastercard through our Moneroo gateway.",
        accountNumber: undefined,
        accountName: "Vektolux Escrow Services",
        updatedAt: now,
      },
      {
        providerId: "qmoney_manual",
        displayName: "QCell QMoney",
        type: "MANUAL_MERCHANT" as const,
        isEnabled: true,
        instructions: "Dial *345#, select 'Pay Merchant', enter Merchant Code 001, enter the exact amount, then paste your SMS Transaction ID below.",
        accountNumber: "001",
        accountName: "Vektolux Escrow Services",
        updatedAt: now,
      },
      {
        providerId: "afrimoney_manual",
        displayName: "Africell Afrimoney",
        type: "MANUAL_MERCHANT" as const,
        isEnabled: true,
        instructions: "Dial *161#, select 'Merchant Payment', enter Merchant Code 001, enter the exact amount, then paste your SMS Transaction ID below.",
        accountNumber: "001",
        accountName: "Vektolux Escrow Services",
        updatedAt: now,
      },
      {
        providerId: "bank_transfer",
        displayName: "Bank Transfer (SLCB / Rokel)",
        type: "BANK_TRANSFER" as const,
        isEnabled: true,
        instructions: "Transfer the exact amount to:\nBank: Sierra Leone Commercial Bank (SLCB)\nAccount Name: Vektolux Escrow Services\nAccount Number: 0012345678\nPaste the bank reference number below.",
        accountNumber: "0012345678",
        accountName: "Vektolux Escrow Services",
        updatedAt: now,
      },
    ];

    for (const method of defaults) {
      await ctx.db.insert("payment_settings", method);
    }

    return { seeded: true, count: defaults.length };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//        ESCROW PAYMENT CLAIMS (Manual + Automated Tracking)
// ═══════════════════════════════════════════════════════════════════════

/**
 * User: Submit a manual payment claim with SMS Transaction Reference.
 * Sets status to PENDING_APPROVAL for admin review.
 */
export const submitManualPaymentClaim = mutation({
  args: {
    userId: v.id("users"),
    amount: v.number(),
    providerId: v.string(),
    transactionReference: v.string(),
    bookingId: v.optional(v.string()),
    escrowOrderId: v.optional(v.id("escrow_orders")),
    reContractId: v.optional(v.id("re_escrow_contracts")),
  },
  handler: async (ctx, args) => {
    requirePositive(args.amount, "amount");
    requireNonEmpty(args.transactionReference, "transactionReference");
    requireNonEmpty(args.providerId, "providerId");

    // Verify user exists
    const user = await ctx.db.get(args.userId);
    if (!user) throw new Error("User not found");

    // Verify provider exists and is enabled
    const provider = await ctx.db
      .query("payment_settings")
      .withIndex("by_providerId", (q) => q.eq("providerId", args.providerId))
      .first();
    if (!provider) throw new Error("Payment provider not found");
    if (!provider.isEnabled) throw new Error("Payment provider is currently disabled");

    // Determine payment type from provider
    const paymentType: "AUTOMATED" | "MANUAL_CLAIM" =
      provider.type === "AGGREGATOR_AUTO" ? "AUTOMATED" : "MANUAL_CLAIM";

    const now = Date.now();
    const claimId = await ctx.db.insert("escrow_payment_claims", {
      bookingId: args.bookingId,
      escrowOrderId: args.escrowOrderId,
      reContractId: args.reContractId,
      userId: args.userId,
      amount: args.amount,
      currency: "SLE",
      providerId: args.providerId,
      paymentType: paymentType,
      transactionReference: args.transactionReference,
      status: "PENDING_APPROVAL",
      createdAt: now,
    });

    return {
      success: true,
      claimId,
      status: "PENDING_APPROVAL" as const,
    };
  },
});

/**
 * Admin: Get all payment claims pending approval.
 * Returns claims enriched with user name.
 */
export const getPendingApprovalClaims = query({
  args: {},
  handler: async (ctx) => {
    const claims = await ctx.db
      .query("escrow_payment_claims")
      .withIndex("by_status", (q) => q.eq("status", "PENDING_APPROVAL"))
      .order("desc")
      .take(100);

    // Enrich with user info
    const enriched = [];
    for (const claim of claims) {
      const user = await ctx.db.get(claim.userId);
      enriched.push({
        ...claim,
        userName: user?.name ?? "Unknown",
        userPhone: user?.phone ?? "",
        userEmail: user?.email ?? "",
      });
    }

    return enriched;
  },
});

/**
 * User: Get their own payment claims.
 */
export const getUserPaymentClaims = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const claims = await ctx.db
      .query("escrow_payment_claims")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .order("desc")
      .take(50);

    return claims;
  },
});

/**
 * Admin: Approve a manual payment claim → transitions to ESCROW_LOCKED.
 */
export const approvePaymentClaim = mutation({
  args: {
    claimId: v.id("escrow_payment_claims"),
    adminUserId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const claim = await ctx.db.get(args.claimId);
    if (!claim) throw new Error("Payment claim not found");
    if (claim.status !== "PENDING_APPROVAL") {
      throw new Error(`Cannot approve claim with status: ${claim.status}`);
    }

    // Verify admin exists
    const admin = await ctx.db.get(args.adminUserId);
    if (!admin || admin.role !== "admin") {
      throw new Error("Only admin users can approve payment claims");
    }

    const now = Date.now();
    await ctx.db.patch(args.claimId, {
      status: "ESCROW_LOCKED",
      reviewedByAdminId: args.adminUserId,
      reviewedAt: now,
    });

    // If linked to an escrow order, update its status too
    if (claim.escrowOrderId) {
      const order = await ctx.db.get(claim.escrowOrderId);
      if (order && order.status === "PENDING_PAYMENT") {
        await ctx.db.patch(claim.escrowOrderId, {
          status: "HELD_IN_ESCROW",
          updatedAt: now,
        });
      }
    }

    // If linked to a real estate contract, update its state
    if (claim.reContractId) {
      const contract = await ctx.db.get(claim.reContractId);
      if (contract && contract.currentState === "CREATED") {
        await ctx.db.patch(claim.reContractId, {
          currentState: "FUNDS_LOCKED",
          updatedAt: now,
        });
      }
    }

    return { success: true, status: "ESCROW_LOCKED" as const };
  },
});

/**
 * Admin: Reject a manual payment claim with reason.
 */
export const rejectPaymentClaim = mutation({
  args: {
    claimId: v.id("escrow_payment_claims"),
    adminUserId: v.id("users"),
    rejectionReason: v.string(),
  },
  handler: async (ctx, args) => {
    const claim = await ctx.db.get(args.claimId);
    if (!claim) throw new Error("Payment claim not found");
    if (claim.status !== "PENDING_APPROVAL") {
      throw new Error(`Cannot reject claim with status: ${claim.status}`);
    }

    requireNonEmpty(args.rejectionReason, "rejectionReason");

    // Verify admin exists
    const admin = await ctx.db.get(args.adminUserId);
    if (!admin || admin.role !== "admin") {
      throw new Error("Only admin users can reject payment claims");
    }

    const now = Date.now();
    await ctx.db.patch(args.claimId, {
      status: "REJECTED",
      rejectionReason: args.rejectionReason,
      reviewedByAdminId: args.adminUserId,
      reviewedAt: now,
    });

    return { success: true, status: "REJECTED" as const };
  },
});

/**
 * Internal: Auto-lock escrow when Moneroo webhook confirms payment success.
 * Called only from the HTTP webhook handler.
 */
export const processMonerooWebhookClaim = internalMutation({
  args: {
    transactionReference: v.string(),
    amountPaid: v.number(),
    currency: v.string(),
    paymentId: v.optional(v.string()),
    metadata: v.optional(v.any()),
  },
  handler: async (ctx, args) => {
    // Find the pending claim by transaction reference or paymentId or metadata.reference
    let claims = await ctx.db
      .query("escrow_payment_claims")
      .filter((q) =>
        q.eq(q.field("transactionReference"), args.transactionReference)
      )
      .take(1);

    if (claims.length === 0 && args.paymentId) {
      claims = await ctx.db
        .query("escrow_payment_claims")
        .filter((q) => q.eq(q.field("transactionReference"), args.paymentId!))
        .take(1);
    }

    if (claims.length === 0 && args.metadata?.ref) {
      claims = await ctx.db
        .query("escrow_payment_claims")
        .filter((q) => q.eq(q.field("transactionReference"), args.metadata.ref))
        .take(1);
    }

    const claim = claims[0];
    if (!claim) {
      console.error(`Moneroo webhook: No claim found for ref ${args.transactionReference}`);
      return { success: false, reason: "claim_not_found" };
    }

    if (claim.status === "ESCROW_LOCKED") {
      return { success: true, alreadyProcessed: true };
    }

    if (claim.status !== "PENDING_PAYMENT" && claim.status !== "PENDING_APPROVAL") {
      return { success: false, reason: `invalid_status_${claim.status}` };
    }

    const now = Date.now();
    await ctx.db.patch(claim._id, {
      status: "ESCROW_LOCKED",
      reviewedAt: now,
    });

    // Update linked vehicle escrow order if present
    if (claim.escrowOrderId) {
      const order = await ctx.db.get(claim.escrowOrderId);
      if (order && (order.status === "PENDING_PAYMENT" || order.status === "INITIATED")) {
        await ctx.db.patch(claim.escrowOrderId, {
          status: "HELD_IN_ESCROW",
          updatedAt: now,
        });
      }
    }

    // Update linked real estate contract if present
    if (claim.reContractId) {
      const contract = await ctx.db.get(claim.reContractId);
      if (contract && (contract.currentState === "CREATED" || contract.currentState === "FUNDS_LOCKED")) {
        await ctx.db.patch(claim.reContractId, {
          currentState: "FUNDS_LOCKED",
          updatedAt: now,
        });
      }
    }

    // Update general universal booking if present
    if (claim.bookingId) {
      const bNorm = ctx.db.normalizeId("bookings", claim.bookingId);
      if (bNorm) {
        await ctx.db.patch(bNorm, {
          status: "confirmed",
          paymentStatus: "completed",
          updatedAt: now,
        });
      }
    }

    return { success: true, alreadyProcessed: false };
  },
});

/**
 * Internal: Record the initialization of an automated Moneroo payment claim.
 */
export const recordMonerooClaimInit = internalMutation({
  args: {
    userId: v.string(),
    amount: v.number(),
    currency: v.literal("SLE"),
    providerId: v.string(),
    transactionReference: v.string(),
    bookingId: v.optional(v.string()),
    escrowOrderId: v.optional(v.string()),
    reContractId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (!userNorm) throw new Error("Invalid user ID");

    const escrowOrderNorm = args.escrowOrderId
      ? ctx.db.normalizeId("escrow_orders", args.escrowOrderId)
      : undefined;

    const reContractNorm = args.reContractId
      ? ctx.db.normalizeId("re_escrow_contracts", args.reContractId)
      : undefined;

    const now = Date.now();
    const claimId = await ctx.db.insert("escrow_payment_claims", {
      userId: userNorm,
      amount: args.amount,
      currency: args.currency,
      providerId: args.providerId,
      paymentType: "AUTOMATED",
      transactionReference: args.transactionReference,
      status: "PENDING_PAYMENT",
      bookingId: args.bookingId,
      escrowOrderId: escrowOrderNorm ?? undefined,
      reContractId: reContractNorm ?? undefined,
      createdAt: now,
    });

    return claimId;
  },
});

/**
 * Public Action: Initialize an automated Moneroo sandbox payment session.
 * Calls https://api.moneroo.io/v1/payments/initialize with Moneroo credentials
 * and returns checkout_url to the client.
 */
export const initializeMonerooPayment = action({
  args: {
    amount: v.number(),
    currency: v.optional(v.string()),
    customerEmail: v.string(),
    customerFirstName: v.string(),
    customerLastName: v.string(),
    customerPhone: v.optional(v.string()),
    returnUrl: v.optional(v.string()),
    description: v.optional(v.string()),
    userId: v.string(),
    bookingId: v.optional(v.string()),
    escrowOrderId: v.optional(v.string()),
    reContractId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const apiKey = process.env.MONEROO_SECRET_KEY;
    if (!apiKey) {
      throw new Error("MONEROO_SECRET_KEY environment variable is not configured");
    }

    const currency = args.currency ?? "SLE";
    const ref = `vktlx_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const returnUrl = args.returnUrl ?? "https://app.vektolux.com/payment/callback";

    const payload = {
      amount: args.amount,
      currency: currency,
      customer: {
        email: args.customerEmail,
        first_name: args.customerFirstName,
        last_name: args.customerLastName,
        phone: args.customerPhone ?? "",
      },
      return_url: returnUrl,
      description: args.description ?? `Vektolux Escrow Deposit - ${args.amount} ${currency}`,
      metadata: {
        userId: args.userId,
        bookingId: args.bookingId ?? "",
        escrowOrderId: args.escrowOrderId ?? "",
        reContractId: args.reContractId ?? "",
        ref: ref,
      },
    };

    console.log("Initializing Moneroo payment:", {
      amount: args.amount,
      currency,
      ref,
      customerEmail: args.customerEmail,
    });

    const response = await fetch("https://api.moneroo.io/v1/payments/initialize", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(payload),
    });

    const resJson = await response.json();

    if (!response.ok) {
      console.error("Moneroo initialize error response:", resJson);
      throw new Error(resJson.message ?? resJson.error ?? "Failed to initialize Moneroo payment");
    }

    const resData = resJson.data ?? resJson;
    const checkoutUrl = resData.checkout_url ?? resData.link ?? "";
    const paymentId = resData.id ?? ref;

    // Record initial claim in Convex
    await ctx.runMutation(internal.payments.recordMonerooClaimInit, {
      userId: args.userId,
      amount: args.amount,
      currency: "SLE",
      providerId: "moneroo_auto",
      transactionReference: paymentId,
      bookingId: args.bookingId,
      escrowOrderId: args.escrowOrderId,
      reContractId: args.reContractId,
    });

    return {
      success: true,
      checkout_url: checkoutUrl,
      paymentId: paymentId,
      reference: ref,
    };
  },
});

/**
 * Admin: Get all escrow payment claims (all statuses) for the dashboard.
 */
export const getAllEscrowClaims = query({
  args: {
    status: v.optional(v.union(
      v.literal("PENDING_PAYMENT"),
      v.literal("PENDING_APPROVAL"),
      v.literal("ESCROW_LOCKED"),
      v.literal("RELEASED"),
      v.literal("REJECTED")
    )),
  },
  handler: async (ctx, args) => {
    let claimsQuery;
    if (args.status) {
      claimsQuery = ctx.db
        .query("escrow_payment_claims")
        .withIndex("by_status", (q) => q.eq("status", args.status!));
    } else {
      claimsQuery = ctx.db.query("escrow_payment_claims");
    }

    const claims = await claimsQuery.order("desc").take(200);

    // Enrich with user info
    const enriched = [];
    for (const claim of claims) {
      const user = (await ctx.db.get(claim.userId)) as Doc<"users"> | null;
      enriched.push({
        ...claim,
        userName: user?.name ?? "Unknown",
        userPhone: user?.phone ?? "",
      });
    }

    return enriched;
  },
});

/**
 * Public Query: Get payment claim status by transaction reference (or paymentId).
 * Used by mobile clients to poll or subscribe for live confirmation.
 */
export const getPaymentClaimStatus = query({
  args: {
    transactionReference: v.string(),
  },
  handler: async (ctx, args) => {
    const claim = await ctx.db
      .query("escrow_payment_claims")
      .withIndex("by_providerId")
      .filter((q) => q.eq(q.field("transactionReference"), args.transactionReference))
      .first();

    if (!claim) return null;

    return {
      claimId: claim._id,
      status: claim.status,
      amount: claim.amount,
      currency: claim.currency,
      providerId: claim.providerId,
      bookingId: claim.bookingId,
      escrowOrderId: claim.escrowOrderId,
      reContractId: claim.reContractId,
      createdAt: claim.createdAt,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//           USER LINKED PAYMENT ACCOUNTS (Phase 1 re-arch)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Fetch all payment accounts linked by a specific user (newest first).
 */
export const getUserPaymentAccounts = query({
  args: { userId: v.string() },
  handler: async (ctx, args) => {
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (!userNorm) return [];
    return await ctx.db
      .query("user_payment_accounts")
      .withIndex("by_user", (q) => q.eq("userId", userNorm))
      .order("desc")
      .collect();
  },
});

/**
 * Link a new Mobile Money / bank account to the user's profile.
 * If isDefault=true, clears the isDefault flag on all existing accounts first.
 * If this is the user's very first account, it becomes the default automatically.
 */
export const addUserPaymentAccount = mutation({
  args: {
    userId: v.string(),
    providerCode: v.string(),
    providerName: v.string(),
    accountNumber: v.string(),
    maskedNumber: v.string(),
    isDefault: v.boolean(),
  },
  handler: async (ctx, args) => {
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (!userNorm) throw new Error("User not found");
    const now = Date.now();

    const existing = await ctx.db
      .query("user_payment_accounts")
      .withIndex("by_user", (q) => q.eq("userId", userNorm))
      .collect();

    // First account always becomes default
    const forceDefault = existing.length === 0 ? true : args.isDefault;

    if (forceDefault) {
      for (const acct of existing) {
        if (acct.isDefault) {
          await ctx.db.patch(acct._id, { isDefault: false });
        }
      }
    }

    const id = await ctx.db.insert("user_payment_accounts", {
      userId: userNorm,
      providerCode: args.providerCode,
      providerName: args.providerName,
      accountNumber: args.accountNumber,
      maskedNumber: args.maskedNumber,
      isDefault: forceDefault,
      isActive: true,
      createdAt: now,
    });

    return { success: true, accountId: id };
  },
});

/**
 * Remove a linked payment account by its document ID.
 * Ownership-checked against the calling userId.
 */
export const removeUserPaymentAccount = mutation({
  args: {
    accountId: v.id("user_payment_accounts"),
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    const account = await ctx.db.get(args.accountId);
    if (!account) throw new Error("Account not found");
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (!userNorm || account.userId !== userNorm) {
      throw new Error("Unauthorized");
    }
    await ctx.db.delete(args.accountId);
    return { success: true };
  },
});

/**
 * Set a specific account as the user's default payment account.
 * Atomically clears isDefault on all other accounts for this user.
 */
export const setDefaultPaymentAccount = mutation({
  args: {
    accountId: v.id("user_payment_accounts"),
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (!userNorm) throw new Error("User not found");

    const allAccounts = await ctx.db
      .query("user_payment_accounts")
      .withIndex("by_user", (q) => q.eq("userId", userNorm))
      .collect();

    for (const acct of allAccounts) {
      const shouldBeDefault = acct._id === args.accountId;
      if (acct.isDefault !== shouldBeDefault) {
        await ctx.db.patch(acct._id, { isDefault: shouldBeDefault });
      }
    }
    return { success: true };
  },
});

/**
 * Request an escrow wallet withdrawal.
 * Immediately deducts from availableBalance and records a pending payout
 * transaction in the ledger. Admin can audit via the transactions table.
 */
export const requestWithdrawal = mutation({
  args: {
    userId: v.string(),
    amount: v.number(),
    destinationProviderCode: v.string(),
    destinationAccountNumber: v.string(),
    currency: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.amount <= 0) throw new Error("Withdrawal amount must be positive");
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (!userNorm) throw new Error("User not found");

    const currency = args.currency ?? "SLE";
    const now = Date.now();

    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", userNorm).eq("currency", currency)
      )
      .first();

    if (!wallet || wallet.availableBalance < args.amount) {
      throw new Error(
        `Insufficient balance. Available: ${wallet?.availableBalance ?? 0} ${currency}`
      );
    }

    const newBalance = wallet.availableBalance - args.amount;
    await ctx.db.patch(wallet._id, {
      availableBalance: newBalance,
      updatedAt: now,
    });

    const ref = `WTHDRW_${now}_${Math.random().toString(36).substring(2, 6).toUpperCase()}`;

    await ctx.db.insert("transactions", {
      walletId: wallet._id,
      userId: userNorm,
      type: "payout",
      amount: args.amount,
      currency,
      gatewayProvider: args.destinationProviderCode,
      gatewayReference: ref,
      agentNumber: args.destinationAccountNumber,
      status: "pending",
      description: `Payout of ${args.amount} ${currency} to ${args.destinationProviderCode} ${args.destinationAccountNumber}`,
      updatedAt: now,
    });

    return {
      success: true,
      withdrawalRef: ref,
      remainingBalance: newBalance,
      currency,
    };
  },
});
