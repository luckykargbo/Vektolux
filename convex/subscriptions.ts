// convex/subscriptions.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Dynamic Subscription & Anti-Double-Pay Guard Engine
// Powers dynamic admin-managed pricing, promotional strike-throughs,
// strict 72-hour renewal gating, and vendor verification badge locks.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

const RENEWAL_WINDOW_MS = 72 * 60 * 60 * 1000; // 72 Hours

// ═══════════════════════════════════════════════════════════════════════
// 1. GET PLANS (Public Dynamic Pricing with Promotional Strike-Through)
// ═══════════════════════════════════════════════════════════════════════

export const getPlans = query({
  args: {
    roleTarget: v.optional(
      v.union(v.literal("hotel_operator"), v.literal("agent"), v.literal("merchant"))
    ),
  },
  handler: async (ctx, args) => {
    let plansQuery = ctx.db.query("subscription_plans");

    const plans = await plansQuery.take(50);
    const now = Date.now();

    const filtered = plans.filter((p) => {
      if (!p.isActive) return false;
      if (args.roleTarget && p.roleTarget !== args.roleTarget) return false;
      return true;
    });

    return filtered.map((p) => {
      const isPromoActive =
        p.discountPercent > 0 &&
        (!p.promoStart || now >= p.promoStart) &&
        (!p.promoEnd || now <= p.promoEnd);

      const discountAmount = isPromoActive
        ? Math.round(p.basePrice * (p.discountPercent / 100))
        : 0;

      const effectivePrice = p.basePrice - discountAmount;

      return {
        id: p._id,
        name: p.name,
        tierCode: p.tierCode,
        roleTarget: p.roleTarget,
        basePrice: p.basePrice,
        effectivePrice,
        currency: p.currency,
        billingInterval: p.billingInterval,
        intervalDays: p.intervalDays,
        discountPercent: isPromoActive ? p.discountPercent : 0,
        isPromoActive,
        promoEnd: p.promoEnd,
        features: p.features,
      };
    });
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 2. GET USER ACTIVE SUBSCRIPTION
// ═══════════════════════════════════════════════════════════════════════

export const getUserActiveSubscription = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const activeSub = await ctx.db
      .query("vendor_subscriptions")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .filter((q) =>
        q.or(q.eq(q.field("status"), "active"), q.eq(q.field("status"), "dunning"))
      )
      .first();

    if (!activeSub) {
      return null;
    }

    const plan = await ctx.db.get(activeSub.planId);
    const now = Date.now();
    const isExpired = now > activeSub.expiryDate;
    const timeUntilExpiry = activeSub.expiryDate - now;
    const canRenew = timeUntilExpiry <= RENEWAL_WINDOW_MS;

    return {
      id: activeSub._id,
      planId: activeSub.planId,
      planName: plan?.name ?? activeSub.tierCode,
      tierCode: activeSub.tierCode,
      status: isExpired ? "expired" : activeSub.status,
      startDate: activeSub.startDate,
      expiryDate: activeSub.expiryDate,
      gracePeriodEndsAt: activeSub.gracePeriodEndsAt,
      amountPaid: activeSub.amountPaid,
      currency: activeSub.currency,
      autoRenew: activeSub.autoRenew,
      canRenew,
      hoursRemaining: Math.max(0, Math.floor(timeUntilExpiry / (60 * 60 * 1000))),
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 3. INITIATE SUBSCRIPTION (Anti-Double-Pay Guard)
// ═══════════════════════════════════════════════════════════════════════

export const initiateSubscription = mutation({
  args: {
    userId: v.id("users"),
    tierCode: v.string(),
    paymentMethod: v.string(), // "orange_money" | "africell_money" | "card" | "wallet"
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    // 1. Fetch requested plan
    const plan = await ctx.db
      .query("subscription_plans")
      .withIndex("by_tierCode", (q) => q.eq("tierCode", args.tierCode))
      .first();

    if (!plan || !plan.isActive) {
      throw new Error(`The requested subscription tier '${args.tierCode}' is currently unavailable.`);
    }

    // 2. Anti-Double-Pay Guard: Check if user already holds an active/non-expiring subscription
    const existingActive = await ctx.db
      .query("vendor_subscriptions")
      .withIndex("by_userId_and_status", (q) =>
        q.eq("userId", args.userId).eq("status", "active")
      )
      .first();

    if (existingActive) {
      const timeRemaining = existingActive.expiryDate - now;

      // If subscription has more than 72 hours remaining, block purchase strictly!
      if (timeRemaining > RENEWAL_WINDOW_MS) {
        const daysRemaining = Math.ceil(timeRemaining / (24 * 60 * 60 * 1000));
        throw new Error(
          `Active subscription detected. You are already subscribed to '${existingActive.tierCode}' with ${daysRemaining} day(s) remaining. Re-purchasing is locked until 72 hours before expiration to prevent accidental double-billing.`
        );
      }
    }

    // 3. Calculate dynamic effective price
    const isPromoActive =
      plan.discountPercent > 0 &&
      (!plan.promoStart || now >= plan.promoStart) &&
      (!plan.promoEnd || now <= plan.promoEnd);

    const discountAmount = isPromoActive
      ? Math.round(plan.basePrice * (plan.discountPercent / 100))
      : 0;
    const finalAmount = plan.basePrice - discountAmount;

    // 4. Generate checkout reference
    const checkoutRef = `SUB-${Date.now()}-${Math.floor(1000 + Math.random() * 9000)}`;

    return {
      checkoutReference: checkoutRef,
      planId: plan._id,
      tierCode: plan.tierCode,
      amountToPay: finalAmount,
      currency: plan.currency,
      paymentMethod: args.paymentMethod,
      message: `Checkout session initialized for ${plan.name} at SLE ${finalAmount}.`,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 4. RENEW SUBSCRIPTION (Within 72h Window or Expired)
// ═══════════════════════════════════════════════════════════════════════

export const renewSubscription = mutation({
  args: {
    userId: v.id("users"),
    subscriptionId: v.id("vendor_subscriptions"),
    paymentMethod: v.string(),
  },
  handler: async (ctx, args) => {
    const sub = await ctx.db.get(args.subscriptionId);
    if (!sub || sub.userId !== args.userId) {
      throw new Error("Subscription not found or unauthorized.");
    }

    const now = Date.now();
    const timeUntilExpiry = sub.expiryDate - now;

    // Must be either within 72 hours of expiry OR already expired
    if (timeUntilExpiry > RENEWAL_WINDOW_MS) {
      const hoursToWait = Math.ceil((timeUntilExpiry - RENEWAL_WINDOW_MS) / (60 * 60 * 1000));
      throw new Error(
        `Renewal is not yet open. You can renew your plan in ${hoursToWait} hour(s) (within 72 hours of expiration).`
      );
    }

    const plan = await ctx.db.get(sub.planId);
    if (!plan || !plan.isActive) {
      throw new Error("The associated subscription plan is no longer active. Please choose another tier.");
    }

    // Compute effective renewal price
    const isPromoActive =
      plan.discountPercent > 0 &&
      (!plan.promoStart || now >= plan.promoStart) &&
      (!plan.promoEnd || now <= plan.promoEnd);

    const finalAmount = isPromoActive
      ? plan.basePrice - Math.round(plan.basePrice * (plan.discountPercent / 100))
      : plan.basePrice;

    const renewalRef = `REN-${Date.now()}-${Math.floor(1000 + Math.random() * 9000)}`;

    return {
      renewalReference: renewalRef,
      subscriptionId: sub._id,
      tierCode: sub.tierCode,
      amountToPay: finalAmount,
      currency: plan.currency,
      currentExpiry: sub.expiryDate,
      message: "Renewal checkout generated. Existing remaining time will be preserved upon confirmation.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 5. COMPLETE SUBSCRIPTION PAYMENT (Webhook / Confirmation Handler)
// ═══════════════════════════════════════════════════════════════════════

export const completeSubscriptionPayment = mutation({
  args: {
    userId: v.id("users"),
    tierCode: v.string(),
    paymentReference: v.string(),
    paymentMethod: v.string(),
    amountPaid: v.number(),
  },
  handler: async (ctx, args) => {
    const now = Date.now();

    const plan = await ctx.db
      .query("subscription_plans")
      .withIndex("by_tierCode", (q) => q.eq("tierCode", args.tierCode))
      .first();

    if (!plan) {
      throw new Error(`Plan '${args.tierCode}' does not exist.`);
    }

    const planDurationMs = plan.intervalDays * 24 * 60 * 60 * 1000;

    // Check if user has an existing subscription record
    const existing = await ctx.db
      .query("vendor_subscriptions")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .first();

    let newExpiryDate: number;
    let subscriptionId;

    if (existing) {
      // If renewed before expiry, add duration on top of current expiry
      if (existing.expiryDate > now) {
        newExpiryDate = existing.expiryDate + planDurationMs;
      } else {
        newExpiryDate = now + planDurationMs;
      }

      await ctx.db.patch(existing._id, {
        planId: plan._id,
        tierCode: plan.tierCode,
        status: "active",
        expiryDate: newExpiryDate,
        amountPaid: args.amountPaid,
        paymentReference: args.paymentReference,
        paymentMethod: args.paymentMethod,
        lastRenewedAt: now,
        updatedAt: now,
      });
      subscriptionId = existing._id;
    } else {
      newExpiryDate = now + planDurationMs;
      subscriptionId = await ctx.db.insert("vendor_subscriptions", {
        userId: args.userId,
        planId: plan._id,
        tierCode: plan.tierCode,
        status: "active",
        startDate: now,
        expiryDate: newExpiryDate,
        amountPaid: args.amountPaid,
        currency: plan.currency,
        paymentReference: args.paymentReference,
        paymentMethod: args.paymentMethod,
        autoRenew: true,
        createdAt: now,
        updatedAt: now,
      });
    }

    // Automatically update vendor verification badge if role is hotel_operator
    const hotel = await ctx.db
      .query("hotel_profiles")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .first();

    if (hotel) {
      await ctx.db.patch(hotel._id, {
        isVerified: true,
        verificationStatus: "verified",
        updatedAt: now,
      });
    }

    return {
      success: true,
      subscriptionId,
      tierCode: plan.tierCode,
      expiryDate: newExpiryDate,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 6. ADMIN PLAN MANAGEMENT (Dynamic Pricing Controls)
// ═══════════════════════════════════════════════════════════════════════

export const adminUpsertPlan = mutation({
  args: {
    tierCode: v.string(),
    name: v.string(),
    roleTarget: v.union(v.literal("hotel_operator"), v.literal("agent"), v.literal("merchant")),
    basePrice: v.number(),
    currency: v.string(),
    billingInterval: v.union(v.literal("monthly"), v.literal("quarterly"), v.literal("annual")),
    intervalDays: v.number(),
    discountPercent: v.number(),
    promoStart: v.optional(v.number()),
    promoEnd: v.optional(v.number()),
    isActive: v.boolean(),
    features: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("subscription_plans")
      .withIndex("by_tierCode", (q) => q.eq("tierCode", args.tierCode))
      .first();

    const now = Date.now();

    if (existing) {
      await ctx.db.patch(existing._id, {
        name: args.name,
        roleTarget: args.roleTarget,
        basePrice: args.basePrice,
        currency: args.currency,
        billingInterval: args.billingInterval,
        intervalDays: args.intervalDays,
        discountPercent: args.discountPercent,
        promoStart: args.promoStart,
        promoEnd: args.promoEnd,
        isActive: args.isActive,
        features: args.features,
        updatedAt: now,
      });
      return { planId: existing._id, action: "updated" };
    } else {
      const planId = await ctx.db.insert("subscription_plans", {
        name: args.name,
        tierCode: args.tierCode,
        roleTarget: args.roleTarget,
        basePrice: args.basePrice,
        currency: args.currency,
        billingInterval: args.billingInterval,
        intervalDays: args.intervalDays,
        discountPercent: args.discountPercent,
        promoStart: args.promoStart,
        promoEnd: args.promoEnd,
        isActive: args.isActive,
        features: args.features,
        createdAt: now,
        updatedAt: now,
      });
      return { planId, action: "created" };
    }
  },
});

export const adminTogglePlanStatus = mutation({
  args: {
    planId: v.id("subscription_plans"),
    isActive: v.boolean(),
  },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.planId, {
      isActive: args.isActive,
      updatedAt: Date.now(),
    });
    return { success: true };
  },
});
