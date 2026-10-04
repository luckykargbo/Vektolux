// convex/subscriptions.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Dynamic Subscription & Anti-Double-Pay Guard Engine
// Powers dynamic admin-managed pricing, promotional strike-throughs,
// strict 72-hour renewal gating, and vendor verification badge locks.
// ═══════════════════════════════════════════════════════════════════════

import { internalMutation, internalQuery, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireAdmin, requireSelf } from "./lib/auth";
import { Id } from "./_generated/dataModel";
import { verifyAndTrackPin } from "./lib/pin";
import { chargeSubscription, findByIdempotencyKey } from "./walletCore";
import {
  activeSubscription,
  configuredPolicyLaunchTimestamp,
  LEGACY_GRACE_PERIOD_MS,
  legacyAgentGrace,
  businessRole,
  isRoleApproved,
  postingPermission,
  professionalBadge,
  SubscriptionRole,
  hasCarDealerCapability,
  professionalTitle,
} from "./lib/permissions";

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
    userId: v.optional(v.id("users")),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken, args.userId);
    const activeSub = await ctx.db
      .query("vendor_subscriptions")
      .withIndex("by_userId", (q) => q.eq("userId", userId))
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
      // (The record's payment-dunning `gracePeriodEndsAt` is deliberately NOT exposed: nothing sets
      // it, no client reads it, and the name collides with the legacy-agent policy grace period
      // reported by getMyProfessionalStatus.)
      amountPaid: activeSub.amountPaid,
      currency: activeSub.currency,
      autoRenew: activeSub.autoRenew,
      canRenew,
      hoursRemaining: Math.max(0, Math.floor(timeUntilExpiry / (60 * 60 * 1000))),
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 3. PURCHASE / RENEWAL
// ═══════════════════════════════════════════════════════════════════════

// Subscription purchase/renewal = subscribeWithWallet (wallet, PIN) or
// payments:initiateMoniMePayment({ subscriptionTierCode }) (direct, verified by Monime).
// The old quote-only initiateSubscription / renewSubscription returned references that no
// payment flow consumed and were removed.

// ═══════════════════════════════════════════════════════════════════════
// 5. COMPLETE SUBSCRIPTION PAYMENT (Webhook / Confirmation Handler)
// ═══════════════════════════════════════════════════════════════════════

/** Effective price right now (base price minus an active promotional discount). */
export function effectivePrice(
  plan: { basePrice: number; discountPercent: number; promoStart?: number; promoEnd?: number },
  now: number = Date.now()
): number {
  const promo =
    plan.discountPercent > 0 && (!plan.promoStart || now >= plan.promoStart) && (!plan.promoEnd || now <= plan.promoEnd);
  return promo ? plan.basePrice - Math.round(plan.basePrice * (plan.discountPercent / 100)) : plan.basePrice;
}

/**
 * Activates / renews a subscription for a VERIFIED payment (wallet charge, provider-confirmed
 * payment, or an audited admin grant). Idempotent on paymentReference: the same payment can never
 * extend a subscription twice. Renewing before expiry adds the new period on top of the remaining time.
 */
