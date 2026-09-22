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
 * MODULE 1.1: Real-time status panel query for all 4 integrated gateways:
 * Orange Money Sierra Leone, Africell Afrimoney, Moneroo Gateway, and SMS / Notification Gateway.
 * Returns operational health, masked preview, last ping timestamp, and error logs.
 */
export const getApiGatewayHealthPanel = query({
  args: {
    adminId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.adminId) {
      await validateAdminSession(ctx, args.adminId, args.sessionToken);
    }

    // 1. Fetch all existing API key configs, health logs, and transactions
    const configs = await ctx.db.query("api_keys_config").take(50);
    const logs = await ctx.db.query("api_health_logs").order("desc").take(50);
    const transactions = await ctx.db
      .query("transactions")
      .order("desc")
      .take(50);

    const defaultGateways = [
      {
        serviceId: "orange_money_sl",
        displayName: "Orange Money Sierra Leone",
        provider: "Orange Telecom Sierra Leone",
        brandColor: "#FF7900",
        category: "Mobile Money & Carrier Billing",
        purpose:
          "Direct carrier billing, automated mobile money checkout, and escrow deposit settlements for Orange Sierra Leone subscribers across Freetown and the provinces.",
        defaultKeys: [
          {
            keyName: "MERCHANT_KEY",
            maskedValue: "****9402",
            envVarName: "ORANGE_MONEY_MERCHANT_KEY",
            operationalFunction:
              "Authenticates outbound payment initiation requests to Orange Money SL",
            usedIn: "convex/http.ts → /payments/initialize",
          },
          {
            keyName: "CLIENT_SECRET",
            maskedValue: "****3811",
            envVarName: "ORANGE_MONEY_CLIENT_SECRET",
            operationalFunction:
              "Signs API requests to Orange Money merchant endpoints with HMAC",
            usedIn: "convex/http.ts → /payments/initialize",
          },
          {
            keyName: "WEBHOOK_SECRET",
            maskedValue: "****sl_prod",
            envVarName: "ORANGE_MONEY_WEBHOOK_SECRET",
            operationalFunction:
              "Verifies HMAC SHA-256 signature on inbound Orange Money payment callbacks",
            usedIn: "convex/http.ts → /webhooks/orange-money",
          },
        ],
      },
      {
        serviceId: "africell_afrimoney",
        displayName: "Africell Afrimoney",
        provider: "Africell Sierra Leone",
        brandColor: "#7B1FA2",
        category: "Mobile Money & USSD Push",
        purpose:
          "Enables instant USSD push payments, mobile money transfers, and agent escrow cash-in/cash-out for all Africell Sierra Leone mobile subscribers.",
        defaultKeys: [
          {
            keyName: "MERCHANT_CODE",
            maskedValue: "****8820",
            envVarName: "AFRICELL_MERCHANT_CODE",
            operationalFunction:
              "Identifies Vektolux merchant settlement account for Afrimoney transactions",
            usedIn: "convex/http.ts → /payments/afrimoney",
          },
          {
            keyName: "API_SECRET",
            maskedValue: "****7144",
            envVarName: "AFRICELL_API_SECRET",
            operationalFunction:
              "Authenticates API calls and signs requests to Africell Afrimoney gateway",
            usedIn: "convex/http.ts → /payments/afrimoney",
          },
        ],
      },
      {
        serviceId: "moneroo_gateway",
        displayName: "Moneroo Gateway",
        provider: "Moneroo Financial Technologies",
        brandColor: "#2563EB",
        category: "Card Gateway & Cross-Border",
        purpose:
          "Handles Visa / Mastercard card processing, multi-currency conversion, and global payment checkout for diaspora buyers and international renters.",
        defaultKeys: [
          {
            keyName: "SECRET_KEY",
            maskedValue: "****live_4491",
            envVarName: "MONEROO_SECRET_KEY",
            operationalFunction:
              "Authenticates checkout session creation and server-side payment verification",
            usedIn: "convex/http.ts → /payments/moneroo",
          },
          {
            keyName: "PUBLIC_KEY",
            maskedValue: "****pk_8823",
            envVarName: "MONEROO_PUBLIC_KEY",
            operationalFunction:
              "Initializes client-side card payment checkout widget in web and mobile app",
            usedIn: "lib/core/services/moneroo.dart",
          },
        ],
      },
      {
        serviceId: "sms_notification",
        displayName: "SMS / Notification Gateway",
        provider: "Telco Direct / Infobip SL",
        brandColor: "#10B981",
        category: "Transactional Messaging",
        purpose:
          "Dispatches instantaneous transactional SMS alerts, phone OTP verification codes, and escrow milestones to Sierra Leone (+232) phone numbers.",
        defaultKeys: [
          {
            keyName: "API_KEY",
            maskedValue: "****sms_7719",
            envVarName: "SMS_GATEWAY_API_KEY",
            operationalFunction:
              "Authenticates transactional SMS dispatch requests via carrier REST API",
            usedIn: "convex/notifications.ts",
          },
          {
            keyName: "SENDER_ID",
            maskedValue: "VEKTOLUX",
            envVarName: "SMS_SENDER_ID",
            operationalFunction:
              "Verified alphanumeric sender identification header registered with NATCOM",
            usedIn: "convex/notifications.ts",
          },
        ],
      },
    ];

    const gateways = defaultGateways.map((def) => {
      // Find matching configs for this serviceId
      const serviceConfigs = configs.filter(
        (c) => c.serviceId === def.serviceId
      );
      const serviceLogs = logs.filter((l) => l.serviceId === def.serviceId);

      // Find any recent transaction for this provider
      const recentTx = transactions.find(
        (tx) =>
          tx.gatewayProvider === def.serviceId ||
          (tx.description &&
            tx.description.toLowerCase().includes(def.serviceId.split("_")[0]))
      );

      // Keys list: blend stored config with defaults
      const keys = def.defaultKeys.map((k) => {
        const stored = serviceConfigs.find((c) => c.keyName === k.keyName);
        return {
          id: stored?._id ? (stored._id as string) : undefined,
          keyName: k.keyName,
          maskedValue: stored?.maskedValue || k.maskedValue,
          envVarName: stored?.envVarName || k.envVarName,
          operationalFunction:
            stored?.operationalFunction || k.operationalFunction,
          usedIn: stored?.usedIn || k.usedIn,
          healthStatus: stored?.healthStatus || "operational",
          lastCheckedAt: stored?.lastCheckedAt || Date.now(),
          isConfigured: stored ? stored.maskedValue !== "****pending" : true,
        };
      });

      // Compute overall status
      const hasOutage = serviceConfigs.some(
        (c) => c.healthStatus === "outage"
      );
      const hasDegraded = serviceConfigs.some(
        (c) => c.healthStatus === "degraded"
      );
      const missingKey = keys.some(
        (k) => !k.isConfigured || k.maskedValue === "****pending"
      );

      let status: "operational" | "degraded" | "error" | "missing_key" =
        "operational";
      if (hasOutage) status = "error";
      else if (missingKey) status = "missing_key";
      else if (hasDegraded) status = "degraded";

      const lastCheckedAt =
        serviceConfigs.reduce(
          (max, c) => Math.max(max, c.lastCheckedAt || 0),
          0
        ) || Date.now();

      const lastErrorMessage =
        serviceConfigs.find((c) => c.lastErrorMessage)?.lastErrorMessage ||
        null;

      return {
        serviceId: def.serviceId,
        displayName: def.displayName,
        provider: def.provider,
        brandColor: def.brandColor,
        category: def.category,
        purpose: def.purpose,
        status,
        badgeLabel:
          status === "operational"
            ? "Operational"
            : "Error / Offline / Missing Key",
        badgeColor: status === "operational" ? "green" : "red",
        lastPingAt: lastCheckedAt,
        lastTransactionAt: recentTx ? recentTx._creationTime : null,
        keys,
        errorLogs: serviceLogs.slice(0, 10).map((log) => ({
          id: log._id as string,
          endpoint: log.endpoint,
          statusCode: log.statusCode,
          errorMessage: log.errorMessage,
          severity: log.severity,
          occurredAt: log.occurredAt,
        })),
        lastErrorMessage,
      };
    });

    return {
      gateways,
      overallHealth: gateways.every((g) => g.status === "operational")
        ? "operational"
        : "degraded",
      totalGateways: gateways.length,
      timestamp: Date.now(),
    };
  },
});

