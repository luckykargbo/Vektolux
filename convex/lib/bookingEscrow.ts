// convex/lib/bookingEscrow.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Marketplace booking escrow: funding and settlement (server-only logic).
//
//   pending_payment ──pay──▶ confirmed (settlement "held", releaseEligibleAt = endTime + 24h)
//       held ──buyer confirms (after start) / 24h after end with no dispute / admin──▶ released
//       held ──buyer cancels before start / vendor cancels / admin──▶ refunded (full, incl. fees)
//       held ──buyer or vendor disputes──▶ disputed ──admin──▶ released | refunded
//
// The vendor can never release; a client never chooses an amount or a split. Every movement goes
// through walletCore with idempotency keys tied to the booking's escrow lock.
// ═══════════════════════════════════════════════════════════════════════

import { Doc, Id } from "../_generated/dataModel";
import { MutationCtx } from "../_generated/server";
import { findByIdempotencyKey, holdFunds, refundHeldFunds, releaseHeldFunds } from "../walletCore";

/** Auto-release delay after the booking's end time (user decision: 24 hours). */
export const BOOKING_RELEASE_DELAY_MS = 24 * 60 * 60 * 1000;
const BOOKING_LEGACY_COMMISSION_BPS = 1500; // default marketplace commission (85/15)

export type SettlementState = "held" | "disputed" | "released" | "refunded";
export type ReleasedBy = "buyer" | "auto" | "admin";

/**
 * The SERVER's split of a marketplace booking: from the booking's fee snapshot (default: Vektolux
 * keeps 15% of what the buyer pays, the vendor receives 85%). Bookings created before snapshots
 * existed use the default commission on their stored total. A client never chooses the split.
 */
export function bookingSplit(booking: Doc<"bookings">): { total: number; vendorAmount: number; platformFee: number } {
  const total = booking.totalAmount;
  const snap = booking.feeSnapshot;
  const platformFee =
    snap && Math.abs(snap.buyerTotal - total) <= 0.01
      ? snap.platformTotal
      : Math.round((total * BOOKING_LEGACY_COMMISSION_BPS) / 10000);
  const vendorAmount = Math.round((total - platformFee) * 100) / 100;
  if (!(platformFee >= 0 && vendorAmount >= 0)) throw new Error("Invalid booking split.");
  return { total, vendorAmount, platformFee };
}

/** Settlement state, including paid bookings funded before settlement tracking existed. */
export function settlementOf(booking: Doc<"bookings">): SettlementState | null {
  if (booking.settlementStatus) return booking.settlementStatus;
  if (booking.paymentStatus === "completed" && booking.escrowId && booking.status !== "completed") return "held";
  return null;
}

export type BookingActor = { id?: Id<"users">; role: "buyer" | "vendor" | "admin" | "system"; note?: string };

/** Appends to the booking's settlement history (never edited). */
export async function logBookingEvent(
  ctx: { db: any },
  bookingId: Id<"bookings">,
  action: "PAID" | "DISPUTE_OPENED" | "ADMIN_DECISION" | "RELEASED" | "REFUNDED" | "SETTLEMENT_BACKFILLED",
  actor: BookingActor,
  extra: { amount?: number; platformFee?: number; transactionCode?: string; ledgerCode?: string; note?: string } = {}
) {
  await ctx.db.insert("booking_events", {
    bookingId,
    action,
    actorId: actor.id,
    actorRole: actor.role,
    amount: extra.amount,
    platformFee: extra.platformFee,
    transactionCode: extra.transactionCode,
    ledgerCode: extra.ledgerCode,
    note: (extra.note ?? actor.note)?.slice(0, 1000),
    at: Date.now(),
  });
}

/** The wallet transaction code written for an idempotency key (to link history to the ledger). */
async function txCodeFor(ctx: { db: any }, userId: Id<"users">, key: string): Promise<string | undefined> {
  const tx = await findByIdempotencyKey(ctx, userId, key);
  return tx?.transactionId ?? undefined;
}

/**
 * What the booking's escrow holds right now, from the escrow lock itself (never thrown; for views
 * and for checking an admin's confirmed amount against the server's).
 */
export async function bookingEscrowSummary(ctx: { db: any }, booking: Doc<"bookings">) {
  const txId = booking.escrowId ? ctx.db.normalizeId("transactions", booking.escrowId) : null;
  const tx: Doc<"transactions"> | null = txId ? await ctx.db.get(txId) : null;
  const valid = !!tx && tx.type === "escrow_lock" && tx.userId === booking.buyerId && tx.referenceId === (booking._id as string);
  if (!valid) return null;
  const platformFee = typeof tx!.platformFeeAmount === "number" ? tx!.platformFeeAmount : bookingSplit(booking).platformFee;
  const locked = tx!.escrowStatus === "locked";
  return {
    escrowTransactionCode: tx!.transactionId ?? null,
    escrowStatus: tx!.escrowStatus ?? null,
    amountPaid: tx!.amount,
    platformFee,
    vendorAmount: Math.round((tx!.amount - platformFee) * 100) / 100,
    heldAmount: locked ? tx!.amount : 0,
    // Refund rule: a refund of a held booking returns everything held, including the service fee.
    refundableAmount: locked ? tx!.amount : 0,
    currency: tx!.currency,
  };
}

