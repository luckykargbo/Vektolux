// convex/adminPortal.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Master Admin Portal Backend Functions
// API Key Health, Merchant Terminals, Financial Analytics,
// User Session Tracking, and Contact Request Relay.
// All functions enforce admin role validation.
// ═══════════════════════════════════════════════════════════════════════

import { query, mutation, internalMutation } from "./_generated/server";
import { v } from "convex/values";
import type { Id } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";

// ═══════════════════════════════════════════════════════════════════════
//                       SHARED ADMIN VALIDATION
// ═══════════════════════════════════════════════════════════════════════

async function validateAdminSession(
  ctx: QueryCtx | MutationCtx,
  adminId: string,
  sessionToken?: string
) {
  const adminDocId = ctx.db.normalizeId("users", adminId);
  if (!adminDocId) {
    throw new Error("Unauthorized: Invalid administrator credentials.");
  }
  const adminUser = await ctx.db.get(adminDocId);
  if (!adminUser || adminUser.role !== "admin") {
    throw new Error("Forbidden: Access restricted to platform administrators.");
  }
  if (
    sessionToken &&
    adminUser.sessionToken &&
    adminUser.sessionToken !== sessionToken
  ) {
    throw new Error(
      "Unauthorized: Session token expired. Please sign in again."
    );
  }
  return { adminDocId, adminUser };
}

// ═══════════════════════════════════════════════════════════════════════
//  MODULE 1 — API KEY HEALTH, MANAGEMENT & STATUS MONITOR
// ═══════════════════════════════════════════════════════════════════════

/**
 * Seeds the initial API key metadata records for all 4 platform services.
 * Only inserts records that don't already exist (by serviceId + keyName).
 */
export const seedApiKeysConfig = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const seedRecords = [
      {
        serviceId: "orange_money_sl",
        displayName: "Orange Money Sierra Leone",
        keyName: "MERCHANT_KEY",
        maskedValue: "****pending",
        envVarName: "ORANGE_MONEY_MERCHANT_KEY",
        operationalFunction:
          "Authenticates outbound payment initiation requests to Orange Money SL",
        usedIn: "convex/http.ts → /payments/initialize",
      },
      {
        serviceId: "orange_money_sl",
        displayName: "Orange Money Sierra Leone",
        keyName: "CLIENT_SECRET",
        maskedValue: "****pending",
        envVarName: "ORANGE_MONEY_CLIENT_SECRET",
        operationalFunction:
          "Signs API requests to Orange Money merchant endpoints",
        usedIn: "convex/http.ts → /payments/initialize",
      },
      {
        serviceId: "orange_money_sl",
        displayName: "Orange Money Sierra Leone",
        keyName: "WEBHOOK_SECRET",
        maskedValue: "****pending",
        envVarName: "ORANGE_MONEY_WEBHOOK_SECRET",
        operationalFunction:
          "Verifies HMAC signature on inbound Orange Money webhook callbacks",
        usedIn: "convex/http.ts → /webhooks/orange-money",
      },
      {
        serviceId: "africell_afrimoney",
        displayName: "Africell Afrimoney",
        keyName: "MERCHANT_CODE",
        maskedValue: "****pending",
        envVarName: "AFRICELL_MERCHANT_CODE",
        operationalFunction:
          "Identifies Vektolux merchant account for Afrimoney transactions",
        usedIn: "convex/http.ts → /payments/afrimoney",
      },
      {
        serviceId: "africell_afrimoney",
        displayName: "Africell Afrimoney",
        keyName: "API_SECRET",
        maskedValue: "****pending",
        envVarName: "AFRICELL_API_SECRET",
        operationalFunction:
          "Authenticates API calls to Africell Afrimoney gateway",
        usedIn: "convex/http.ts → /payments/afrimoney",
      },
      {
        serviceId: "moneroo_gateway",
        displayName: "Moneroo Payment Gateway",
        keyName: "SECRET_KEY",
        maskedValue: "****pending",
        envVarName: "MONEROO_SECRET_KEY",
        operationalFunction:
          "Authenticates checkout session creation and payment verification",
        usedIn: "convex/http.ts → /payments/moneroo",
      },
      {
        serviceId: "sms_notification",
        displayName: "SMS / USSD Notification Gateway",
        keyName: "API_KEY",
        maskedValue: "****pending",
        envVarName: "SMS_GATEWAY_API_KEY",
        operationalFunction:
          "Sends transactional SMS notifications (OTP, payment receipts, alerts)",
        usedIn: "convex/notifications.ts",
      },
    ];

    let inserted = 0;
    const now = Date.now();

    for (const record of seedRecords) {
      const existing = await ctx.db
        .query("api_keys_config")
        .withIndex("by_serviceId_keyName", (q) =>
          q.eq("serviceId", record.serviceId).eq("keyName", record.keyName)
        )
        .first();

      if (!existing) {
        await ctx.db.insert("api_keys_config", {
          ...record,
          healthStatus: "operational",
          isActive: false,
          updatedAt: now,
        });
        inserted++;
      }
    }

    return {
      inserted,
      total: seedRecords.length,
      message: `Seeded ${inserted} API key config records (${seedRecords.length - inserted} already existed).`,
    };
  },
});

