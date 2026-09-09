// convex/rides.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Geospatial Queries & Ride Fare Calculator
// Handles: nearby driver search, nearby property search, fare estimation,
//          ride request lifecycle
// ═══════════════════════════════════════════════════════════════════════

import { v } from "convex/values";
import { query, mutation, internalMutation } from "./_generated/server";
import { Doc, Id } from "./_generated/dataModel";
import {
  encodeGeohash,
  geohashNeighbors,
  haversineDistanceKm,
  precisionForRadiusKm,
  isValidLatitude,
  isValidLongitude,
} from "./lib/geo";
import { requirePositive } from "./lib/validation";

// ─── FARE CONFIGURATION ─────────────────────────────────────────────

/** Fare rates by vehicle type. All amounts in SLE (Sierra Leone Leones). */
const FARE_CONFIG: Record<
  string,
  {
    baseFare: number;
    ratePerKm: number;
    ratePerMin: number;
    minimumFare: number;
    surgeCap: number;
  }
> = {
  bike: {
    baseFare: 5,
    ratePerKm: 3.0,
    ratePerMin: 0.5,
    minimumFare: 5,
    surgeCap: 2.0,
  },
  okada: {
    baseFare: 5,
    ratePerKm: 3.0,
    ratePerMin: 0.5,
    minimumFare: 5,
    surgeCap: 2.0,
  },
  kekeh: {
    baseFare: 8,
    ratePerKm: 4.5,
    ratePerMin: 0.8,
    minimumFare: 8,
    surgeCap: 2.0,
  },
  taxi: {
    baseFare: 15,
    ratePerKm: 8.0,
    ratePerMin: 1.0,
    minimumFare: 15,
    surgeCap: 2.5,
  },
  sedan: {
    baseFare: 15,
    ratePerKm: 8.0,
    ratePerMin: 1.0,
    minimumFare: 15,
    surgeCap: 2.5,
  },
  delivery_van: {
    baseFare: 25,
    ratePerKm: 12.0,
    ratePerMin: 1.5,
    minimumFare: 25,
    surgeCap: 2.0,
  },
  suv: {
    baseFare: 25,
    ratePerKm: 12.0,
    ratePerMin: 1.5,
    minimumFare: 25,
    surgeCap: 2.0,
  },
  truck: {
    baseFare: 50,
    ratePerKm: 20.0,
    ratePerMin: 2.0,
    minimumFare: 50,
    surgeCap: 1.5,
  },
};

/** Platform commission rate in basis points (1500 = 15%). */
const PLATFORM_COMMISSION_BPS = 1500;

// ═══════════════════════════════════════════════════════════════════════
//                     GEOSPATIAL QUERIES
// ═══════════════════════════════════════════════════════════════════════

/**
 * Find active drivers near a given location.
 * Uses geohash prefix matching + Haversine refinement.
 *
 * @param lat        Center latitude
 * @param lng        Center longitude
 * @param radiusKm   Search radius in kilometers (default 5)
 * @param vehicleType Optional filter by vehicle type
 * @returns Array of nearby drivers sorted by distance (ascending)
 */