async function notify(ctx: { db: any }, userId: string, title: string, body: string) {
  await ctx.db.insert("user_notifications", { userId, targetType: "single_user", title, body, read: false, createdAt: Date.now() });
}

/**
 * Holds a booking's total from the buyer's AVAILABLE wallet balance in escrow (server split recorded
 * on the lock). soft=true never throws for business reasons (used after a verified Monime deposit).
 */
export async function fundBookingFromWallet(
  ctx: MutationCtx,
  bookingId: Id<"bookings">,
  soft = false
): Promise<{ funded: boolean; reason?: string; transactionDocId?: string; duplicate?: boolean; availableBalance?: number; escrowBalance?: number }> {
  const booking = await ctx.db.get(bookingId);
  const fail = (reason: string) => {
    if (soft) return { funded: false, reason };
    throw new Error(reason);
  };
  if (!booking) return fail("Booking not found.");
  if (booking.paymentStatus === "completed") return fail("This booking has already been paid.");
  if (booking.status !== "pending_payment" && booking.status !== "confirmed") return fail("This booking is not awaiting payment.");
  const buyerId = ctx.db.normalizeId("users", booking.buyerId);
  const vendorId = ctx.db.normalizeId("users", booking.vendorId);
  const vendor = vendorId ? await ctx.db.get(vendorId) : null;
  if (!buyerId || !vendorId || !vendor || vendor.isActive === false) return fail("Vendor account not found.");
  if (buyerId === vendorId) return fail("You cannot pay yourself.");
  const split = bookingSplit(booking);
  const currency = (booking.currency || "SLE").toUpperCase();
  if (soft) {
    const w = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) => q.eq("userId", buyerId).eq("currency", currency))
      .first();
    if (!w || w.availableBalance < split.total) return fail("Available balance is lower than the booking total.");
  }
  const held = await holdFunds(ctx, {
    userId: buyerId,
    amount: split.total,
    currency,
    referenceType: booking.bookingType,
    referenceId: booking._id as string,
    idempotencyKey: `escrow:${booking._id}`,
    counterpartyId: vendorId,
    description: `Escrow locked for ${booking.bookingType} (#${booking._id})`,
    extra: {
      partnerSplitPercent: split.total > 0 ? Math.round((split.vendorAmount / split.total) * 10000) / 100 : 0,
      partnerAmount: split.vendorAmount,
      platformFeeAmount: split.platformFee,
    },
  });
  await ctx.db.patch(booking._id, {
    status: "confirmed",
    paymentStatus: "completed",
    escrowId: held.transactionDocId ? (held.transactionDocId as string) : booking.escrowId,
    settlementStatus: "held",
    releaseEligibleAt: booking.endTime + BOOKING_RELEASE_DELAY_MS,
    updatedAt: Date.now(),
  });
  if (!held.duplicate) {
    await logBookingEvent(ctx, booking._id, "PAID", { id: buyerId, role: "buyer" }, {
      amount: split.total,
      platformFee: split.platformFee,
      transactionCode: held.transactionDocId ? (await ctx.db.get(held.transactionDocId))?.transactionId ?? undefined : undefined,
      ledgerCode: `ESC-LOCK-escrow:${booking._id}`,
    });
    await notify(ctx, booking.vendorId, "Booking paid", `The payment for "${booking.listingTitle}" is secured in escrow.`);
  }
  return {
    funded: true,
    transactionDocId: held.transactionDocId ? (held.transactionDocId as string) : undefined,
    duplicate: held.duplicate,
    availableBalance: held.availableBalance,
    escrowBalance: held.escrowBalance,
  };
}

/** The booking's own escrow lock, still locked. */
async function lockedEscrow(ctx: { db: any }, booking: Doc<"bookings">): Promise<Doc<"transactions">> {
  const txId = booking.escrowId ? ctx.db.normalizeId("transactions", booking.escrowId) : null;
  const tx: Doc<"transactions"> | null = txId ? await ctx.db.get(txId) : null;
  if (!tx || tx.type !== "escrow_lock" || tx.userId !== booking.buyerId || tx.referenceId !== (booking._id as string)) {
    throw new Error("This booking has no escrow to settle.");
  }
  if (tx.escrowStatus !== "locked") throw new Error(`Escrow is already ${tx.escrowStatus ?? "resolved"}.`);
  if (!tx.counterpartyId || tx.counterpartyId !== booking.vendorId) throw new Error("Escrow has no valid beneficiary.");
  return tx;
}