/**
 * Returns all API key configuration records with masked values and health status.
 */
export const getApiKeysConfig = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const configs = await ctx.db.query("api_keys_config").take(50);

    return configs.map((c) => ({
      id: c._id as string,
      serviceId: c.serviceId,
      displayName: c.displayName,
      keyName: c.keyName,
      maskedValue: c.maskedValue,
      envVarName: c.envVarName,
      operationalFunction: c.operationalFunction,
      usedIn: c.usedIn,
      healthStatus: c.healthStatus,
      lastCheckedAt: c.lastCheckedAt,
      lastErrorMessage: c.lastErrorMessage,
      lastErrorCode: c.lastErrorCode,
      lastErrorAt: c.lastErrorAt,
      isActive: c.isActive,
      updatedAt: c.updatedAt,
    }));
  },
});

/**
 * Returns recent API health incidents, filterable by serviceId.
 */
export const getApiHealthIncidents = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    serviceId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    let incidents;
    if (args.serviceId) {
      incidents = await ctx.db
        .query("api_health_logs")
        .withIndex("by_serviceId", (q) => q.eq("serviceId", args.serviceId!))
        .order("desc")
        .take(50);
    } else {
      incidents = await ctx.db
        .query("api_health_logs")
        .order("desc")
        .take(50);
    }

    return incidents.map((i) => ({
      id: i._id as string,
      serviceId: i.serviceId,
      endpoint: i.endpoint,
      statusCode: i.statusCode,
      errorMessage: i.errorMessage,
      severity: i.severity,
      resolvedAt: i.resolvedAt,
      occurredAt: i.occurredAt,
    }));
  },
});

/**
 * Internal mutation: Called by webhook handlers to update key health status.
 */
export const updateApiKeyHealth = internalMutation({
  args: {
    serviceId: v.string(),
    healthStatus: v.union(
      v.literal("operational"),
      v.literal("degraded"),
      v.literal("outage")
    ),
    errorMessage: v.optional(v.string()),
    errorCode: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const configs = await ctx.db
      .query("api_keys_config")
      .withIndex("by_serviceId", (q) => q.eq("serviceId", args.serviceId))
      .take(20);

    for (const config of configs) {
      const patch: Record<string, unknown> = {
        healthStatus: args.healthStatus,
        lastCheckedAt: now,
        updatedAt: now,
      };
      if (args.errorMessage) {
        patch.lastErrorMessage = args.errorMessage;
        patch.lastErrorAt = now;
      }
      if (args.errorCode) {
        patch.lastErrorCode = args.errorCode;
      }
      await ctx.db.patch(config._id, patch);
    }
  },
});

/**
 * Internal mutation: Appends an incident to the api_health_logs table.
 */
export const logApiHealthIncident = internalMutation({
  args: {
    serviceId: v.string(),
    endpoint: v.string(),
    statusCode: v.optional(v.number()),
    errorMessage: v.string(),
    severity: v.union(
      v.literal("warning"),
      v.literal("critical"),
      v.literal("info")
    ),
  },
  handler: async (ctx, args) => {
    await ctx.db.insert("api_health_logs", {
      serviceId: args.serviceId,
      endpoint: args.endpoint,
      statusCode: args.statusCode,
      errorMessage: args.errorMessage,
      severity: args.severity,
      occurredAt: Date.now(),
    });
  },
});

/**
 * Admin mutation: Updates the masked preview after key rotation in env vars.
 */