export const findNearbyDrivers = query({
  args: {
    lat: v.number(),
    lng: v.number(),
    radiusKm: v.optional(v.number()),
    vehicleType: v.optional(
      v.union(
        v.literal("bike"),
        v.literal("okada"),
        v.literal("kekeh"),
        v.literal("taxi"),
        v.literal("sedan"),
        v.literal("delivery_van"),
        v.literal("suv"),
        v.literal("truck")
      )
    ),
  },
  handler: async (ctx, args) => {
    const { lat, lng } = args;
    const radiusKm = args.radiusKm ?? 5;

    // ── Input validation ──────────────────────────────────────────
    if (!isValidLatitude(lat)) throw new Error("Invalid latitude: must be -90 to 90");
    if (!isValidLongitude(lng)) throw new Error("Invalid longitude: must be -180 to 180");
    if (radiusKm <= 0 || radiusKm > 100) {
      throw new Error("radiusKm must be between 0 and 100");
    }

    // ── Geohash prefix search ─────────────────────────────────────
    const precision = precisionForRadiusKm(radiusKm);
    const centerGeohash = encodeGeohash(lat, lng, precision);
    const searchCells = geohashNeighbors(centerGeohash);

    // ── Query drivers in matching geohash cells ───────────────────
    const candidateDrivers: Doc<"users">[] = [];

    for (const cellPrefix of searchCells) {
      const driversInCell = await ctx.db
        .query("users")
        .withIndex("by_geohash", (q) =>
          q.gte("currentGeohash", cellPrefix).lte("currentGeohash", cellPrefix + "\uffff")
        )
        .collect();

      candidateDrivers.push(...driversInCell);
    }

    // ── Filter: role=driver, isActive, has location ───────────────
    const activeDrivers = candidateDrivers.filter(
      (u) =>
        u.role === "driver" &&
        u.isActive &&
        u.currentLat !== undefined &&
        u.currentLng !== undefined
    );

    // ── Haversine refinement + optional vehicle type filter ───────
    // For vehicle type filtering, we check the driver's active vehicle
    let vehicleMap: Map<Id<"users">, Doc<"vehicleListings">> | undefined;

    if (args.vehicleType) {
      // Batch lookup: find ride_hailing vehicles for these drivers
      const vehiclePromises = activeDrivers.map(async (driver) => {
        const vehicle = await ctx.db
          .query("vehicleListings")
          .withIndex("by_owner", (q) => q.eq("ownerId", driver._id))
          .filter((q) =>
            q.and(
              q.eq(q.field("vehicleType"), args.vehicleType!),
              q.eq(q.field("listingIntent"), "ride_hailing"),
              q.eq(q.field("availabilityStatus"), "available")
            )
          )
          .first();
        return { driverId: driver._id, vehicle };
      });

      const results = await Promise.all(vehiclePromises);
      vehicleMap = new Map();
      for (const r of results) {
        if (r.vehicle) vehicleMap.set(r.driverId, r.vehicle);
      }
    }

    // ── Compute distances & build result ──────────────────────────
    type NearbyDriver = {
      driverId: Id<"users">;
      name: string;
      distanceKm: number;
      lat: number;
      lng: number;
      vehicleType?: string;
      vehicleMake?: string;
      vehicleModel?: string;
      locationUpdatedAt?: number;
    };

    const nearbyDrivers: NearbyDriver[] = [];

    for (const driver of activeDrivers) {
      // Vehicle type filter
      if (args.vehicleType && vehicleMap && !vehicleMap.has(driver._id)) {
        continue;
      }

      const distance = haversineDistanceKm(
        lat,
        lng,
        driver.currentLat!,
        driver.currentLng!
      );

      if (distance <= radiusKm) {
        const vehicle = vehicleMap?.get(driver._id);
        nearbyDrivers.push({
          driverId: driver._id,
          name: driver.name,
          distanceKm: Math.round(distance * 100) / 100,
          lat: driver.currentLat!,
          lng: driver.currentLng!,
          vehicleType: vehicle?.vehicleType,
          vehicleMake: vehicle?.make,
          vehicleModel: vehicle?.model,
          locationUpdatedAt: driver.locationUpdatedAt,
        });
      }
    }

    // ── Sort by distance ascending ────────────────────────────────
    nearbyDrivers.sort((a, b) => a.distanceKm - b.distanceKm);

    return {
      drivers: nearbyDrivers.slice(0, 20), // Cap at 20 results
      totalFound: nearbyDrivers.length,
      searchRadiusKm: radiusKm,
      geohashPrecision: precision,
    };
  },
});

/**
 * Find real estate listings near a given location.
 * Supports optional category and price range filtering.
 */