export async function applySubscriptionPayment(
  ctx: { db: any },
  args: { userId: Id<"users">; tierCode: string; paymentReference: string; paymentMethod: string; amountPaid: number }
): Promise<{ success: true; subscriptionId: Id<"vendor_subscriptions">; tierCode: string; expiryDate: number; duplicate: boolean }> {
  const now = Date.now();
  const plan = await ctx.db.query("subscription_plans").withIndex("by_tierCode", (q: any) => q.eq("tierCode", args.tierCode)).first();
  if (!plan) throw new Error(`Plan '${args.tierCode}' does not exist.`);

  const userSubs = await ctx.db.query("vendor_subscriptions").withIndex("by_userId", (q: any) => q.eq("userId", args.userId)).take(50);
  const replay = userSubs.find((x: any) => x.paymentReference === args.paymentReference);
  if (replay) {
    return { success: true, subscriptionId: replay._id, tierCode: replay.tierCode, expiryDate: replay.expiryDate, duplicate: true };
  }

  const durationMs = plan.intervalDays * 24 * 60 * 60 * 1000;
  // Renew the subscription for the SAME professional role (agent vs hotel), if one exists.
  let existing: any = null;
  for (const sub of userSubs) {
    const p = await ctx.db.get(sub.planId);
    if (p?.roleTarget === plan.roleTarget) {
      existing = sub;
      break;
    }
  }

  if (existing) {
    const expiryDate = existing.expiryDate > now ? existing.expiryDate + durationMs : now + durationMs;
    await ctx.db.patch(existing._id, {
      planId: plan._id,
      tierCode: plan.tierCode,
      status: "active",
      expiryDate,
      amountPaid: args.amountPaid,
      currency: plan.currency,
      paymentReference: args.paymentReference,
      paymentMethod: args.paymentMethod,
      lastRenewedAt: now,
      reminderSentAt: undefined,
      updatedAt: now,
    });
    return { success: true, subscriptionId: existing._id, tierCode: plan.tierCode, expiryDate, duplicate: false };
  }
  const expiryDate = now + durationMs;
  const subscriptionId = await ctx.db.insert("vendor_subscriptions", {
    userId: args.userId,
    planId: plan._id,
    tierCode: plan.tierCode,
    status: "active",
    startDate: now,
    expiryDate,
    amountPaid: args.amountPaid,
    currency: plan.currency,
    paymentReference: args.paymentReference,
    paymentMethod: args.paymentMethod,
    autoRenew: false,
    createdAt: now,
    updatedAt: now,
  });
  // NOTE: no permanent "verified" flag is written anywhere — the professional badge is computed
  // from the active, unexpired subscription (lib/permissions.ts).
  return { success: true, subscriptionId, tierCode: plan.tierCode, expiryDate, duplicate: false };
}

// INTERNAL ONLY: activates a subscription for a payment that was verified elsewhere.
export const completeSubscriptionPayment = internalMutation({
  args: {
    userId: v.id("users"),
    tierCode: v.string(),
    paymentReference: v.string(),
    paymentMethod: v.string(),
    amountPaid: v.number(),
  },
  handler: async (ctx, args) => applySubscriptionPayment(ctx, args),
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
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: __adminId } = await requireAdmin(ctx, { sessionToken: args.sessionToken });
    await ctx.db.insert("audit_logs", {
      adminUserId: __adminId,
      action: "SUBSCRIPTION_PLAN_CHANGED",
      targetTransactionId: args.tierCode,
      snapshot: JSON.stringify({ basePrice: args.basePrice, discountPercent: args.discountPercent, intervalDays: args.intervalDays, isActive: args.isActive, roleTarget: args.roleTarget }),
      timestamp: Date.now(),
    });
    if (args.basePrice < 0 || args.discountPercent < 0 || args.discountPercent > 100 || args.intervalDays <= 0) {
      throw new Error("Invalid plan values.");
    }
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
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx, { sessionToken: args.sessionToken });
    await ctx.db.patch(args.planId, {
      isActive: args.isActive,
      updatedAt: Date.now(),
    });
    return { success: true };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 7. SUBSCRIBE / RENEW WITH WALLET FUNDS (PIN-authorized, idempotent)
// ═══════════════════════════════════════════════════════════════════════

function roleForPlan(roleTarget: string): { role: string; label: string } {
  if (roleTarget === "agent") return { role: "real_estate_agent", label: "Real Estate Agent" };
  if (roleTarget === "hotel_operator") return { role: "hotel_owner", label: "Hotel / Guest House Owner" };
  return { role: "vehicle_dealer", label: "Car Dealer" };
}

/** Only an APPROVED professional of the plan's role may subscribe to it. */
function assertEligibleForPlan(user: any, plan: { roleTarget: string }) {
  const needed = roleForPlan(plan.roleTarget);
  if (businessRole(user) !== needed.role || !isRoleApproved(user)) {
    throw new Error(`This plan requires an approved ${needed.label} account.`);
  }
}

