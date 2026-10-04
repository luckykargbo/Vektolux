// convex/users.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — User Profile Queries & Mutations
// ═══════════════════════════════════════════════════════════════════════

import { action, mutation, query, internalMutation, internalQuery } from "./_generated/server";
import { internal } from "./_generated/api";
import { verifyAppleIdToken, verifyGoogleIdToken } from "./lib/oauth";
import { issueSession } from "./lib/session";
import { v } from "convex/values";
import { userRole } from "./schema";
import { verifyPassword } from "./auth";
import { hasCarDealerCapability, isRoleApproved, professionalBadge, professionalTitle, roleForApplication } from "./lib/permissions";
import { requireAuthenticatedUser, requireAdmin, requireSelf, resolveOptionalUser } from "./lib/auth";
import { isListingPublic, toPublicProperty, toPublicVehicle } from "./lib/publicListing";

// ═══════════════════════════════════════════════════════════════════════
//                        GET USER BY ID
// ═══════════════════════════════════════════════════════════════════════

/**
 * Helper to determine if a user has verified seller / dealership status.
 * Standard clients/buyers must NOT receive seller status unless approved.
 */
export function isUserVerifiedSeller(user: {
  role?: string;
  isVerifiedSeller?: boolean;
  isVerifiedAgent?: boolean;
  isVerifiedMerchant?: boolean;
  isVerified?: boolean;
  verificationStatus?: string;
  verificationBadge?: string;
}): boolean {
  if (user.isVerifiedSeller === true) return true;
  if (user.isVerifiedAgent === true) return true;
  if (user.isVerifiedMerchant === true) return true;

  const isApproved =
    user.isVerified === true ||
    user.verificationStatus === "VERIFIED" ||
    user.verificationStatus === "verified" ||
    user.verificationStatus === "approved";

  const sellerRoles = [
    "seller",
    "merchant",
    "agent",
    "dealer",
    "Vehicle Merchant",
    "Real Estate Agent",
    "admin",
  ];
  if (isApproved && user.role && sellerRoles.includes(user.role)) {
    return true;
  }
  return false;
}

