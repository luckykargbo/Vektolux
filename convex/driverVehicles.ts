// convex/driverVehicles.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Vehicle Registration & Private Verification Engine
// Handles multi-step vehicle onboarding, private admin document storage,
// automated 3D model tier binding, and verification status gating.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { vehicleCategoryEnum } from "./schema";

// ═══════════════════════════════════════════════════════════════════════
//                   REGISTER / UPDATE DRIVER VEHICLE
// ═══════════════════════════════════════════════════════════════════════

export const registerDriverVehicle = mutation({
  args: {
    driverId: v.string(), // Driver's userId or driverProfileId
    vehicleType: v.string(), // "keke" | "okada" | "car" | "van"
    category: vehicleCategoryEnum,
    make: v.string(),
    model: v.string(),
    year: v.number(),
    color: v.string(),
    licensePlate: v.string(),
    licenseFrontUrl: v.optional(v.string()),
    licenseBackUrl: v.optional(v.string()),
    registrationDocUrl: v.optional(v.string()),
    insuranceDocUrl: v.optional(v.string()),
    inspectionPhotoUrl: v.optional(v.string()), // Private for admin review
  },
  returns: v.object({
    success: v.boolean(),
    vehicleId: v.optional(v.string()),
    verificationStatus: v.string(),
    errorMessage: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    try {
      const formattedPlate = args.licensePlate.toUpperCase().trim();
      const now = Date.now();

      // Check if this driver already has a registered vehicle
      const existingVehicle = await ctx.db
        .query("driver_vehicles")
        .withIndex("by_driver", (q) => q.eq("driverId", args.driverId))
        .first();

      let vehicleId: string;

      if (existingVehicle) {
        // Update existing vehicle registration
        await ctx.db.patch(existingVehicle._id, {
          vehicleType: args.vehicleType,
          category: args.category,
          make: args.make.trim(),
          model: args.model.trim(),
          year: args.year,
          color: args.color.trim(),
          licensePlate: formattedPlate,
          verificationStatus: "pending",
          isVerified: false,
          licenseFrontUrl: args.licenseFrontUrl,
          licenseBackUrl: args.licenseBackUrl,
          registrationDocUrl: args.registrationDocUrl,
          insuranceDocUrl: args.insuranceDocUrl,
          inspectionPhotoUrl: args.inspectionPhotoUrl,
          updatedAt: now,
        });
        vehicleId = existingVehicle._id as string;
      } else {
        // Insert new vehicle registration record
        const insertedId = await ctx.db.insert("driver_vehicles", {
          driverId: args.driverId,
          vehicleType: args.vehicleType,
          category: args.category,
          make: args.make.trim(),
          model: args.model.trim(),
          year: args.year,
          color: args.color.trim(),
          licensePlate: formattedPlate,
          verificationStatus: "pending",
          isVerified: false,
          licenseFrontUrl: args.licenseFrontUrl,
          licenseBackUrl: args.licenseBackUrl,
          registrationDocUrl: args.registrationDocUrl,
          insuranceDocUrl: args.insuranceDocUrl,
          inspectionPhotoUrl: args.inspectionPhotoUrl,
          updatedAt: now,
        });
        vehicleId = insertedId as string;
      }

      // Ensure any associated driver profile remains offline while verification is pending
      const normalizedDriverProfileId = ctx.db.normalizeId("driver_profiles", args.driverId);
      if (normalizedDriverProfileId) {
        await ctx.db.patch(normalizedDriverProfileId, {
          isOnline: false,
          isAvailable: false,
          updatedAt: now,
        });
      }

      return {
        success: true,
        vehicleId,
        verificationStatus: "pending",
      };
    } catch (e) {
      return {
        success: false,
        verificationStatus: "pending",
        errorMessage: (e as Error).message ?? "Failed to register driver vehicle",
      };
    }
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                       GET DRIVER VEHICLE
// ═══════════════════════════════════════════════════════════════════════

export const getDriverVehicle = query({
  args: {
    driverId: v.string(),
  },
  returns: v.union(
    v.null(),
    v.object({
      id: v.string(),
      driverId: v.string(),
      vehicleType: v.optional(v.string()),
      category: v.string(),
      make: v.string(),
      model: v.string(),
      year: v.number(),
      color: v.string(),
      licensePlate: v.string(),
      verificationStatus: v.string(),
      isVerified: v.boolean(),
      licenseFrontUrl: v.optional(v.string()),
      licenseBackUrl: v.optional(v.string()),
      registrationDocUrl: v.optional(v.string()),
      insuranceDocUrl: v.optional(v.string()),
      inspectionPhotoUrl: v.optional(v.string()),
      rejectionReason: v.optional(v.string()),
      approvedAt: v.optional(v.number()),
      updatedAt: v.number(),
    })
  ),
  handler: async (ctx, args) => {
    // Look up by driverId directly
    const vehicle = await ctx.db
      .query("driver_vehicles")
      .withIndex("by_driver", (q) => q.eq("driverId", args.driverId))
      .first();

    if (!vehicle) return null;

    return {
      id: vehicle._id as string,
      driverId: vehicle.driverId,
      vehicleType: vehicle.vehicleType,
      category: vehicle.category,
      make: vehicle.make,
      model: vehicle.model,
      year: vehicle.year,
      color: vehicle.color,
      licensePlate: vehicle.licensePlate,
      verificationStatus: vehicle.verificationStatus,
      isVerified: vehicle.isVerified,
      licenseFrontUrl: vehicle.licenseFrontUrl,
      licenseBackUrl: vehicle.licenseBackUrl,
      registrationDocUrl: vehicle.registrationDocUrl,
      insuranceDocUrl: vehicle.insuranceDocUrl,
      inspectionPhotoUrl: vehicle.inspectionPhotoUrl,
      rejectionReason: vehicle.rejectionReason,
      approvedAt: vehicle.approvedAt,
      updatedAt: vehicle.updatedAt,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 ADMIN / DEMO APPROVE VEHICLE
// ═══════════════════════════════════════════════════════════════════════

export const mockApproveDriverVehicle = mutation({
  args: {
    vehicleId: v.string(),
    status: v.union(v.literal("approved"), v.literal("rejected"), v.literal("pending")),
    rejectionReason: v.optional(v.string()),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const vId = ctx.db.normalizeId("driver_vehicles", args.vehicleId);
    if (!vId) return false;

    const isApproved = args.status === "approved";
    const now = Date.now();

    await ctx.db.patch(vId, {
      verificationStatus: args.status,
      isVerified: isApproved,
      rejectionReason: args.status === "rejected" ? (args.rejectionReason ?? "Document unreadable") : undefined,
      approvedAt: isApproved ? now : undefined,
      updatedAt: now,
    });

    return true;
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 CHECK CAN DRIVER GO ONLINE
// ═══════════════════════════════════════════════════════════════════════

export const checkDriverCanGoOnline = query({
  args: {
    driverId: v.string(),
  },
  returns: v.object({
    canGoOnline: v.boolean(),
    verificationStatus: v.string(),
    reason: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    const vehicle = await ctx.db
      .query("driver_vehicles")
      .withIndex("by_driver", (q) => q.eq("driverId", args.driverId))
      .first();

    if (!vehicle) {
      return {
        canGoOnline: false,
        verificationStatus: "unregistered",
        reason: "Please register your vehicle before going online.",
      };
    }

    if (vehicle.verificationStatus !== "approved") {
      return {
        canGoOnline: false,
        verificationStatus: vehicle.verificationStatus,
        reason: vehicle.verificationStatus === "rejected"
          ? `Vehicle registration rejected: ${vehicle.rejectionReason ?? "Please re-upload valid documents"}`
          : "Vehicle documents are currently under admin review. You can go online once approved.",
      };
    }

    return {
      canGoOnline: true,
      verificationStatus: "approved",
    };
  },
});
