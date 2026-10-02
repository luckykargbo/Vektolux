// convex/wallet.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Reactive Wallet Balance & Account Queries
// ═══════════════════════════════════════════════════════════════════════

import { query } from "./_generated/server";
import { v } from "convex/values";
import { requireSelf } from "./lib/auth";

/**
 * Reactive query for user's wallet balance.
 * Automatically updates connected Flutter clients in real time when balance changes.
 */
export const getUserBalance = query({
  args: {
    userId: v.optional(v.string()),
    currency: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  returns: v.object({
    walletId: v.optional(v.id("walletBalances")),
    availableBalance: v.number(),
    pendingBalance: v.number(),
    escrowBalance: v.number(),
    currency: v.string(),
    exists: v.boolean(),
    updatedAt: v.number(),
  }),
  handler: async (ctx, args) => {
    const currency = args.currency ?? "SLE";
    // Identity comes ONLY from the authenticated session. A supplied userId
    // must match it; there is no fallback to a client-claimed user.
    const { userId: userConvexId } = await requireSelf(ctx, args.sessionToken, args.userId);

    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", userConvexId!).eq("currency", currency)
      )
      .first();

    if (!wallet) {
      return {
        availableBalance: 0,
        pendingBalance: 0,
        escrowBalance: 0,
        currency,
        exists: false,
        updatedAt: Date.now(),
      };
    }

    return {
      walletId: wallet._id,
      availableBalance: wallet.availableBalance,
      pendingBalance: wallet.pendingBalance,
      escrowBalance: wallet.escrowBalance ?? 0,
      currency: wallet.currency,
      exists: true,
      updatedAt: wallet.updatedAt,
    };
  },
});

/**
 * Get wallet balance strictly filtered by the user's ID.
 * If no wallet record exists, returns 0 balances.
 */
export const getWalletBalance = query({
  args: {
    userId: v.string(),
    currency: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  returns: v.object({
    walletId: v.optional(v.id("walletBalances")),
    availableBalance: v.number(),
    pendingBalance: v.number(),
    escrowLockedBalance: v.number(),
    escrowBalance: v.number(),
    currency: v.string(),
    exists: v.boolean(),
    updatedAt: v.optional(v.number()),
  }),
  handler: async (ctx, args) => {
    const currency = args.currency ?? "SLE";
    const { userId: userConvexId } = await requireSelf(ctx, args.sessionToken, args.userId);

    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user", (q) => q.eq("userId", userConvexId!))
      .first();

    if (!wallet) {
      return {
        availableBalance: 0.0,
        pendingBalance: 0.0,
        escrowLockedBalance: 0.0,
        escrowBalance: 0.0,
        currency,
        exists: false,
      };
    }

    return {
      walletId: wallet._id,
      availableBalance: wallet.availableBalance,
      pendingBalance: wallet.pendingBalance,
      escrowLockedBalance: wallet.escrowBalance ?? 0.0,
      escrowBalance: wallet.escrowBalance ?? 0.0,
      currency: wallet.currency,
      exists: true,
      updatedAt: wallet.updatedAt,
    };
  },
});