export const getUserById = query({
  args: {
    userId: v.string(),
    sessionToken: v.optional(v.string()),
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
      isVerifiedSeller: v.optional(v.boolean()),
      avatarUrl: v.optional(v.string()),
      bio: v.optional(v.string()),
      address: v.optional(v.string()),
      region: v.optional(v.string()),
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
      // Private contact / KYC / wallet fields are returned ONLY to the account owner.
      const viewer = await resolveOptionalUser(ctx, { sessionToken: args.sessionToken });
      const isSelf = viewer?.userId === user._id;

      return {
        id: user._id as string,
        name: user.name,
        email: isSelf ? user.email : "",
        phone: isSelf ? user.phone : "",
        role: user.role,
        isVerified: user.isVerified,
        isActive: user.isActive,
        isVerifiedSeller: isUserVerifiedSeller(user),
        avatarUrl: user.avatarUrl,
        bio: user.bio,
        address: isSelf ? user.address : undefined,
        region: user.region,
        kycStatus: isSelf ? user.kycStatus : undefined,
        walletAddress: isSelf ? user.walletAddress : undefined,
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

// INTERNAL ONLY: email -> account lookup must not be public (user enumeration).
export const getUserByEmail = internalQuery({
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
    sessionToken: v.optional(v.string()),
    userId: v.string(),
    name: v.optional(v.string()),
    phone: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    bio: v.optional(v.string()),
    address: v.optional(v.string()),
    region: v.optional(v.string()),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    // Only the account owner (valid session) may act on this account.
    await requireSelf(ctx, args.sessionToken, String(args.userId));
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
    if (args.address !== undefined) updates.address = args.address;
    if (args.region !== undefined) updates.region = args.region;

    await ctx.db.patch(userDoc._id, updates);
    return true;
  },
});

export const updateAvatar = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    userId: v.string(),
    avatarUrl: v.string(),
  },
  returns: v.object({
    success: v.boolean(),
    userId: v.string(),
    avatarUrl: v.string(),
  }),
  handler: async (ctx, args) => {
    // Only the account owner (valid session) may act on this account.
    await requireSelf(ctx, args.sessionToken, String(args.userId));
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

// INTERNAL ONLY: it overwrote role / KYC status / session token for any account (privilege
// escalation + account takeover). Not used by the app.
export const syncUser = internalMutation({
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
    sessionToken: v.optional(v.string()),
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
    // Only the account owner (valid session) may act on this account.
    await requireSelf(ctx, args.sessionToken, String(args.userId));
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



// ═══════════════════════════════════════════════════════════════════════
//                     APPLY FOR ROLE UPGRADE
// ═══════════════════════════════════════════════════════════════════════

export const applyRoleUpgrade = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    userId: v.string(),
    // "driver" is no longer offered (ride system removed); "merchant" is the legacy dealer label.
    targetRole: v.union(
      v.literal("agent"),
      v.literal("property_owner"),
      v.literal("dealer"),
      v.literal("merchant"),
      v.literal("hotel_operator")
    ),
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
    licenseNumber: v.optional(v.string()),
    documentUrls: v.optional(v.array(v.string())),
  },
  returns: v.object({
    success: v.boolean(),
    applicationId: v.optional(v.string()),
    errorCode: v.optional(v.string()),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    // Only the account owner (valid session) may act on this account.
    const { userId, user } = await requireSelf(ctx, args.sessionToken, String(args.userId));
    if (user.role === "admin") return { success: false, errorCode: "NOT_ALLOWED", message: "Administrators cannot apply for a business role." };
    const targetRole = args.targetRole === "merchant" ? "dealer" : args.targetRole;
    const docs = (args.documentUrls ?? []).filter((d) => typeof d === "string" && d.length <= 500).slice(0, 10);

    const existing = await ctx.db.query("role_applications").withIndex("by_user", (q) => q.eq("userId", userId)).take(50);
    if (existing.some((a) => a.status === "pending")) {
      return { success: false, errorCode: "APPLICATION_PENDING", message: "You already have an application under review." };
    }
    if (roleForApplication(targetRole) === user.role && isRoleApproved(user)) {
      return { success: false, errorCode: "ALREADY_GRANTED", message: "Your account already has this role." };
    }
    // Car Dealer held as an add-on to the Real Estate Agent role counts as granted too.
    if (targetRole === "dealer" && hasCarDealerCapability(user)) {
      return { success: false, errorCode: "ALREADY_GRANTED", message: "Your account is already an approved Car Dealer." };
    }
    const now = Date.now();
    const appId = await ctx.db.insert("role_applications", {
      userId,
      targetRole,
      businessName: args.businessName?.trim().slice(0, 200),
      tinNumber: args.tinNumber?.trim().slice(0, 50),
      licenseNumber: args.licenseNumber?.trim().slice(0, 50),
      documentUrls: docs,
      status: "pending",
      updatedAt: now,
    });

    return {
      success: true,
      applicationId: appId as string,
      message: "Application submitted. An administrator will review it.",
    };
  },
});


// ═══════════════════════════════════════════════════════════════════════
//                     SOCIAL / PUBLIC PROFILE
// ═══════════════════════════════════════════════════════════════════════

export const getUserProfile = query({
  args: { userId: v.id("users"), sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    // Email and phone are private: returned only to the profile owner.
    const viewer = await resolveOptionalUser(ctx, { sessionToken: args.sessionToken });
    const isSelf = !!viewer && String(viewer.userId) === String(args.userId);
    const user = await ctx.db.get(args.userId);
    if (!user) return null;

    const isVerifiedSeller = isUserVerifiedSeller(user);
    const badge = await professionalBadge(ctx, user);

    return {
      _id: user._id,
      name: user.name,
      // Server-derived professional identity, e.g. "Real Estate Agent & Car Dealer".
      professionalTitle: professionalTitle(user),
      verifiedAgent: badge.verifiedAgent,
      email: isSelf ? user.email : undefined,
      phone: isSelf ? user.phone : undefined,
      avatarUrl: user.avatarUrl,
      bio: user.bio,
      role: user.role,
      verificationBadge: user.verificationBadge,
      followersCount: user.followersCount || 0,
      followingCount: user.followingCount || 0,
      isVerified: user.isVerified,
      isVerifiedSeller,
      canPublishListings: isVerifiedSeller || user.role === "admin",
      kycStatus: isSelf ? user.kycStatus : undefined,
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
      // Public profile view: never private phone / street address / coordinates.
      // Public listings only: no drafts, listings under review, rejected, archived or removed ones.
      ...realEstate.filter((r) => isListingPublic(r)).map((r) => ({ ...toPublicProperty(r), type: "property" })),
      ...vehicles
        .filter((v) => v.isDeleted !== true && v.isPublished !== false && v.status !== "TAKEN_DOWN")
        .map((v) => ({ ...toPublicVehicle(v), type: "vehicle" })),
    ];

    combined.sort((a: any, b: any) => b._creationTime - a._creationTime);
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
    await requireSelf(ctx, args.sessionToken, args.userId);
    await ctx.db.patch(args.userId, { bio: args.bio.slice(0, 500), updatedAt: Date.now() });
    return { success: true };
  },
});

/**
 * Dynamic Wallet & Profile endpoint
 * Returns user identity, KYC badge, live wallet balance, active deal count, and QR payload.
 */
export const getWalletProfile = query({
  args: { userId: v.optional(v.string()), sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    // Wallet/escrow summary is private: identity comes from the session only.
    const { user } = await requireSelf(ctx, args.sessionToken, args.userId);

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

    const isVerifiedSeller = isUserVerifiedSeller(user);

    return {
      userId: user._id as string,
      fullName: user.name,
      phone: user.phone,
      email: user.email,
      role: user.role,
      avatarUrl: user.avatarUrl ?? null,
      address: user.address ?? null,
      region: user.region ?? null,
      verificationStatus: user.verificationStatus ?? (isVerifiedCitizen ? "VERIFIED" : "UNVERIFIED"),
      verificationBadge: user.verificationBadge ?? (isVerifiedCitizen ? "VERIFIED CITIZEN ID • ESCROW ENABLED" : "UNVERIFIED"),
      isVerifiedSeller,
      canPublishListings: isVerifiedSeller || user.role === "admin",
      walletBalance: wallet?.availableBalance ?? 0.0,
      lockedEscrowBalance: wallet?.escrowBalance ?? 0.0,
      currency: "SLE",
      activeEscrowDeals: activeDeals,
      qrPayload,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 SELLER & DEALERSHIP VERIFICATION MUTATIONS
// ═══════════════════════════════════════════════════════════════════════

/**
 * Allows a client/buyer to apply for Verified Seller / Dealership status.
 */
export const applyForSellerVerification = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    userId: v.string(),
    sellerType: v.union(
      v.literal("real_estate"),
      v.literal("dealership"),
      v.literal("vendor"),
      v.literal("individual")
    ),
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    // Only the account owner (valid session) may act on this account.
    await requireSelf(ctx, args.sessionToken, String(args.userId));
    let user = null;
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (userNorm) user = await ctx.db.get(userNorm);
    if (!user) {
      user = await ctx.db
        .query("users")
        .withIndex("by_sessionToken", (q) => q.eq("sessionToken", args.userId))
        .first();
    }
    if (!user) return { success: false, message: "User not found" };

    const targetRole = args.sellerType === "real_estate" ? "agent" : "merchant";

    await ctx.db.patch(user._id, {
      sellerType: args.sellerType,
      businessName: args.businessName ?? user.businessName,
      tinNumber: args.tinNumber ?? user.tinNumber,
      updatedAt: Date.now(),
    });

    await ctx.db.insert("role_applications", {
      userId: user._id,
      targetRole,
      businessName: args.businessName,
      tinNumber: args.tinNumber,
      documentUrls: [],
      status: "pending",
      updatedAt: Date.now(),
    });

    return {
      success: true,
      message: "Seller verification application submitted. Our team will review within 24 hours.",
    };
  },
});

/**
 * Admin action: Approve seller/dealer verification.
 */
export const approveSellerVerification = mutation({
  args: {
    userId: v.string(),
    sellerType: v.optional(
      v.union(
        v.literal("real_estate"),
        v.literal("dealership"),
        v.literal("vendor"),
        v.literal("individual")
      )
    ),
    sessionToken: v.optional(v.string()),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    // Enforce admin privileges
    const { userId: adminId } = await requireAdmin(ctx, { sessionToken: args.sessionToken });

    let user = null;
    const userNorm = ctx.db.normalizeId("users", args.userId);
    if (userNorm) user = await ctx.db.get(userNorm);
    if (!user) return false;

    const sType = args.sellerType ?? user.sellerType ?? "vendor";
    const role = sType === "real_estate" ? "agent" : "merchant";

    // Business-role approval only. Identity (KYC) verification is a separate, admin-reviewed
    // status and is NOT granted here.
    await ctx.db.patch(user._id, {
      isVerifiedSeller: true,
      roleApprovedAt: Date.now(),
      roleApprovedBy: adminId,
      role,
      activeRole: role,
      sellerType: sType,
      sellerApprovedAt: Date.now(),
      updatedAt: Date.now(),
    });

    return true;
  },
});

async function generateDeterministicHash(payload: string): Promise<string> {
  const enc = new TextEncoder();
  const data = enc.encode(payload);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Verify Transaction PIN or Account Password for payment authorization.
 */
export const verifyTransactionPin = query({
  args: {
    sessionToken: v.optional(v.string()),
    userId: v.string(),
    pin: v.string(),
  },
  handler: async (ctx, args) => {
    // Only the account owner (valid session) may act on this account.
    await requireSelf(ctx, args.sessionToken, String(args.userId));
    const userId = ctx.db.normalizeId("users", args.userId);
    if (!userId) return { valid: false, message: "Invalid user ID", hasPin: false };

    const user = await ctx.db.get(userId);
    if (!user) return { valid: false, message: "User not found", hasPin: false };

    const pinStr = args.pin.trim();
    if (!pinStr) return { valid: false, message: "PIN / Password cannot be empty", hasPin: Boolean(user.walletPinHash) };

    // 1. Check wallet security PIN
    if (user.walletPinHash) {
      const testPinHash = await generateDeterministicHash(`wallet_pin_${userId}_${pinStr}`);
      if (testPinHash === user.walletPinHash) {
        return { valid: true, hasPin: true };
      }
    }

    // 2. Check account password as authorization fallback
    if (user.passwordHash) {
      const isPasswordValid = await verifyPassword(pinStr, user.passwordHash);
      if (isPasswordValid) {
        return { valid: true, hasPin: Boolean(user.walletPinHash) };
      }
    }

    // 3. Fallback: if user has neither wallet PIN nor password configured yet
    if (!user.walletPinHash && !user.passwordHash) {
      return {
        valid: false,
        message: "No security PIN or password configured. Please set a transaction PIN before performing this action.",
        hasPin: false,
      };
    }

    return {
      valid: false,
      message: user.walletPinHash
        ? "Incorrect 4-digit PIN or account password."
        : "Incorrect account password.",
      hasPin: Boolean(user.walletPinHash),
    };
  },
});

/**
 * Permanently delete and anonymize user account (Apple App Store Guideline 5.1.1(v) & Google Play Compliance).
 */
export const deleteUserAccount = mutation({
  args: {
    userId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    // Authenticate caller — user can only delete own account unless admin
    const auth = await requireAuthenticatedUser(ctx, { sessionToken: args.sessionToken, userId: args.userId });
    const userId = auth.userId;
    const user = auth.user;

    const now = Date.now();
    const randomizedSuffix = Math.random().toString(36).substring(2, 8);

    // Anonymize and erase all PII in accordance with GDPR & App Store Guidelines
    await ctx.db.patch(userId, {
      name: "Deleted User",
      email: `deleted_${now}_${randomizedSuffix}@vektolux.com`,
      phone: `0000000000_${randomizedSuffix}`,
      isActive: false,
      sessionToken: undefined,
      passwordHash: undefined,
      walletPinHash: undefined,
      avatarUrl: undefined,
      bio: undefined,
      address: undefined,
      updatedAt: now,
    });

    return {
      success: true,
      message: "Your account and personal data have been permanently erased.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                  AUTHENTICATE WITH OAUTH (Google / Apple)
// ═══════════════════════════════════════════════════════════════════════
// Trust-based MVP — the client already verified the token with the provider
// SDK; we do a DB-level find-or-create keyed on (authProvider, externalAuthId).
//
// Priority order:
//   1. by_external_auth  — exact provider + externalId match (returning user)
//   2. by_email          — same email, link the OAuth credential
//   3. insert new user   — first time, create account + wallet
//
// NEVER accept a userId argument and trust it — derive identity from the DB.
// ═══════════════════════════════════════════════════════════════════════

function _generateSessionToken(): string {
  // 32-byte random hex token via the Convex runtime's crypto.getRandomValues
  const arr = new Uint8Array(32);
  crypto.getRandomValues(arr);
  return Array.from(arr)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ═══════════════════════════════════════════════════════════════════════
//                        SOCIAL SIGN IN
// Returns { userId, hasPhone, sessionToken, user }
// If hasPhone is false, client prompts to complete Sierra Leone phone number.
// ═══════════════════════════════════════════════════════════════════════

// INTERNAL: completes a social sign-in for an identity ALREADY verified by socialSignIn.
export const completeSocialSignIn = internalMutation({
  args: {
    provider: v.string(),
    sub: v.string(),
    email: v.optional(v.string()),
    emailVerified: v.boolean(),
    name: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
  },
  returns: v.object({
    userId: v.string(),
    hasPhone: v.boolean(),
    sessionToken: v.string(),
    user: v.object({
      id: v.string(),
      name: v.string(),
      email: v.string(),
      phone: v.string(),
      phoneNumber: v.optional(v.string()),
      role: v.string(),
      isVerified: v.boolean(),
      avatarUrl: v.optional(v.string()),
      walletAddress: v.optional(v.string()),
    }),
  }),
  handler: async (ctx, args) => {
    const now = Date.now();
    const { sessionToken, sessionExpiresAt } = issueSession(now);
    const verifiedEmail = args.emailVerified && args.email ? args.email.trim().toLowerCase() : undefined;

    // 1. The provider's stable subject id identifies the account.
    let existing = await ctx.db
      .query("users")
      .withIndex("by_external_auth", (q) => q.eq("authProvider", args.provider).eq("externalAuthId", args.sub))
      .first();

    // 2. Otherwise link an existing account ONLY by an email the provider itself verified.
    if (!existing && verifiedEmail) {
      existing = await ctx.db.query("users").withIndex("by_email", (q) => q.eq("email", verifiedEmail)).first();
    }

    if (existing) {
      if (existing.isActive === false) throw new Error("Account has been deactivated. Please contact support.");
      const hasPhone = !!(
        (existing.phoneNumber && existing.phoneNumber.trim().length > 0) ||
        (existing.phone && existing.phone.trim().length > 0)
      );
      await ctx.db.patch(existing._id, {
        sessionToken,
        sessionExpiresAt,
        lastLoginAt: now,
        updatedAt: now,
        authProvider: args.provider,
        externalAuthId: args.sub,
        ...(args.avatarUrl && !existing.avatarUrl ? { avatarUrl: args.avatarUrl } : {}),
      });
      return {
        userId: existing._id as string,
        hasPhone,
        sessionToken,
        user: {
          id: existing._id as string,
          name: existing.name,
          email: existing.email,
          phone: existing.phone ?? "",
          phoneNumber: existing.phoneNumber,
          role: existing.role,
          isVerified: existing.isVerified,
          avatarUrl: existing.avatarUrl,
          walletAddress: existing.walletAddress,
        },
      };
    }

    // 3. New account: always a CLIENT and never pre-verified (identity verification is separate KYC).
    const email = verifiedEmail ?? `${args.provider}_${args.sub}@users.vektolux.invalid`;
    const displayName = args.name && args.name.trim().length > 0 ? args.name.trim().slice(0, 80) : email.split("@")[0];
    const userId = await ctx.db.insert("users", {
      name: displayName,
      email,
      phone: "",
      phoneNumber: undefined,
      role: "client",
      authProvider: args.provider,
      externalAuthId: args.sub,
      sessionToken,
      sessionExpiresAt,
      isVerified: false,
      isActive: true,
      avatarUrl: args.avatarUrl,
      lastLoginAt: now,
      updatedAt: now,
    });
    await ctx.db.insert("walletBalances", {
      userId,
      availableBalance: 0,
      pendingBalance: 0,
      escrowBalance: 0,
      currency: "SLE",
      updatedAt: now,
    });
    return {
      userId: userId as string,
      hasPhone: false,
      sessionToken,
      user: {
        id: userId as string,
        name: displayName,
        email,
        phone: "",
        phoneNumber: undefined,
        role: "client",
        isVerified: false,
        avatarUrl: args.avatarUrl,
        walletAddress: undefined,
      },
    };
  },
});

/**
 * Social sign-in (Google / Apple). `providerId` MUST be the provider's signed ID token; it is
 * verified server-side before any session is issued. The email/name sent by the client are
 * NOT used to choose the account.
 */
export const socialSignIn = action({
  args: {
    email: v.optional(v.string()), // ignored for identity
    name: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    provider: v.string(),
    providerId: v.string(), // the provider ID token
  },
  returns: v.object({
    userId: v.string(),
    hasPhone: v.boolean(),
    sessionToken: v.string(),
    user: v.object({
      id: v.string(),
      name: v.string(),
      email: v.string(),
      phone: v.string(),
      phoneNumber: v.optional(v.string()),
      role: v.string(),
      isVerified: v.boolean(),
      avatarUrl: v.optional(v.string()),
      walletAddress: v.optional(v.string()),
    }),
  }),
  handler: async (ctx, args): Promise<any> => {
    const provider = args.provider.trim().toLowerCase();
    const identity =
      provider === "google"
        ? await verifyGoogleIdToken(args.providerId)
        : provider === "apple"
          ? await verifyAppleIdToken(args.providerId)
          : null;
    if (!identity) throw new Error("Unsupported sign-in provider.");
    return await ctx.runMutation(internal.users.completeSocialSignIn, {
      provider: identity.provider,
      sub: identity.sub,
      email: identity.email,
      emailVerified: identity.emailVerified,
      name: args.name ?? identity.name,
      avatarUrl: args.avatarUrl,
    });
  },
});


// ═══════════════════════════════════════════════════════════════════════
//                      LINK PHONE NUMBER
// Formats and stores Sierra Leone phone number, ensures wallet exists.
// ═══════════════════════════════════════════════════════════════════════

export const linkPhoneNumber = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    userId: v.id("users"),
    phoneNumber: v.string(),
  },
  returns: v.object({
    success: v.boolean(),
    phoneNumber: v.string(),
  }),
  handler: async (ctx, args) => {
    // Only the account owner (valid session) may act on this account.
    await requireSelf(ctx, args.sessionToken, String(args.userId));
    const user = await ctx.db.get(args.userId);
    if (!user) {
      throw new Error("User not found");
    }

    // Format phone number to Sierra Leone E.164 (+232...)
    let digits = args.phoneNumber.replace(/\D/g, "");
    if (digits.startsWith("232")) {
      digits = digits.substring(3);
    } else if (digits.startsWith("0")) {
      digits = digits.substring(1);
    }
    const formattedPhone = `+232${digits}`;

    const now = Date.now();
    await ctx.db.patch(args.userId, {
      phone: formattedPhone,
      phoneNumber: formattedPhone,
      updatedAt: now,
    });

    // Ensure wallet balance exists
    const existingWallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .first();

    if (!existingWallet) {
      await ctx.db.insert("walletBalances", {
        userId: args.userId,
        availableBalance: 0,
        pendingBalance: 0,
        escrowBalance: 0,
        currency: "SLE",
        updatedAt: now,
      });
    }

    return {
      success: true,
      phoneNumber: formattedPhone,
    };
  },
});


