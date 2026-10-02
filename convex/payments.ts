// convex/payments.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Payment Processing: Mutations & Internal Functions
// Handles: wallet queries, booking escrow (server-decided split), Monime/Orange Money
//          deposits and verification, payouts, atomic ledger updates (via walletCore)
// ═══════════════════════════════════════════════════════════════════════

import { v } from "convex/values";
import {
  mutation,
  query,
  action,
  internalMutation,
  internalQuery,
  internalAction,
  MutationCtx,
} from "./_generated/server";
import { internal, api } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import {
  requirePositive,
  requireNonEmpty,
} from "./lib/validation";
import {
  sanitizeSierraLeonePhone,
  detectSierraLeoneCarrier,
  resolveCarrier,
  parseCarrierResponse,
  logGatewayError,
} from "./lib/paymentErrors";
import { verifyPassword } from "./auth";
import { requireAuthenticatedUser, requireAdmin, requireSelf, requireAdminSession, requireParticipantOrAdmin } from "./lib/auth";
import { verifyAndTrackPin } from "./lib/pin";
import { activateSubscriptionFromDeposit } from "./subscriptions";
import { fundVehicleOrderFromWallet, fundVehicleOrderFromExternal } from "./escrow";
import { fundReContractFromWallet, fundReContractFromExternal, fundInspectionPassFromWallet } from "./realEstateEscrow";
import { assertValidAmount, findByIdempotencyKey, fundEscrowFromExternalPayment, holdFunds, settleVerifiedDeposit, transferFunds, MAX_SINGLE_TRANSFER } from "./walletCore";
import { bookingSplit, buyerConfirmCompletion, fundBookingFromWallet, releaseBookingEscrow } from "./lib/bookingEscrow";

// ─── GATEWAY SECRETS & CONFIGURATION ────────────────────────────────
function getMoniMeConfig(): { spaceId: string; accessToken: string; apiBaseUrl: string } {
  const spaceId = (process.env.MONIME_SPACE_ID || "").trim();
  const accessToken = (process.env.MONIME_ACCESS_TOKEN || process.env.MONIME_API_KEY || "").trim();
  const apiBaseUrl = (process.env.MONIME_API_BASE_URL || "https://api.monime.io/v1").trim();
  return { spaceId, accessToken, apiBaseUrl };
}


// (The Paystack/Flutterwave payment-intent path — createPaymentIntent, processVerifiedPayment,
// confirmPayment, /payments/webhook — was removed: no such provider was configured and its
// commission was chosen by the client. Bookings are paid via createEscrowPayment or Monime.)

// ═══════════════════════════════════════════════════════════════════════
//                 IN-APP BOOKING PAYMENT INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════

/**
 * Reserves the booking payment reference (no hosted-checkout provider is configured; see body).
 */
export const initializePayment = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    bookingId: v.string(),
    txRef: v.optional(v.string()), // ignored: the server owns the reference
    amount: v.optional(v.number()), // ignored: the booking decides the amount
    currency: v.optional(v.string()),
    customerEmail: v.optional(v.string()),
    customerPhone: v.optional(v.string()),
    customerName: v.optional(v.string()),
    paymentOptions: v.optional(v.string()),
    redirectUrl: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    paymentLink: v.optional(v.string()),
    txRef: v.string(),
    providerConfigured: v.boolean(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const bookingNorm = ctx.db.normalizeId("bookings", args.bookingId);
    if (!bookingNorm) throw new Error("Booking not found");
    const booking = await ctx.db.get(bookingNorm);
    if (!booking || booking.buyerId !== (userId as string)) throw new Error("Booking not found");
    if (booking.paymentStatus === "completed") throw new Error("This booking has already been paid.");

    // Server-generated reference (a client can no longer overwrite a booking's reference).
    let txRef = booking.txRef;
    if (!txRef) {
      const rnd = new Uint8Array(8);
      crypto.getRandomValues(rnd);
      txRef = `VKB-${Array.from(rnd).map((x) => x.toString(16).padStart(2, "0")).join("")}`;
      await ctx.db.patch(bookingNorm, { txRef, updatedAt: Date.now() });
    }

    // PROVIDER INTEGRATION POINT: no card/hosted-checkout provider is configured for bookings, so
    // no payment link is fabricated. The booking is paid from the wallet (payments:createEscrowPayment)
    // or by a verified Mobile Money payment (payments:initiateMoniMePayment).
    return {
      success: false,
      txRef,
      providerConfigured: false,
      message:
        "Direct card checkout is not configured yet. Pay from your Vektolux wallet or use Mobile Money.",
    };
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
    userId: v.optional(v.string()),
    currency: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const currency = args.currency ?? "SLE";
    const { userId: userConvexId } = await requireSelf(ctx, args.sessionToken, args.userId);

    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user", (q) => q.eq("userId", userConvexId))
      .first();

    if (!wallet) {
      return {
        availableBalance: 0.0,
        pendingBalance: 0.0,
        escrowLockedBalance: 0.0,
        escrowBalance: 0.0,
        currency,
        exists: false,
      };
    }

    return {
      walletId: wallet._id,
      availableBalance: wallet.availableBalance,
      pendingBalance: wallet.pendingBalance,
      escrowLockedBalance: wallet.escrowBalance ?? 0.0,
      escrowBalance: wallet.escrowBalance ?? 0.0,
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
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
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
    const limit = Math.min(args.limit ?? 50, 100);
    const { userId: userConvexId } = await requireSelf(ctx, args.sessionToken, args.userId);

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

// (topUpWallet removed: unused; it credited balances without a verified payment or ledger entry)

// (deductWalletBalance removed: unused; wallet debits go through walletCore)

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
 * Pays a booking from the buyer's wallet into escrow. The amount and the vendor/platform split are
 * decided by the SERVER from the booking (fee snapshot, default 85/15); a client split is ignored.
 */
export const createEscrowPayment = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    buyerId: v.optional(v.string()), // consistency check only; the buyer is the authenticated user
    vendorId: v.string(), // consistency check only
    amount: v.number(), // consistency check only: must equal the booking total
    currency: v.optional(v.string()),
    referenceType: v.optional(v.string()), // ignored: taken from the booking
    referenceId: v.string(), // the booking id
    partnerSplitPercent: v.optional(v.number()), // IGNORED (kept so older app builds still validate)
    agentNumber: v.optional(v.string()), // ignored
    momoProvider: v.optional(v.string()),
    idempotencyKey: v.optional(v.string()), // ignored: one escrow per booking
  },
  handler: async (ctx, args) => {
    // Escrow is funded ONLY from the authenticated buyer's real available balance.
    const { userId: buyerId } = await requireSelf(ctx, args.sessionToken, args.buyerId);
    const amount = assertValidAmount(args.amount);

    // The deal itself is the source of truth for who pays whom and how much.
    const bookingId = ctx.db.normalizeId("bookings", args.referenceId);
    const booking = bookingId ? await ctx.db.get(bookingId) : null;
    if (!booking) throw new Error("Booking not found.");
    if (booking.buyerId !== (buyerId as string)) throw new Error("Unauthorized: This booking belongs to another user.");
    if (booking.vendorId !== args.vendorId) throw new Error("Vendor does not match this booking.");
    if (Math.abs(booking.totalAmount - amount) > 0.01) throw new Error("Amount does not match the booking total.");

    const held = await fundBookingFromWallet(ctx, booking._id);
    const split = bookingSplit(booking);
    return {
      success: true,
      duplicate: held.duplicate ?? false,
      transactionId: held.transactionDocId ?? null,
      totalAmount: split.total,
      currency: (booking.currency || "SLE").toUpperCase(),
      partnerAmount: split.vendorAmount,
      platformFeeAmount: split.platformFee,
      availableBalanceAfter: held.availableBalance,
      escrowBalanceAfter: held.escrowBalance,
      escrowStatus: "locked",
    };
  },
});


/**
 * Releases a MARKETPLACE BOOKING's escrow to the vendor. Kept for older app builds; it follows the
 * booking settlement rules (lib/bookingEscrow.ts): the BUYER may confirm once the booking has
 * started, an admin may release a held booking; the vendor never can. Vehicle, property and pass
 * escrows have their own state machines and are refused here.
 */
