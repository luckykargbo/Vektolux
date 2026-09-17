// convex/driverVehicles.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Vehicle Registration (Deprecated Passenger System)
// Replaced by Commercial Vehicle Listings in convex/mobility.ts
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const registerDriverVehicle = mutation({
  args: {
    driverId: v.string(),
    vehicleType: v.optional(v.string()),
    category: v.optional(v.string()),
    make: v.optional(v.string()),
    model: v.optional(v.string()),
    year: v.optional(v.number()),
    color: v.optional(v.string()),
    licensePlate: v.optional(v.string()),
    licenseFrontUrl: v.optional(v.string()),
    licenseBackUrl: v.optional(v.string()),
    registrationDocUrl: v.optional(v.string()),
    insuranceDocUrl: v.optional(v.string()),
    inspectionPhotoUrl: v.optional(v.string()),
  },
  handler: async () => {
    return {
      success: true,
      vehicleId: "commercial_migrated",
      verificationStatus: "approved",
    };
  },
});

export const getDriverVehicle = query({
  args: { driverId: v.string() },
  handler: async () => {
    return null;
  },
});

export const mockApproveDriverVehicle = mutation({
  args: {
    vehicleId: v.optional(v.string()),
    driverId: v.optional(v.string()),
    status: v.optional(v.string()),
    approve: v.optional(v.boolean()),
    rejectionReason: v.optional(v.string()),
  },
  handler: async () => {
    return true;
  },
});