export const rotateApiKeyMask = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    configId: v.string(),
    newMaskedValue: v.string(),
  },
  handler: async (ctx, args) => {
    const { adminDocId } = await validateAdminSession(
      ctx,
      args.adminId,
      args.sessionToken
    );

    const docId = ctx.db.normalizeId("api_keys_config", args.configId);
    if (!docId) throw new Error("API key config not found.");

    const config = await ctx.db.get(docId);
    if (!config) throw new Error("API key config not found.");

    await ctx.db.patch(docId, {
      maskedValue: args.newMaskedValue,
      isActive: true,
      healthStatus: "operational" as const,
      lastCheckedAt: Date.now(),
      updatedAt: Date.now(),
      updatedByAdminId: adminDocId,
    });

    return { status: "ROTATED", keyName: config.keyName };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//  MODULE 2 — AGENT & MERCHANT CODE CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════

/**
 * Returns all merchant terminals with status.
 */
export const getMerchantTerminals = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    statusFilter: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    let terminals;
    if (
      args.statusFilter &&
      (args.statusFilter === "active" ||
        args.statusFilter === "suspended" ||
        args.statusFilter === "maintenance")
    ) {
      terminals = await ctx.db
        .query("merchant_terminals")
        .withIndex("by_status", (q) =>
          q.eq("status", args.statusFilter as "active" | "suspended" | "maintenance")
        )
        .take(50);
    } else {
      terminals = await ctx.db
        .query("merchant_terminals")
        .order("desc")
        .take(50);
    }

    return terminals.map((t) => ({
      id: t._id as string,
      merchantUserId: t.merchantUserId as string | undefined,
      terminalCode: t.terminalCode,
      merchantId: t.merchantId,
      displayName: t.displayName,
      carrierProvider: t.carrierProvider,
      clearingAccount: t.clearingAccount,
      ledgerAccountType: t.ledgerAccountType,
      status: t.status,
      notes: t.notes,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
    }));
  },
});

/**
 * Creates or updates a merchant terminal configuration.
 */
export const upsertMerchantTerminal = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    terminalId: v.optional(v.string()),
    terminalCode: v.string(),
    merchantId: v.string(),
    displayName: v.string(),
    carrierProvider: v.string(),
    clearingAccount: v.optional(v.string()),
    ledgerAccountType: v.string(),
    status: v.union(
      v.literal("active"),
      v.literal("suspended"),
      v.literal("maintenance")
    ),
    notes: v.optional(v.string()),
    merchantUserId: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);
    const now = Date.now();

    // Resolve merchantUserId if provided
    let resolvedMerchantUserId: Id<"users"> | undefined;
    if (args.merchantUserId) {
      const uid = ctx.db.normalizeId("users", args.merchantUserId);
      if (uid) resolvedMerchantUserId = uid;
    }

    if (args.terminalId) {
      // Update existing
      const docId = ctx.db.normalizeId("merchant_terminals", args.terminalId);
      if (!docId) throw new Error("Terminal not found.");

      await ctx.db.patch(docId, {
        terminalCode: args.terminalCode,
        merchantId: args.merchantId,
        displayName: args.displayName,
        carrierProvider: args.carrierProvider,
        clearingAccount: args.clearingAccount,
        ledgerAccountType: args.ledgerAccountType,
        status: args.status,
        notes: args.notes,
        merchantUserId: resolvedMerchantUserId,
        updatedAt: now,
      });
      return { status: "UPDATED", terminalId: args.terminalId };
    } else {
      // Create new terminal
      // Check for duplicate terminal code
      const existing = await ctx.db
        .query("merchant_terminals")
        .withIndex("by_terminalCode", (q) =>
          q.eq("terminalCode", args.terminalCode)
        )
        .first();
      if (existing) {
        throw new Error(
          `Terminal code "${args.terminalCode}" already exists. Use a unique code.`
        );
      }

      const newId = await ctx.db.insert("merchant_terminals", {
        terminalCode: args.terminalCode,
        merchantId: args.merchantId,
        displayName: args.displayName,
        carrierProvider: args.carrierProvider,
        clearingAccount: args.clearingAccount,
        ledgerAccountType: args.ledgerAccountType,
        status: args.status,
        notes: args.notes,
        merchantUserId: resolvedMerchantUserId,
        createdAt: now,
        updatedAt: now,
      });
      return { status: "CREATED", terminalId: newId as string };
    }
  },
});