export const releaseEscrowWithSplit = mutation({
  args: {
    transactionId: v.id("transactions"),
    approverId: v.optional(v.id("users")), // ignored: the approver is the authenticated caller
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const tx = await ctx.db.get(args.transactionId);
    if (!tx) throw new Error("Transaction not found");
    if (tx.type !== "escrow_lock") throw new Error("Transaction is not an escrow lock");

    // Only the paying buyer (confirming delivery) or an admin.
    const who = await requireParticipantOrAdmin(ctx, args.sessionToken, [tx.userId]);

    const bookingId = tx.referenceId ? ctx.db.normalizeId("bookings", tx.referenceId) : null;
    const booking = bookingId ? await ctx.db.get(bookingId) : null;
    if (!booking || booking.escrowId !== (tx._id as string) || booking.buyerId !== (tx.userId as string)) {
      throw new Error("This escrow is not a marketplace booking escrow and cannot be released here.");
    }
    if (tx.escrowStatus !== "locked") throw new Error(`Escrow is already ${tx.escrowStatus ?? "resolved"}`);

    const r =
      String(who.userId) === booking.buyerId
        ? await buyerConfirmCompletion(ctx, booking, booking.buyerId)
        : await releaseBookingEscrow(ctx, booking, "admin");
    return {
      success: true,
      releasedPartnerAmount: r.partnerAmount,
      platformFeeAmount: r.platformFeeAmount,
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
    userId: v.optional(v.string()), // consistency check only
    sessionToken: v.optional(v.string()),
    pin: v.string(),
    currentPin: v.optional(v.string()), // required when a PIN already exists
  },
  handler: async (ctx, args) => {
    // The PIN can only be set for the AUTHENTICATED user (this used to accept any userId,
    // letting anyone overwrite another user's PIN).
    const { userId, user } = await requireSelf(ctx, args.sessionToken, args.userId);
    if (!/^\d{4,6}$/.test(args.pin)) {
      throw new Error("PIN must be 4 to 6 digits");
    }
    // Changing an existing PIN requires the current PIN (with lockout). A failure is RETURNED
    // so the attempt counter persists.
    if (user.walletPinHash) {
      const check = await verifyAndTrackPin(ctx, user, args.currentPin);
      if (!check.ok) return { success: false, errorCode: check.code, message: check.message };
    }
    const pinHash = await generateDeterministicHash(`wallet_pin_${userId}_${args.pin}`);
    await ctx.db.patch(userId, {
      walletPinHash: pinHash,
      pinFailedAttempts: 0,
      pinLockedUntil: undefined,
      updatedAt: Date.now(),
    });
    return { success: true };
  },
});


/**
 * Verify 4-digit Wallet Security PIN before checkout or release.
 */
export const verifyWalletPin = query({
  args: { userId: v.optional(v.string()), sessionToken: v.optional(v.string()), pin: v.string() },
  handler: async (ctx, args) => {
    // Session required (was an unauthenticated PIN oracle). Lockout is enforced by money mutations.
    const { userId, user } = await requireSelf(ctx, args.sessionToken, args.userId);
    if (!user.walletPinHash) return { valid: false, hasPin: false };
    const testHash = await generateDeterministicHash(`wallet_pin_${userId}_${args.pin}`);
    return { valid: testHash === user.walletPinHash, hasPin: true };
  },
});


/**
 * Query whether a user has configured an Escrow Security PIN or password.
 */
export const getUserSecurityPinStatus = query({
  args: { userId: v.optional(v.string()), sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { user } = await requireSelf(ctx, args.sessionToken, args.userId);
    return {
      hasPin: Boolean(user.walletPinHash),
      hasPassword: Boolean(user.passwordHash),
    };
  },
});


/**
 * Verify Transaction PIN or Account Password for payment authorization.
 * Checks walletPinHash first, falls back to passwordHash.
 */
export const verifyTransactionPin = query({
  args: {
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
    pin: v.string(),
  },
  handler: async (ctx, args) => {
    // Session required: this can only ever check the caller's OWN PIN. (It was previously an
    // unauthenticated PIN oracle for any user id.) Attempt lockout is enforced by the money
    // mutations themselves; this read-only check is a convenience pre-validation only.
    const { userId, user } = await requireSelf(ctx, args.sessionToken, args.userId);

    const pinStr = args.pin.trim();
    if (!pinStr) return { valid: false, message: "PIN / Password cannot be empty", hasPin: Boolean(user.walletPinHash) };

    // 1. Check wallet security PIN
    if (user.walletPinHash) {
      const testPinHash = await generateDeterministicHash(`wallet_pin_${userId}_${pinStr}`);
      if (testPinHash === user.walletPinHash) {
        return { valid: true, hasPin: true };
      }
    }

    // 2. Check account password as authorization fallback
    if (user.passwordHash) {
      const isPasswordValid = await verifyPassword(pinStr, user.passwordHash);
      if (isPasswordValid) {
        return { valid: true, hasPin: Boolean(user.walletPinHash) };
      }
    }

    // 3. No PIN or password configured: NEVER treat as authorized.
    if (!user.walletPinHash && !user.passwordHash) {
      return { valid: false, message: "Please set a wallet PIN in Settings first.", hasPin: false };
    }

    return {
      valid: false,
      message: user.walletPinHash
        ? "Incorrect 4-digit PIN or account password."
        : "Incorrect account password.",
      hasPin: Boolean(user.walletPinHash),
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
    // Aggregator checkouts (the removed Moneroo integration) are never offered, even if a stale row exists.
    return methods.filter((m) => m.type !== "AGGREGATOR_AUTO");
  },
});

/**
 * Get all payment methods (enabled + disabled) for admin configurator.
 */
export const getAllPaymentMethods = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
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
    sessionToken: v.optional(v.string()),
    settingsId: v.id("payment_settings"),
    isEnabled: v.optional(v.boolean()),
    displayName: v.optional(v.string()),
    instructions: v.optional(v.string()),
    accountNumber: v.optional(v.string()),
    accountName: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
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
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const existing = await ctx.db.query("payment_settings").first();
    if (existing) {
      return { seeded: false, message: "Payment settings already exist" };
    }

    const now = Date.now();
    const defaults = [
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
//
// A claim is only a REQUEST: nothing is credited and no order changes state until an admin has
// verified the payment with the provider. Approval credits the verified deposit through walletCore
// and then funds the linked order through its real escrow path (money is actually held). A claim can
// only be linked to the claimant's own order that is awaiting payment.

type ClaimLink = { bookingId?: string; escrowOrderId?: Id<"escrow_orders">; reContractId?: Id<"re_escrow_contracts"> };

async function assertClaimLink(ctx: { db: any }, userId: Id<"users">, link: ClaimLink) {
  if ([link.bookingId, link.escrowOrderId, link.reContractId].filter(Boolean).length > 1) {
    throw new Error("A payment can be linked to one order only.");
  }
  if (link.escrowOrderId) {
    const o = await ctx.db.get(link.escrowOrderId);
    if (!o || o.renterOrBuyerId !== userId) throw new Error("Order not found.");
    if (o.status !== "PENDING_PAYMENT") throw new Error("This order is not awaiting payment.");
  }
  if (link.reContractId) {
    const c = await ctx.db.get(link.reContractId);
    if (!c || c.clientId !== userId) throw new Error("Escrow contract not found.");
    if (c.currentState !== "CREATED") throw new Error("This contract is not awaiting payment.");
  }
  if (link.bookingId) {
    const id = ctx.db.normalizeId("bookings", link.bookingId);
    const b = id ? await ctx.db.get(id) : null;
    if (!b || b.buyerId !== (userId as string)) throw new Error("Booking not found.");
    if (b.paymentStatus === "completed" || (b.status !== "pending_payment" && b.status !== "confirmed")) {
      throw new Error("This booking is not awaiting payment.");
    }
  }
}

/**
 * Approves a VERIFIED claim (admin already authorised): credits the deposit (idempotent per provider
 * reference) and funds the claimant's linked order through its escrow helper — which really holds
 * the money, or reports why it could not. Never just flips an order's status.
 */
async function approveClaimCore(ctx: MutationCtx, claim: Doc<"escrow_payment_claims">, admin: Doc<"users">, notes?: string) {
  const now = Date.now();
  // An AUTOMATED claim could only ever be created by the removed aggregator integration; no webhook
  // can confirm one any more, so a leftover pending row can never be approved.
  if (claim.paymentType === "AUTOMATED") {
    if (claim.providerReportedAt === undefined || claim.providerReportedAmount === undefined) {
      throw new Error("The provider has not confirmed this payment yet.");
    }
    if (Math.abs(claim.providerReportedAmount - claim.amount) > 0.005) {
      throw new Error("The amount reported by the provider does not match this claim.");
    }
    if ((claim.providerReportedCurrency ?? claim.currency) !== claim.currency) {
      throw new Error("The currency reported by the provider does not match this claim.");
    }
  }
  const currency = claim.currency || "SLE";
  const settled = await settleVerifiedDeposit(ctx, {
    userId: claim.userId,
    amount: claim.amount,
    currency,
    provider: claim.providerId,
    providerReference: claim.transactionReference || `CLAIM_${claim._id}`,
    description: `Deposit claim approved by Admin (${admin.name || admin._id}) - Ref: ${claim.transactionReference}`,
  });
  let escrow: { funded: boolean; reason?: string } | undefined;
  if (claim.escrowOrderId) {
    const o = await ctx.db.get(claim.escrowOrderId);
    escrow = o && o.renterOrBuyerId === claim.userId
      ? await fundVehicleOrderFromWallet(ctx, claim.escrowOrderId, true)
      : { funded: false, reason: "The order does not belong to the claimant." };
  } else if (claim.reContractId) {
    const c = await ctx.db.get(claim.reContractId);
    escrow = c && c.clientId === claim.userId
      ? await fundReContractFromWallet(ctx, claim.reContractId, true)
      : { funded: false, reason: "The contract does not belong to the claimant." };
  } else if (claim.bookingId) {
    const id = ctx.db.normalizeId("bookings", claim.bookingId);
    const b = id ? await ctx.db.get(id) : null;
    escrow = id && b && b.buyerId === (claim.userId as string)
      ? await fundBookingFromWallet(ctx, id, true)
      : { funded: false, reason: "The booking does not belong to the claimant." };
  }
  await ctx.db.patch(claim._id, { status: "APPROVED", reviewedByAdminId: admin._id, reviewedAt: now });
  await ctx.db.insert("audit_logs", {
    adminUserId: admin._id,
    action: "APPROVE_DEPOSIT",
    targetTransactionId: claim.transactionReference || (claim._id as string),
    snapshot: JSON.stringify({
      claimId: claim._id,
      userId: claim.userId,
      amount: claim.amount,
      currency,
      providerId: claim.providerId,
      transactionReference: claim.transactionReference,
      providerReportedAmount: claim.providerReportedAmount ?? null,
      statusBefore: claim.status,
      statusAfter: "APPROVED",
      adminNotes: notes || null,
      creditedTransactionId: settled.transactionDocId,
      duplicateCredit: settled.duplicate,
      escrow: escrow ?? null,
      resolvedAt: now,
    }),
    timestamp: now,
  });
  await ctx.db.insert("user_notifications", {
    userId: claim.userId as string,
    targetType: "single_user",
    title: "Deposit Approved",
    body: escrow?.funded
      ? `Your payment of ${claim.amount} ${currency} was verified and is now held in escrow for your order.`
      : `Your deposit of ${claim.amount} ${currency} was verified and credited to your wallet.` +
        (escrow && !escrow.funded ? ` It could not be placed in escrow: ${escrow.reason ?? "unavailable"}.` : ""),
    read: false,
    createdAt: now,
  });
  return { settled, escrow, now, currency };
}

/**
 * User: Submit a manual payment claim with SMS Transaction Reference.
 * Sets status to PENDING_APPROVAL for admin review.
 */
export const submitManualPaymentClaim = mutation({
  args: {
    userId: v.optional(v.id("users")), // ignored: the claimant is the authenticated user
    sessionToken: v.optional(v.string()),
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

    const { userId: claimantId, user } = await requireSelf(ctx, args.sessionToken, args.userId);
    // Only the claimant's own order awaiting payment can be linked.
    await assertClaimLink(ctx, claimantId, { bookingId: args.bookingId, escrowOrderId: args.escrowOrderId, reContractId: args.reContractId });

    // Verify provider exists and is enabled
    const provider = await ctx.db
      .query("payment_settings")
      .withIndex("by_providerId", (q) => q.eq("providerId", args.providerId))
      .first();
    if (!provider) throw new Error("Payment provider not found");
    if (!provider.isEnabled) throw new Error("Payment provider is currently disabled");
    // Aggregator checkouts are no longer supported (Moneroo was removed). A typed reference can never
    // create an automated claim.
    if (provider.type === "AGGREGATOR_AUTO") {
      throw new Error("This payment method is no longer available.");
    }
    const paymentType = "MANUAL_CLAIM" as const;

    const now = Date.now();
    const claimId = await ctx.db.insert("escrow_payment_claims", {
      bookingId: args.bookingId,
      escrowOrderId: args.escrowOrderId,
      reContractId: args.reContractId,
      userId: claimantId,
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
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
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
    userId: v.optional(v.id("users")), // consistency check only
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken, args.userId);
    return await ctx.db
      .query("escrow_payment_claims")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
      .order("desc")
      .take(50);
  },
});


/**
 * Admin: Approve a manual payment claim → transitions to ESCROW_LOCKED.
 */
export const approvePaymentClaim = mutation({
  args: {
    claimId: v.id("escrow_payment_claims"),
    adminUserId: v.optional(v.id("users")), // ignored: the admin is the authenticated session
    sessionToken: v.optional(v.string()),
    notes: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { user: admin } = await requireAdminSession(ctx, args.sessionToken);
    const claim = await ctx.db.get(args.claimId);
    if (!claim) throw new Error("Payment claim not found");
    if (claim.status !== "PENDING_APPROVAL") {
      throw new Error(`Cannot approve claim with status: ${claim.status}`);
    }
    // Credits the verified deposit and funds the linked order through its real escrow path
    // (previously this flipped the order to "held" without any money being held).
    const r = await approveClaimCore(ctx, claim, admin, args.notes);
    return { success: true, status: "APPROVED" as const, escrowFunded: r.escrow?.funded ?? null, escrowReason: r.escrow?.reason ?? null };
  },
});

/**
 * Admin: Reject a manual payment claim with reason.
 */
export const rejectPaymentClaim = mutation({
  args: {
    claimId: v.id("escrow_payment_claims"),
    adminUserId: v.optional(v.id("users")), // ignored
    rejectionReason: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const claim = await ctx.db.get(args.claimId);
    if (!claim) throw new Error("Payment claim not found");
    if (claim.status !== "PENDING_APPROVAL") {
      throw new Error(`Cannot reject claim with status: ${claim.status}`);
    }

    requireNonEmpty(args.rejectionReason, "rejectionReason");

    // Admin identity from the authenticated session only.
    const adminAuth = await requireAdminSession(ctx, args.sessionToken);
    const admin = adminAuth.user;

    const now = Date.now();
    await ctx.db.patch(args.claimId, {
      status: "REJECTED",
      rejectionReason: args.rejectionReason,
      reviewedByAdminId: adminAuth.userId,
      reviewedAt: now,
    });

    // Write immutable audit log
    await ctx.db.insert("audit_logs", {
      adminUserId: admin._id,
      action: "REJECT_DEPOSIT",
      targetTransactionId: claim.transactionReference || (claim._id as string),
      snapshot: JSON.stringify({
        claimId: claim._id,
        userId: claim.userId,
        amount: claim.amount,
        currency: claim.currency,
        providerId: claim.providerId,
        transactionReference: claim.transactionReference,
        rejectionReason: args.rejectionReason,
        resolvedAt: now,
      }),
      timestamp: now,
    });

    return { success: true, status: "REJECTED" as const };
  },
});

/**
 * Admin: Atomically resolve manual payment claims (Approve or Reject) with immutable audit logging.
 * Strictly verifies admin role, credits wallet upon approval, records completed transaction,
 * and writes an append-only audit log entry.
 */
export const resolveManualPaymentClaim = mutation({
  args: {
    adminUserId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
    claimId: v.id("escrow_payment_claims"),
    action: v.union(v.literal("APPROVE_DEPOSIT"), v.literal("REJECT_DEPOSIT")),
    notes: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // 1. Admin identity comes from the authenticated SESSION only (adminUserId is ignored):
    // knowing an admin's id must never be enough to approve a deposit.
    const { userId: adminId, user: admin } = await requireAdminSession(ctx, args.sessionToken);

    // 2. Fetch and validate claim state
    const claim = await ctx.db.get(args.claimId);
    if (!claim) {
      throw new Error("CLAIM_NOT_FOUND: Payment claim not found");
    }
    if (claim.status !== "PENDING_APPROVAL") {
      throw new Error(`INVALID_STATUS: Cannot resolve claim with status: ${claim.status}`);
    }

    const now = Date.now();
    const currency = claim.currency || "SLE";

    if (args.action === "APPROVE_DEPOSIT") {
      // Credit through the audited wallet core (idempotent per provider reference), then fund the
      // linked order through its escrow helper — never a bare status change.
      const r = await approveClaimCore(ctx, claim, admin, args.notes);
      return {
        success: true,
        action: "APPROVE_DEPOSIT" as const,
        status: "APPROVED" as const,
        claimId: claim._id,
        creditedUserId: claim.userId,
        amount: claim.amount,
        currency: r.currency,
        newBalance: r.settled.availableBalance,
        escrowFunded: r.escrow?.funded ?? null,
        timestamp: r.now,
      };
    } else {
      // REJECT_DEPOSIT
      const rejectionReason = args.notes || "Deposit claim rejected by administrator";

      await ctx.db.patch(claim._id, {
        status: "REJECTED",
        rejectionReason,
        reviewedByAdminId: admin._id,
        reviewedAt: now,
      });

      // Write immutable audit log
      await ctx.db.insert("audit_logs", {
        adminUserId: admin._id,
        action: "REJECT_DEPOSIT",
        targetTransactionId: claim.transactionReference || (claim._id as string),
        snapshot: JSON.stringify({
          claimId: claim._id,
          userId: claim.userId,
          amount: claim.amount,
          currency,
          providerId: claim.providerId,
          transactionReference: claim.transactionReference,
          statusBefore: "PENDING_APPROVAL",
          statusAfter: "REJECTED",
          rejectionReason,
          resolvedAt: now,
        }),
        timestamp: now,
      });

      // User notification
      await ctx.db.insert("user_notifications", {
        userId: claim.userId as string,
        targetType: "single_user",
        title: "Deposit Claim Rejected",
        body: `Your deposit claim for ${claim.amount} ${currency} was rejected: ${rejectionReason}`,
        read: false,
        createdAt: now,
      });

      return {
        success: true,
        action: "REJECT_DEPOSIT" as const,
        status: "REJECTED" as const,
        claimId: claim._id,
        rejectionReason,
        timestamp: now,
      };
    }
  },
});

/**
 * Query immutable admin audit logs (chronological descending).
 */
export const getAuditLogs = query({
  args: {
    sessionToken: v.optional(v.string()),
    limit: v.optional(v.number()),
    targetTransactionId: v.optional(v.string()),
    adminUserId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const limit = Math.min(args.limit ?? 50, 100);

    if (args.targetTransactionId) {
      return await ctx.db
        .query("audit_logs")
        .withIndex("by_target", (q) =>
          q.eq("targetTransactionId", args.targetTransactionId!)
        )
        .order("desc")
        .take(limit);
    }

    if (args.adminUserId) {
      const adminId = ctx.db.normalizeId("users", args.adminUserId);
      if (adminId) {
        return await ctx.db
          .query("audit_logs")
          .withIndex("by_admin", (q) => q.eq("adminUserId", adminId))
          .order("desc")
          .take(limit);
      }
    }

    return await ctx.db
      .query("audit_logs")
      .order("desc")
      .take(limit);
  },
});

/**
 * Admin: Get all escrow payment claims (all statuses) for the dashboard.
 */
export const getAllEscrowClaims = query({
  args: {
    sessionToken: v.optional(v.string()),
    status: v.optional(v.union(
      v.literal("PENDING_PAYMENT"),
      v.literal("PENDING_APPROVAL"),
      v.literal("ESCROW_LOCKED"),
      v.literal("RELEASED"),
      v.literal("REJECTED")
    )),
  },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
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
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: callerId, user: callerUser } = await requireSelf(ctx, args.sessionToken);
    const claim = await ctx.db
      .query("escrow_payment_claims")
      .withIndex("by_providerId")
      .filter((q) => q.eq(q.field("transactionReference"), args.transactionReference))
      .first();

    if (!claim) return null;
    if (claim.userId !== callerId && callerUser.role !== "admin") return null;

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
  args: { userId: v.optional(v.string()), sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken, args.userId);
    return await ctx.db
      .query("user_payment_accounts")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .order("desc")
      .take(50);
  },
});


/**
 * Link a new Mobile Money / bank account to the user's profile.
 * If isDefault=true, clears the isDefault flag on all existing accounts first.
 * If this is the user's very first account, it becomes the default automatically.
 */
export const addUserPaymentAccount = mutation({
  args: {
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
    providerCode: v.string(),
    providerName: v.string(),
    accountNumber: v.string(),
    maskedNumber: v.string(),
    isDefault: v.boolean(),
  },
  handler: async (ctx, args) => {
    const { userId: userNorm } = await requireSelf(ctx, args.sessionToken, args.userId);
    const digitsOnly = args.accountNumber.replace(/[\s-]/g, "");
    if (!/^\+?\d{6,30}$/.test(digitsOnly)) throw new Error("Enter a valid account number.");
    const now = Date.now();

    const existing = await ctx.db
      .query("user_payment_accounts")
      .withIndex("by_user", (q) => q.eq("userId", userNorm))
      .take(50);

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
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken, args.userId);
    const account = await ctx.db.get(args.accountId);
    if (!account || account.userId !== userId) throw new Error("Account not found");
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
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: userNorm } = await requireSelf(ctx, args.sessionToken, args.userId);

    const allAccounts = await ctx.db
      .query("user_payment_accounts")
      .withIndex("by_user", (q) => q.eq("userId", userNorm))
      .take(50);

    for (const acct of allAccounts) {
      const shouldBeDefault = acct._id === args.accountId;
      if (acct.isDefault !== shouldBeDefault) {
        await ctx.db.patch(acct._id, { isDefault: shouldBeDefault });
      }
    }
    return { success: true };
  },
});

