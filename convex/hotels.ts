// convex/hotels.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Hotel & Guest House Hospitality Management Backend
// Supports hotels, short-stay guest houses, hourly day-rooms,
// verified vendor badging, and inventory management.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// ═══════════════════════════════════════════════════════════════════════
// 1. CREATE HOTEL / GUEST HOUSE PROFILE
// ═══════════════════════════════════════════════════════════════════════

export const createHotelProfile = mutation({
  args: {
    userId: v.id("users"),
    businessName: v.string(),
    operationalType: v.union(v.literal("hotel"), v.literal("guest_house")),
    address: v.string(),
    city: v.string(),
    phone: v.string(),
    email: v.optional(v.string()),
    description: v.string(),
    amenities: v.array(v.string()),
    supportsHourlyStays: v.boolean(),
    tinNumber: v.optional(v.string()),
    commercialLicenseUrl: v.optional(v.string()),
    coverImageUrl: v.optional(v.string()),
    mediaUrls: v.optional(v.array(v.string())),
    checkInTime: v.optional(v.string()),
    checkOutTime: v.optional(v.string()),
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    // 1. Verify user exists and upgrade role to hotel_operator if needed
    const user = await ctx.db.get(args.userId);
    if (!user) {
      throw new Error("User does not exist.");
    }

    if (user.role !== "hotel_operator" && user.role !== "admin") {
      await ctx.db.patch(args.userId, {
        role: "hotel_operator",
        updatedAt: Date.now(),
      });
    }

    // 2. Prevent duplicate hotel profile for the same user
    const existing = await ctx.db
      .query("hotel_profiles")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .first();

    if (existing) {
      throw new Error("A hotel or guest house profile already exists for this account.");
    }

    const now = Date.now();

    const hotelId = await ctx.db.insert("hotel_profiles", {
      userId: args.userId,
      businessName: args.businessName,
      operationalType: args.operationalType,
      isVerified: false,
      verificationStatus: "pending",
      tinNumber: args.tinNumber,
      commercialLicenseUrl: args.commercialLicenseUrl,
      address: args.address,
      city: args.city,
      latitude: args.latitude,
      longitude: args.longitude,
      phone: args.phone,
      email: args.email,
      amenities: args.amenities,
      coverImageUrl: args.coverImageUrl,
      mediaUrls: args.mediaUrls ?? [],
      description: args.description,
      starRating: args.operationalType === "hotel" ? 3.0 : undefined,
      checkInTime: args.checkInTime ?? "14:00",
      checkOutTime: args.checkOutTime ?? "11:00",
      supportsHourlyStays: args.supportsHourlyStays,
      updatedAt: now,
    });

    return {
      hotelId,
      message: "Hotel profile created successfully. Submit subscription to activate verified status.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 2. UPDATE HOTEL PROFILE
// ═══════════════════════════════════════════════════════════════════════

export const updateHotelProfile = mutation({
  args: {
    hotelId: v.id("hotel_profiles"),
    businessName: v.optional(v.string()),
    description: v.optional(v.string()),
    address: v.optional(v.string()),
    city: v.optional(v.string()),
    phone: v.optional(v.string()),
    email: v.optional(v.string()),
    amenities: v.optional(v.array(v.string())),
    coverImageUrl: v.optional(v.string()),
    mediaUrls: v.optional(v.array(v.string())),
    checkInTime: v.optional(v.string()),
    checkOutTime: v.optional(v.string()),
    supportsHourlyStays: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const hotel = await ctx.db.get(args.hotelId);
    if (!hotel) {
      throw new Error("Hotel profile not found.");
    }

    const updates: Record<string, unknown> = { updatedAt: Date.now() };
    if (args.businessName !== undefined) updates.businessName = args.businessName;
    if (args.description !== undefined) updates.description = args.description;
    if (args.address !== undefined) updates.address = args.address;
    if (args.city !== undefined) updates.city = args.city;
    if (args.phone !== undefined) updates.phone = args.phone;
    if (args.email !== undefined) updates.email = args.email;
    if (args.amenities !== undefined) updates.amenities = args.amenities;
    if (args.coverImageUrl !== undefined) updates.coverImageUrl = args.coverImageUrl;
    if (args.mediaUrls !== undefined) updates.mediaUrls = args.mediaUrls;
    if (args.checkInTime !== undefined) updates.checkInTime = args.checkInTime;
    if (args.checkOutTime !== undefined) updates.checkOutTime = args.checkOutTime;
    if (args.supportsHourlyStays !== undefined) updates.supportsHourlyStays = args.supportsHourlyStays;

    await ctx.db.patch(args.hotelId, updates);
    return { success: true };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 3. ADD ROOM / INVENTORY UNIT
// ═══════════════════════════════════════════════════════════════════════

export const addRoom = mutation({
  args: {
    hotelId: v.id("hotel_profiles"),
    name: v.string(),
    roomType: v.union(
      v.literal("Standard"),
      v.literal("Deluxe"),
      v.literal("Suite"),
      v.literal("Executive"),
      v.literal("Hourly Short-Stay")
    ),
    pricePerNight: v.optional(v.number()),
    pricePerHour: v.optional(v.number()),
    supportsHourly: v.boolean(),
    capacityGuests: v.number(),
    bedConfiguration: v.string(),
    amenities: v.array(v.string()),
    images: v.array(v.string()),
    totalRoomUnits: v.number(),
  },
  handler: async (ctx, args) => {
    const hotel = await ctx.db.get(args.hotelId);
    if (!hotel) {
      throw new Error("Hotel not found.");
    }

    if (!args.pricePerNight && !args.pricePerHour) {
      throw new Error("Must provide either a price per night or a price per hour.");
    }

    const roomId = await ctx.db.insert("hotel_rooms", {
      hotelId: args.hotelId,
      name: args.name,
      roomType: args.roomType,
      pricePerNight: args.pricePerNight,
      pricePerHour: args.pricePerHour,
      supportsHourly: args.supportsHourly,
      capacityGuests: args.capacityGuests,
      bedConfiguration: args.bedConfiguration,
      amenities: args.amenities,
      images: args.images,
      isAvailable: true,
      totalRoomUnits: Math.max(1, args.totalRoomUnits),
      createdAt: Date.now(),
      updatedAt: Date.now(),
    });

    return { roomId, message: "Room added successfully." };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 4. GET HOTELS (Public Query — Verified First with Green Badges)
// ═══════════════════════════════════════════════════════════════════════

export const getHotels = query({
  args: {
    city: v.optional(v.string()),
    operationalType: v.optional(v.union(v.literal("hotel"), v.literal("guest_house"))),
    onlyHourly: v.optional(v.boolean()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const max = args.limit ?? 25;
    const hotels = await ctx.db.query("hotel_profiles").take(max * 2);

    const filtered = hotels.filter((h) => {
      if (args.city && h.city.toLowerCase() !== args.city.toLowerCase()) return false;
      if (args.operationalType && h.operationalType !== args.operationalType) return false;
      if (args.onlyHourly && !h.supportsHourlyStays) return false;
      return true;
    });

    // Sort: Verified vendors always float to top with green badges
    filtered.sort((a, b) => {
      if (a.isVerified === b.isVerified) {
        return b.updatedAt - a.updatedAt;
      }
      return a.isVerified ? -1 : 1;
    });

    return filtered.slice(0, max).map((h) => ({
      id: h._id,
      businessName: h.businessName,
      operationalType: h.operationalType,
      isVerified: h.isVerified,
      starRating: h.starRating,
      city: h.city,
      address: h.address,
      phone: h.phone,
      coverImageUrl: h.coverImageUrl,
      mediaUrls: h.mediaUrls,
      amenities: h.amenities,
      supportsHourlyStays: h.supportsHourlyStays,
      checkInTime: h.checkInTime,
      checkOutTime: h.checkOutTime,
      description: h.description,
    }));
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 5. GET HOTEL DETAILS & ROOMS
// ═══════════════════════════════════════════════════════════════════════

export const getHotelDetails = query({
  args: {
    hotelId: v.id("hotel_profiles"),
  },
  handler: async (ctx, args) => {
    const hotel = await ctx.db.get(args.hotelId);
    if (!hotel) return null;

    const rooms = await ctx.db
      .query("hotel_rooms")
      .withIndex("by_hotelId_and_isAvailable", (q) =>
        q.eq("hotelId", args.hotelId).eq("isAvailable", true)
      )
      .collect();

    return {
      hotel,
      rooms,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 6. GET OPERATOR DASHBOARD DATA
// ═══════════════════════════════════════════════════════════════════════

export const getOperatorDashboardData = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const hotel = await ctx.db
      .query("hotel_profiles")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .first();

    if (!hotel) return null;

    const rooms = await ctx.db
      .query("hotel_rooms")
      .withIndex("by_hotelId", (q) => q.eq("hotelId", hotel._id))
      .collect();

    const activeBookings = await ctx.db
      .query("hotel_bookings")
      .withIndex("by_hotelId", (q) => q.eq("hotelId", hotel._id))
      .filter((q) =>
        q.or(
          q.eq(q.field("status"), "in_escrow"),
          q.eq(q.field("status"), "checked_in")
        )
      )
      .take(50);

    // Operator Wallet Balance
    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .first();

    // Held in Escrow across all upcoming stays
    const pendingEscrowTotal = activeBookings.reduce(
      (sum, b) => sum + b.operatorPayoutAmount,
      0
    );

    return {
      hotel,
      roomsCount: rooms.length,
      rooms,
      activeBookingsCount: activeBookings.length,
      activeBookings,
      walletBalance: wallet?.availableBalance ?? 0,
      pendingEscrowTotal,
      currency: "SLE",
    };
  },
});