export const subscribeWithWallet = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    tierCode: v.string(),
    pin: v.string(),
    idempotencyKey: v.string(),
  },
  handler: async (ctx, args) => {
    const { userId, user } = await requireSelf(ctx, args.sessionToken);
    const key = args.idempotencyKey.trim();
    if (key.length < 16 || key.length > 100) throw new Error("A valid idempotency key is required.");

    const plan = await ctx.db.query("subscription_plans").withIndex("by_tierCode", (q) => q.eq("tierCode", args.tierCode)).first();
    if (!plan || !plan.isActive) throw new Error("This subscription plan is currently unavailable.");
    assertEligibleForPlan(user, plan);

    // Replay of an already-processed request: report the current state, charge nothing.
    const prior = await findByIdempotencyKey(ctx, userId, key);
    if (prior) {
      const sub = await activeSubscription(ctx, userId, plan.roleTarget as SubscriptionRole);
      return { success: true as const, duplicate: true, expiryDate: sub?.expiryDate ?? null, tierCode: plan.tierCode };
    }

    // Anti double-pay: renewal opens 72h before expiry.
    const current = await activeSubscription(ctx, userId, plan.roleTarget as SubscriptionRole);
    if (current && current.expiryDate - Date.now() > RENEWAL_WINDOW_MS) {
      throw new Error("Your subscription is active. Renewal opens 72 hours before it expires.");
    }

    const pinCheck = await verifyAndTrackPin(ctx, user, args.pin);
    if (!pinCheck.ok) return { success: false as const, errorCode: pinCheck.code, message: pinCheck.message };

    const price = effectivePrice(plan);
    let reference: string;
    if (price > 0) {
      const charge = await chargeSubscription(ctx, {
        userId,
        amount: price,
        currency: plan.currency,
        idempotencyKey: key,
        description: `${plan.name} subscription`,
        tierCode: plan.tierCode,
      });
      reference = charge.transactionCode;
    } else {
      reference = `free:${userId}:${key}`;
    }
    const r = await applySubscriptionPayment(ctx, {
      userId,
      tierCode: plan.tierCode,
      paymentReference: reference,
      paymentMethod: price > 0 ? "wallet" : "free_plan",
      amountPaid: price,
    });
    await ctx.db.insert("user_notifications", {
      userId: userId as string,
      targetType: "single_user",
      title: "Subscription active",
      body: `Your ${plan.name} subscription is active until ${new Date(r.expiryDate).toDateString()}.`,
      read: false,
      createdAt: Date.now(),
    });
    return { success: true as const, duplicate: false, expiryDate: r.expiryDate, tierCode: plan.tierCode, amountCharged: price, currency: plan.currency };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 8. STATUS / BADGES (computed, never stored)
// ═══════════════════════════════════════════════════════════════════════

export const getMyProfessionalStatus = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { user } = await requireSelf(ctx, args.sessionToken);
    const now = Date.now();
    const badge = await professionalBadge(ctx, user, now);
    const role = businessRole(user);
    const apps = await ctx.db.query("role_applications").withIndex("by_user", (q) => q.eq("userId", user._id)).order("desc").take(5);

    // Paid subscription for this professional role (server data only).
    const subRole: SubscriptionRole | null =
      role === "real_estate_agent" ? "agent" : role === "hotel_owner" ? "hotel_operator" : null;
    const hasActiveSubscription = subRole ? !!(await activeSubscription(ctx, user._id, subRole, now)) : false;
    // Legacy grace: fixed window from constants; never counted as a paid subscription.
    const grace = legacyAgentGrace(user, now);
    const isInGracePeriod = !hasActiveSubscription && grace.active;

    return {
      role,
      roleApproved: isRoleApproved(user),
      // Separately approved capabilities and the resulting professional identity (server-derived).
      isCarDealer: hasCarDealerCapability(user),
      professionalTitle: professionalTitle(user),
      ...badge,
      hasActiveSubscription,
      isInGracePeriod,
      gracePeriodEndsAt: isInGracePeriod ? grace.endsAt : null,
      // set when an eligible legacy agent's grace window is over (for "ended on" messaging)
      legacyGraceEndedAt: grace.eligible && !grace.active ? grace.endsAt : null,
      subscriptionPolicyConfigured: grace.configured,
      canPostProperty: (await postingPermission(ctx, user, "property")).allowed,
      canPostVehicle: (await postingPermission(ctx, user, "vehicle")).allowed,
      canManageHotel: (await postingPermission(ctx, user, "hotel")).allowed,
      applications: apps.map((a) => ({ id: a._id as string, targetRole: a.targetRole, status: a.status, reviewNotes: a.reviewNotes ?? null })),
    };
  },
});

/** Public: the computed professional badge of any user (for listing cards / profiles). */
export const getProfessionalBadge = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) return { verifiedAgent: false, verifiedHotel: false };
    const b = await professionalBadge(ctx, user);
    return { verifiedAgent: b.verifiedAgent, verifiedHotel: b.verifiedHotel };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 9. ADMIN: SUBSCRIPTIONS
// ═══════════════════════════════════════════════════════════════════════