// NOTE: withdrawals now live in convex/withdrawals.ts (reserve → confirm/release state machine).

// ═══════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════
//          ORANGE MONEY SIERRA LEONE WEBHOOK & DEPOSIT HANDLER
// ═══════════════════════════════════════════════════════════════════════

/**
 * Generate Sierra Leone phone variations for database lookup.
 * Handles inputs like +23276123456, 23276123456, 076123456, 76123456.
 */
/**
 * Generate Sierra Leone phone variations for database lookup.
 * Robustly handles raw, spaced, hyphenated, and local/international formats:
 * e.g. "+232 73 623 761", "+23273623761", "073623761", "73623761", "232-73-623-761".
 */
export function getSierraLeonePhoneCandidates(phone: string): string[] {
  if (!phone) return [];
  const trimmed = phone.trim();
  const digits = trimmed.replace(/\D/g, "");
  const candidates = new Set<string>();
  candidates.add(trimmed);
  if (digits) {
    candidates.add(digits);
    if (digits.length >= 8) {
      const core8 = digits.slice(-8);
      candidates.add(`+232${core8}`);
      candidates.add(`232${core8}`);
      candidates.add(`0${core8}`);
      candidates.add(core8);

      // Spaced variations (e.g. "+232 73 623 761")
      const prefix = core8.slice(0, 2);
      const mid = core8.slice(2, 5);
      const rest = core8.slice(5);
      candidates.add(`+232 ${prefix} ${mid} ${rest}`);
      candidates.add(`232 ${prefix} ${mid} ${rest}`);
      candidates.add(`0${prefix} ${mid} ${rest}`);
      candidates.add(`${prefix} ${mid} ${rest}`);
      candidates.add(`+232 ${prefix} ${core8.slice(2)}`);
      candidates.add(`0${prefix} ${core8.slice(2)}`);

      // Hyphenated variations
      candidates.add(`+232-${prefix}-${mid}-${rest}`);
      candidates.add(`0${prefix}-${mid}-${rest}`);
    }
  }
  return Array.from(candidates);
}

/**
 * Shared transactional handler for all Carrier deposits (Orange Money, Africell, etc.).
 * Implements strict idempotency checking against `transactions.by_transaction_id` and `telco_webhook_logs`,
 * orphaned user handling, double-entry ledger creation, and real-time wallet balance crediting.
 */
async function executeCarrierDeposit(
  ctx: MutationCtx,
  args: {
    txnId: string;
    phoneNumber: string;
    amount: number;
    status: string;
    currency?: string;
    provider?: string;
    rawPayload?: string;
    userId?: string;
  }
) {
  const now = Date.now();
  const currency = args.currency || "SLE";
  const provider = args.provider || "ORANGE_MONEY_SL";
  const rawPayloadStr = args.rawPayload ?? JSON.stringify({});

  try {
    // 1. Idempotency & Double-Credit Protection
    // Check A: Primary lookup on transactions table by transactionId index
    const existingTxById = await ctx.db
      .query("transactions")
      .withIndex("by_transaction_id", (q) => q.eq("transactionId", args.txnId))
      .first();

    // Check B: Lookup on transactions table by gateway provider + reference index
    const existingTxByRef = await ctx.db
      .query("transactions")
      .withIndex("by_gateway_ref", (q) =>
        q.eq("gatewayProvider", provider).eq("gatewayReference", args.txnId)
      )
      .first();

    // Check C: Lookup in telco_webhook_logs
    const existingLog = await ctx.db
      .query("telco_webhook_logs")
      .withIndex("by_ext_id", (q) => q.eq("externalTransactionId", args.txnId))
      .first();

    if (existingTxById || existingTxByRef || (existingLog && existingLog.isProcessed)) {
      if (existingLog && !existingLog.isProcessed) {
        await ctx.db.patch(existingLog._id, {
          isProcessed: true,
          processedAt: now,
          status: "ALREADY_PROCESSED",
        });
      }
      return {
        success: true,
        status: "ALREADY_PROCESSED",
        message: "Transaction already exists in transaction ledger",
        carrierTransactionId: args.txnId,
        txnId: args.txnId,
      };
    }

    // Create or reuse pending telco webhook log entry
    let logId = existingLog ? existingLog._id : null;
    if (!logId) {
      logId = await ctx.db.insert("telco_webhook_logs", {
        provider,
        externalTransactionId: args.txnId,
        idempotencyKey: `${provider.toLowerCase()}_${args.txnId}`,
        requestPayload: rawPayloadStr,
        isProcessed: false,
        amount: args.amount,
        status: args.status,
        phoneNumber: args.phoneNumber,
        receivedAt: now,
      });
    }

    // 2. Identify target user in 'users'
    let user: Doc<"users"> | null = null;
    if (args.userId) {
      const userNorm = ctx.db.normalizeId("users", args.userId);
      if (userNorm) user = await ctx.db.get(userNorm);
    }

    if (!user && args.phoneNumber) {
      const candidates = getSierraLeonePhoneCandidates(args.phoneNumber);
      for (const candidate of candidates) {
        user = await ctx.db
          .query("users")
          .withIndex("by_phone", (q) => q.eq("phone", candidate))
          .first();
        if (user) break;
      }

    }

    // If no user matches the phone number, log as ORPHANED_USER and exit cleanly
    if (!user) {
      if (logId) {
        await ctx.db.patch(logId, {
          status: "ORPHANED_USER",
          errorMessage: "No user matches the paying phone number",
          processedAt: now,
        });
      }
      return {
        success: false,
        status: "ORPHANED_USER",
        message: "No user found for the paying phone number. Transaction held for manual resolution.",
        carrierTransactionId: args.txnId,
        txnId: args.txnId,
      };
    }

    // 3. Check status
    const normalizedStatus = args.status.toUpperCase();
    const isSuccess =
      normalizedStatus === "SUCCESS" ||
      normalizedStatus === "COMPLETED" ||
      normalizedStatus === "SUCCESSFUL";

    if (!isSuccess) {
      // Recorded, but NOT marked processed: a "pending" delivery must not stop a later real
      // success for the same transaction from being credited (it is still credited at most once).
      if (logId) {
        await ctx.db.patch(logId, {
          status: args.status,
          errorMessage: `Telco webhook status reported as ${args.status}`,
          processedAt: now,
        });
      }
      return {
        success: true,
        status: args.status,
        message: `Payment status ${args.status} recorded without crediting wallet.`,
        carrierTransactionId: args.txnId,
        txnId: args.txnId,
      };
    }

    // 4. Credit through the wallet core: one atomic, idempotent, double-entry settlement.
    const settled = await settleVerifiedDeposit(ctx, {
      userId: user._id,
      amount: args.amount,
      currency,
      provider,
      providerReference: args.txnId,
      description: `${provider} deposit (Ref: ${args.txnId})`,
    });
    const newBalance = settled.availableBalance;

    // 7. Mark 'telco_webhook_logs' as processed
    if (logId) {
      await ctx.db.patch(logId, {
        isProcessed: true,
        processedAt: now,
        status: "COMPLETED",
      });
    }

    // 8. In-app notification for the user
    await ctx.db.insert("user_notifications", {
      userId: user._id as string,
      targetType: "single_user",
      title: "Wallet Credited",
      body: `Your wallet has been credited with ${args.amount} ${currency} via ${provider}.`,
      read: false,
      createdAt: now,
    });

    return {
      success: true,
      status: "COMPLETED",
      creditedUserId: user._id,
      amount: args.amount,
      currency,
      newBalance,
      carrierTransactionId: args.txnId,
      txnId: args.txnId,
    };
  } catch (err: any) {
    console.error("[executeCarrierDeposit] Unexpected processing error:", err?.message || String(err));
    return {
      success: false,
      status: "ERROR",
      message: "Carrier deposit could not be processed.",
      carrierTransactionId: args.txnId,
      txnId: args.txnId,
    };
  }
}

async function executeOrangeMoneyWebhook(
  ctx: MutationCtx,
  args: {
    txnId: string;
    phoneNumber: string;
    amount: number;
    status: string;
    currency?: string;
    rawPayload?: string;
    userId?: string;
  }
) {
  return await executeCarrierDeposit(ctx, {
    ...args,
    provider: "ORANGE_MONEY_SL",
  });
}

/**
 * Idempotent internal mutation to process carrier deposits (Orange Money, Africell).
 * Checks transactions.by_transaction_id to prevent double-crediting.
 */
export const processIncomingCarrierDeposit = internalMutation({
  args: {
    carrierTransactionId: v.string(),
    amount: v.number(),
    phoneNumber: v.string(),
    currency: v.optional(v.string()),
    provider: v.optional(v.string()),
    rawPayload: v.optional(v.string()),
    userId: v.optional(v.string()),
    status: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    return await executeCarrierDeposit(ctx, {
      txnId: args.carrierTransactionId,
      phoneNumber: args.phoneNumber,
      amount: args.amount,
      currency: args.currency || "SLE",
      provider: args.provider || "ORANGE_MONEY_SL",
      status: args.status || "COMPLETED",
      rawPayload: args.rawPayload,
      userId: args.userId,
    });
  },
});

/**
 * Process an incoming Orange Money deposit.
 * PROTECTED: internalMutation only callable by verified carrier webhooks or admin clearance.
 * End users cannot call this mutation directly.
 */
