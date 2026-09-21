// convex/wallet.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Reactive Wallet Balance & Account Queries
// ═══════════════════════════════════════════════════════════════════════

import { query } from "./_generated/server";
import { v } from "convex/values";

/**
 * Reactive query for user's wallet balance.
 * Automatically updates connected Flutter clients in real time when balance changes.
 */
export const getUserBalance = query({
  args: {
    userId: v.optional(v.string()),
    currency: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const currency = args.currency ?? "SLE";
    let userConvexId = null;

    // 1. Try deriving from authenticated session identity
    const identity = await ctx.auth.getUserIdentity();
    if (identity) {
      const userDoc = await ctx.db
        .query("users")
        .withIndex("by_external_auth", (q) =>
          q.eq("authProvider", "convex").eq("externalAuthId", identity.tokenIdentifier)
        )
        .first();
      if (userDoc) {
        userConvexId = userDoc._id;
      }
    }

    // 2. Fall back to explicit userId passed by client
    if (!userConvexId && args.userId) {
      userConvexId = ctx.db.normalizeId("users", args.userId);
    }

    if (!userConvexId) {
      return {
        availableBalance: 0,
        pendingBalance: 0,
        escrowBalance: 0,
        currency,
        exists: false,
        updatedAt: Date.now(),
      };
    }

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