export const adminListSubscriptions = query({
  args: {
    sessionToken: v.optional(v.string()),
    status: v.optional(v.union(v.literal("active"), v.literal("expired"), v.literal("cancelled"), v.literal("dunning"))),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx, { sessionToken: args.sessionToken });
    const rows = args.status
      ? await ctx.db.query("vendor_subscriptions").withIndex("by_status_and_expiryDate", (q) => q.eq("status", args.status!)).order("desc").take(200)
      : await ctx.db.query("vendor_subscriptions").order("desc").take(200);
    const now = Date.now();
    return await Promise.all(
      rows.map(async (r) => {
        const u = await ctx.db.get(r.userId);
        return {
          id: r._id as string,
          userName: u?.name ?? "Unknown",
          tierCode: r.tierCode,
          status: r.status === "active" && r.expiryDate <= now ? "expired" : r.status,
          expiryDate: r.expiryDate,
          amountPaid: r.amountPaid,
          currency: r.currency,
          paymentMethod: r.paymentMethod,
        };
      })
    );
  },
});

/** Complimentary / grandfathered subscription granted by an admin (audited, no money moves). */
export const adminGrantSubscription = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    userId: v.id("users"),
    tierCode: v.string(),
    reason: v.string(),
  },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdmin(ctx, { sessionToken: args.sessionToken });
    if (args.reason.trim().length < 5) throw new Error("A reason is required.");
    const r = await applySubscriptionPayment(ctx, {
      userId: args.userId,
      tierCode: args.tierCode,
      paymentReference: `admin_grant:${adminId}:${Date.now()}`,
      paymentMethod: "admin_grant",
      amountPaid: 0,
    });
    await ctx.db.insert("audit_logs", {
      adminUserId: adminId,
      action: "SUBSCRIPTION_GRANTED",
      targetTransactionId: r.subscriptionId as string,
      snapshot: JSON.stringify({ userId: args.userId, tierCode: args.tierCode, expiryDate: r.expiryDate, reason: args.reason }),
      timestamp: Date.now(),
    });
    return r;
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 10. EXPIRY & RENEWAL REMINDERS (cron). Privileges already depend on the real expiry date
//     at every check; this job only records the status change and notifies users.
// ═══════════════════════════════════════════════════════════════════════

const REMINDER_WINDOW_MS = 3 * 24 * 60 * 60 * 1000;

export const expireAndRemind = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const expired = await ctx.db
      .query("vendor_subscriptions")
      .withIndex("by_status_and_expiryDate", (q) => q.eq("status", "active").lte("expiryDate", now))
      .take(200);
    for (const s of expired) {
      await ctx.db.patch(s._id, { status: "expired", updatedAt: now });
      await ctx.db.insert("user_notifications", {
        userId: s.userId as string,
        targetType: "single_user",
        title: "Subscription expired",
        body: "Your Vektolux professional subscription has expired. Your verified status and posting privileges are paused until you renew. Your listings and history are kept.",
        read: false,
        createdAt: now,
      });
    }
    const soon = await ctx.db
      .query("vendor_subscriptions")
      .withIndex("by_status_and_expiryDate", (q) => q.eq("status", "active").gt("expiryDate", now).lte("expiryDate", now + REMINDER_WINDOW_MS))
      .take(200);
    let reminded = 0;
    for (const s of soon) {
      if (s.reminderSentAt) continue;
      await ctx.db.patch(s._id, { reminderSentAt: now, updatedAt: now });
      await ctx.db.insert("user_notifications", {
        userId: s.userId as string,
        targetType: "single_user",
        title: "Subscription expiring soon",
        body: "Your Vektolux Agent subscription expires soon. Renew to keep your verified status and posting privileges.",
        read: false,
        createdAt: now,
      });
      reminded++;
    }
    return { expired: expired.length, reminded };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 11. DIRECT PROVIDER PAYMENT (Monime checkout / USSD) — "Model B"
//     The payment is recorded as a pending deposit tagged with the plan. Only when Monime's API
//     confirms it (payments.settleMoniMeReference) is the deposit credited AND, in the same
//     atomic mutation, the subscription charged and activated. If activation is impossible
//     (e.g. role suspended meanwhile) the money stays in the user's wallet — never lost.
// ═══════════════════════════════════════════════════════════════════════

