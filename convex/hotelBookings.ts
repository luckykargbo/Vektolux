// convex/hotelBookings.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Hospitality Escrow Booking Engine
// Manages daily & hourly guest house stays, anti-collision reservations,
// locked escrow, check-in verification, and operator payouts.
//
// MONEY RULES (server-authoritative):
//  • A booking is only "in_escrow" once REAL money is held: either a hold from the
//    guest's available wallet balance, or a provider-VERIFIED external payment
//    (`confirmHotelBookingPayment`, internal).
//  • Release / refund move REAL escrowed funds through the wallet core (throws if the
//    funds are not actually in escrow), so no path can mint money.
//  • The guest is always the authenticated user; client-supplied ids are never trusted.
// ═══════════════════════════════════════════════════════════════════════

import { internalMutation, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { requireAdminSession, requireParticipantOrAdmin, requireSelf } from "./lib/auth";
import { fundEscrowFromExternalPayment, holdFunds, refundHeldFunds, releaseHeldFunds } from "./walletCore";
import { priceOrder } from "./lib/fees";
import { hotelIsVerified, hotelOperatingPermission } from "./lib/hotelAccess";

/** The operator may request payout only this long after check-out (the guest's window to report a problem). */
const HOTEL_OPERATOR_RELEASE_DELAY_MS = 24 * 60 * 60 * 1000;

/** What the guest pays and what is held in escrow (subtotal + any buyer fee). Older rows: subtotal. */
function heldAmount(b: { guestTotalAmount?: number; subtotalAmount: number }): number {
  return b.guestTotalAmount ?? b.subtotalAmount;
}

async function countOverlaps(
  ctx: { db: any },
  roomId: Id<"hotel_rooms">,
  checkIn: number,
  checkOut: number
): Promise<number> {
  const overlapping = await ctx.db
    .query("hotel_bookings")
    .withIndex("by_roomId_and_status", (q: any) => q.eq("roomId", roomId))
    .filter((q: any) =>
      q.and(
        q.or(q.eq(q.field("status"), "in_escrow"), q.eq(q.field("status"), "checked_in")),
        q.lt(q.field("checkInTimestamp"), checkOut),
        q.gt(q.field("checkOutTimestamp"), checkIn)
      )
    )
    .take(200);
  return overlapping.length;
}

// ═══════════════════════════════════════════════════════════════════════
// 1. CREATE BOOKING WITH ESCROW
// ═══════════════════════════════════════════════════════════════════════

export const createBookingWithEscrow = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    hotelId: v.id("hotel_profiles"),
    roomId: v.id("hotel_rooms"),
    guestId: v.optional(v.id("users")), // consistency check only; the guest is the authenticated user
    guestName: v.string(),
    guestPhone: v.string(),
    guestEmail: v.optional(v.string()),
    bookingCategory: v.union(v.literal("nightly"), v.literal("hourly")),
    checkInTimestamp: v.number(),
    checkOutTimestamp: v.number(),
    numberOfGuests: v.number(),
    numberOfNights: v.optional(v.number()),
    numberOfHours: v.optional(v.number()),
    specialRequests: v.optional(v.string()),
    // true (default): pay now from the wallet. false: book now and pay by a direct external
    // payment; the booking stays "pending_payment" until the provider confirms it.
    payFromWallet: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const { userId: guestId } = await requireSelf(ctx, args.sessionToken, args.guestId);

    if (args.checkInTimestamp >= args.checkOutTimestamp) {
      throw new Error("Check-out time must be after check-in time.");
    }

    const room = await ctx.db.get(args.roomId);
    if (!room || !room.isAvailable) throw new Error("This room is currently unavailable.");
    const hotel = await ctx.db.get(args.hotelId);
    if (!hotel) throw new Error("Hotel profile not found.");
    if (room.hotelId !== args.hotelId) throw new Error("This room does not belong to the selected hotel.");
    if (hotel.userId === guestId) throw new Error("You cannot book your own property.");
    // A booking (and so money) is accepted only while the property is admin-verified, its operator's
    // role is approved AND their paid subscription is active — checked here, at booking time.
    const operating = await hotelOperatingPermission(ctx, hotel);
    if (!operating.allowed) throw new Error(`This property cannot take bookings: ${operating.reason}`);

    if ((await countOverlaps(ctx, args.roomId, args.checkInTimestamp, args.checkOutTimestamp)) >= room.totalRoomUnits) {
      throw new Error(
        "All units for this room type are fully booked for the selected time slot. Please choose another date or room."
      );
    }

    // Price is computed from the ROOM, never from the client.
    let subtotal = 0;
    if (args.bookingCategory === "hourly") {
      if (!room.supportsHourly || !room.pricePerHour) throw new Error("This room does not support hourly short-stays.");
      subtotal = room.pricePerHour * Math.max(1, args.numberOfHours ?? 1);
    } else {
      if (!room.pricePerNight) throw new Error("Nightly price is not configured for this room.");
      subtotal = room.pricePerNight * Math.max(1, args.numberOfNights ?? 1);
    }
    const payNow = args.payFromWallet ?? true;
    const now = Date.now();
    // Fee & Commission Engine (default: 10% commission from the operator, whole leones, as before).
    const fees = await priceOrder(ctx, "hotel_booking", subtotal, { hasAgent: false, now });
    const commissionAmount = fees.platformTotal;
    const operatorPayout = fees.payeeNet;
    const guestTotal = fees.buyerTotal;
    const bookingRef = `HB-${now.toString(36).toUpperCase()}-${Math.floor(1000 + Math.random() * 9000)}`;

    const bookingId = await ctx.db.insert("hotel_bookings", {
      bookingReference: bookingRef,
      hotelId: args.hotelId,
      roomId: args.roomId,
      guestId,
      guestName: args.guestName,
      guestPhone: args.guestPhone,
      guestEmail: args.guestEmail,
      bookingCategory: args.bookingCategory,
      checkInTimestamp: args.checkInTimestamp,
      checkOutTimestamp: args.checkOutTimestamp,
      numberOfGuests: args.numberOfGuests,
      numberOfNights: args.numberOfNights,
      numberOfHours: args.numberOfHours,
      subtotalAmount: subtotal,
      platformCommissionRate: fees.ownerFeeBps / 10000,
      platformCommissionAmount: commissionAmount,
      operatorPayoutAmount: operatorPayout,
      guestTotalAmount: guestTotal,
      feeSnapshot: fees,
      currency: "SLE",
      status: payNow ? "in_escrow" : "pending_payment",
      escrowLockedAt: payNow ? now : undefined,
      specialRequests: args.specialRequests,
      createdAt: now,
      updatedAt: now,
    });

    if (payNow) {
      // Real money moves here or the whole mutation (including the booking row) rolls back.
      await holdFunds(ctx, {
        userId: guestId,
        amount: guestTotal,
        referenceType: "hotel_booking",
        referenceId: bookingRef,
        idempotencyKey: `hotel:${bookingId}`,
        counterpartyId: hotel.userId,
        description: `Hotel booking ${bookingRef} held in escrow`,
      });
    }

    return {
      bookingId,
      bookingReference: bookingRef,
      subtotalAmount: subtotal,
      guestTotalAmount: guestTotal,
      platformCommissionAmount: commissionAmount,
      operatorPayoutAmount: operatorPayout,
      status: payNow ? "in_escrow" : "pending_payment",
      message: payNow
        ? "Booking confirmed. Your payment is held in Vektolux Escrow until the stay is completed."
        : "Booking reserved. Complete the payment to confirm it.",
    };
  },
});