/**
 * Toggles a merchant terminal's status.
 */
export const toggleTerminalStatus = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    terminalId: v.string(),
    status: v.union(
      v.literal("active"),
      v.literal("suspended"),
      v.literal("maintenance")
    ),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const docId = ctx.db.normalizeId("merchant_terminals", args.terminalId);
    if (!docId) throw new Error("Terminal not found.");

    const terminal = await ctx.db.get(docId);
    if (!terminal) throw new Error("Terminal not found.");

    await ctx.db.patch(docId, {
      status: args.status,
      updatedAt: Date.now(),
    });

    return {
      status: "TOGGLED",
      terminalCode: terminal.terminalCode,
      previousStatus: terminal.status,
      newStatus: args.status,
    };
  },
});

/**
 * Deletes a merchant terminal.
 */
export const deleteMerchantTerminal = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    terminalId: v.string(),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const docId = ctx.db.normalizeId("merchant_terminals", args.terminalId);
    if (!docId) throw new Error("Terminal not found.");

    const terminal = await ctx.db.get(docId);
    if (!terminal) throw new Error("Terminal not found.");

    await ctx.db.delete(docId);
    return {
      status: "DELETED",
      terminalCode: terminal.terminalCode,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//  MODULE 3 — REAL-TIME FINANCIAL & USER DEMOGRAPHIC ANALYTICS
// ═══════════════════════════════════════════════════════════════════════

/**
 * Returns financial summary aggregates: gross volume, escrow locked,
 * P2P completed, and withdrawals. Scans bounded to 500 transactions.
 */
export const getFinancialSummary = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const transactions = await ctx.db
      .query("transactions")
      .order("desc")
      .take(500);

    let grossVolume = 0;
    let escrowLocked = 0;
    let p2pCompleted = 0;
    let withdrawalTotal = 0;
    let depositTotal = 0;
    let totalCount = 0;
    let completedCount = 0;
    let pendingCount = 0;
    let failedCount = 0;

    for (const tx of transactions) {
      const amount = tx.amount ?? 0;
      totalCount++;

      const txStatus = String(tx.status).toLowerCase();
      const txType = String(tx.type).toLowerCase();

      if (txStatus === "completed") {
        grossVolume += amount;
        completedCount++;

        if (txType === "p2p_transfer" || txType === "transfer") {
          p2pCompleted += amount;
        } else if (txType === "top_up" || txType === "payment") {
          depositTotal += amount;
        } else if (txType === "withdrawal" || txType === "payout") {
          withdrawalTotal += amount;
        }
      } else if (txType === "escrow_lock" || txStatus === "pending") {
        if (txType === "escrow_lock") {
          escrowLocked += amount;
        }
        pendingCount++;
      } else if (txStatus === "failed" || txStatus === "reversed" || txStatus === "disputed") {
        failedCount++;
      }
    }

    return {
      grossVolume,
      escrowLocked,
      p2pCompleted,
      depositTotal,
      withdrawalTotal,
      totalCount,
      completedCount,
      pendingCount,
      failedCount,
      currency: "SLE",
      scannedRecords: transactions.length,
    };
  },
});

/**
 * Returns user demographics: role distribution counts + gender distribution.
 * Scans bounded to 500 users.
 */
export const getUserDemographics = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const users = await ctx.db.query("users").take(500);

    const roleDistribution: Record<string, number> = {};
    const genderDistribution: Record<string, number> = {
      male: 0,
      female: 0,
      unspecified: 0,
    };
    let totalUsers = 0;
    let activeUsers = 0;
    let verifiedUsers = 0;
    const regionDistribution: Record<string, number> = {};

    for (const user of users) {
      totalUsers++;

      // Role counts
      const role = user.activeRole ?? user.role ?? "unknown";
      roleDistribution[role] = (roleDistribution[role] ?? 0) + 1;

      // Gender counts (treat undefined as unspecified per user decision)
      const gender = user.gender ?? "unspecified";
      genderDistribution[gender] = (genderDistribution[gender] ?? 0) + 1;

      // Active count
      if (user.isActive !== false) activeUsers++;

      // Verified count
      if (user.isVerified === true) verifiedUsers++;

      // Region distribution
      const region = user.region ?? "Unknown";
      regionDistribution[region] = (regionDistribution[region] ?? 0) + 1;
    }

    return {
      totalUsers,
      activeUsers,
      verifiedUsers,
      roleDistribution,
      genderDistribution,
      regionDistribution,
      scannedRecords: users.length,
    };
  },
});

