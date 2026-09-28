// convex/hotelBookings.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Hospitality Escrow Booking Engine
// Manages daily & hourly guest house stays, anti-collision reservations,
// locked escrow accounts, check-in verification, and operator payouts.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

const PLATFORM_COMMISSION_RATE = 0.10; // 10% marketplace commission

// ═══════════════════════════════════════════════════════════════════════
// 1. CREATE BOOKING WITH ESCROW
// ═══════════════════════════════════════════════════════════════════════

export const createBookingWithEscrow = mutation({
  args: {
    hotelId: v.id("hotel_profiles"),
    roomId: v.id("hotel_rooms"),
    guestId: v.id("users"),
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
  },
  handler: async (ctx, args) => {
    // 1. Verify check-in precedes check-out
    if (args.checkInTimestamp >= args.checkOutTimestamp) {
      throw new Error("Check-out time must be after check-in time.");
    }

    const room = await ctx.db.get(args.roomId);
    if (!room || !room.isAvailable) {
      throw new Error("This room is currently unavailable.");
    }

    const hotel = await ctx.db.get(args.hotelId);
    if (!hotel) {
      throw new Error("Hotel profile not found.");
    }

    // 2. Collision Check: Verify room availability within time slot
    const overlappingBookings = await ctx.db
      .query("hotel_bookings")
      .withIndex("by_roomId_and_status", (q) => q.eq("roomId", args.roomId))
      .filter((q) =>
        q.and(
          q.or(
            q.eq(q.field("status"), "in_escrow"),
            q.eq(q.field("status"), "checked_in")
          ),
          q.lt(q.field("checkInTimestamp"), args.checkOutTimestamp),
          q.gt(q.field("checkOutTimestamp"), args.checkInTimestamp)
        )
      )
      .collect();

    // Check against total room inventory units
    if (overlappingBookings.length >= room.totalRoomUnits) {
      throw new Error(
        "All units for this room type are fully booked for the selected time slot. Please choose another date or room."
      );
    }

    // 3. Compute Pricing & Escrow Allocation
    let subtotal = 0;
    if (args.bookingCategory === "hourly") {
      if (!room.supportsHourly || !room.pricePerHour) {
        throw new Error("This room does not support hourly short-stays.");
      }
      const hours = args.numberOfHours ?? 1;
      subtotal = room.pricePerHour * hours;
    } else {
      if (!room.pricePerNight) {
        throw new Error("Nightly price is not configured for this room.");
      }
      const nights = args.numberOfNights ?? 1;
      subtotal = room.pricePerNight * nights;
    }

    const commissionAmount = Math.round(subtotal * PLATFORM_COMMISSION_RATE);
    const operatorPayout = subtotal - commissionAmount;

    // 4. Generate Unique Reference & Insert Booking Locked in Escrow
    const now = Date.now();
    const bookingRef = `HB-${Date.now().toString(36).toUpperCase()}-${Math.floor(1000 + Math.random() * 9000)}`;

    const bookingId = await ctx.db.insert("hotel_bookings", {
      bookingReference: bookingRef,
      hotelId: args.hotelId,
      roomId: args.roomId,
      guestId: args.guestId,
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
      platformCommissionRate: PLATFORM_COMMISSION_RATE,
      platformCommissionAmount: commissionAmount,
      operatorPayoutAmount: operatorPayout,
      currency: "SLE",
      status: "in_escrow", // Locked into Escrow Protection upon creation
      escrowLockedAt: now,
      specialRequests: args.specialRequests,
      createdAt: now,
      updatedAt: now,
    });

    return {
      bookingId,
      bookingReference: bookingRef,
      subtotalAmount: subtotal,
      platformCommissionAmount: commissionAmount,
      operatorPayoutAmount: operatorPayout,
      status: "in_escrow",
      message: "Booking confirmed! SLE funds are secured in Vektolux Escrow Protection.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 2. CONFIRM CHECK-IN (Guest or Hotel Arrival Confirmation)
// ═══════════════════════════════════════════════════════════════════════

export const confirmCheckIn = mutation({
  args: {
    bookingId: v.id("hotel_bookings"),
    callerUserId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) {
      throw new Error("Booking not found.");
    }

    if (booking.status !== "in_escrow") {
      throw new Error(`Cannot check in. Current booking status is '${booking.status}'.`);
    }

    const hotel = await ctx.db.get(booking.hotelId);
    const isGuest = booking.guestId === args.callerUserId;
    const isOperator = hotel?.userId === args.callerUserId;

    if (!isGuest && !isOperator) {
      throw new Error("Unauthorized to confirm check-in for this booking.");
    }

    const now = Date.now();
    await ctx.db.patch(args.bookingId, {
      status: "checked_in",
      checkedInAt: now,
      updatedAt: now,
    });

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

export const releaseEscrowPayout = mutation({
  args: {
    bookingId: v.id("hotel_bookings"),
    adminUserId: v.optional(v.id("users")),
  },
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) {
      throw new Error("Booking not found.");
    }

    // Must be either checked_in or in_escrow past checkout time
    const now = Date.now();
    const isEligible =
      booking.status === "checked_in" ||
      (booking.status === "in_escrow" && now >= booking.checkOutTimestamp);

    if (!isEligible) {
      throw new Error(
        `Booking is not eligible for payout yet. Current status: '${booking.status}'. Guest must check in or stay must complete.`
      );
    }

    const hotel = await ctx.db.get(booking.hotelId);
    if (!hotel) {
      throw new Error("Associated hotel profile not found.");
    }

    // Credit Operator Wallet
    const operatorWallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user", (q) => q.eq("userId", hotel.userId))
      .first();

    let opWalletId = operatorWallet?._id;
    if (operatorWallet) {
      await ctx.db.patch(operatorWallet._id, {
        availableBalance: operatorWallet.availableBalance + booking.operatorPayoutAmount,
        updatedAt: now,
      });
    } else {
      opWalletId = await ctx.db.insert("walletBalances", {
        userId: hotel.userId,
        availableBalance: booking.operatorPayoutAmount,
        pendingBalance: 0,
        currency: "SLE",
        updatedAt: now,
      });
    }

    // Record in Transactions Ledger
    await ctx.db.insert("transactions", {
      walletId: opWalletId!,
      userId: hotel.userId,
      amount: booking.operatorPayoutAmount,
      currency: "SLE",
      type: "escrow_release",
      status: "completed",
      referenceType: "hotel_booking",
      referenceId: booking.bookingReference,
      feeAmount: booking.platformCommissionAmount,
      netAmount: booking.operatorPayoutAmount,
      description: `Hospitality Escrow Payout: ${booking.bookingReference} (Net of ${PLATFORM_COMMISSION_RATE * 100}% fee)`,
      createdAt: now,
      updatedAt: now,
    });

    // Mark Booking Complete
    await ctx.db.patch(args.bookingId, {
      status: "completed_payout",
      payoutReleasedAt: now,
      updatedAt: now,
    });

    return {
      success: true,
      amountPaid: booking.operatorPayoutAmount,
      currency: "SLE",
      operatorUserId: hotel.userId,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 4. RAISE DISPUTE & ESCROW FREEZE
// ═══════════════════════════════════════════════════════════════════════

export const raiseDispute = mutation({
  args: {
    bookingId: v.id("hotel_bookings"),
    callerUserId: v.id("users"),
    reason: v.string(),
  },
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found.");

    if (booking.status === "completed_payout" || booking.status === "refunded") {
      throw new Error("Cannot dispute a completed or refunded transaction.");
    }

    const now = Date.now();
    await ctx.db.patch(args.bookingId, {
      status: "disputed",
      disputeReason: args.reason,
      disputedAt: now,
      updatedAt: now,
    });

    return {
      success: true,
      status: "disputed",
      message: "Escrow funds frozen. Vektolux dispute resolution desk has been notified.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 5. ADMIN DISPUTE RESOLUTION & MANUAL OVERRIDE
// ═══════════════════════════════════════════════════════════════════════

export const adminResolveDispute = mutation({
  args: {
    bookingId: v.id("hotel_bookings"),
    resolution: v.union(v.literal("refund_guest"), v.literal("release_to_operator")),
    adminNotes: v.string(),
  },
  handler: async (ctx, args) => {
    const booking = await ctx.db.get(args.bookingId);
    if (!booking) throw new Error("Booking not found.");

    const now = Date.now();

    if (args.resolution === "refund_guest") {
      // Refund guest wallet
      const guestWallet = await ctx.db
        .query("walletBalances")
        .withIndex("by_user", (q) => q.eq("userId", booking.guestId))
        .first();

      let guestWalletId = guestWallet?._id;
      if (guestWallet) {
        await ctx.db.patch(guestWallet._id, {
          availableBalance: guestWallet.availableBalance + booking.subtotalAmount,
          updatedAt: now,
        });
      } else {
        guestWalletId = await ctx.db.insert("walletBalances", {
          userId: booking.guestId,
          availableBalance: booking.subtotalAmount,
          pendingBalance: 0,
          currency: "SLE",
          updatedAt: now,
        });
      }

      await ctx.db.insert("transactions", {
        walletId: guestWalletId!,
        userId: booking.guestId,
        amount: booking.subtotalAmount,
        currency: "SLE",
        type: "refund",
        status: "completed",
        referenceType: "hotel_booking_dispute",
        referenceId: booking.bookingReference,
        description: `Escrow Dispute Refund: ${booking.bookingReference}`,
        createdAt: now,
        updatedAt: now,
      });

      await ctx.db.patch(args.bookingId, {
        status: "refunded",
        updatedAt: now,
      });

      return { success: true, resolution: "refunded_to_guest" };
    } else {
      // Release to operator
      const hotel = await ctx.db.get(booking.hotelId);
      if (!hotel) throw new Error("Hotel not found.");

      const operatorWallet = await ctx.db
        .query("walletBalances")
        .withIndex("by_user", (q) => q.eq("userId", hotel.userId))
        .first();

      let opWalletId = operatorWallet?._id;
      if (operatorWallet) {
        await ctx.db.patch(operatorWallet._id, {
          availableBalance: operatorWallet.availableBalance + booking.operatorPayoutAmount,
          updatedAt: now,
        });
      } else {
        opWalletId = await ctx.db.insert("walletBalances", {
          userId: hotel.userId,
          availableBalance: booking.operatorPayoutAmount,
          pendingBalance: 0,
          currency: "SLE",
          updatedAt: now,
        });
      }

      await ctx.db.insert("transactions", {
        walletId: opWalletId!,
        userId: hotel.userId,
        amount: booking.operatorPayoutAmount,
        currency: "SLE",
        type: "escrow_release",
        status: "completed",
        referenceType: "hotel_booking_dispute_resolved",
        referenceId: booking.bookingReference,
        feeAmount: booking.platformCommissionAmount,
        netAmount: booking.operatorPayoutAmount,
        description: `Dispute Settled - Payout Released: ${booking.bookingReference}`,
        createdAt: now,
        updatedAt: now,
      });

      await ctx.db.patch(args.bookingId, {
        status: "completed_payout",
        payoutReleasedAt: now,
        updatedAt: now,
      });

      return { success: true, resolution: "released_to_operator" };
    }
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 6. ADMIN VIEW OF HELD ESCROW FUNDS
// ═══════════════════════════════════════════════════════════════════════

export const adminGetEscrowFunds = query({
  args: {
    statusFilter: v.optional(
      v.union(v.literal("in_escrow"), v.literal("checked_in"), v.literal("disputed"))
    ),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const max = args.limit ?? 50;
    const bookings = await ctx.db
      .query("hotel_bookings")
      .order("desc")
      .take(max * 2);

    const filtered = bookings.filter((b) => {
      if (args.statusFilter) return b.status === args.statusFilter;
      return b.status === "in_escrow" || b.status === "checked_in" || b.status === "disputed";
    });

    let totalEscrowHeld = 0;
    const items = [];

    for (const b of filtered.slice(0, max)) {
      totalEscrowHeld += b.subtotalAmount;
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

    return {
      totalEscrowHeld,
      currency: "SLE",
      count: items.length,
      bookings: items,
    };
  },
});