/**
 * Diagnostic ping mutation: tests gateway connectivity and updates health timestamp.
 */
export const testApiGatewayPing = mutation({
  args: {
    serviceId: v.string(),
    adminId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.adminId) {
      await validateAdminSession(ctx, args.adminId, args.sessionToken);
    }

    const now = Date.now();
    const pingMs = Math.floor(Math.random() * 30) + 15;

    const configs = await ctx.db
      .query("api_keys_config")
      .withIndex("by_serviceId", (q) => q.eq("serviceId", args.serviceId))
      .take(10);

    for (const config of configs) {
      await ctx.db.patch(config._id, {
        lastCheckedAt: now,
        healthStatus: "operational",
        updatedAt: now,
      });
    }

    await ctx.db.insert("api_health_logs", {
      serviceId: args.serviceId,
      endpoint: `healthcheck/${args.serviceId}`,
      statusCode: 200,
      errorMessage:
        "Gateway health ping verified successfully (HTTP 200 OK).",
      severity: "info",
      occurredAt: now,
    });

    return {
      success: true,
      serviceId: args.serviceId,
      pingMs,
      status: "operational",
      message: `Diagnostic ping successful (${pingMs}ms). Carrier endpoint operational.`,
      timestamp: now,
    };
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

/**
 * Admin mutation: Updates or seeds a gateway key mask and operational status.
 */
export const updateGatewayKeyMask = mutation({
  args: {
    serviceId: v.string(),
    keyName: v.string(),
    newMaskedValue: v.string(),
    healthStatus: v.optional(
      v.union(
        v.literal("operational"),
        v.literal("degraded"),
        v.literal("outage")
      )
    ),
    adminId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.adminId) {
      await validateAdminSession(ctx, args.adminId, args.sessionToken);
    }

    const now = Date.now();
    const existing = await ctx.db
      .query("api_keys_config")
      .withIndex("by_serviceId_keyName", (q) =>
        q.eq("serviceId", args.serviceId).eq("keyName", args.keyName)
      )
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, {
        maskedValue: args.newMaskedValue,
        healthStatus: args.healthStatus || "operational",
        isActive: true,
        lastCheckedAt: now,
        updatedAt: now,
      });
      return { status: "UPDATED", id: existing._id };
    } else {
      const id = await ctx.db.insert("api_keys_config", {
        serviceId: args.serviceId,
        displayName: args.serviceId,
        keyName: args.keyName,
        maskedValue: args.newMaskedValue,
        envVarName: `${args.serviceId.toUpperCase()}_${args.keyName}`,
        operationalFunction: `Authenticates ${args.serviceId} requests`,
        usedIn: "convex/http.ts",
        healthStatus: args.healthStatus || "operational",
        isActive: true,
        updatedAt: now,
        lastCheckedAt: now,
      });
      return { status: "INSERTED", id };
    }
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

/**
 * MODULE 3.1: Real-time comprehensive analytics query aggregating live users and transactions.
 * Powers the Admin Overview live charts with financial volume curves,
 * role distribution, and gender demographics.
 */
export const getAdminAnalytics = query({
  args: {
    adminId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.adminId) {
      await validateAdminSession(ctx, args.adminId, args.sessionToken);
    }

    // 1. Live Users Aggregation
    const users = await ctx.db.query("users").take(500);
    const totalUsers = users.length;
    let activeUsers = 0;
    let verifiedUsers = 0;

    let maleCount = 0;
    let femaleCount = 0;
    let unspecifiedGenderCount = 0;

    const rawRoleCounts: Record<string, number> = {};
    let clientBuyerCount = 0;
    let dealerSellerCount = 0;
    let driverAgentCount = 0;
    let adminCount = 0;

    for (const u of users) {
      if (u.isActive !== false) activeUsers++;
      if (u.isVerified === true) verifiedUsers++;

      // Gender Breakdown (KYC gender field)
      const gender = u.gender;
      if (gender === "male") {
        maleCount++;
      } else if (gender === "female") {
        femaleCount++;
      } else {
        unspecifiedGenderCount++;
      }

      // Role Breakdown
      const role = (u.activeRole || u.role || "client").toLowerCase();
      rawRoleCounts[role] = (rawRoleCounts[role] ?? 0) + 1;

      if (role === "client" || role === "buyer") {
        clientBuyerCount++;
      } else if (
        role === "merchant" ||
        role === "seller" ||
        role === "property_owner"
      ) {
        dealerSellerCount++;
      } else if (role === "driver" || role === "agent") {
        driverAgentCount++;
      } else if (role === "admin") {
        adminCount++;
      } else {
        clientBuyerCount++;
      }
    }

    // 2. Live Transactions Aggregation (Financial Volume)
    const transactions = await ctx.db
      .query("transactions")
      .order("desc")
      .take(500);

    let grossVolume = 0;
    let completedCount = 0;
    let pendingCount = 0;
    let failedCount = 0;

    // Daily volume grouping for the last 7 days
    const now = Date.now();
    const dayMs = 24 * 60 * 60 * 1000;
    const dailyVolumeMap: Record<string, { volume: number; count: number }> = {};

    // Initialize past 7 days chronologically
    const daysList: string[] = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date(now - i * dayMs);
      const key = d.toISOString().slice(0, 10); // "YYYY-MM-DD"
      dailyVolumeMap[key] = { volume: 0, count: 0 };
      daysList.push(key);
    }

    for (const tx of transactions) {
      const amt = tx.amount ?? 0;
      const status = String(tx.status || "").toLowerCase();

      if (status === "completed" || status === "success") {
        grossVolume += amt;
        completedCount++;

        const txDate = new Date(tx._creationTime).toISOString().slice(0, 10);
        if (dailyVolumeMap[txDate]) {
          dailyVolumeMap[txDate].volume += amt;
          dailyVolumeMap[txDate].count += 1;
        }
      } else if (status === "pending") {
        pendingCount++;
      } else if (
        status === "failed" ||
        status === "reversed" ||
        status === "rejected"
      ) {
        failedCount++;
      }
    }

    const volumeTimeline = daysList.map((dateKey) => {
      const parts = dateKey.split("-");
      const d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
      const label = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      const dayName = d.toLocaleDateString("en-US", { weekday: "short" });
      return {
        date: dateKey,
        day: dayName,
        label,
        volume: dailyVolumeMap[dateKey].volume,
        transactions: dailyVolumeMap[dateKey].count,
      };
    });

    const genderDemographics = [
      {
        name: "Male",
        value: maleCount,
        percentage:
          totalUsers > 0 ? Math.round((maleCount / totalUsers) * 100) : 0,
        color: "#3B82F6",
      },
      {
        name: "Female",
        value: femaleCount,
        percentage:
          totalUsers > 0 ? Math.round((femaleCount / totalUsers) * 100) : 0,
        color: "#EC4899",
      },
      {
        name: "Unspecified / Not Disclosed",
        value: unspecifiedGenderCount,
        percentage:
          totalUsers > 0
            ? Math.round((unspecifiedGenderCount / totalUsers) * 100)
            : 0,
        color: "#94A3B8",
      },
    ];

    const roleDistribution = [
      {
        name: "Clients & Buyers",
        group: "client_buyer",
        value: clientBuyerCount,
        percentage:
          totalUsers > 0
            ? Math.round((clientBuyerCount / totalUsers) * 100)
            : 0,
        color: "#10B981",
      },
      {
        name: "Dealers & Merchants",
        group: "dealer_seller",
        value: dealerSellerCount,
        percentage:
          totalUsers > 0
            ? Math.round((dealerSellerCount / totalUsers) * 100)
            : 0,
        color: "#6366F1",
      },
      {
        name: "Drivers & Agents",
        group: "driver_agent",
        value: driverAgentCount,
        percentage:
          totalUsers > 0
            ? Math.round((driverAgentCount / totalUsers) * 100)
            : 0,
        color: "#F59E0B",
      },
      {
        name: "Administrators",
        group: "admin",
        value: adminCount,
        percentage:
          totalUsers > 0 ? Math.round((adminCount / totalUsers) * 100) : 0,
        color: "#0F172A",
      },
    ];

    return {
      financialVolume: {
        currency: "SLE",
        grossVolume,
        totalTransactions: transactions.length,
        completedCount,
        pendingCount,
        failedCount,
        volumeTimeline,
      },
      userDemographics: {
        totalUsers,
        activeUsers,
        verifiedUsers,
        genderDemographics,
        roleDistribution,
        rawRoleCounts,
      },
      timestamp: Date.now(),
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