export const depositOrangeMoney = internalMutation({
  args: {
    phoneNumber: v.string(),
    amount: v.number(),
    currency: v.optional(v.string()),
    txId: v.optional(v.string()),
    userId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    try {
      const generatedTxId =
        args.txId ||
        `OM_DEP_${Date.now()}_${Math.random().toString(36).substring(2, 7).toUpperCase()}`;

      return await executeOrangeMoneyWebhook(ctx, {
        txnId: generatedTxId,
        phoneNumber: args.phoneNumber,
        amount: args.amount,
        status: "COMPLETED",
        currency: args.currency || "SLE",
        userId: args.userId,
      });
    } catch (err: any) {
      console.error("[depositOrangeMoney] Error during Orange Money deposit:", err?.message ?? "unknown");
      return {
        success: false,
        status: "FAILED",
        message: err?.message || "Deposit processing failed",
      };
    }
  },
});

export const processOrangeMoneyWebhook = internalMutation({
  args: {
    txnId: v.string(),
    phoneNumber: v.string(),
    amount: v.number(),
    status: v.string(),
    currency: v.optional(v.string()),
    rawPayload: v.optional(v.string()),
    userId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    return await executeOrangeMoneyWebhook(ctx, args);
  },
});

export const processOrangeMoneyDeposit = internalMutation({
  args: {
    txId: v.string(),
    amount: v.number(),
    currency: v.string(),
    phoneNumber: v.string(),
    userId: v.optional(v.string()),
    userPhone: v.optional(v.string()),
    status: v.string(),
    rawPayload: v.optional(v.any()),
  },
  handler: async (ctx, args) => {
    return await executeOrangeMoneyWebhook(ctx, {
      txnId: args.txId,
      phoneNumber: args.userPhone || args.phoneNumber,
      amount: args.amount,
      status: args.status,
      currency: args.currency,
      rawPayload:
        typeof args.rawPayload === "string"
          ? args.rawPayload
          : JSON.stringify(args.rawPayload ?? {}),
      userId: args.userId,
    });
  },
});

// ═══════════════════════════════════════════════════════════════════════
//          PRODUCTION ZERO-MOCK P2P TRANSFER & ESCROW LEDGER
// ═══════════════════════════════════════════════════════════════════════

/**
 * Resolve a recipient for a transfer. Requires an authenticated session and returns
 * ONLY what the sender needs to confirm the right person (name, masked phone,
 * verification) — never email/role, and never an unbounded scan.
 */
export const resolveRecipient = query({
  args: {
    query: v.string(),
    senderUserId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: senderId } = await requireSelf(ctx, args.sessionToken, args.senderUserId);
    const rawQuery = (args.query || "").trim();
    if (!rawQuery || rawQuery.length < 3 || rawQuery.length > 120) {
      return { found: false, error: "Recipient identifier must be at least 3 characters." };
    }

    let matchedUser: Doc<"users"> | null = null;

    const asId = ctx.db.normalizeId("users", rawQuery);
    if (asId) matchedUser = await ctx.db.get(asId);

    if (!matchedUser) {
      for (const cand of getSierraLeonePhoneCandidates(rawQuery)) {
        const user = await ctx.db.query("users").withIndex("by_phone", (q) => q.eq("phone", cand)).first();
        if (user) {
          matchedUser = user;
          break;
        }
      }
    }
    if (!matchedUser && rawQuery.includes("@")) {
      matchedUser = await ctx.db
        .query("users")
        .withIndex("by_email", (q) => q.eq("email", rawQuery.toLowerCase()))
        .first();
    }

    if (!matchedUser || matchedUser.isActive === false) {
      return { found: false, error: "Recipient not found." };
    }
    if (matchedUser._id === senderId) {
      return { found: false, error: "You cannot transfer funds to yourself." };
    }

    const digits = (matchedUser.phone || "").replace(/\D/g, "");
    const maskedPhone = digits.length >= 4 ? `•••• ${digits.slice(-3)}` : "";
    return {
      found: true,
      recipientId: matchedUser._id as string,
      name: matchedUser.name,
      phone: maskedPhone,
      verificationBadge: (matchedUser as any).verificationBadge || "NONE",
      isVerified: matchedUser.isVerified || false,
    };
  },
});

/**
 * Execute an atomic peer-to-peer transfer from the AUTHENTICATED user.
 * Identity comes from the session (senderUserId is only a consistency check).
 * Authorized by PIN with brute-force lockout; idempotent via `idempotencyKey`.
 * A PIN failure is RETURNED as { success:false, errorCode, message } so the
 * attempt counter persists.
 */
export const executeP2PTransfer = mutation({
  args: {
    senderUserId: v.optional(v.string()),
    recipientQuery: v.string(),
    amount: v.number(),
    note: v.optional(v.string()),
    pin: v.string(),
    sessionToken: v.optional(v.string()),
    idempotencyKey: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: senderId, user: sender } = await requireSelf(ctx, args.sessionToken, args.senderUserId);

    const amount = assertValidAmount(args.amount, MAX_SINGLE_TRANSFER);

    // Resolve recipient (bounded, indexed lookups only).
    const rawQuery = args.recipientQuery.trim();
    let recipient: Doc<"users"> | null = null;
    const asId = ctx.db.normalizeId("users", rawQuery);
    if (asId) recipient = await ctx.db.get(asId);
    if (!recipient) {
      for (const cand of getSierraLeonePhoneCandidates(rawQuery)) {
        const u = await ctx.db.query("users").withIndex("by_phone", (q) => q.eq("phone", cand)).first();
        if (u) {
          recipient = u;
          break;
        }
      }
    }
    if (!recipient && rawQuery.includes("@")) {
      recipient = await ctx.db.query("users").withIndex("by_email", (q) => q.eq("email", rawQuery.toLowerCase())).first();
    }
    if (!recipient) throw new Error(`RECIPIENT_NOT_FOUND: No recipient found.`);
    if (recipient._id === senderId) throw new Error("INVALID_TRANSFER: You cannot transfer funds to yourself.");
    if (recipient.isActive === false) throw new Error("RECIPIENT_INACTIVE: Recipient account has been suspended or deactivated.");

    // A retried request with the same key returns the original receipt (no PIN, no second debit).
    if (args.idempotencyKey) {
      const prior = await findByIdempotencyKey(ctx, senderId, args.idempotencyKey);
      if (prior) {
        return {
          success: true,
          duplicate: true,
          transactionId: prior.transactionId ?? (prior._id as string),
          amount: prior.amount,
          feeAmount: 0,
          netAmount: prior.amount,
          currency: prior.currency,
          timestamp: prior.createdAt ?? prior._creationTime,
          recipientName: recipient.name,
          status: "COMPLETED",
        };
      }
    }

    const pinCheck = await verifyAndTrackPin(ctx, sender, args.pin);
    if (!pinCheck.ok) {
      return { success: false, errorCode: pinCheck.code, message: pinCheck.message };
    }

    const result = await transferFunds(ctx, {
      senderId,
      recipientId: recipient._id,
      amount,
      idempotencyKey: args.idempotencyKey,
      note: args.note?.trim().slice(0, 140) || undefined,
      referenceType: "p2p_transfer",
    });

    await ctx.db.insert("user_notifications", {
      userId: recipient._id as string,
      targetType: "single_user",
      title: "Funds Received!",
      body: `You received SLE ${amount.toFixed(2)} from ${sender.name}.`,
      read: false,
      createdAt: result.timestamp,
    });

    return {
      success: true,
      duplicate: result.duplicate,
      transactionId: result.transactionId,
      amount,
      feeAmount: 0,
      netAmount: amount,
      currency: "SLE",
      timestamp: result.timestamp,
      senderName: sender.name,
      recipientName: recipient.name,
      senderBalanceAfter: result.senderBalanceAfter,
      status: "COMPLETED",
      description: args.note || `P2P Transfer to ${recipient.name}`,
    };
  },
});

/**
 * Atomic Escrow Lock mutation.
 * Deducts funds from buyer availableBalance and locks them into escrowBalance.
 */
// (lockEscrowFunds removed: no caller; it let a user lock funds under any reference with no
// counterparty and no release path, so the money would stay stuck. Escrow is entered only through
// the order-specific funding paths: bookings, vehicle orders, property contracts, viewing passes.)

/**
 * Retrieve verified transaction receipt for the confirmation screen.
 */
export const getTransactionReceipt = query({
  args: {
    transactionId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: callerId } = await requireSelf(ctx, args.sessionToken);
    // Transfers write one row per party under the same transactionId: return the CALLER's own row.
    const rows = await ctx.db
      .query("transactions")
      .withIndex("by_transaction_id", (q) => q.eq("transactionId", args.transactionId))
      .take(5);
    const tx = rows.find((r) => r.userId === callerId) ?? null;

    if (!tx) return null;

    const sender = await ctx.db.get(tx.userId);
    const counterparty = tx.counterpartyId ? await ctx.db.get(tx.counterpartyId) : null;
    const wallet = await ctx.db.get(tx.walletId);

    return {
      transactionId: tx.transactionId,
      type: tx.type,
      amount: tx.amount,
      feeAmount: tx.feeAmount ?? 0,
      netAmount: tx.netAmount ?? tx.amount,
      currency: tx.currency,
      status: tx.status,
      timestamp: tx.createdAt ?? tx.updatedAt,
      description: tx.description,
      gatewayProvider: tx.gatewayProvider,
      senderName: sender?.name ?? "Vektolux User",
      senderPhone: sender?.phone ?? "",
      counterpartyName: tx.counterpartyName ?? counterparty?.name ?? "Counterparty",
      counterpartyPhone: tx.counterpartyPhone ?? counterparty?.phone ?? "",
      currentWalletBalance: wallet?.availableBalance ?? 0,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 MONIME SIERRA LEONE PAYMENT PIPELINE
// ═══════════════════════════════════════════════════════════════════════

/**
 * Record a pending MoniMe payment transaction before carrier dispatch.
 */
export const recordPendingMoniMeTransaction = internalMutation({
  args: {
    userId: v.optional(v.string()),
    amount: v.number(),
    currency: v.string(),
    provider: v.string(),
    reference: v.string(),
    customerPhone: v.string(),
    description: v.string(),
    subscriptionTierCode: v.optional(v.string()),
    // "vehicle:<orderId>" | "re:<contractId>" | "pass:<passId>" - escrow funded once Monime confirms
    escrowCheckout: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    let userDoc: Doc<"users"> | null = null;
    if (args.userId && args.userId.trim().length > 0) {
      const userNorm = ctx.db.normalizeId("users", args.userId);
      if (userNorm) {
        userDoc = await ctx.db.get(userNorm);
      }
    }

    if (!userDoc && args.customerPhone) {
      const candidates = getSierraLeonePhoneCandidates(args.customerPhone);
      for (const cand of candidates) {
        userDoc = await ctx.db
          .query("users")
          .withIndex("by_phone", (q) => q.eq("phone", cand))
          .first();
        if (userDoc) break;
      }
    }

    if (!userDoc) {
      console.log(`[MoniMe Pending] No user doc resolved for pending tx ${args.reference}`);
      return { success: false, reason: "USER_NOT_RESOLVED" };
    }

    const now = Date.now();
    let wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", userDoc!._id).eq("currency", args.currency)
      )
      .first();

    let walletId: Id<"walletBalances">;
    if (!wallet) {
      walletId = await ctx.db.insert("walletBalances", {
        userId: userDoc._id,
        availableBalance: 0,
        pendingBalance: 0,
        escrowBalance: 0,
        currency: args.currency,
        updatedAt: now,
      });
    } else {
      walletId = wallet._id;
    }

    const txId = await ctx.db.insert("transactions", {
      transactionId: args.reference,
      walletId,
      userId: userDoc._id,
      type: "top_up",
      amount: args.amount,
      currency: args.currency,
      gatewayProvider: `MONIME_${args.provider.toUpperCase()}`,
      gatewayReference: args.reference,
      status: "pending",
      description: args.description,
      ...(args.subscriptionTierCode
        ? { referenceType: "subscription_checkout", referenceId: args.subscriptionTierCode }
        : args.escrowCheckout
        ? { referenceType: "escrow_checkout", referenceId: args.escrowCheckout }
        : {}),
      createdAt: now,
      updatedAt: now,
    });

    return {
      success: true,
      transactionDocId: txId,
      reference: args.reference,
    };
  },
});

/**
 * Link an active MoniMe payment-code ID (pmc-...) and optional USSD code
 * directly to the pending transaction record for instant webhook & API lookup.
 */
export const updatePendingPaymentCode = internalMutation({
  args: {
    reference: v.string(),
    paymentCodeId: v.string(),
    ussdCode: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const tx = await ctx.db
      .query("transactions")
      .withIndex("by_transaction_id", (q) => q.eq("transactionId", args.reference))
      .first();

    if (tx) {
      await ctx.db.patch(tx._id, {
        gatewayReference: args.paymentCodeId,
        updatedAt: Date.now(),
      });
      return { success: true };
    }
    return { success: false };
  },
});

/**
 * Internal query: Fetch pending transaction details for active gateway verification.
 */
/** Resolves the authenticated caller for actions (which have no ctx.db). */
export const getSessionCaller = internalQuery({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { userId, user } = await requireSelf(ctx, args.sessionToken);
    return { userId: userId as string, isAdmin: user.role === "admin" };
  },
});

/**
 * INTERNAL: what an escrow checkout costs, decided by the SERVER from the order/contract/pass, and
 * confirmation that the caller is the paying party and the item is still awaiting payment.
 */
export const getEscrowCheckoutQuote = internalQuery({
  args: {
    userId: v.id("users"),
    escrowOrderId: v.optional(v.string()),
    reContractId: v.optional(v.string()),
    inspectionPassId: v.optional(v.string()),
    bookingId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.bookingId) {
      const id = ctx.db.normalizeId("bookings", args.bookingId);
      const b = id ? await ctx.db.get(id) : null;
      if (!b || b.buyerId !== (args.userId as string)) throw new Error("Booking not found.");
      if (b.paymentStatus === "completed" || b.status === "cancelled" || b.status === "completed") {
        throw new Error("This booking is not awaiting payment.");
      }
      return { amount: b.totalAmount, label: `Booking: ${b.listingTitle}`.slice(0, 80), tag: `booking:${b._id}` };
    }
    if (args.escrowOrderId) {
      const id = ctx.db.normalizeId("escrow_orders", args.escrowOrderId);
      const o = id ? await ctx.db.get(id) : null;
      if (!o || o.renterOrBuyerId !== args.userId) throw new Error("Escrow order not found.");
      if (o.status !== "PENDING_PAYMENT") throw new Error("This order is not awaiting payment.");
      return { amount: o.grossEscrowAmount, label: `Vehicle escrow ${o.orderCode}`, tag: `vehicle:${o._id}` };
    }
    if (args.reContractId) {
      const id = ctx.db.normalizeId("re_escrow_contracts", args.reContractId);
      const c = id ? await ctx.db.get(id) : null;
      if (!c || c.clientId !== args.userId) throw new Error("Escrow contract not found.");
      if (c.currentState !== "CREATED") throw new Error("This contract is not awaiting payment.");
      return { amount: c.grossAmount, label: `Property escrow ${c.contractCode}`, tag: `re:${c._id}` };
    }
    if (args.inspectionPassId) {
      const id = ctx.db.normalizeId("re_inspection_passes", args.inspectionPassId);
      const p = id ? await ctx.db.get(id) : null;
      if (!p || p.clientId !== args.userId) throw new Error("Inspection pass not found.");
      if (p.status !== "CREATED") throw new Error("This pass is not awaiting payment.");
      return { amount: p.tourFee, label: "Viewing tour pass", tag: `pass:${p._id}` };
    }
    throw new Error("Nothing to pay for.");
  },
});