/** Pays the vendor from the booking's escrow (split recorded at hold time). */
export async function releaseBookingEscrow(
  ctx: { db: any },
  booking: Doc<"bookings">,
  by: ReleasedBy,
  actor?: BookingActor
): Promise<{ partnerAmount: number; platformFeeAmount: number; escrowTx: Doc<"transactions"> }> {
  const state = settlementOf(booking);
  if (state !== "held" && !(by === "admin" && state === "disputed")) {
    throw new Error(state === "disputed" ? "This booking is disputed; an administrator will resolve it." : "This booking has no escrow awaiting release.");
  }
  const tx = await lockedEscrow(ctx, booking);
  const platformFeeAmount = typeof tx.platformFeeAmount === "number" ? tx.platformFeeAmount : bookingSplit(booking).platformFee;
  if (!(platformFeeAmount >= 0 && platformFeeAmount <= tx.amount)) throw new Error("Invalid escrow split.");
  const partnerAmount = Math.round((tx.amount - platformFeeAmount) * 100) / 100;
  await releaseHeldFunds(ctx, {
    buyerId: tx.userId,
    recipientId: tx.counterpartyId!,
    amount: tx.amount,
    platformFee: platformFeeAmount,
    currency: tx.currency,
    referenceType: tx.referenceType ?? "booking",
    referenceId: booking._id as string,
    idempotencyKey: `release:${tx._id}`,
  });
  const now = Date.now();
  await ctx.db.patch(tx._id, { escrowStatus: "released", updatedAt: now });
  await ctx.db.patch(booking._id, {
    status: "completed",
    settlementStatus: "released",
    releasedAt: now,
    releasedBy: by,
    ...(by === "buyer" ? { buyerConfirmedAt: now } : {}),
    updatedAt: now,
  });
  await logBookingEvent(
    ctx,
    booking._id,
    "RELEASED",
    actor ?? { id: by === "buyer" ? (tx.userId as Id<"users">) : undefined, role: by === "auto" ? "system" : by === "buyer" ? "buyer" : "admin" },
    {
      amount: partnerAmount,
      platformFee: platformFeeAmount,
      transactionCode: await txCodeFor(ctx, tx.userId, `release:${tx._id}`),
      ledgerCode: `ESC-REL-release:${tx._id}`,
    }
  );
  await notify(ctx, booking.vendorId, "Booking payment released", `The payment for "${booking.listingTitle}" has been released to your wallet.`);
  return { partnerAmount, platformFeeAmount, escrowTx: tx };
}

/** Full refund of the booking's escrow to the buyer (including service fees); the booking is cancelled. */
export async function refundBookingEscrow(
  ctx: { db: any },
  booking: Doc<"bookings">,
  reason: string,
  actor: BookingActor = { role: "system" }
): Promise<{ refunded: number }> {
  const state = settlementOf(booking);
  if (state !== "held" && state !== "disputed") throw new Error("This booking has no escrow to refund.");
  const tx = await lockedEscrow(ctx, booking);
  await refundHeldFunds(ctx, {
    userId: tx.userId,
    amount: tx.amount,
    currency: tx.currency,
    referenceType: tx.referenceType ?? "booking",
    referenceId: booking._id as string,
    idempotencyKey: `refund:${tx._id}`,
  });
  const now = Date.now();
  const note = reason.trim().slice(0, 500);
  await ctx.db.patch(tx._id, { escrowStatus: "refunded", updatedAt: now });
  await ctx.db.patch(booking._id, {
    status: "cancelled",
    paymentStatus: "refunded",
    settlementStatus: "refunded",
    refundedAt: now,
    refundReason: note,
    cancelledAt: now,
    cancelReason: note,
    updatedAt: now,
  });
  await logBookingEvent(ctx, booking._id, "REFUNDED", actor, {
    amount: tx.amount,
    transactionCode: await txCodeFor(ctx, tx.userId, `refund:${tx._id}`),
    ledgerCode: `ESC-REF-refund:${tx._id}`,
    note,
  });
  await notify(ctx, booking.buyerId, "Booking refunded", `Your payment for "${booking.listingTitle}" was refunded to your wallet.`);
  await notify(ctx, booking.vendorId, "Booking cancelled", `The booking for "${booking.listingTitle}" was cancelled and refunded to the buyer.`);
  return { refunded: tx.amount };
}

/** The buyer confirms the service happened: releases the escrow (never before the start time). */
export async function buyerConfirmCompletion(ctx: { db: any }, booking: Doc<"bookings">, callerId: string, now = Date.now()) {
  if (booking.buyerId !== callerId) throw new Error("Unauthorized: You are not a party to this transaction.");
  if (now < booking.startTime) throw new Error("You can confirm the booking only after it has started.");
  if (booking.status !== "confirmed" && booking.status !== "in_progress") {
    throw new Error(booking.status === "disputed" ? "This booking is disputed; an administrator will resolve it." : "This booking cannot be confirmed.");
  }
  return releaseBookingEscrow(ctx, booking, "buyer");
}