/**
 * Returns transaction volume grouped by hour (last 7 days) and region.
 * Bounded scan of 500 transactions.
 */
export const getTransactionHeatmap = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;

    const transactions = await ctx.db
      .query("transactions")
      .order("desc")
      .take(500);

    // Filter to last 7 days
    const recentTx = transactions.filter(
      (tx) => tx._creationTime >= sevenDaysAgo
    );

    // Group by hour of day (0-23)
    const hourlyVolume: Record<number, { count: number; volume: number }> = {};
    for (let h = 0; h < 24; h++) {
      hourlyVolume[h] = { count: 0, volume: 0 };
    }

    // Group by day
    const dailyVolume: Record<string, { count: number; volume: number }> = {};

    for (const tx of recentTx) {
      const date = new Date(tx._creationTime);
      const hour = date.getUTCHours();
      const dayKey = date.toISOString().slice(0, 10); // "YYYY-MM-DD"

      hourlyVolume[hour].count++;
      hourlyVolume[hour].volume += tx.amount ?? 0;

      if (!dailyVolume[dayKey]) {
        dailyVolume[dayKey] = { count: 0, volume: 0 };
      }
      dailyVolume[dayKey].count++;
      dailyVolume[dayKey].volume += tx.amount ?? 0;
    }

    return {
      hourlyVolume,
      dailyVolume,
      totalRecentTransactions: recentTx.length,
      periodStart: sevenDaysAgo,
      periodEnd: Date.now(),
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//  MODULE 4 — USER PROFILE AUDITING, SESSION TRACKING & DEVICE LOGS
// ═══════════════════════════════════════════════════════════════════════

/**
 * Records a new user session at login. Called by the Flutter client
 * with device info when the user authenticates.
 */
export const recordUserSession = mutation({
  args: {
    userId: v.string(),
    sessionToken: v.string(),
    deviceModel: v.optional(v.string()),
    osVersion: v.optional(v.string()),
    appVersion: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userDocId = ctx.db.normalizeId("users", args.userId);
    if (!userDocId) throw new Error("User not found.");

    const user = await ctx.db.get(userDocId);
    if (!user) throw new Error("User not found.");

    const now = Date.now();

    // Deactivate any previous active sessions for this user
    const activeSessions = await ctx.db
      .query("user_sessions")
      .withIndex("by_userId_isActive", (q) =>
        q.eq("userId", userDocId).eq("isActive", true)
      )
      .take(10);

    for (const session of activeSessions) {
      await ctx.db.patch(session._id, {
        isActive: false,
        logoutAt: now,
      });
    }

    // Create new session record
    const sessionId = await ctx.db.insert("user_sessions", {
      userId: userDocId,
      sessionToken: args.sessionToken,
      deviceModel: args.deviceModel,
      osVersion: args.osVersion,
      appVersion: args.appVersion,
      isActive: true,
      loginAt: now,
      lastActiveAt: now,
    });

    return {
      sessionId: sessionId as string,
      status: "SESSION_RECORDED",
    };
  },
});

/**
 * Marks a user session as inactive (logout).
 */
export const endUserSession = mutation({
  args: {
    userId: v.string(),
    sessionToken: v.string(),
  },
  handler: async (ctx, args) => {
    const userDocId = ctx.db.normalizeId("users", args.userId);
    if (!userDocId) throw new Error("User not found.");

    const session = await ctx.db
      .query("user_sessions")
      .withIndex("by_sessionToken", (q) =>
        q.eq("sessionToken", args.sessionToken)
      )
      .first();

    if (!session) return { status: "NO_SESSION_FOUND" };

    await ctx.db.patch(session._id, {
      isActive: false,
      logoutAt: Date.now(),
    });

    return { status: "SESSION_ENDED" };
  },
});

/**
 * Returns paginated session history for a specific user (admin view).
 */
export const getUserSessionHistory = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    targetUserId: v.string(),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const targetDocId = ctx.db.normalizeId("users", args.targetUserId);
    if (!targetDocId) return [];

    const sessions = await ctx.db
      .query("user_sessions")
      .withIndex("by_userId", (q) => q.eq("userId", targetDocId))
      .order("desc")
      .take(20);

    return sessions.map((s) => ({
      id: s._id as string,
      sessionToken: s.sessionToken.slice(0, 8) + "****",
      deviceModel: s.deviceModel ?? "Unknown Device",
      osVersion: s.osVersion ?? "Unknown OS",
      appVersion: s.appVersion ?? "Unknown",
      isActive: s.isActive,
      loginAt: s.loginAt,
      logoutAt: s.logoutAt,
      lastActiveAt: s.lastActiveAt,
    }));
  },
});