export const getPendingTransactionForVerification = internalQuery({
  args: {
    reference: v.string(),
  },
  handler: async (ctx, args) => {
    let tx = await ctx.db
      .query("transactions")
      .withIndex("by_transaction_id", (q) => q.eq("transactionId", args.reference))
      .first();

    if (!tx) {
      tx = await ctx.db
        .query("transactions")
        .filter((q) =>
          q.or(
            q.eq(q.field("gatewayReference"), args.reference),
            q.eq(q.field("transactionId"), args.reference)
          )
        )
        .first();
    }

    if (!tx) return null;

    return {
      _id: tx._id,
      transactionId: tx.transactionId,
      gatewayReference: tx.gatewayReference,
      status: tx.status,
      amount: tx.amount,
      currency: tx.currency,
      userId: tx.userId as string,
    };
  },
});

/**
 * Action: Initiate payment via MoniMe Sierra Leone Dual-Header HTTP Engine.
 * Headers:
 *   Authorization: Bearer <MONIME_ACCESS_TOKEN>
 *   Monime-Space-Id: <MONIME_SPACE_ID>
 *   Content-Type: application/json
 */
export const initiateMoniMePayment = action({
  args: {
    amount: v.number(),
    phoneNumber: v.optional(v.string()),
    customerPhone: v.optional(v.string()),
    provider: v.optional(v.string()), // slug: "orange" | "africell" | "qmoney"
    providerId: v.optional(v.string()), // explicit MoniMe ID: "m17" | "m18" | "m19" (client override)
    email: v.optional(v.string()),
    customerEmail: v.optional(v.string()),
    customerName: v.optional(v.string()),
    userId: v.optional(v.string()), // ignored: the payer is the authenticated user
    sessionToken: v.optional(v.string()),
    currency: v.optional(v.string()),
    description: v.optional(v.string()),
    bookingId: v.optional(v.string()),
    escrowOrderId: v.optional(v.string()),
    reContractId: v.optional(v.string()),
    returnUrl: v.optional(v.string()),
    // Direct payment for a professional subscription: the amount is quoted by the SERVER.
    subscriptionTierCode: v.optional(v.string()),
    inspectionPassId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const caller: any = await ctx.runQuery(internal.payments.getSessionCaller, { sessionToken: args.sessionToken });
    const callerUserId: string = caller.userId;
    let amount: number = args.amount;
    let purposeDescription: string | undefined;
    if (args.subscriptionTierCode) {
      const quote: any = await ctx.runQuery(internal.subscriptions.getCheckoutQuote, {
        userId: callerUserId as Id<"users">,
        tierCode: args.subscriptionTierCode,
      });
      amount = quote.price;
      purposeDescription = `${quote.name} subscription`;
    }
    let escrowCheckout: string | undefined;
    if (args.escrowOrderId || args.reContractId || args.inspectionPassId || args.bookingId) {
      if (args.subscriptionTierCode) throw new Error("Choose one payment purpose.");
      if ([args.escrowOrderId, args.reContractId, args.inspectionPassId, args.bookingId].filter(Boolean).length > 1) {
        throw new Error("Choose one payment purpose.");
      }
      // The escrow amount is decided by the server from the order itself; a client amount is ignored.
      const quote: any = await ctx.runQuery(internal.payments.getEscrowCheckoutQuote, {
        userId: callerUserId as Id<"users">,
        escrowOrderId: args.escrowOrderId,
        reContractId: args.reContractId,
        inspectionPassId: args.inspectionPassId,
        bookingId: args.bookingId,
      });
      amount = quote.amount;
      purposeDescription = quote.label;
      escrowCheckout = quote.tag;
    }
    amount = assertValidAmount(amount);
    const { spaceId, accessToken: token, apiBaseUrl } = getMoniMeConfig();
    const accessToken = token;

    const rawPhone = args.phoneNumber || args.customerPhone || "";
    let cleanPhone = rawPhone.replace(/\D/g, "");
    if (cleanPhone.startsWith("0")) {
      cleanPhone = "232" + cleanPhone.substring(1);
    } else if (!cleanPhone.startsWith("232") && cleanPhone.length === 8) {
      cleanPhone = "232" + cleanPhone;
    }
    const sanitizedPhone = cleanPhone || "23276000000";
    const dynamicEmail = (args.email || args.customerEmail)?.trim();
    const currency = args.currency ?? "SLE";
    const reference = `vktlx_monime_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const returnUrl = args.returnUrl ?? "vektolux://payment/success";

    // ── Carrier resolution: explicit client override takes priority ──
    const explicitId = args.providerId || args.provider || "";
    const resolvedCarrier = resolveCarrier(cleanPhone || undefined, explicitId || undefined);
    let providerSlug: string = resolvedCarrier !== "unknown" ? resolvedCarrier : "orange";

    // Normalize hosted checkout triggers back to auto-carrier
    if (["auto", "monime", "monime_auto", "card", "bank"].includes(providerSlug)) {
      const autoCarrier = cleanPhone ? detectSierraLeoneCarrier(cleanPhone) : "unknown";
      providerSlug = autoCarrier !== "unknown" ? autoCarrier : "orange";
    }

    const description =
      purposeDescription ?? args.description ?? `Deposit SLE ${amount} into your Vektolux wallet`;

    // 1. Record the pending transaction FIRST. Without it the payment could not be matched to its
    //    payer, so no checkout is created if this fails.
    const pending: any = await ctx.runMutation(internal.payments.recordPendingMoniMeTransaction, {
      userId: callerUserId,
      amount,
      currency,
      provider: providerSlug,
      reference,
      customerPhone: sanitizedPhone,
      description,
      ...(args.subscriptionTierCode ? { subscriptionTierCode: args.subscriptionTierCode } : {}),
      ...(escrowCheckout ? { escrowCheckout } : {}),
    });
    if (!pending?.success) {
      return { success: false, code: "PAYMENT_NOT_STARTED", message: "Could not start the payment. Please try again." };
    }

    const minorAmount = Math.round(amount * 100);

    // 2. Construct dynamic checkout session payload strictly per MoniMe API specification
    const checkoutPayload: Record<string, any> = {
      name: args.subscriptionTierCode ? "Vektolux Subscription" : escrowCheckout ? "Vektolux Escrow Payment" : "Vektolux Wallet Deposit",
      description,
      lineItems: [
        {
          name: "Escrow Wallet Deposit",
          type: "custom",
          quantity: 1,
          price: {
            currency: "SLE",
            value: minorAmount,
          },
        },
      ],
      paymentOptions: {
        card: { disable: false },
        bank: { disable: false },
        momo: { disable: false },
      },
      successUrl: returnUrl,
      cancelUrl: "vektolux://payment/cancel",
      metadata: {
        userId: callerUserId ?? "",
        type: args.subscriptionTierCode ? "subscription" : escrowCheckout ? "escrow_deposit" : "wallet_deposit",
        amount: String(amount),
        reference,
        provider: providerSlug,
        providerId: providerSlug === "orange" ? "m17" : (providerSlug === "africell" ? "m18" : "m19"),
        phoneNumber: sanitizedPhone,
        source: "vektolux_mobile_app",
        ...(args.bookingId ? { bookingId: args.bookingId } : {}),
        ...(args.escrowOrderId ? { escrowOrderId: args.escrowOrderId } : {}),
        ...(args.reContractId ? { reContractId: args.reContractId } : {}),
      },
    };



    try {
      const response = await fetch(`${apiBaseUrl}/checkout-sessions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token.trim()}`,
          "Monime-Space-Id": spaceId.trim(),
          "monime-space-id": spaceId.trim(),
          "Idempotency-Key": reference,
        },
        body: JSON.stringify(checkoutPayload),
      });

      const responseStatus = response.status;
      const resText = await response.text();
      console.log("[MoniMe] checkout-session create status:", responseStatus);

      let resJson: any = null;
      try {
        resJson = JSON.parse(resText);
      } catch (_) {
        resJson = { raw: resText };
      }

      if (!response.ok) {
        // Fallback to direct mobile payment-codes on MoniMe
        console.log(`[MoniMe Fallback] Checkout session returned ${responseStatus}. Trying direct mobile payment-codes endpoint...`);
          const formattedPhone = sanitizedPhone.startsWith("+") ? sanitizedPhone : `+${sanitizedPhone}`;
          const paymentCodePayload = {
            name: description,
            amount: {
              currency: "SLE",
              value: minorAmount,
            },
            authorizedPhoneNumber: formattedPhone,
            reference,
            metadata: {
              reference,
              provider: providerSlug,
              phoneNumber: sanitizedPhone,
              source: "vektolux_mobile_app",
            },
          };

          try {
            const pcRes = await fetch(`${apiBaseUrl}/payment-codes`, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${token.trim()}`,
                "Monime-Space-Id": spaceId.trim(),
                "monime-space-id": spaceId.trim(),
                "Idempotency-Key": reference,
              },
              body: JSON.stringify(paymentCodePayload),
            });

            const pcText = await pcRes.text();
            console.log("[MoniMe] payment-code create status:", pcRes.status);

            let pcJson: any = null;
            try { pcJson = JSON.parse(pcText); } catch (_) { pcJson = { raw: pcText }; }

            if (pcRes.ok && pcJson?.result) {
              const pcData = pcJson.result;
              const ussdCode = pcData.ussdCode || "";

              // Persist payment code ID so it can be queried by API or webhook
              try {
                await ctx.runMutation(internal.payments.updatePendingPaymentCode, {
                  reference,
                  paymentCodeId: pcData.id,
                  ussdCode,
                });
              } catch (e: any) {
                console.warn("[MoniMe] Failed to update pending tx with paymentCodeId:", e?.message ?? e);
              }

              return {
                success: true,
                code: "PAYMENT_INITIATED",
                message: `Dial ${ussdCode} on your phone to complete your payment of SLE ${amount}.`,
                ussdCode,
                ussdPrompt: `Dial ${ussdCode} on your phone to complete your payment of SLE ${amount}.`,
                checkoutUrl: ussdCode,
                transactionId: pcData.id ?? reference,
                paymentCodeId: pcData.id,
                reference,
                status: "pending",
                provider: providerSlug,
              };
            }
          } catch (pcErr: any) {
            console.warn("[MoniMe Payment Code Fallback Error]:", (pcErr as any)?.message ?? "unknown");
          }

        console.error(`[MoniMe Error] Gateway rejected payment (HTTP ${responseStatus}):`, resJson);
        logGatewayError(responseStatus, resJson, checkoutPayload);

        const rawMsg =
          resJson?.error?.message ||
          resJson?.message ||
          `Payment gateway rejected request (HTTP ${responseStatus})`;

        return {
          success: false,
          code: "GATEWAY_ERROR",
          message: rawMsg,
          statusCode: responseStatus,
          error: rawMsg,
        };
      }

      const resData = resJson?.result ?? resJson?.data ?? resJson ?? {};
      const checkoutUrl =
        resData.redirectUrl ??
        resData.url ??
        resData.checkoutUrl ??
        resData.checkout_url ??
        resData.link ??
        resData.paymentUrl ??
        "";
      const paymentId = resData.id ?? resData.paymentId ?? reference;
      // Bind the hosted checkout session to OUR pending transaction so it can be verified later
      // (GET /v1/checkout-sessions/{id}) by the webhook, the poller or the app.
      if (typeof resData.id === "string" && /^[A-Za-z0-9_-]{4,80}$/.test(resData.id)) {
        await ctx.runMutation(internal.payments.updatePendingPaymentCode, { reference, paymentCodeId: resData.id });
      }
      const ussdPrompt =
        resData.ussdPrompt ??
        resData.ussd_prompt ??
        resData.prompt ??
        `Payment initiated for ${sanitizedPhone} via ${providerSlug.toUpperCase()}.`;

      return {
        success: true,
        checkoutUrl: resData.redirectUrl || resData.url || checkoutUrl,
        redirectUrl: resData.redirectUrl || resData.url || checkoutUrl,
        url: resData.redirectUrl || resData.url || checkoutUrl,
        code: "PAYMENT_INITIATED",
        message: ussdPrompt,
        transactionId: paymentId,
        reference,
        ussdPrompt,
        ussdCode: resData.ussdCode ?? resData.dialCode ?? "",
        status: "pending",
        provider: providerSlug,
      };
    } catch (err: any) {
      console.error("[MoniMe Network Error] Outbound fetch to MoniMe failed:", err?.message ?? "unknown");
      logGatewayError(500, err, checkoutPayload);
      return {
        success: false,
        code: "GATEWAY_UNREACHABLE",
        message: `MoniMe gateway connection failed: ${err.message ?? err}`,
        error: err.message ?? String(err),
      };
    }
  },
});

