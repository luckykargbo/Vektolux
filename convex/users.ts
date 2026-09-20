// convex/users.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — User Profile Queries & Mutations
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { userRole } from "./schema";

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
      bio: v.optional(v.string()),
      kycStatus: v.optional(v.string()),
      walletAddress: v.optional(v.string()),
      createdAt: v.number(),
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
        bio: user.bio,
        kycStatus: user.kycStatus,
        walletAddress: user.walletAddress,
        createdAt: user._creationTime,
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
      bio: v.optional(v.string()),
      kycStatus: v.optional(v.string()),
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
      bio: user.bio,
      kycStatus: user.kycStatus,
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
    bio: v.optional(v.string()),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    let userDoc = null;
    const normalized = ctx.db.normalizeId("users", args.userId);
    if (normalized) {
      userDoc = await ctx.db.get(normalized);
    }
    if (!userDoc) {
      userDoc = await ctx.db
        .query("users")
        .withIndex("by_sessionToken", (q) => q.eq("sessionToken", args.userId))
        .first();
    }
    if (!userDoc) {
      userDoc = await ctx.db
        .query("users")
        .withIndex("by_email", (q) => q.eq("email", args.userId))
        .first();
    }
    if (!userDoc) {
      userDoc = await ctx.db
        .query("users")
        .withIndex("by_phone", (q) => q.eq("phone", args.userId))
        .first();
    }
    if (!userDoc) {
      throw new Error(`User not found with identifier: ${args.userId}`);
    }

    const updates: Record<string, unknown> = { updatedAt: Date.now() };
    if (args.name !== undefined) updates.name = args.name;
    if (args.phone !== undefined) updates.phone = args.phone;
    if (args.avatarUrl !== undefined) updates.avatarUrl = args.avatarUrl;
    if (args.bio !== undefined) updates.bio = args.bio;

    await ctx.db.patch(userDoc._id, updates);
    return true;
  },
});