/**
 * INTERNAL: a provider-VERIFIED external payment confirms a pending booking and funds escrow
 * directly (no wallet top-up needed). Idempotent on the provider reference.
 */
export const confirmHotelBookingPayment = internalMutation({
  args: {
    bookingId: v.id("hotel_bookings"),
    providerReference: v.string(),
    amountPaid: v.number(),
    provider: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found.");
    if (booking.status === "in_escrow") return { success: true, alreadyProcessed: true };
    if (booking.status !== "pending_payment") {
      throw new Error(`Booking cannot be paid in status '${booking.status}'.`);
    }
    if (args.amountPaid + 0.005 < heldAmount(booking)) {
      throw new Error("AMOUNT_MISMATCH: The verified payment is less than the booking total.");
    }
    const room = await ctx.db.get(booking.roomId);
    if (room && (await countOverlaps(ctx, booking.roomId, booking.checkInTimestamp, booking.checkOutTimestamp)) >= room.totalRoomUnits) {
      throw new Error("The room was booked by someone else while payment was pending; refund required.");
    }
    const hotel = await ctx.db.get(booking.hotelId);
    await fundEscrowFromExternalPayment(ctx, {
      userId: booking.guestId,
      amount: heldAmount(booking),
      provider: args.provider ?? "mobile_money",
      providerReference: args.providerReference,
      referenceType: "hotel_booking",
      referenceId: booking.bookingReference,
      counterpartyId: hotel?.userId,
    });
    const now = Date.now();
    await ctx.db.patch(booking._id, { status: "in_escrow", escrowLockedAt: now, paymentGatewayRef: args.providerReference, updatedAt: now });
    return { success: true, alreadyProcessed: false };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 2. CONFIRM CHECK-IN (Guest or Hotel Arrival Confirmation)
// ═══════════════════════════════════════════════════════════════════════

export const confirmCheckIn = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    bookingId: v.id("hotel_bookings"),
    callerUserId: v.optional(v.id("users")), // ignored
  },
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found.");
    const hotel = await ctx.db.get(booking.hotelId);
    await requireParticipantOrAdmin(ctx, args.sessionToken, [booking.guestId, hotel?.userId]);

    if (booking.status !== "in_escrow") {
      throw new Error(`Cannot check in. Current booking status is '${booking.status}'.`);
    }
    const now = Date.now();
    await ctx.db.patch(args.bookingId, { status: "checked_in", checkedInAt: now, updatedAt: now });
    return {
      success: true,
      bookingReference: booking.bookingReference,
      status: "checked_in",
      message: "Check-in confirmed! Escrow payout is now queued for settlement.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 3. RELEASE ESCROW PAYOUT (Transfer Net Funds to Operator)
// ═══════════════════════════════════════════════════════════════════════

async function payOperatorFromEscrow(ctx: { db: any }, booking: Doc<"hotel_bookings">, hotel: Doc<"hotel_profiles">, key: string) {
  // Moves REAL escrowed funds (throws if they are not actually held in the guest's escrow).
  await releaseHeldFunds(ctx, {
    buyerId: booking.guestId,
    recipientId: hotel.userId,
    amount: heldAmount(booking),
    platformFee: booking.platformCommissionAmount,
    currency: booking.currency,
    referenceType: "hotel_booking",
    referenceId: booking.bookingReference,
    idempotencyKey: key,
  });
}

export const releaseEscrowPayout = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    bookingId: v.id("hotel_bookings"),
    adminUserId: v.optional(v.id("users")), // ignored
  },
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found.");
    const hotel = await ctx.db.get(booking.hotelId);
    if (!hotel) throw new Error("Associated hotel profile not found.");

    // The guest (confirming the stay), the operator (after the stay) or an admin.
    await requireParticipantOrAdmin(ctx, args.sessionToken, [booking.guestId, hotel.userId]);

    const now = Date.now();
    // Who may release, and when (the operator can never pay themselves before the guest had a
    // chance to report a problem):
    //   guest  — after check-in, or once the stay has ended;
    //   admin  — once checked in or the stay has ended;
    //   hotel  — only 24h after check-out, if not disputed.
    const caller = await requireSelf(ctx, args.sessionToken);
    const isAdmin = caller.user.role === "admin";
    const isGuest = String(caller.userId) === String(booking.guestId);
    const active = booking.status === "in_escrow" || booking.status === "checked_in";
    const stayEnded = now >= booking.checkOutTimestamp;
    // A suspended / rejected / unverified property cannot pull its own payout; the guest or an admin decides.
    const operatorMayRelease = hotelIsVerified(hotel) && now >= booking.checkOutTimestamp + HOTEL_OPERATOR_RELEASE_DELAY_MS;
    const isEligible = active && (
      isGuest || isAdmin
        ? booking.status === "checked_in" || stayEnded
        : operatorMayRelease
    );
    if (!isEligible) {
      throw new Error(
        `Booking is not eligible for payout yet. Current status: '${booking.status}'. ` +
          (isGuest || isAdmin ? "The guest must check in or the stay must complete." : "The hotel can request payout 24 hours after check-out.")
      );
    }

    await payOperatorFromEscrow(ctx, booking, hotel, `hotel-release:${booking._id}`);
    await ctx.db.patch(args.bookingId, { status: "completed_payout", payoutReleasedAt: now, updatedAt: now });
    return { success: true, amountPaid: booking.operatorPayoutAmount, currency: "SLE", operatorUserId: hotel.userId };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 4. RAISE DISPUTE & ESCROW FREEZE
// ═══════════════════════════════════════════════════════════════════════

export const raiseDispute = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    bookingId: v.id("hotel_bookings"),
    callerUserId: v.optional(v.id("users")), // ignored
    reason: v.string(),
  },
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found.");
    const hotel = await ctx.db.get(booking.hotelId);
    await requireParticipantOrAdmin(ctx, args.sessionToken, [booking.guestId, hotel?.userId]);

    if (booking.status !== "in_escrow" && booking.status !== "checked_in") {
      throw new Error("Only a booking with funds in escrow can be disputed.");
    }
    const now = Date.now();
    await ctx.db.patch(args.bookingId, {
      status: "disputed",
      disputeReason: args.reason.trim().slice(0, 1000),
      disputedAt: now,
      updatedAt: now,
    });
    return { success: true, status: "disputed", message: "Escrow funds frozen. Vektolux dispute resolution desk has been notified." };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 5. ADMIN DISPUTE RESOLUTION
// ═══════════════════════════════════════════════════════════════════════

export const adminResolveDispute = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    bookingId: v.id("hotel_bookings"),
    resolution: v.union(v.literal("refund_guest"), v.literal("release_to_operator")),
    adminNotes: v.string(),
  },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found.");
    if (booking.status !== "disputed") throw new Error("Only a disputed booking can be resolved.");
    const now = Date.now();

    if (args.resolution === "refund_guest") {
      await refundHeldFunds(ctx, {
        userId: booking.guestId,
        amount: heldAmount(booking),
        currency: booking.currency,
        referenceType: "hotel_booking_dispute",
        referenceId: booking.bookingReference,
        idempotencyKey: `hotel-refund:${booking._id}`,
      });
      await ctx.db.patch(args.bookingId, { status: "refunded", updatedAt: now });
      return { success: true, resolution: "refunded_to_guest" };
    }

    const hotel = await ctx.db.get(booking.hotelId);
    if (!hotel) throw new Error("Hotel not found.");
    await payOperatorFromEscrow(ctx, booking, hotel, `hotel-release:${booking._id}`);
    await ctx.db.patch(args.bookingId, { status: "completed_payout", payoutReleasedAt: now, updatedAt: now });
    return { success: true, resolution: "released_to_operator" };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 6. ADMIN VIEW OF HELD ESCROW FUNDS