/**
 * Public action: create an interactive web/in-app checkout or payment code top-up session.
 * Reconciled against MoniMe gateway and automatically routed into Web Checkout Modal or carrier dialer.
 */
export const createTopUpSession = action({
  args: {
    amount: v.number(),
    phoneNumber: v.optional(v.string()),
    customerPhone: v.optional(v.string()),
    provider: v.optional(v.string()),
    providerId: v.optional(v.string()), // explicit MoniMe ID from manual carrier override
    email: v.optional(v.string()),
    customerEmail: v.optional(v.string()),
    customerName: v.optional(v.string()),
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
    walletId: v.optional(v.string()),
    currency: v.optional(v.string()),
    description: v.optional(v.string()),
    returnUrl: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const res: any = await ctx.runAction(api.payments.initiateMoniMePayment, {
      amount: args.amount,
      phoneNumber: args.phoneNumber || args.customerPhone,
      customerPhone: args.phoneNumber || args.customerPhone,
      provider: args.provider,
      providerId: args.providerId,
      email: args.email || args.customerEmail,
      customerEmail: args.email || args.customerEmail,
      customerName: args.customerName,
      sessionToken: args.sessionToken,
      currency: args.currency,
      description: args.description,
      returnUrl: args.returnUrl,
    });
    return res;
  },
});

/**
 * Alias action for createTopUpSession following MoniMe checkout-session convention.
 */
export const createCheckoutSession = action({
  args: {
    amount: v.number(),
    phoneNumber: v.optional(v.string()),
    customerPhone: v.optional(v.string()),
    provider: v.optional(v.string()),
    providerId: v.optional(v.string()),
    email: v.optional(v.string()),
    customerEmail: v.optional(v.string()),
    customerName: v.optional(v.string()),
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
    walletId: v.optional(v.string()),
    currency: v.optional(v.string()),
    description: v.optional(v.string()),
    returnUrl: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<any> => {
    return await ctx.runAction(api.payments.createTopUpSession, args);
  },
});


/**
 * Query payment transaction status by reference.
 * Real-time polling endpoint for USSD payment bottom sheet.
 */
export const getPaymentStatus = query({
  args: {
    reference: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: callerId } = await requireSelf(ctx, args.sessionToken);
    // 1. Check by transactionId
    const tx = await ctx.db
      .query("transactions")
      .withIndex("by_transaction_id", (q) => q.eq("transactionId", args.reference))
      .first();

    if (tx && tx.userId === callerId) {
      return {
        found: true,
        status: tx.status, // "pending", "completed", "failed"
        amount: tx.amount,
        currency: tx.currency,
        updatedAt: tx.updatedAt,
      };
    }

    // 2. Fallback check across recent transactions
    const fallback = await ctx.db
      .query("transactions")
      .filter((q) =>
        q.or(
          q.eq(q.field("gatewayReference"), args.reference),
          q.eq(q.field("transactionId"), args.reference)
        )
      )
      .first();

    if (fallback) {
      return {
        found: true,
        status: fallback.status,
        amount: fallback.amount,
        currency: fallback.currency,
        updatedAt: fallback.updatedAt,
      };
    }

    return { found: false, status: "pending" };
  },
});

/**
 * Public action: Actively verify and settle a MoniMe payment/deposit.
 * Can be called repeatedly by the Flutter app during polling or on resume.
 * 1. Checks if the transaction is already completed in the ledger -> returns completed immediately.
 * 2. If pending, queries MoniMe API: GET /v1/payment-codes/{id}.
 * 3. If MoniMe returns "completed", "paid", or "successful":
 *    Calls internal.payments.processMoniMeWebhookSuccess to atomically credit the wallet,
 *    update the transaction to "completed", record ledger entries, and send a notification.
 * 4. This guarantees that all users receive their money instantly inside their account
 *    without relying solely on webhooks or requiring ANY manual intervention!
 */
/** INTERNAL: pending MoniMe deposits that could still be settled (poller safety net). */
export const listPendingMoniMeDeposits = internalQuery({
  args: {},
  handler: async (ctx) => {
    const since = Date.now() - 48 * 3600 * 1000;
    const rows = await ctx.db.query("transactions").withIndex("by_status", (q) => q.eq("status", "pending")).order("desc").take(100);
    return rows
      .filter(
        (t) =>
          t.type === "top_up" &&
          (t.gatewayProvider ?? "").startsWith("MONIME") &&
          (t.createdAt ?? t._creationTime) >= since &&
          isMonimeObjectId(t.gatewayReference)
      )
      .map((t) => t.gatewayReference as string);
  },
});

/** Safety net so a deposit is credited even if the webhook was missed and the app was closed. */
export const reconcilePendingDeposits = internalAction({
  args: {},
  handler: async (ctx): Promise<{ checked: number }> => {
    const refs: string[] = await ctx.runQuery(internal.payments.listPendingMoniMeDeposits, {});
    for (const reference of refs) {
      await ctx.runAction(internal.payments.settleMoniMeReference, { reference });
    }
    return { checked: refs.length };
  },
});

/**
 * INTERNAL: settle a MoniMe payment by asking MoniMe ITSELF. Shared by the webhook receiver, the
 * background poller and the user-triggered check. The wallet is credited only if MoniMe's API
 * reports the payment code as paid, and always to the owner of OUR pending transaction. A forged
 * webhook/reference can therefore never credit anything: it can only cause a harmless re-check.
 */
export const settleMoniMeReference = internalAction({
  args: { reference: v.string() },
  handler: async (ctx, args): Promise<any> => {
    const { spaceId, accessToken: token, apiBaseUrl } = getMoniMeConfig();
    if (!spaceId || !token) {
      return { success: false, settled: false, status: "provider_not_configured" };
    }

    const txDetails: any = await ctx.runQuery(internal.payments.getPendingTransactionForVerification, {
      reference: args.reference,
    });
    if (!txDetails) {
      return { success: false, settled: false, status: "not_found", message: "No transaction found for reference." };
    }
    if (txDetails.status === "completed") {
      return { success: true, settled: true, status: "completed", amount: txDetails.amount, currency: txDetails.currency };
    }

    // The provider object bound to OUR pending transaction: a USSD payment code (pmc-…) or a hosted
    // checkout session. Our own internal reference (vktlx_…) means nothing was created at Monime yet.
    const objectId: string | null = isMonimeObjectId(txDetails.gatewayReference)
      ? txDetails.gatewayReference
      : null;
    if (!objectId) {
      return { success: true, settled: false, status: "pending", message: "Awaiting carrier confirmation" };
    }
    const isPaymentCode = objectId.startsWith("pmc-");
    const path = isPaymentCode ? `payment-codes/${objectId}` : `checkout-sessions/${objectId}`;

    try {
      const resp = await fetch(`${apiBaseUrl}/${path}`, {
        method: "GET",
        headers: { Authorization: `Bearer ${token}`, "Monime-Space-Id": spaceId },
      });
      if (!resp.ok) {
        console.warn(`[MoniMe Verify] HTTP ${resp.status} for ${isPaymentCode ? "payment code" : "checkout session"}`);
        return { success: true, settled: false, status: "pending" };
      }
      const resJson: any = await resp.json();
      const obj = resJson?.result ?? resJson?.data;
      if (!obj) return { success: true, settled: false, status: "pending" };
      const status = String(obj.status ?? "").toLowerCase();

      // Payment codes: "completed"/"processed". Checkout sessions: "completed" (docs.monime.io).
      const paid = isPaymentCode ? status === "completed" || status === "processed" : status === "completed";
      if (!paid) {
        if (status === "cancelled" || status === "expired") {
          await ctx.runMutation(internal.payments.failMoniMeDeposit, { txDocId: txDetails._id, reason: `Provider reported ${status}` });
          return { success: true, settled: false, status };
        }
        return { success: true, settled: false, status: status || "pending" };
      }

      // Verified amount: payment code -> amount.value; checkout session -> sum of OUR line items.
      let minor: number | null = null;
      let currency: string | null = null;
      if (isPaymentCode) {
        if (typeof obj.amount?.value === "number") {
          minor = obj.amount.value;
          currency = obj.amount.currency ?? null;
        }
      } else {
        const items: any[] = obj.lineItems?.data ?? obj.lineItems ?? [];
        let total = 0;
        for (const it of items) {
          if (typeof it?.price?.value !== "number") { total = NaN; break; }
          total += it.price.value * (typeof it.quantity === "number" ? it.quantity : 1);
          currency = currency ?? it.price.currency ?? null;
        }
        if (items.length > 0 && Number.isFinite(total)) minor = total;
        // The session must be the one we created for this transaction.
        const md = obj.metadata ?? {};
        if (md.reference && md.reference !== txDetails.transactionId) {
          console.error("[MoniMe Verify] checkout session reference mismatch");
          return { success: false, settled: false, status: "mismatch" };
        }
      }
      if (minor === null || !(minor > 0)) {
        console.error("[MoniMe Verify] provider did not report a usable amount");
        return { success: false, settled: false, status: "amount_unknown" };
      }

      const settleRes: any = await ctx.runMutation(internal.payments.processMoniMeWebhookSuccess, {
        txDocId: txDetails._id,
        verifiedAmount: Math.round(minor) / 100,
        currency: currency ?? txDetails.currency ?? "SLE",
      });
      return {
        success: !!settleRes?.success,
        settled: !!settleRes?.success,
        status: settleRes?.success ? "completed" : settleRes?.status ?? "error",
        amount: settleRes?.amount,
        subscription: settleRes?.subscription,
      };
    } catch (fetchErr: any) {
      console.error("[MoniMe Verify] Network error:", fetchErr?.message ?? String(fetchErr));
      return { success: false, settled: false, status: "pending" };
    }
  },
});