/** Server-side price quote for a direct subscription payment (never trusts a client amount). */
export const getCheckoutQuote = internalQuery({
  args: { userId: v.id("users"), tierCode: v.string() },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) throw new Error("Account not found.");
    const plan = await ctx.db.query("subscription_plans").withIndex("by_tierCode", (q) => q.eq("tierCode", args.tierCode)).first();
    if (!plan || !plan.isActive) throw new Error("This subscription plan is currently unavailable.");
    assertEligibleForPlan(user, plan);
    const current = await activeSubscription(ctx, user._id, plan.roleTarget as SubscriptionRole);
    if (current && current.expiryDate - Date.now() > RENEWAL_WINDOW_MS) {
      throw new Error("Your subscription is active. Renewal opens 72 hours before it expires.");
    }
    const price = effectivePrice(plan);
    if (price <= 0) throw new Error("This plan is free — activate it from the subscription screen.");
    return { price, currency: plan.currency, name: plan.name, tierCode: plan.tierCode };
  },
});

/**
 * Called inside the deposit-settlement mutation, right after a VERIFIED deposit tagged for a
 * subscription was credited. Never throws for business reasons (so the credit is never rolled back).
 */
export async function activateSubscriptionFromDeposit(
  ctx: { db: any },
  userId: Id<"users">,
  tierCode: string,
  depositTxId: Id<"transactions">
): Promise<{ activated: boolean; reason?: string; expiryDate?: number }> {
  const now = Date.now();
  const notify = (title: string, body: string) =>
    ctx.db.insert("user_notifications", { userId: userId as string, targetType: "single_user", title, body, read: false, createdAt: now });

  const user = await ctx.db.get(userId);
  const plan = await ctx.db.query("subscription_plans").withIndex("by_tierCode", (q: any) => q.eq("tierCode", tierCode)).first();
  let reason: string | null = null;
  if (!user || !plan || !plan.isActive) reason = "The plan is no longer available.";
  else {
    try {
      assertEligibleForPlan(user, plan);
    } catch (e: any) {
      reason = e.message;
    }
  }
  const price = plan ? effectivePrice(plan) : 0;
  if (!reason && plan) {
    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q: any) => q.eq("userId", userId).eq("currency", plan.currency))
      .first();
    if (!wallet || wallet.availableBalance < price) reason = "The amount received is lower than the plan price.";
  }
  if (reason || !plan) {
    await notify(
      "Payment received — subscription not activated",
      `Your payment was credited to your Vektolux wallet, but the subscription could not be activated: ${reason} You can activate it from your wallet or contact support.`
    );
    return { activated: false, reason: reason ?? "unavailable" };
  }
  const charge = await chargeSubscription(ctx, {
    userId,
    amount: price,
    currency: plan.currency,
    idempotencyKey: `subcheckout:${depositTxId}`,
    description: `${plan.name} subscription`,
    tierCode: plan.tierCode,
  });
  const r = await applySubscriptionPayment(ctx, {
    userId,
    tierCode: plan.tierCode,
    paymentReference: charge.transactionCode,
    paymentMethod: "monime",
    amountPaid: price,
  });
  if (!r.duplicate) {
    await notify("Subscription active", `Your ${plan.name} subscription is active until ${new Date(r.expiryDate).toDateString()}.`);
  }
  return { activated: true, expiryDate: r.expiryDate };
}

// ═══════════════════════════════════════════════════════════════════════
// 12. LEGACY-AGENT PRE-LAUNCH REVIEW (read-only, internal)
//     Run from the Convex dashboard / CLI before setting the launch timestamp to see exactly which
//     accounts would receive the one-time grace period. Pass the planned launch time (Unix ms).
// ═══════════════════════════════════════════════════════════════════════
export const legacyAgentPolicyReport = internalQuery({
  args: { plannedLaunchTimestamp: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const launch = args.plannedLaunchTimestamp ?? configuredPolicyLaunchTimestamp();
    if (launch === null || launch === undefined) {
      return { configured: false, message: "No launch timestamp configured or supplied.", candidates: [] };
    }
    const agents = await ctx.db.query("users").filter((q) => q.eq(q.field("role"), "agent")).take(2000);
    const candidates = [];
    for (const u of agents) {
      const g = legacyAgentGrace(u, launch, launch);
      if (!g.eligible) continue;
      candidates.push({
        userId: u._id as string,
        name: u.name,
        path: typeof u.roleApprovedAt === "number" ? "B: roleApprovedAt before launch" : "A: old approval flow (isVerifiedAgent)",
        roleApprovedAt: u.roleApprovedAt ?? null,
        accountCreatedAt: u._creationTime,
      });
    }
    return {
      configured: true,
      launch,
      graceEndsAt: launch + LEGACY_GRACE_PERIOD_MS,
      agentsScanned: agents.length,
      eligibleCount: candidates.length,
      candidates,
    };
  },
});
