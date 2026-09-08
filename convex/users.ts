// convex/users.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — User Profile Queries & Mutations
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

// ═══════════════════════════════════════════════════════════════════════
//                        GET USER BY ID
// ═══════════════════════════════════════════════════════════════════════

export const getUserById = query({
  args: {
    userId: v.string(),
  },
  returns: v.union(
    v.object({
      id: v.string(),
      name: v.string(),
      email: v.string(),
      phone: v.string(),
      role: v.string(),
      isVerified: v.boolean(),
      isActive: v.boolean(),
      avatarUrl: v.optional(v.string()),
      walletAddress: v.optional(v.string()),
      createdAt: v.number(),
      activeRole: v.optional(v.string()),
      isVerifiedDriver: v.optional(v.boolean()),
      isVerifiedAgent: v.optional(v.boolean()),
      isVerifiedMerchant: v.optional(v.boolean()),
    }),
    v.null()
  ),
  handler: async (ctx, args) => {
    try {
      const userId = ctx.db.normalizeId("users", args.userId);
      if (!userId) return null;
      
      const user = await ctx.db.get(userId);
      if (!user) return null;

      return {
        id: user._id as string,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role,
        isVerified: user.isVerified,
        isActive: user.isActive,
        avatarUrl: user.avatarUrl,
        walletAddress: user.walletAddress,
        createdAt: user._creationTime,
        activeRole: user.activeRole ?? (user.role === "driver" || user.role === "agent" || user.role === "merchant" ? user.role : "client"),
        isVerifiedDriver: user.isVerifiedDriver ?? (user.role === "driver"),
        isVerifiedAgent: user.isVerifiedAgent ?? (user.role === "agent"),
        isVerifiedMerchant: user.isVerifiedMerchant ?? (user.role === "merchant"),
      };
    } catch {
      return null;
    }
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                      GET USER BY EMAIL
// ═══════════════════════════════════════════════════════════════════════

export const getUserByEmail = query({
  args: {
    email: v.string(),
  },
  returns: v.union(
    v.object({
      id: v.string(),
      name: v.string(),
      email: v.string(),
      phone: v.string(),
      role: v.string(),
      isVerified: v.boolean(),
    }),
    v.null()
  ),
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", args.email))
      .first();

    if (!user) return null;

    return {
      id: user._id as string,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
      isVerified: user.isVerified,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    UPDATE USER PROFILE
// ═══════════════════════════════════════════════════════════════════════

export const updateUserProfile = mutation({
  args: {
    userId: v.string(),
    name: v.optional(v.string()),
    phone: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    try {
      const userId = ctx.db.normalizeId("users", args.userId);
      if (!userId) return false;

      const updates: Record<string, unknown> = { updatedAt: Date.now() };
      if (args.name !== undefined) updates.name = args.name;
      if (args.phone !== undefined) updates.phone = args.phone;
      if (args.avatarUrl !== undefined) updates.avatarUrl = args.avatarUrl;

      await ctx.db.patch(userId, updates);
      return true;
    } catch {
      return false;
    }
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                      SWITCH ACTIVE ROLE
// ═══════════════════════════════════════════════════════════════════════

export const switchActiveRole = mutation({
  args: {
    userId: v.string(),
    targetRole: v.union(
      v.literal("client"),
      v.literal("driver"),
      v.literal("agent"),
      v.literal("merchant")
    ),
  },
  returns: v.object({
    success: v.boolean(),
    activeRole: v.string(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.userId);
    if (!userId) {
      return { success: false, activeRole: "client", message: "User not found" };
    }
    const user = await ctx.db.get(userId);
    if (!user) {
      return { success: false, activeRole: "client", message: "User not found" };
    }

    // Role eligibility check
    if (args.targetRole === "driver" && !user.isVerifiedDriver && user.role !== "driver") {
      return { success: false, activeRole: user.activeRole ?? "client", message: "Driver verification required" };
    }
    if (args.targetRole === "agent" && !user.isVerifiedAgent && user.role !== "agent") {
      return { success: false, activeRole: user.activeRole ?? "client", message: "Agent verification required" };
    }
    if (args.targetRole === "merchant" && !user.isVerifiedMerchant && user.role !== "merchant") {
      return { success: false, activeRole: user.activeRole ?? "client", message: "Merchant verification required" };
    }

    await ctx.db.patch(userId, {
      activeRole: args.targetRole,
      updatedAt: Date.now(),
    });

    return {
      success: true,
      activeRole: args.targetRole,
      message: `Switched to ${args.targetRole} mode`,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     APPLY FOR ROLE UPGRADE
// ═══════════════════════════════════════════════════════════════════════

export const applyRoleUpgrade = mutation({
  args: {
    userId: v.string(),
    targetRole: v.union(v.literal("driver"), v.literal("agent"), v.literal("merchant")),
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
    licenseNumber: v.optional(v.string()),
    documentUrls: v.optional(v.array(v.string())),
  },
  returns: v.object({
    success: v.boolean(),
    applicationId: v.optional(v.string()),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.userId);
    if (!userId) {
      return { success: false, message: "User not found" };
    }
    const now = Date.now();
    const appId = await ctx.db.insert("role_applications", {
      userId,
      targetRole: args.targetRole,
      businessName: args.businessName,
      tinNumber: args.tinNumber,
      licenseNumber: args.licenseNumber,
      documentUrls: args.documentUrls ?? [],
      status: "pending",
      updatedAt: now,
    });

    return {
      success: true,
      applicationId: appId as string,
      message: `Application submitted for ${args.targetRole} verification`,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 MOCK APPROVE ROLE UPGRADE (DEMO)
// ═══════════════════════════════════════════════════════════════════════

export const mockApproveRoleUpgrade = mutation({
  args: {
    userId: v.string(),
    targetRole: v.union(v.literal("driver"), v.literal("agent"), v.literal("merchant")),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.userId);
    if (!userId) return false;

    const updates: Record<string, unknown> = {
      updatedAt: Date.now(),
      activeRole: args.targetRole,
    };

    if (args.targetRole === "driver") {
      updates.isVerifiedDriver = true;
      updates.role = "driver";
    } else if (args.targetRole === "agent") {
      updates.isVerifiedAgent = true;
      updates.role = "agent";
    } else if (args.targetRole === "merchant") {
      updates.isVerifiedMerchant = true;
      updates.role = "merchant";
    }

    await ctx.db.patch(userId, updates);

    // Also update any pending role application
    const app = await ctx.db
      .query("role_applications")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .filter((q) => q.eq(q.field("targetRole"), args.targetRole))
      .first();

    if (app) {
      await ctx.db.patch(app._id, {
        status: "approved",
        reviewedAt: Date.now(),
        updatedAt: Date.now(),
      });
    }

    return true;
  },
});