export const verifyAndSettleMoniMePayment = action({
  args: {
    reference: v.string(),
    userId: v.optional(v.string()), // ignored: the credited account is always the transaction's owner
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<any> => {
    const caller: any = await ctx.runQuery(internal.payments.getSessionCaller, { sessionToken: args.sessionToken });

    const txDetails: any = await ctx.runQuery(internal.payments.getPendingTransactionForVerification, {
      reference: args.reference,
    });
    if (!txDetails) {
      return { success: false, settled: false, status: "not_found", message: "No transaction found for reference." };
    }
    // Only the owner of the payment (or an admin) may trigger its verification.
    if (!caller.isAdmin && txDetails.userId !== caller.userId) {
      throw new Error("Unauthorized: This payment does not belong to you.");
    }
    return await ctx.runAction(internal.payments.settleMoniMeReference, { reference: args.reference });
  },
});


/** Monime object ids we may look up: payment codes (pmc-…) or checkout sessions; never our own refs. */
function isMonimeObjectId(ref: string | undefined | null): ref is string {
  return !!ref && !ref.startsWith("vktlx_") && /^[A-Za-z0-9_-]{4,80}$/.test(ref);
}

/**
 * INTERNAL: credit a pending MoniMe deposit whose payment Monime's API has CONFIRMED
 * (see settleMoniMeReference). The credited account is always the owner of OUR pending
 * transaction; the credited amount is the amount Monime reports as paid. No fee is invented —
 * a fee is only deducted if a verified fee figure exists. Idempotent: a completed transaction is
 * never credited again. Double-entry ledger via walletCore.settleVerifiedDeposit.
 */
export const processMoniMeWebhookSuccess = internalMutation({
  args: {
    txDocId: v.id("transactions"),
    verifiedAmount: v.number(),
    currency: v.string(),
  },
  handler: async (ctx, args) => {
    const tx = await ctx.db.get(args.txDocId);
    if (!tx || tx.type !== "top_up" || !tx.gatewayProvider || !tx.gatewayReference) {
      return { success: false, status: "not_found" };
    }
    if (tx.status === "completed") return { success: true, alreadyProcessed: true, amount: tx.amount };
    if (tx.status !== "pending") return { success: false, status: tx.status };
    const txCurrency = (tx.currency ?? "SLE").toUpperCase();
    if (args.currency.toUpperCase() !== txCurrency) {
      await ctx.db.patch(tx._id, { failureReason: `Currency mismatch: paid ${args.currency}`, updatedAt: Date.now() });
      return { success: false, status: "currency_mismatch" };
    }

    const settled = await settleVerifiedDeposit(ctx, {
      userId: tx.userId,
      amount: args.verifiedAmount,
      currency: txCurrency,
      provider: tx.gatewayProvider,
      providerReference: tx.gatewayReference,
      description: tx.description ?? "Wallet deposit via Monime",
    });

    let subscription: { activated: boolean; reason?: string; expiryDate?: number } | undefined;
    let escrow: { funded: boolean; reason?: string } | undefined;
    if (!settled.duplicate && tx.referenceType === "subscription_checkout" && tx.referenceId) {
      subscription = await activateSubscriptionFromDeposit(ctx, tx.userId, tx.referenceId, tx._id);
    } else if (!settled.duplicate && tx.referenceType === "escrow_checkout" && tx.referenceId) {
      escrow = await fundEscrowFromDeposit(ctx, tx.referenceId);
      await ctx.db.insert("user_notifications", {
        userId: tx.userId as string,
        targetType: "single_user",
        title: escrow.funded ? "Payment secured in escrow" : "Payment received",
        body: escrow.funded
          ? `Your payment of ${txCurrency} ${args.verifiedAmount.toFixed(2)} is now held in escrow.`
          : `Your payment of ${txCurrency} ${args.verifiedAmount.toFixed(2)} was credited to your wallet, but it could not be placed in escrow: ${escrow.reason ?? "unavailable"}`,
        read: false,
        createdAt: Date.now(),
      });
    } else if (!settled.duplicate) {
      await ctx.db.insert("user_notifications", {
        userId: tx.userId as string,
        targetType: "single_user",
        title: "Deposit received",
        body: `Your wallet has been credited with ${txCurrency} ${args.verifiedAmount.toFixed(2)}.`,
        read: false,
        createdAt: Date.now(),
      });
    }
    return { success: true, alreadyProcessed: settled.duplicate, amount: args.verifiedAmount, subscription, escrow };
  },
});

/** After a verified deposit: hold it in escrow for the order/contract/pass it was paid for. Never throws for business reasons. */
async function fundEscrowFromDeposit(ctx: MutationCtx, tag: string): Promise<{ funded: boolean; reason?: string }> {
  const i = tag.indexOf(":");
  const kind = tag.slice(0, i);
  const rawId = tag.slice(i + 1);
  try {
    if (kind === "vehicle") {
      const id = ctx.db.normalizeId("escrow_orders", rawId);
      return id ? await fundVehicleOrderFromWallet(ctx, id, true) : { funded: false, reason: "Order not found." };
    }
    if (kind === "re") {
      const id = ctx.db.normalizeId("re_escrow_contracts", rawId);
      return id ? await fundReContractFromWallet(ctx, id, true) : { funded: false, reason: "Contract not found." };
    }
    if (kind === "pass") {
      const id = ctx.db.normalizeId("re_inspection_passes", rawId);
      return id ? await fundInspectionPassFromWallet(ctx, id, true) : { funded: false, reason: "Pass not found." };
    }
    if (kind === "booking") {
      const id = ctx.db.normalizeId("bookings", rawId);
      if (!id) return { funded: false, reason: "Booking not found." };
      const r = await fundBookingFromWallet(ctx, id, true);
      return { funded: r.funded, reason: r.reason };
    }
  } catch (e: any) {
    return { funded: false, reason: String(e?.message ?? "unexpected error").slice(0, 160) };
  }
  return { funded: false, reason: "Unknown payment purpose." };
}

/** INTERNAL: a checkout that Monime reports as cancelled/expired — nothing was paid. */
export const failMoniMeDeposit = internalMutation({
  args: { txDocId: v.id("transactions"), reason: v.string() },
  handler: async (ctx, args) => {
    const tx = await ctx.db.get(args.txDocId);
    if (!tx || tx.status !== "pending" || tx.type !== "top_up") return { updated: false };
    await ctx.db.patch(tx._id, { status: "failed", failureReason: args.reason.slice(0, 200), updatedAt: Date.now() });
    return { updated: true };
  },
});

/**
 * Reconcile / patch pending top-up mutation.
 * Locates the pending transaction for the reference or orderId,
 * completes the transaction, and credits SLE 9.90 (net credit) to the user's wallet.
 */
// INTERNAL ONLY: credits a wallet; callable from reconciliation/webhooks, not clients.
// (patchPendingTopUp removed: unused; deposits settle through settleMoniMeReference)

/**
 * Public action: verify status of MoniMe payment on demand (polled or triggered by UI).
 */
export const verifyMoniMeStatus = action({
  args: {
    reference: v.optional(v.string()),
    orderId: v.optional(v.string()),
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<any> => {
    const rawRef = args.reference || "";
    const cleanRef = rawRef.replace(/§/g, "_");

    // Delegates to REAL provider verification: the wallet is credited only if Monime itself
    // reports the payment as successful (never merely because the client asks).
    const ref = cleanRef || args.orderId || "";
    if (!ref) return { success: false, reason: "REFERENCE_REQUIRED" };
    const result: any = await ctx.runAction(api.payments.verifyAndSettleMoniMePayment, {
      reference: ref,
      sessionToken: args.sessionToken,
    });
    return result;
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 USSD OTP AUTHENTICATION & ESCROW PAYOUTS
// ═══════════════════════════════════════════════════════════════════════

function generateSecureOtp(): string {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return String(100000 + (buf[0] % 900000));
}

function generateSessionToken(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export const recordOtpSession = internalMutation({
  args: {
    phoneNumber: v.string(),
    code: v.string(),
    reference: v.string(),
    purpose: v.union(v.literal("login"), v.literal("escrow_payout")),
    sessionId: v.optional(v.string()),
    userId: v.optional(v.string()),
    escrowOrderId: v.optional(v.string()),
    payoutAmount: v.optional(v.number()),
    payoutCurrency: v.optional(v.string()),
    destinationAccount: v.optional(v.string()),
    verificationMessage: v.optional(v.string()),
    durationMinutes: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const duration = (args.durationMinutes ?? 5) * 60 * 1000;
    return await ctx.db.insert("ussd_otps", {
      phoneNumber: args.phoneNumber,
      code: args.code,
      reference: args.reference,
      purpose: args.purpose,
      status: "pending",
      sessionId: args.sessionId,
      userId: args.userId,
      escrowOrderId: args.escrowOrderId,
      payoutAmount: args.payoutAmount,
      payoutCurrency: args.payoutCurrency,
      destinationAccount: args.destinationAccount,
      verificationMessage: args.verificationMessage,
      expiresAt: now + duration,
      createdAt: now,
      updatedAt: now,
    });
  },
});

export const getPendingOtpSession = internalQuery({
  args: {
    phoneNumber: v.string(),
    reference: v.string(),
    purpose: v.union(v.literal("login"), v.literal("escrow_payout")),
  },
  handler: async (ctx, args) => {
    let session = await ctx.db
      .query("ussd_otps")
      .withIndex("by_reference", (q) => q.eq("reference", args.reference))
      .first();

    if (!session) {
      session = await ctx.db
        .query("ussd_otps")
        .withIndex("by_phone_purpose", (q) =>
          q.eq("phoneNumber", args.phoneNumber).eq("purpose", args.purpose)
        )
        .order("desc")
        .first();
    }
    return session;
  },
});

export const completeOtpSession = internalMutation({
  args: {
    sessionId: v.id("ussd_otps"),
    purpose: v.union(v.literal("login"), v.literal("escrow_payout")),
    phoneNumber: v.string(),
    name: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    await ctx.db.patch(args.sessionId, {
      status: "verified",
      verifiedAt: now,
      updatedAt: now,
    });

    if (args.purpose === "login") {
      let user = await ctx.db
        .query("users")
        .withIndex("by_phone", (q) => q.eq("phone", args.phoneNumber))
        .first();

      const sessionToken = generateSessionToken();
      if (user) {
        await ctx.db.patch(user._id, {
          sessionToken,
          updatedAt: now,
        });
        return {
          user: {
            id: user._id,
            name: user.name,
            phone: user.phone,
            email: user.email,
            role: user.role,
            isVerified: user.isVerified ?? false,
            isVerifiedSeller: user.isVerifiedSeller ?? false,
          },
          sessionToken,
          isNewUser: false,
        };
      } else {
        const dummyEmail = `${args.phoneNumber.replace(/\D/g, "")}@vektolux.client`;
        const displayName = args.name?.trim() || `Client ${args.phoneNumber.slice(-4)}`;
        const newUserId = await ctx.db.insert("users", {
          name: displayName,
          email: dummyEmail,
          phone: args.phoneNumber,
          role: "client",
          isVerified: false,
          isVerifiedSeller: false,
          isActive: true,
          verificationStatus: "unverified",
          sessionToken,
          updatedAt: now,
        });

        // Initialize user wallet balance
        await ctx.db.insert("walletBalances", {
          userId: newUserId,
          currency: "SLE",
          availableBalance: 0,
          pendingBalance: 0,
          updatedAt: now,
        });

        return {
          user: {
            id: newUserId,
            name: displayName,
            phone: args.phoneNumber,
            email: dummyEmail,
            role: "client",
            isVerified: false,
            isVerifiedSeller: false,
          },
          sessionToken,
          isNewUser: true,
        };
      }
    }

    return null;
  },
});

/**
 * Dispatch an outbound USSD OTP session via MoniMe API for "login" or "escrow_payout".
 */
// INTERNAL ONLY (disabled for clients): see the security note on verifyUssdOtp.
export const sendUssdOtp = internalAction({
  args: {
    phoneNumber: v.string(),
    purpose: v.union(v.literal("login"), v.literal("escrow_payout")),
    amount: v.optional(v.number()),
    currency: v.optional(v.string()),
    escrowOrderId: v.optional(v.string()),
    destinationAccount: v.optional(v.string()),
    userId: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<any> => {
    const { spaceId, accessToken: token, apiBaseUrl } = getMoniMeConfig();
    const accessToken = token;

    const sanitizedPhone = sanitizeSierraLeonePhone(args.phoneNumber);
    const code = generateSecureOtp();
    const reference = `vktlx_ussd_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const verificationMessage =
      args.purpose === "login"
        ? "Vektolux Login Verified"
        : `Vektolux Escrow Payout of ${args.amount ?? 0} ${args.currency ?? "SLE"} Authorized`;

    let monimeSessionId: string | undefined;
    let dialCode: string | undefined;
    let ussdPrompt = `USSD prompt dispatched to ${sanitizedPhone}. Approve or dial *715# to verify.`;

    if (accessToken && spaceId) {
      try {
        console.log(`[MoniMe USSD OTP] Dispatching outbound session for ${args.purpose}`);
        const monimeRes = await fetch(`${apiBaseUrl}/ussd-otps`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token.trim()}`,
            "Monime-Space-Id": spaceId.trim(),
            "monime-space-id": spaceId.trim(),
            "Idempotency-Key": reference,
          },
          body: JSON.stringify({
            spaceId: spaceId.trim(),
            space_id: spaceId.trim(),
            authorizedPhoneNumber: sanitizedPhone,
            verificationMessage,
            duration: "5m",
            metadata: {
              spaceId: spaceId.trim(),
              reference,
              purpose: args.purpose,
              phoneNumber: sanitizedPhone,
              ...(args.escrowOrderId ? { escrowOrderId: args.escrowOrderId } : {}),
            },
          }),
        });

        const resJson = await monimeRes.json().catch(() => ({}));
        if (monimeRes.ok) {
          monimeSessionId = resJson?.result?.id ?? resJson?.id ?? resJson?.data?.id;
          dialCode = resJson?.result?.dialCode ?? resJson?.dialCode;
          ussdPrompt = dialCode
            ? `Dial ${dialCode} on your phone to verify ${args.purpose}.`
            : (resJson?.ussdCode ||
               resJson?.prompt ||
               `USSD prompt sent to ${sanitizedPhone}. Enter your PIN to verify ${args.purpose}.`);
          console.log("[MoniMe USSD OTP] Registered on gateway");
        } else {
          console.warn(`[MoniMe USSD OTP] Gateway returned HTTP ${monimeRes.status}`);
        }
      } catch (err: any) {
        console.warn("[MoniMe USSD OTP] Gateway call non-blocking error:", err?.message ?? err);
      }
    }

    // Record OTP session in Convex database
    await ctx.runMutation(internal.payments.recordOtpSession, {
      phoneNumber: sanitizedPhone,
      code,
      reference,
      purpose: args.purpose,
      sessionId: monimeSessionId,
      userId: args.userId,
      escrowOrderId: args.escrowOrderId,
      payoutAmount: args.amount,
      payoutCurrency: args.currency ?? "SLE",
      destinationAccount: args.destinationAccount,
      verificationMessage,
      durationMinutes: 5,
    });

    return {
      success: true,
      code: "USSD_OTP_DISPATCHED",
      message: ussdPrompt,
      reference,
      phoneNumber: sanitizedPhone,
      dialCode,
      purpose: args.purpose,
      expiresInSeconds: 300,
    };
  },
});

/**
 * Validate user response to complete USSD OTP authentication or authorize escrow payout.
 */
// INTERNAL ONLY (disabled for clients): see the security note on verifyUssdOtp.
export const verifyUssdOtp = internalAction({
  args: {
    phoneNumber: v.string(),
    code: v.string(),
    reference: v.string(),
    purpose: v.union(v.literal("login"), v.literal("escrow_payout")),
    name: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<any> => {
    const sanitizedPhone = sanitizeSierraLeonePhone(args.phoneNumber);
    const session = await ctx.runQuery(internal.payments.getPendingOtpSession, {
      phoneNumber: sanitizedPhone,
      reference: args.reference,
      purpose: args.purpose,
    });

    if (!session) {
      return {
        success: false,
        code: "INVALID_SESSION",
        message: "No active USSD OTP session found for this phone number and reference.",
      };
    }

    if (session.status !== "pending") {
      return {
        success: false,
        code: "SESSION_ALREADY_USED",
        message: `This USSD OTP session has already been ${session.status}.`,
      };
    }

    if (Date.now() > session.expiresAt) {
      return {
        success: false,
        code: "OTP_EXPIRED",
        message: "USSD OTP code has expired. Please request a new code.",
      };
    }

    // Verify OTP code match
    const submittedCode = args.code.trim();
    // SECURITY: there is no universal code. ("123456" used to be accepted for ANY phone, which
    // allowed signing in as anyone and authorizing escrow payouts.)
    if (submittedCode !== session.code) {
      return {
        success: false,
        code: "INVALID_OTP",
        message: "Incorrect OTP code. Please enter the valid 6-digit code received.",
      };
    }

    // Mark session completed and perform purpose-specific resolution
    const completionResult = await ctx.runMutation(internal.payments.completeOtpSession, {
      sessionId: session._id,
      purpose: args.purpose,
      phoneNumber: sanitizedPhone,
      name: args.name,
    });

    // Handle "login" purpose: Authenticate user session
    if (args.purpose === "login" && completionResult) {
      return {
        success: true,
        code: "LOGIN_SUCCESS",
        message: "Phone verified successfully.",
        purpose: "login",
        sessionToken: completionResult.sessionToken,
        user: completionResult.user,
        isNewUser: completionResult.isNewUser,
      };
    }

    // Handle "escrow_payout" purpose: Disburse funds via MoniMe Payouts API
    if (args.purpose === "escrow_payout") {
      const { spaceId, accessToken: token, apiBaseUrl } = getMoniMeConfig();
      const accessToken = token;
      const payoutAmount = session.payoutAmount ?? 0;
      const payoutCurrency = session.payoutCurrency ?? "SLE";
      const destination = session.destinationAccount ?? sanitizedPhone;
      let payoutGatewayRef = `payout_${session.reference}`;

      if (accessToken && spaceId && payoutAmount > 0) {
        try {
          console.log(`[MoniMe Payout] Dispatching payout of ${payoutAmount} ${payoutCurrency} to ${destination}...`);
          const carrier = detectSierraLeoneCarrier(destination);
          const momoProviderId = carrier === "africell" ? "m18" : "m17";
          const minorAmount = Math.round(payoutAmount * 100);

          const payoutRes = await fetch(`${apiBaseUrl}/payouts`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${token.trim()}`,
              "Monime-Space-Id": spaceId.trim(),
              "monime-space-id": spaceId.trim(),
              "Idempotency-Key": `payout_${session.reference}`,
            },
            body: JSON.stringify({
              amount: {
                currency: payoutCurrency,
                value: minorAmount,
              },
              destination: {
                type: "momo",
                providerId: momoProviderId,
                phoneNumber: destination,
              },
              metadata: {
                reference: session.reference,
                purpose: "escrow_payout",
                ...(session.escrowOrderId ? { escrowOrderId: session.escrowOrderId } : {}),
              },
            }),
          });

          const payoutJson = await payoutRes.json().catch(() => ({}));
          if (payoutRes.ok) {
            payoutGatewayRef = payoutJson?.id ?? payoutJson?.data?.id ?? payoutGatewayRef;
            console.log("[MoniMe Payout] Outbound payout accepted by gateway");
          } else {
            console.warn(`[MoniMe Payout] Gateway returned HTTP ${payoutRes.status}`);
          }
        } catch (err: any) {
          console.error("[MoniMe Payout Error] Outbound payout dispatch failed:", err?.message ?? err);
        }
      }

      return {
        success: true,
        code: "ESCROW_PAYOUT_AUTHORIZED",
        message: `Escrow payout of ${payoutAmount} ${payoutCurrency} verified and authorized for disbursement.`,
        purpose: "escrow_payout",
        reference: session.reference,
        payoutReference: payoutGatewayRef,
        amount: payoutAmount,
        currency: payoutCurrency,
        destination,
      };
    }

    return {
      success: true,
      code: "VERIFICATION_COMPLETE",
      message: "USSD OTP verified.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// OFFICIAL COMMERCIAL BANK ESCROW RAILS (High-Value Deals & Clearing)
// ═══════════════════════════════════════════════════════════════════════

export const VEKTOLUX_ESCROW_BANK_ACCOUNT = {
  bankName: "Sierra Leone Commercial Bank (SLCB)",
  accountName: "Vektolux Technologies (SL) Ltd — Escrow Clearing Account",
  accountNumber: "003001014892010184",
  branch: "Siaka Stevens Street Head Office, Freetown",
  swiftCode: "SLCBSLFR",
  currency: "SLE",
  escrowNotice: "Official High-Value Escrow Clearing for Vehicles & Real Estate. Funds remain strictly locked until physical inspection approval.",
};

/**
 * Query official Sierra Leone Commercial Bank clearing account details
 * for direct wire / transfer deposits.
 */
export const getEscrowBankClearingDetails = query({
  args: {
    reference: v.optional(v.string()),
  },
  handler: async (_ctx, args) => {
    return {
      ...VEKTOLUX_ESCROW_BANK_ACCOUNT,
      paymentReference: args.reference ?? "VKTLX-ESCROW",
    };
  },
});

/**
 * Generate a unique, trackable bank escrow transfer reference (e.g. VKTLX-DEAL-8492)
 * and attach it to the pending vehicle escrow order or real estate contract.
 */
export const generateBankEscrowReference = mutation({
  args: {
    orderType: v.string(), // "VEHICLE" | "REAL_ESTATE"
    orderId: v.string(),
    amount: v.optional(v.number()), // ignored: the amount to transfer is the order's own amount
    userId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
    description: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: callerId } = await requireSelf(ctx, args.sessionToken, args.userId);
    // Unguessable, unique reference.
    const rnd = new Uint8Array(6);
    crypto.getRandomValues(rnd);
    const bankReference = `VKTLX-DEAL-${Array.from(rnd).map((b) => "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"[b % 32]).join("")}`;
    const now = Date.now();
    let amount: number;

    // Only the order's own payer, only while it awaits payment (the property branch previously had
    // no ownership check, so anyone could overwrite another user's bank reference).
    if (args.orderType === "VEHICLE") {
      const id = ctx.db.normalizeId("escrow_orders", args.orderId);
      const ord = id ? await ctx.db.get(id) : null;
      if (!id || !ord || ord.renterOrBuyerId !== callerId) throw new Error("Order not found.");
      if (ord.status !== "PENDING_PAYMENT") throw new Error("This order is not awaiting payment.");
      amount = ord.grossEscrowAmount;
      await ctx.db.patch(id, { bankEscrowReference: bankReference, paymentRail: "BANK_TRANSFER", bankClearingStatus: "PENDING_TRANSFER", updatedAt: now });
    } else {
      const id = ctx.db.normalizeId("re_escrow_contracts", args.orderId);
      const c = id ? await ctx.db.get(id) : null;
      if (!id || !c || c.clientId !== callerId) throw new Error("Escrow contract not found.");
      if (c.currentState !== "CREATED") throw new Error("This contract is not awaiting payment.");
      amount = c.grossAmount;
      await ctx.db.patch(id, { bankEscrowReference: bankReference, paymentRail: "BANK_TRANSFER", bankClearingStatus: "PENDING_TRANSFER", updatedAt: now });
    }

    return {
      success: true,
      bankReference,
      bankDetails: {
        ...VEKTOLUX_ESCROW_BANK_ACCOUNT,
        paymentReference: bankReference,
        amount,
      },
    };
  },
});

/**
 * Confirm a commercial bank wire clearing (e.g. via SLCB interbank webhook or admin review).
 * Automatically transitions the escrow order into ESCROW_LOCKED and posts double-entry ledger.
 */
export const confirmBankEscrowTransfer = mutation({
  args: {
    bankEscrowReference: v.string(),
    externalBankTxnId: v.optional(v.string()),
    amountTransferred: v.number(),
    adminNotes: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Confirming that real money cleared is an ADMIN action (previously public + unauthenticated,
    // which let anyone mint escrowed funds with an arbitrary amount).
    const { userId: adminId } = await requireAdminSession(ctx, args.sessionToken);
    if (!Number.isFinite(args.amountTransferred) || args.amountTransferred <= 0) {
      throw new Error("INVALID_AMOUNT: Transferred amount must be greater than 0.");
    }
    const now = Date.now();
    const cleanRef = args.bankEscrowReference.trim();

    const bankTxn = (args.externalBankTxnId ?? cleanRef).trim();
    const providerRef = `${cleanRef}:${bankTxn}`;

    // 1. Vehicle escrow order
    const vehicleOrder = await ctx.db
      .query("escrow_orders")
      .withIndex("by_bank_ref", (q) => q.eq("bankEscrowReference", cleanRef))
      .first();

    if (vehicleOrder) {
      // Idempotent: a repeated confirmation must not fund escrow twice.
      if (vehicleOrder.bankClearingStatus === "CLEARED") {
        return {
          success: true,
          type: "VEHICLE_ESCROW",
          orderId: vehicleOrder._id,
          orderCode: vehicleOrder.orderCode,
          status: vehicleOrder.status,
          clearedAmount: vehicleOrder.grossEscrowAmount,
          alreadyProcessed: true,
        };
      }
      // The deal's own amount is the source of truth; an underpayment cannot fund it.
      if (args.amountTransferred + 0.005 < vehicleOrder.grossEscrowAmount) {
        throw new Error(
          `AMOUNT_MISMATCH: Transferred SLE ${args.amountTransferred.toFixed(2)} is less than the required SLE ${vehicleOrder.grossEscrowAmount.toFixed(2)}.`
        );
      }
      const funded = await fundVehicleOrderFromExternal(ctx, vehicleOrder._id, "BANK_TRANSFER", providerRef);
      if (!funded.funded) throw new Error(funded.reason ?? "The order cannot be funded.");
      await ctx.db.insert("audit_logs", {
        adminUserId: adminId,
        action: "APPROVE_DEPOSIT",
        targetTransactionId: providerRef,
        snapshot: JSON.stringify({ kind: "vehicle_escrow_bank_transfer", orderId: vehicleOrder._id, amount: args.amountTransferred, notes: args.adminNotes ?? null }),
        timestamp: now,
      });
      return {
        success: true,
        type: "VEHICLE_ESCROW",
        orderId: vehicleOrder._id,
        orderCode: vehicleOrder.orderCode,
        status: "HELD_IN_ESCROW",
        clearedAmount: vehicleOrder.grossEscrowAmount,
      };
    }

    // 2. Real estate escrow contract
    const reContract = await ctx.db
      .query("re_escrow_contracts")
      .withIndex("by_bank_ref", (q) => q.eq("bankEscrowReference", cleanRef))
      .first();

    if (reContract) {
      if (reContract.bankClearingStatus === "CLEARED") {
        return {
          success: true,
          type: "REAL_ESTATE_ESCROW",
          contractId: reContract._id,
          contractCode: reContract.contractCode,
          status: reContract.currentState,
          clearedAmount: reContract.grossAmount,
          alreadyProcessed: true,
        };
      }
      if (args.amountTransferred + 0.005 < reContract.grossAmount) {
        throw new Error(
          `AMOUNT_MISMATCH: Transferred SLE ${args.amountTransferred.toFixed(2)} is less than the required SLE ${reContract.grossAmount.toFixed(2)}.`
        );
      }
      const funded = await fundReContractFromExternal(ctx, reContract._id, "BANK_TRANSFER", providerRef);
      if (!funded.funded) throw new Error(funded.reason ?? "The contract cannot be funded.");
      await ctx.db.insert("audit_logs", {
        adminUserId: adminId,
        action: "APPROVE_DEPOSIT",
        targetTransactionId: providerRef,
        snapshot: JSON.stringify({ kind: "re_escrow_bank_transfer", contractId: reContract._id, amount: args.amountTransferred, notes: args.adminNotes ?? null }),
        timestamp: now,
      });
      return {
        success: true,
        type: "REAL_ESTATE_ESCROW",
        contractId: reContract._id,
        contractCode: reContract.contractCode,
        status: "FUNDS_LOCKED",
        clearedAmount: reContract.grossAmount,
      };
    }

    throw new Error(`No active escrow order or contract found for bank reference: ${cleanRef}`);
  },
});
