// convex/rides.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Rides (Deprecated Passenger Ride-Hailing System)
// All commercial vehicle logistics and fleet bookings are handled in convex/mobility.ts
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const findNearbyDrivers = query({
  args: {
    lat: v.optional(v.number()),
    lng: v.optional(v.number()),
    radiusKm: v.optional(v.number()),
    tier: v.optional(v.string()),
    serviceFilter: v.optional(v.string()),
  },
  handler: async () => [],
});

export const estimateRideFare = query({
  args: {
    pickupLat: v.optional(v.number()),
    pickupLng: v.optional(v.number()),
    dropoffLat: v.optional(v.number()),
    dropoffLng: v.optional(v.number()),
    vehicleTier: v.optional(v.string()),
  },
  handler: async () => null,
});

export const requestRide = mutation({
  args: {
    passengerId: v.optional(v.string()),
    pickupLat: v.optional(v.number()),
    pickupLng: v.optional(v.number()),
    pickupAddress: v.optional(v.string()),
    dropoffLat: v.optional(v.number()),
    dropoffLng: v.optional(v.number()),
    dropoffAddress: v.optional(v.string()),
    vehicleTier: v.optional(v.string()),
    fareAmount: v.optional(v.number()),
  },
  handler: async () => "deprecated_ride_system",
});

export const cancelRide = mutation({
  args: {
    rideId: v.optional(v.string()),
    reason: v.optional(v.string()),
  },
  handler: async () => true,
});

export const getPassengerRideHistory = query({
  args: { passengerId: v.optional(v.string()) },
  handler: async () => [],
});

export const checkInDriverArrival = mutation({
  args: {
    rideId: v.optional(v.string()),
    driverId: v.optional(v.string()),
  },
  handler: async () => true,
});