export const findNearbyProperties = query({
  args: {
    lat: v.number(),
    lng: v.number(),
    radiusKm: v.optional(v.number()),
    category: v.optional(
      v.union(
        v.literal("sale"),
        v.literal("long_term_rent"),
        v.literal("hourly_guesthouse")
      )
    ),
    minPrice: v.optional(v.number()),
    maxPrice: v.optional(v.number()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const { lat, lng } = args;
    const radiusKm = args.radiusKm ?? 10;
    const limit = args.limit ?? 50;

    if (!isValidLatitude(lat)) throw new Error("Invalid latitude");
    if (!isValidLongitude(lng)) throw new Error("Invalid longitude");

    const precision = precisionForRadiusKm(radiusKm);
    const centerGeohash = encodeGeohash(lat, lng, precision);
    const searchCells = geohashNeighbors(centerGeohash);

    // ── Fetch candidates from all geohash cells ───────────────────
    const candidates: Doc<"realEstateListings">[] = [];

    for (const cellPrefix of searchCells) {
      const listings = await ctx.db
        .query("realEstateListings")
        .withIndex("by_geohash", (q) =>
          q.gte("geohash", cellPrefix).lte("geohash", cellPrefix + "\uffff")
        )
        .collect();

      candidates.push(...listings);
    }

    // ── Filter & refine ───────────────────────────────────────────
    const results = candidates
      .filter((listing) => {
        if (listing.availabilityStatus !== "available") return false;
        if (args.category && listing.category !== args.category) return false;
        if (args.minPrice && listing.price < args.minPrice) return false;
        if (args.maxPrice && listing.price > args.maxPrice) return false;

        const distance = haversineDistanceKm(
          lat,
          lng,
          listing.latitude,
          listing.longitude
        );
        return distance <= radiusKm;
      })
      .map((listing) => ({
        ...listing,
        distanceKm:
          Math.round(
            haversineDistanceKm(lat, lng, listing.latitude, listing.longitude) *
              100
          ) / 100,
      }))
      .sort((a, b) => a.distanceKm - b.distanceKm)
      .slice(0, limit);

    return {
      listings: results,
      totalFound: results.length,
      searchRadiusKm: radiusKm,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     FARE ESTIMATION
// ═══════════════════════════════════════════════════════════════════════

/**
 * Estimate ride fare based on pickup/dropoff coordinates and vehicle type.
 *
 * Formula: Fare = Base_Fare + (Distance_KM × Rate_Per_KM) + (Duration_Min × Rate_Per_Min)
 *
 * Duration is estimated using average speed heuristics:
 *   - bike: 25 km/h
 *   - taxi: 30 km/h
 *   - delivery_van: 25 km/h
 *   - truck: 20 km/h
 *
 * Surge multiplier is clamped to vehicle-specific caps.
 */
export const estimateRideFare = query({
  args: {
    pickupLat: v.number(),
    pickupLng: v.number(),
    dropoffLat: v.number(),
    dropoffLng: v.number(),
    vehicleType: v.union(
      v.literal("bike"),
      v.literal("okada"),
      v.literal("kekeh"),
      v.literal("taxi"),
      v.literal("sedan"),
      v.literal("delivery_van"),
      v.literal("suv"),
      v.literal("truck")
    ),
    surgeMultiplier: v.optional(v.number()),
  },
  handler: async (_ctx, args) => {
    // ── Validate coordinates ──────────────────────────────────────
    if (!isValidLatitude(args.pickupLat) || !isValidLongitude(args.pickupLng)) {
      throw new Error("Invalid pickup coordinates");
    }
    if (!isValidLatitude(args.dropoffLat) || !isValidLongitude(args.dropoffLng)) {
      throw new Error("Invalid dropoff coordinates");
    }

    // ── Distance calculation ──────────────────────────────────────
    const distanceKm = haversineDistanceKm(
      args.pickupLat,
      args.pickupLng,
      args.dropoffLat,
      args.dropoffLng
    );

    if (distanceKm < 0.1) {
      throw new Error(
        "Pickup and dropoff are too close (minimum 100 meters)"
      );
    }
    if (distanceKm > 500) {
      throw new Error("Route exceeds maximum distance of 500 km");
    }

    // ── Duration estimation ───────────────────────────────────────
    const AVG_SPEEDS: Record<string, number> = {
      bike: 28,
      okada: 28,
      kekeh: 25,
      taxi: 22,
      sedan: 22,
      delivery_van: 24,
      suv: 24,
      truck: 18,
    };

    const avgSpeedKmh = AVG_SPEEDS[args.vehicleType] ?? 22;
    const estimatedDurationMin = (distanceKm / avgSpeedKmh) * 60;

    // ── Fare calculation ──────────────────────────────────────────
    const config = FARE_CONFIG[args.vehicleType];
    if (!config) {
      throw new Error(`Unknown vehicle type: ${args.vehicleType}`);
    }

    // Apply surge (clamped to vehicle-specific cap)
    let surge = args.surgeMultiplier ?? 1.0;
    surge = Math.max(1.0, Math.min(surge, config.surgeCap));

    const rawFare =
      config.baseFare +
      distanceKm * config.ratePerKm +
      estimatedDurationMin * config.ratePerMin;

    const surgedFare = Math.round(rawFare * surge);
    const finalFare = Math.max(surgedFare, config.minimumFare);

    // ── Commission split ──────────────────────────────────────────
    const platformFee = Math.round(
      (finalFare * PLATFORM_COMMISSION_BPS) / 10000
    );
    const driverPayout = finalFare - platformFee;

    return {
      distanceKm: Math.round(distanceKm * 100) / 100,
      estimatedDurationMin: Math.round(estimatedDurationMin),
      baseFare: config.baseFare,
      distanceCharge: Math.round(distanceKm * config.ratePerKm),
      durationCharge: Math.round(estimatedDurationMin * config.ratePerMin),
      surgeMultiplier: surge,
      fareBeforeSurge: Math.round(rawFare),
      fareAmount: finalFare,
      platformFee,
      driverPayout,
      currency: "SLE", // Sierra Leonean Leone
      vehicleType: args.vehicleType,
      breakdown: {
        formula:
          "Fare = Base_Fare + (Distance_KM × Rate_Per_KM) + (Duration_Min × Rate_Per_Min)",
        baseFare: config.baseFare,
        ratePerKm: config.ratePerKm,
        ratePerMin: config.ratePerMin,
        minimumFare: config.minimumFare,
      },
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     RIDE REQUEST LIFECYCLE
// ═══════════════════════════════════════════════════════════════════════

/**
 * Create a new ride request. The passenger initiates a ride and the system
 * computes the fare. Geohash is computed for the pickup location.
 */
export const requestRide = mutation({
  args: {
    passengerId: v.id("users"),
    pickupLat: v.number(),
    pickupLng: v.number(),
    pickupAddress: v.optional(v.string()),
    dropoffLat: v.number(),
    dropoffLng: v.number(),
    dropoffAddress: v.optional(v.string()),
    vehicleType: v.union(
      v.literal("bike"),
      v.literal("okada"),
      v.literal("kekeh"),
      v.literal("taxi"),
      v.literal("sedan"),
      v.literal("delivery_van"),
      v.literal("suv"),
      v.literal("truck")
    ),
  },
  handler: async (ctx, args) => {
    // ── Auth & validation ─────────────────────────────────────────
    const passenger = await ctx.db.get(args.passengerId);
    if (!passenger) throw new Error("Passenger not found");
    if (!passenger.isActive) throw new Error("Account is deactivated");

    if (!isValidLatitude(args.pickupLat) || !isValidLongitude(args.pickupLng)) {
      throw new Error("Invalid pickup coordinates");
    }
    if (!isValidLatitude(args.dropoffLat) || !isValidLongitude(args.dropoffLng)) {
      throw new Error("Invalid dropoff coordinates");
    }

    // ── Check for active ride ─────────────────────────────────────
    const activeRide = await ctx.db
      .query("rideRequests")
      .withIndex("by_passenger_status", (q) =>
        q.eq("passengerId", args.passengerId).eq("status", "in_transit")
      )
      .first();

    if (activeRide) {
      throw new Error("You already have an active ride in progress");
    }

    // ── Compute fare ──────────────────────────────────────────────
    const distanceKm = haversineDistanceKm(
      args.pickupLat,
      args.pickupLng,
      args.dropoffLat,
      args.dropoffLng
    );

    if (distanceKm < 0.1) {
      throw new Error("Pickup and dropoff are too close");
    }

    const config = FARE_CONFIG[args.vehicleType];
    const avgSpeed =
      {
        bike: 28,
        okada: 28,
        kekeh: 25,
        taxi: 22,
        sedan: 22,
        delivery_van: 24,
        suv: 24,
        truck: 18,
      }[args.vehicleType] ?? 22;
    const durationMin = (distanceKm / avgSpeed) * 60;

    const rawFare =
      config.baseFare +
      distanceKm * config.ratePerKm +
      durationMin * config.ratePerMin;
    const fareAmount = Math.max(Math.round(rawFare), config.minimumFare);

    const platformFee = Math.round(
      (fareAmount * PLATFORM_COMMISSION_BPS) / 10000
    );
    const driverPayout = fareAmount - platformFee;

    // ── Compute geohash for pickup ────────────────────────────────
    const pickupGeohash = encodeGeohash(args.pickupLat, args.pickupLng, 6);

    // ── Create ride request ───────────────────────────────────────
    const now = Date.now();
    const rideId = await ctx.db.insert("rideRequests", {
      passengerId: args.passengerId,
      pickupLat: args.pickupLat,
      pickupLng: args.pickupLng,
      pickupGeohash,
      pickupAddress: args.pickupAddress,
      dropoffLat: args.dropoffLat,
      dropoffLng: args.dropoffLng,
      dropoffAddress: args.dropoffAddress,
      distanceKm: Math.round(distanceKm * 100) / 100,
      estimatedDurationMin: Math.round(durationMin),
      fareAmount,
      currency: "SLE",
      platformFee,
      driverPayout,
      status: "requested",
      paymentStatus: "pending",
      updatedAt: now,
    });

    return {
      rideId,
      fareAmount,
      distanceKm: Math.round(distanceKm * 100) / 100,
      estimatedDurationMin: Math.round(durationMin),
      platformFee,
      driverPayout,
    };
  },
});

/**
 * Driver accepts a ride request. Updates status and assigns the driver.
 */
export const acceptRide = mutation({
  args: {
    rideId: v.id("rideRequests"),
    driverId: v.id("users"),
    vehicleId: v.id("vehicleListings"),
  },
  handler: async (ctx, args) => {
    // ── Validation ────────────────────────────────────────────────
    const ride = await ctx.db.get(args.rideId);
    if (!ride) throw new Error("Ride request not found");
    if (ride.status !== "requested") {
      throw new Error(`Cannot accept ride in status: ${ride.status}`);
    }

    const driver = await ctx.db.get(args.driverId);
    if (!driver) throw new Error("Driver not found");
    if (driver.role !== "driver") throw new Error("User is not a driver");
    if (!driver.isActive) throw new Error("Driver account is deactivated");

    const vehicle = await ctx.db.get(args.vehicleId);
    if (!vehicle) throw new Error("Vehicle not found");
    if (vehicle.ownerId !== args.driverId) {
      throw new Error("Vehicle does not belong to this driver");
    }
    if (vehicle.availabilityStatus !== "available") {
      throw new Error("Vehicle is not available");
    }

    // ── Check driver doesn't have active ride ─────────────────────
    const activeDriverRide = await ctx.db
      .query("rideRequests")
      .withIndex("by_driver_status", (q) =>
        q.eq("driverId", args.driverId).eq("status", "in_transit")
      )
      .first();

    if (activeDriverRide) {
      throw new Error("Driver already has an active ride");
    }

    // ── Update ride ───────────────────────────────────────────────
    const now = Date.now();
    await ctx.db.patch(args.rideId, {
      driverId: args.driverId,
      vehicleId: args.vehicleId,
      status: "accepted",
      acceptedAt: now,
      updatedAt: now,
    });

    // Mark vehicle as booked
    await ctx.db.patch(args.vehicleId, {
      availabilityStatus: "booked",
      updatedAt: now,
    });

    return { success: true, acceptedAt: now };
  },
});

/**
 * Update ride status through lifecycle stages.
 * driver_arriving → in_transit → completed
 */
export const updateRideStatus = mutation({
  args: {
    rideId: v.id("rideRequests"),
    driverId: v.id("users"),
    newStatus: v.union(
      v.literal("driver_arriving"),
      v.literal("arrived"),
      v.literal("in_transit"),
      v.literal("completed"),
      v.literal("cancelled")
    ),
    cancelReason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const ride = await ctx.db.get(args.rideId);
    if (!ride) throw new Error("Ride not found");

    // ── Authorization ─────────────────────────────────────────────
    if (ride.driverId !== args.driverId) {
      throw new Error("Only the assigned driver can update ride status");
    }

    // ── Valid state transitions ───────────────────────────────────
    const VALID_TRANSITIONS: Record<string, string[]> = {
      accepted: ["driver_arriving", "arrived", "cancelled"],
      driver_arriving: ["arrived", "in_transit", "cancelled"],
      arrived: ["in_transit", "cancelled"],
      in_transit: ["completed"],
    };

    const allowed = VALID_TRANSITIONS[ride.status];
    if (!allowed || !allowed.includes(args.newStatus)) {
      throw new Error(
        `Invalid transition: ${ride.status} → ${args.newStatus}`
      );
    }

    // ── Apply update ──────────────────────────────────────────────
    const now = Date.now();
    const patch: Record<string, unknown> = {
      status: args.newStatus,
      updatedAt: now,
    };

    if (args.newStatus === "arrived") {
      patch.arrivedAt = now;
    } else if (args.newStatus === "in_transit") {
      patch.startedAt = now;
    } else if (args.newStatus === "completed") {
      patch.completedAt = now;
    } else if (args.newStatus === "cancelled") {
      patch.cancelledAt = now;
      patch.cancelReason = args.cancelReason ?? "Cancelled by driver";

      // Release vehicle
      if (ride.vehicleId) {
        await ctx.db.patch(ride.vehicleId, {
          availabilityStatus: "available",
          updatedAt: now,
        });
      }
    }

    await ctx.db.patch(args.rideId, patch);

    // ── On completion: release vehicle ────────────────────────────
    if (args.newStatus === "completed" && ride.vehicleId) {
      await ctx.db.patch(ride.vehicleId, {
        availabilityStatus: "available",
        updatedAt: now,
      });
    }

    return { success: true, newStatus: args.newStatus, timestamp: now };
  },
});

/**
 * Check in driver arrival when approaching within proximity (<= 50m) of pickup.
 */
export const checkInDriverArrival = mutation({
  args: {
    rideId: v.id("rideRequests"),
    driverId: v.id("users"),
    lat: v.optional(v.number()),
    lng: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const ride = await ctx.db.get(args.rideId);
    if (!ride) throw new Error("Ride request not found");
    if (ride.driverId !== args.driverId) {
      throw new Error("Only the assigned driver can check in at pickup");
    }

    if (ride.status !== "accepted" && ride.status !== "driver_arriving") {
      if (ride.status === "arrived") {
        return { success: true, alreadyArrived: true };
      }
      throw new Error(`Cannot check in driver in status: ${ride.status}`);
    }

    const now = Date.now();
    await ctx.db.patch(args.rideId, {
      status: "arrived",
      arrivedAt: now,
      updatedAt: now,
    });

    if (args.lat !== undefined && args.lng !== undefined) {
      const geohash = encodeGeohash(args.lat, args.lng, 7);
      await ctx.db.patch(args.driverId, {
        currentLat: args.lat,
        currentLng: args.lng,
        currentGeohash: geohash,
        locationUpdatedAt: now,
        updatedAt: now,
      });
    }

    return {
      success: true,
      status: "arrived",
      arrivedAt: now,
      message: "Driver checked in at pickup location",
    };
  },
});

/**
 * Get the current active ride for a passenger with live driver telemetry.
 */
export const getActiveRideForPassenger = query({
  args: {
    passengerId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const activeRide = await ctx.db
      .query("rideRequests")
      .withIndex("by_passenger", (q) => q.eq("passengerId", args.passengerId))
      .filter((q) =>
        q.and(
          q.neq(q.field("status"), "completed"),
          q.neq(q.field("status"), "cancelled")
        )
      )
      .first();

    if (!activeRide) return null;

    let driver = null;
    if (activeRide.driverId) {
      const driverDoc = await ctx.db.get(activeRide.driverId);
      if (driverDoc) {
        driver = {
          id: driverDoc._id,
          name: driverDoc.name,
          phone: driverDoc.phone,
          avatarUrl: driverDoc.avatarUrl,
          currentLat: driverDoc.currentLat,
          currentLng: driverDoc.currentLng,
          locationUpdatedAt: driverDoc.locationUpdatedAt,
        };
      }
    }

    return {
      ...activeRide,
      driver,
    };
  },
});

/**
 * Update a driver's live location. Called frequently from the mobile app.
 * Uses geohash encoding for efficient proximity index updates.
 */
export const updateDriverLocation = mutation({
  args: {
    driverId: v.id("users"),
    lat: v.number(),
    lng: v.number(),
  },
  handler: async (ctx, args) => {
    if (!isValidLatitude(args.lat) || !isValidLongitude(args.lng)) {
      throw new Error("Invalid coordinates");
    }

    const driver = await ctx.db.get(args.driverId);
    if (!driver) throw new Error("Driver not found");
    if (driver.role !== "driver") throw new Error("Not a driver account");

    const geohash = encodeGeohash(args.lat, args.lng, 7);
    const now = Date.now();

    await ctx.db.patch(args.driverId, {
      currentLat: args.lat,
      currentLng: args.lng,
      currentGeohash: geohash,
      locationUpdatedAt: now,
      updatedAt: now,
    });

    return { success: true, geohash };
  },
});

/**
 * Get a single ride's full details including driver and vehicle info.
 */
export const getRide = query({
  args: {
    rideId: v.id("rideRequests"),
  },
  handler: async (ctx, args) => {
    const ride = await ctx.db.get(args.rideId);
    if (!ride) return null;

    const [passenger, driver, vehicle] = await Promise.all([
      ctx.db.get(ride.passengerId),
      ride.driverId ? ctx.db.get(ride.driverId) : null,
      ride.vehicleId ? ctx.db.get(ride.vehicleId) : null,
    ]);

    return {
      ...ride,
      passenger: passenger
        ? { name: passenger.name, phone: passenger.phone }
        : null,
      driver: driver
        ? {
            name: driver.name,
            phone: driver.phone,
            currentLat: driver.currentLat,
            currentLng: driver.currentLng,
          }
        : null,
      vehicle: vehicle
        ? {
            make: vehicle.make,
            model: vehicle.model,
            color: vehicle.color,
            licensePlate: vehicle.licensePlate,
          }
        : null,
    };
  },
});

/**
 * Get a passenger's ride history.
 */
export const getPassengerRideHistory = query({
  args: {
    passengerId: v.id("users"),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 20;

    const rides = await ctx.db
      .query("rideRequests")
      .withIndex("by_passenger", (q) => q.eq("passengerId", args.passengerId))
      .order("desc")
      .take(limit);

    return rides;
  },
});

/**
 * Passenger or driver cancels a ride request.
 * Transitions ride to "cancelled", releases vehicle if locked, and frees driver if assigned.
 */
export const cancelRide = mutation({
  args: {
    rideId: v.string(),
    reason: v.optional(v.string()),
    userId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    let rideConvexId = ctx.db.normalizeId("rideRequests", args.rideId);
    let ride = rideConvexId ? await ctx.db.get(rideConvexId) : null;

    if (!ride) {
      // Fallback check trips_deliveries table
      const tripConvexId = ctx.db.normalizeId("trips_deliveries", args.rideId);
      if (tripConvexId) {
        const trip = await ctx.db.get(tripConvexId);
        if (trip) {
          const now = Date.now();
          await ctx.db.patch(tripConvexId, {
            status: "cancelled",
            updatedAt: now,
          });
          if (trip.driverId) {
            const driverProfile = await ctx.db.get(trip.driverId);
            if (driverProfile) {
              await ctx.db.patch(trip.driverId, {
                isAvailable: true,
                updatedAt: now,
              });
            }
          }
          return { success: true, cancelledAt: now };
        }
      }
      throw new Error("Ride not found");
    }

    if (ride.status === "completed") {
      throw new Error("Cannot cancel an already completed ride");
    }

    const now = Date.now();
    await ctx.db.patch(ride._id, {
      status: "cancelled",
      cancelledAt: now,
      cancelReason: args.reason ?? "Cancelled by user",
      updatedAt: now,
    });

    if (ride.vehicleId) {
      await ctx.db.patch(ride.vehicleId, {
        availabilityStatus: "available",
        updatedAt: now,
      });
    }

    return { success: true, cancelledAt: now };
  },
});