export const updateAvatar = mutation({
  args: {
    userId: v.string(),
    avatarUrl: v.string(),
  },
  returns: v.object({
    success: v.boolean(),
    userId: v.string(),
    avatarUrl: v.string(),
  }),
  handler: async (ctx, args) => {
    let userDoc = null;
    const normalized = ctx.db.normalizeId("users", args.userId);
    if (normalized) {
      userDoc = await ctx.db.get(normalized);
    }
    if (!userDoc) {
      userDoc = await ctx.db
        .query("users")
        .withIndex("by_sessionToken", (q) => q.eq("sessionToken", args.userId))
        .first();
    }
    if (!userDoc) {
      userDoc = await ctx.db
        .query("users")
        .withIndex("by_email", (q) => q.eq("email", args.userId))
        .first();
    }
    if (!userDoc) {
      userDoc = await ctx.db
        .query("users")
        .withIndex("by_phone", (q) => q.eq("phone", args.userId))
        .first();
    }
    if (!userDoc) {
      throw new Error(`User not found with identifier: ${args.userId}`);
    }

    await ctx.db.patch(userDoc._id, {
      avatarUrl: args.avatarUrl,
      updatedAt: Date.now(),
    });

    return {
      success: true,
      userId: userDoc._id as string,
      avatarUrl: args.avatarUrl,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    CREATE OR SYNC USER DIRECTLY
// ═══════════════════════════════════════════════════════════════════════

export const syncUser = mutation({
  args: {
    userId: v.optional(v.string()),
    name: v.string(),
    email: v.string(),
    phone: v.string(),
    role: v.optional(userRole),
    bio: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    kycStatus: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    userId: v.string(),
    name: v.string(),
    email: v.string(),
    phone: v.string(),
    role: v.string(),
    kycStatus: v.string(),
    bio: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    let existingUser = null;
    if (args.userId) {
      const normalized = ctx.db.normalizeId("users", args.userId);
      if (normalized) {
        existingUser = await ctx.db.get(normalized);
      }
    }
    if (!existingUser && args.email) {
      existingUser = await ctx.db
        .query("users")
        .withIndex("by_email", (q) => q.eq("email", args.email))
        .first();
    }
    if (!existingUser && args.phone) {
      existingUser = await ctx.db
        .query("users")
        .withIndex("by_phone", (q) => q.eq("phone", args.phone))
        .first();
    }

    const now = Date.now();
    const effectiveRole = args.role ?? (existingUser ? existingUser.role : "client");
    const effectiveKyc = args.kycStatus ?? (existingUser?.kycStatus ?? "PENDING_VERIFICATION");

    if (existingUser) {
      const updates: Record<string, unknown> = {
        name: args.name,
        phone: args.phone,
        updatedAt: now,
      };
      if (args.role) updates.role = args.role;
      if (args.bio !== undefined) updates.bio = args.bio;
      if (args.avatarUrl !== undefined) updates.avatarUrl = args.avatarUrl;
      if (args.kycStatus !== undefined) updates.kycStatus = args.kycStatus;
      if (args.sessionToken !== undefined) updates.sessionToken = args.sessionToken;

      await ctx.db.patch(existingUser._id, updates);
      return {
        success: true,
        userId: existingUser._id as string,
        name: args.name,
        email: existingUser.email,
        phone: args.phone,
        role: (updates.role as string) ?? existingUser.role,
        kycStatus: (updates.kycStatus as string) ?? existingUser.kycStatus ?? "PENDING_VERIFICATION",
        bio: (updates.bio as string) ?? existingUser.bio,
        avatarUrl: (updates.avatarUrl as string) ?? existingUser.avatarUrl,
        sessionToken: (updates.sessionToken as string) ?? existingUser.sessionToken,
      };
    } else {
      const insertedId = await ctx.db.insert("users", {
        name: args.name,
        email: args.email,
        phone: args.phone,
        role: effectiveRole,
        bio: args.bio,
        avatarUrl: args.avatarUrl,
        kycStatus: effectiveKyc as any,
        isActive: true,
        isVerified: false,
        verificationStatus: "pending",
        sessionToken: args.sessionToken,
        updatedAt: now,
      });

      await ctx.db.insert("walletBalances", {
        userId: insertedId,
        availableBalance: 0,
        pendingBalance: 0,
        currency: "SLE",
        updatedAt: now,
      });

      return {
        success: true,
        userId: insertedId as string,
        name: args.name,
        email: args.email,
        phone: args.phone,
        role: effectiveRole,
        kycStatus: effectiveKyc,
        bio: args.bio,
        avatarUrl: args.avatarUrl,
        sessionToken: args.sessionToken,
      };
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
//                 SWITCH USER MODE (DRIVER VS PASSENGER)
// ═══════════════════════════════════════════════════════════════════════

export const switchUserMode = mutation({
  args: {
    userId: v.string(),
    targetMode: v.union(v.literal("passenger"), v.literal("driver")),
  },
  returns: v.object({
    success: v.boolean(),
    activeMode: v.string(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.userId);
    if (!userId) {
      return { success: false, activeMode: "passenger", message: "User not found" };
    }
    const user = await ctx.db.get(userId);
    if (!user) {
      return { success: false, activeMode: "passenger", message: "User not found" };
    }

    const isDriverVerified = Boolean(
      user.is_driver_verified ?? user.isVerifiedDriver ?? (user.role === "driver")
    );

    if (args.targetMode === "driver" && !isDriverVerified) {
      return {
        success: false,
        activeMode: user.active_mode ?? "passenger",
        message: "Driver verification required. Complete registration and vehicle approval.",
      };
    }

    const activeRole = args.targetMode === "driver" ? "driver" : "client";
    const driverStatus = args.targetMode === "driver" ? (user.driver_status ?? "online") : "offline";

    await ctx.db.patch(userId, {
      active_mode: args.targetMode,
      activeRole,
      driver_status: driverStatus,
      updatedAt: Date.now(),
    });

    return {
      success: true,
      activeMode: args.targetMode,
      message: `Switched to ${args.targetMode === "driver" ? "Driver Workspace" : "Passenger Mode"}`,
    };
  },
});

export const getUserMode = query({
  args: {
    userId: v.string(),
  },
  returns: v.union(
    v.object({
      userId: v.string(),
      activeMode: v.string(),
      isDriverVerified: v.boolean(),
      driverStatus: v.string(),
    }),
    v.null()
  ),
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.userId);
    if (!userId) return null;
    const user = await ctx.db.get(userId);
    if (!user) return null;

    const isDriverVerified = Boolean(
      user.is_driver_verified ?? user.isVerifiedDriver ?? (user.role === "driver")
    );
    return {
      userId: user._id as string,
      activeMode: user.active_mode ?? (user.activeRole === "driver" ? "driver" : "passenger"),
      isDriverVerified,
      driverStatus: user.driver_status ?? "offline",
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

// ═══════════════════════════════════════════════════════════════════════
//                     SOCIAL / PUBLIC PROFILE
// ═══════════════════════════════════════════════════════════════════════

export const getUserProfile = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) return null;

    return {
      _id: user._id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      avatarUrl: user.avatarUrl,
      bio: user.bio,
      role: user.role,
      verificationBadge: user.verificationBadge,
      followersCount: user.followersCount || 0,
      followingCount: user.followingCount || 0,
      isVerified: user.isVerified,
      kycStatus: user.kycStatus,
    };
  },
});

export const getUserPosts = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const realEstate = await ctx.db
      .query("realEstateListings")
      .withIndex("by_owner", (q) => q.eq("ownerId", args.userId))
      .order("desc")
      .take(50);

    const vehicles = await ctx.db
      .query("vehicleListings")
      .withIndex("by_owner", (q) => q.eq("ownerId", args.userId))
      .order("desc")
      .take(50);

    const combined = [
      ...realEstate.map((r) => ({ ...r, type: "property" })),
      ...vehicles.map((v) => ({ ...v, type: "vehicle" })),
    ];

    combined.sort((a, b) => b._creationTime - a._creationTime);
    return combined;
  },
});

export const updateBio = mutation({
  args: { 
    userId: v.id("users"), 
    sessionToken: v.optional(v.string()), 
    bio: v.string() 
  },
  handler: async (ctx, args) => {
    if (!args.sessionToken) throw new Error("Unauthorized");
    const user = await ctx.db.get(args.userId);
    if (!user || user.sessionToken !== args.sessionToken) {
      throw new Error("Unauthorized");
    }

    await ctx.db.patch(args.userId, { bio: args.bio, updatedAt: Date.now() });
    return { success: true };
  },
});

/**
 * Dynamic Wallet & Profile endpoint
 * Returns user identity, KYC badge, live wallet balance, active deal count, and QR payload.
 */
export const getWalletProfile = query({
  args: { userId: v.string() },
  handler: async (ctx, args) => {
    let user = null;
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (userNorm) {
      user = await ctx.db.get(userNorm);
    }
    if (!user) {
      user = await ctx.db
        .query("users")
        .withIndex("by_sessionToken", (q) => q.eq("sessionToken", args.userId))
        .first();
    }
    if (!user) {
      user = await ctx.db
        .query("users")
        .withIndex("by_email", (q) => q.eq("email", args.userId))
        .first();
    }
    if (!user) {
      user = await ctx.db
        .query("users")
        .withIndex("by_phone", (q) => q.eq("phone", args.userId))
        .first();
    }
    if (!user) return null;

    // Fetch live wallet balance
    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .first();

    // Fetch active escrow orders
    const buyerOrders = await ctx.db
      .query("escrow_orders")
      .withIndex("by_renter_or_buyer", (q) => q.eq("renterOrBuyerId", user._id))
      .collect();
    const sellerOrders = await ctx.db
      .query("escrow_orders")
      .withIndex("by_owner_or_seller", (q) => q.eq("ownerOrSellerId", user._id))
      .collect();

    const orderMap = new Map();
    for (const o of [...buyerOrders, ...sellerOrders]) {
      orderMap.set(o._id, o);
    }
    const allOrders = Array.from(orderMap.values());
    const activeDeals = allOrders.filter(
      (o) =>
        o.status === "HELD_IN_ESCROW" ||
        o.status === "PARTIALLY_RELEASED" ||
        o.status === "POST_INSPECTION_PENDING" ||
        o.status === "PENDING_PAYMENT"
    ).length;

    const qrPayload = `vektolux://pay?userId=${user._id}&phone=${encodeURIComponent(user.phone)}&name=${encodeURIComponent(user.name)}`;

    const isVerifiedCitizen =
      user.isVerified ||
      user.verificationStatus === "VERIFIED" ||
      user.verificationStatus === "verified" ||
      user.verificationStatus === "approved";

    return {
      userId: user._id as string,
      fullName: user.name,
      phone: user.phone,
      email: user.email,
      role: user.role,
      avatarUrl: user.avatarUrl ?? null,
      verificationStatus: user.verificationStatus ?? (isVerifiedCitizen ? "VERIFIED" : "UNVERIFIED"),
      verificationBadge: user.verificationBadge ?? (isVerifiedCitizen ? "VERIFIED CITIZEN ID • ESCROW ENABLED" : "UNVERIFIED"),
      walletBalance: wallet?.availableBalance ?? 0.0,
      lockedEscrowBalance: wallet?.escrowBalance ?? 0.0,
      currency: "SLE",
      activeEscrowDeals: activeDeals,
      qrPayload,
    };
  },
});