/**
 * Extended admin user audit view: user details + sessions + transactions.
 */
export const getAdminUserAuditView = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    targetUserId: v.string(),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const targetDocId = ctx.db.normalizeId("users", args.targetUserId);
    if (!targetDocId) throw new Error("User not found.");

    const user = await ctx.db.get(targetDocId);
    if (!user) throw new Error("User not found.");

    // Get wallet balance
    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", targetDocId).eq("currency", "SLE")
      )
      .first();

    // Get recent sessions (last 10)
    const sessions = await ctx.db
      .query("user_sessions")
      .withIndex("by_userId", (q) => q.eq("userId", targetDocId))
      .order("desc")
      .take(10);

    // Get recent transactions (last 20)
    const userTransactions = await ctx.db
      .query("transactions")
      .withIndex("by_user", (q) => q.eq("userId", targetDocId))
      .order("desc")
      .take(20);

    return {
      profile: {
        id: user._id as string,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role,
        activeRole: user.activeRole,
        gender: user.gender ?? "unspecified",
        region: user.region,
        isVerified: user.isVerified,
        isActive: user.isActive,
        verificationStatus: user.verificationStatus,
        verificationBadge: user.verificationBadge,
        kycStatus: user.kycStatus,
        accountType: user.accountType,
        businessName: user.businessName,
        tinNumber: user.tinNumber,
        avatarUrl: user.avatarUrl,
        bio: user.bio,
        createdAt: user._creationTime,
        updatedAt: user.updatedAt,
      },
      wallet: wallet
        ? {
            availableBalance: wallet.availableBalance,
            escrowBalance: wallet.escrowBalance ?? 0,
            pendingBalance: wallet.pendingBalance,
            currency: wallet.currency,
          }
        : { availableBalance: 0, escrowBalance: 0, pendingBalance: 0, currency: "SLE" },
      sessions: sessions.map((s) => ({
        id: s._id as string,
        deviceModel: s.deviceModel ?? "Unknown Device",
        osVersion: s.osVersion ?? "Unknown OS",
        appVersion: s.appVersion ?? "Unknown",
        isActive: s.isActive,
        loginAt: s.loginAt,
        logoutAt: s.logoutAt,
        lastActiveAt: s.lastActiveAt,
      })),
      transactions: userTransactions.map((tx) => ({
        id: tx._id as string,
        type: tx.type,
        amount: tx.amount,
        currency: tx.currency,
        status: tx.status,
        description: tx.description,
        userId: tx.userId as string,
        counterpartyId: tx.counterpartyId ? (tx.counterpartyId as string) : undefined,
        createdAt: tx._creationTime,
      })),
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//  MODULE 5 — CONTACT REQUEST RELAY (Phone Privacy)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Buyer submits a contact request for a listing. No phone numbers are exchanged.
 */
export const submitContactRequest = mutation({
  args: {
    buyerId: v.string(),
    listingId: v.string(),
    listingType: v.union(v.literal("property"), v.literal("vehicle")),
    message: v.string(),
  },
  handler: async (ctx, args) => {
    const buyerDocId = ctx.db.normalizeId("users", args.buyerId);
    if (!buyerDocId) throw new Error("Buyer account not found.");

    const buyer = await ctx.db.get(buyerDocId);
    if (!buyer) throw new Error("Buyer account not found.");

    // Resolve the listing and its owner
    let sellerId: Id<"users"> | null = null;

    if (args.listingType === "property") {
      const propId = ctx.db.normalizeId("realEstateListings", args.listingId);
      if (!propId) throw new Error("Property listing not found.");
      const listing = await ctx.db.get(propId);
      if (!listing) throw new Error("Property listing not found.");
      sellerId = listing.ownerId;
    } else {
      const vehId = ctx.db.normalizeId("vehicleListings", args.listingId);
      if (!vehId) throw new Error("Vehicle listing not found.");
      const listing = await ctx.db.get(vehId);
      if (!listing) throw new Error("Vehicle listing not found.");
      sellerId = listing.ownerId;
    }

    if (!sellerId) throw new Error("Seller not found for this listing.");

    // Prevent duplicate pending requests from same buyer on same listing
    const existingPending = await ctx.db
      .query("contact_requests")
      .withIndex("by_buyerId", (q) => q.eq("buyerId", buyerDocId))
      .take(50);

    const duplicate = existingPending.find(
      (r) =>
        r.listingId === args.listingId &&
        r.status === "pending"
    );
    if (duplicate) {
      throw new Error(
        "You already have a pending contact request for this listing."
      );
    }

    const requestId = await ctx.db.insert("contact_requests", {
      buyerId: buyerDocId,
      sellerId,
      listingId: args.listingId,
      listingType: args.listingType,
      message: args.message,
      status: "pending",
      createdAt: Date.now(),
    });

    return {
      requestId: requestId as string,
      status: "SUBMITTED",
      message:
        "Your contact request has been sent to the seller. You will be notified when they respond.",
    };
  },
});

/**
 * Returns pending contact requests for a seller.
 */
export const getSellerContactRequests = query({
  args: {
    sellerId: v.string(),
    statusFilter: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const sellerDocId = ctx.db.normalizeId("users", args.sellerId);
    if (!sellerDocId) return [];

    let requests;
    if (
      args.statusFilter &&
      (args.statusFilter === "pending" ||
        args.statusFilter === "accepted" ||
        args.statusFilter === "declined")
    ) {
      requests = await ctx.db
        .query("contact_requests")
        .withIndex("by_sellerId_status", (q) =>
          q
            .eq("sellerId", sellerDocId)
            .eq("status", args.statusFilter as "pending" | "accepted" | "declined")
        )
        .order("desc")
        .take(30);
    } else {
      requests = await ctx.db
        .query("contact_requests")
        .withIndex("by_sellerId", (q) => q.eq("sellerId", sellerDocId))
        .order("desc")
        .take(30);
    }

    // Hydrate buyer info (name only, no phone)
    const results = [];
    for (const req of requests) {
      const buyer = await ctx.db.get(req.buyerId);
      results.push({
        id: req._id as string,
        buyerName: buyer?.name ?? "Unknown",
        buyerAvatarUrl: buyer?.avatarUrl,
        buyerIsVerified: buyer?.isVerified ?? false,
        listingId: req.listingId,
        listingType: req.listingType,
        message: req.message,
        status: req.status,
        createdAt: req.createdAt,
        respondedAt: req.respondedAt,
      });
    }

    return results;
  },
});

/**
 * Seller responds to a contact request (accept/decline).
 * On accept, the seller's phone is revealed to the buyer.
 */
export const respondToContactRequest = mutation({
  args: {
    sellerId: v.string(),
    requestId: v.string(),
    action: v.union(v.literal("accepted"), v.literal("declined")),
  },
  handler: async (ctx, args) => {
    const sellerDocId = ctx.db.normalizeId("users", args.sellerId);
    if (!sellerDocId) throw new Error("Seller account not found.");

    const reqDocId = ctx.db.normalizeId("contact_requests", args.requestId);
    if (!reqDocId) throw new Error("Contact request not found.");

    const request = await ctx.db.get(reqDocId);
    if (!request) throw new Error("Contact request not found.");

    if (request.sellerId !== sellerDocId) {
      throw new Error("You are not the seller for this listing.");
    }
    if (request.status !== "pending") {
      throw new Error(`This request has already been ${request.status}.`);
    }

    await ctx.db.patch(reqDocId, {
      status: args.action,
      respondedAt: Date.now(),
    });

    // If accepted, return the seller's phone to be shown to the buyer
    let sellerPhone: string | null = null;
    if (args.action === "accepted") {
      const seller = await ctx.db.get(sellerDocId);
      sellerPhone = seller?.phone ?? null;
    }

    return {
      status: args.action === "accepted" ? "ACCEPTED" : "DECLINED",
      sellerPhone,
      message:
        args.action === "accepted"
          ? "Contact request accepted. The buyer can now see your phone number."
          : "Contact request declined.",
    };
  },
});