// ═══════════════════════════════════════════════════════════════════════

export const adminGetEscrowFunds = query({
  args: {
    sessionToken: v.optional(v.string()),
    statusFilter: v.optional(v.union(v.literal("in_escrow"), v.literal("checked_in"), v.literal("disputed"))),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    await requireAdminSession(ctx, args.sessionToken);
    const max = Math.min(args.limit ?? 50, 100);
    const bookings = await ctx.db.query("hotel_bookings").order("desc").take(max * 2);

    const filtered = bookings.filter((b) => {
      if (args.statusFilter) return b.status === args.statusFilter;
      return b.status === "in_escrow" || b.status === "checked_in" || b.status === "disputed";
    });

    let totalEscrowHeld = 0;
    const items = [];
    for (const b of filtered.slice(0, max)) {
      totalEscrowHeld += heldAmount(b);
      const hotel = await ctx.db.get(b.hotelId);
      const room = await ctx.db.get(b.roomId);
      items.push({
        id: b._id,
        bookingReference: b.bookingReference,
        hotelName: hotel?.businessName ?? "Unknown Hotel",
        roomName: room?.name ?? "Room",
        guestName: b.guestName,
        guestPhone: b.guestPhone,
        checkInTimestamp: b.checkInTimestamp,
        checkOutTimestamp: b.checkOutTimestamp,
        subtotalAmount: b.subtotalAmount,
        commissionAmount: b.platformCommissionAmount,
        operatorPayoutAmount: b.operatorPayoutAmount,
        status: b.status,
        disputeReason: b.disputeReason,
        createdAt: b.createdAt,
      });
    }
    return { totalEscrowHeld, currency: "SLE", count: items.length, bookings: items };
  },
});
