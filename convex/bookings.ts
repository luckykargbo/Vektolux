// convex/bookings.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Universal Booking Engine
// Handles: hourly stays, vehicle rentals, site visits, and inspection bookings.
// Includes collision check to prevent double bookings & platform fee calc.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { universalBookingType, paymentMethod } from "./schema";

// ═══════════════════════════════════════════════════════════════════════
//                        CREATE BOOKING
// ═══════════════════════════════════════════════════════════════════════

export const createBooking = mutation({
  args: {
    listingId: v.string(),
    listingType: v.union(v.literal("property"), v.literal("vehicle")),
    listingTitle: v.string(),
    buyerId: v.string(),
    buyerName: v.optional(v.string()),
    buyerPhone: v.optional(v.string()),
    vendorId: v.string(),
    bookingType: universalBookingType,
    startTime: v.number(),
    endTime: v.number(),
    hours: v.optional(v.number()),
    days: v.optional(v.number()),
    rate: v.optional(v.number()),
    paymentMethod: v.optional(paymentMethod),
    notes: v.optional(v.string()),
  },
  returns: v.object({
    bookingId: v.string(),
    txRef: v.string(),
    totalAmount: v.number(),
    subtotal: v.number(),
    serviceFee: v.number(),
    status: v.string(),
    paymentStatus: v.string(),
  }),
  handler: async (ctx, args) => {
    // 1. Double-booking check: verify slot availability
    const existingBookings = await ctx.db
      .query("bookings")
      .withIndex("by_listing", (q) => q.eq("listingId", args.listingId))
      .filter((q) =>
        q.and(
          q.neq(q.field("status"), "cancelled"),
          q.lt(q.field("startTime"), args.endTime),
          q.gt(q.field("endTime"), args.startTime)
        )
      )
      .collect();

    if (existingBookings.length > 0) {
      throw new Error(
        "This time slot is already booked. Please select another time or date."
      );
    }

    const now = Date.now();
    const txRef = `vktlx_booking_${now}_${Math.random().toString(36).substring(2, 8)}`;

    let subtotal = 0;
    let serviceFee = 0;
    let totalAmount = 0;
    let status: "pending_payment" | "confirmed" = "pending_payment";
    let paymentStatus: "pending" | "completed" = "pending";

    // 2. Financial calculation per booking type
    if (
      args.bookingType === "property_inspection" ||
      args.bookingType === "vehicle_inspection"
    ) {
      // Free complimentary inspection
      subtotal = 0;
      serviceFee = 0;
      totalAmount = 0;
      status = "confirmed";
      paymentStatus = "completed";
    } else if (args.bookingType === "hourly_guesthouse") {
      const hours =
        args.hours ??
        Math.max(
          1,
          Math.round((args.endTime - args.startTime) / (1000 * 60 * 60))
        );
      let unitRate = args.rate;
      if (!unitRate) {
        const propId = ctx.db.normalizeId("realEstateListings", args.listingId);
        if (propId) {
          const prop = await ctx.db.get(propId);
          unitRate = prop?.hourlyRate ?? 50;
        } else {
          unitRate = 50;
        }
      }
      subtotal = Math.round(unitRate * hours);
      serviceFee = Math.round(subtotal * 0.05); // 5% platform service fee
      totalAmount = subtotal + serviceFee;
      status = "pending_payment";
      paymentStatus = "pending";
    } else if (args.bookingType === "vehicle_rental") {
      const days =
        args.days ??
        Math.max(
          1,
          Math.round((args.endTime - args.startTime) / (1000 * 60 * 60 * 24))
        );
      let unitRate = args.rate;
      if (!unitRate) {
        const vehId = ctx.db.normalizeId("vehicleListings", args.listingId);
        if (vehId) {
          const veh = await ctx.db.get(vehId);
          unitRate = veh?.pricePerDay ?? 300;
        } else {
          unitRate = 300;
        }
      }
      subtotal = Math.round(unitRate * days);
      serviceFee = Math.round(subtotal * 0.05);
      totalAmount = subtotal + serviceFee;
      status = "pending_payment";
      paymentStatus = "pending";
    }

    // 3. Insert record into bookings collection
    const bookingId = await ctx.db.insert("bookings", {
      listingId: args.listingId,
      listingType: args.listingType,
      listingTitle: args.listingTitle,
      buyerId: args.buyerId,
      buyerName: args.buyerName,
      buyerPhone: args.buyerPhone,
      vendorId: args.vendorId,
      bookingType: args.bookingType,
      status,
      startTime: args.startTime,
      endTime: args.endTime,
      hours: args.hours,
      days: args.days,
      subtotal,
      serviceFee,
      totalAmount,
      currency: "SLE",
      paymentStatus,
      paymentMethod: args.paymentMethod,
      txRef,
      notes: args.notes,
      updatedAt: now,
    });

    // 4. If paid booking, insert linked payment intent
    if (totalAmount > 0) {
      const buyerIdNorm = ctx.db.normalizeId("users", args.buyerId);
      const vendorIdNorm = ctx.db.normalizeId("users", args.vendorId);

      if (buyerIdNorm && vendorIdNorm) {
        const platformCommission = Math.round(totalAmount * 0.15); // 15% platform commission
        const vendorPayout = totalAmount - platformCommission; // 85% vendor payout

        await ctx.db.insert("paymentIntents", {
          userId: buyerIdNorm,
          amount: totalAmount,
          currency: "SLE",
          paymentMethod: args.paymentMethod ?? "mobile_money",
          gatewayProvider: "flutterwave",
          referenceType: args.bookingType,
          referenceId: bookingId,
          platformFeeBps: 1500, // 15%
          platformFeeAmount: platformCommission,
          vendorPayoutAmount: vendorPayout,
          vendorId: vendorIdNorm,
          status: "pending",
          idempotencyKey: txRef,
          webhookVerified: false,
          updatedAt: now,
        });
      }
    }

    return {
      bookingId: bookingId as string,
      txRef,
      totalAmount,
      subtotal,
      serviceFee,
      status,
      paymentStatus,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                        GET USER BOOKINGS
// ═══════════════════════════════════════════════════════════════════════

export const getUserBookings = query({
  args: {
    buyerId: v.string(),
  },
  handler: async (ctx, args) => {
    const list = await ctx.db
      .query("bookings")
      .withIndex("by_buyer", (q) => q.eq("buyerId", args.buyerId))
      .collect();

    // Order descending by start time
    return list.sort((a, b) => b.startTime - a.startTime);
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                       GET VENDOR BOOKINGS
// ═══════════════════════════════════════════════════════════════════════

export const getVendorBookings = query({
  args: {
    vendorId: v.string(),
  },
  handler: async (ctx, args) => {
    const list = await ctx.db
      .query("bookings")
      .withIndex("by_vendor", (q) => q.eq("vendorId", args.vendorId))
      .collect();

    return list.sort((a, b) => b.startTime - a.startTime);
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                       GET BOOKING BY ID
// ═══════════════════════════════════════════════════════════════════════

export const getBookingById = query({
  args: {
    bookingId: v.string(),
  },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("bookings", args.bookingId);
    if (!id) return null;
    return await ctx.db.get(id);
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                         CANCEL BOOKING
// ═══════════════════════════════════════════════════════════════════════

export const cancelBooking = mutation({
  args: {
    bookingId: v.string(),
    userId: v.string(),
    reason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("bookings", args.bookingId);
    if (!id) throw new Error("Booking not found");

    const booking = await ctx.db.get(id);
    if (!booking) throw new Error("Booking not found");

    if (booking.buyerId !== args.userId && booking.vendorId !== args.userId) {
      throw new Error("You are not authorized to cancel this booking");
    }

    if (booking.status === "completed") {
      throw new Error("Cannot cancel an already completed booking");
    }

    const now = Date.now();
    await ctx.db.patch(id, {
      status: "cancelled",
      cancelledAt: now,
      cancelReason: args.reason ?? "Cancelled by user",
      updatedAt: now,
    });

    return true;
  },
});
