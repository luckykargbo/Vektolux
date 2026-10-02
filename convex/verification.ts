// convex/verification.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Automated eIDV Initiation, Queries & Rate Limiting
// Multi-step identity verification supporting Sierra Leone NIN, ECOWAS, Passports.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query, internalMutation } from "./_generated/server";
import { v } from "convex/values";
import { idDocumentTypeEnum, verificationStatusEnum, verificationBadgeEnum } from "./schema";
import { requireSelf, resolveOptionalUser } from "./lib/auth";

const PEPPER = "VKT_EIDV_PEPPER_2026_SLE";
const MAX_ATTEMPTS_PER_24H = 3;

/**
 * SHA-256 salted hash generator for ID deduplication.
 */
async function computeSaltedHash(value: string): Promise<string> {
  const encoder = new TextEncoder();
  const normalized = value.trim().toUpperCase();
  const data = encoder.encode(`${PEPPER}:${normalized}`);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ─── INITIATE VERIFICATION CHECK ──────────────────────────────────────
export const initiateVerification = mutation({
  args: {
    userId: v.string(),
    sessionToken: v.string(),
    documentType: idDocumentTypeEnum,
    idNumber: v.string(), // Sanitized and hashed immediately
    ipAddress: v.optional(v.string()),
    deviceFingerprint: v.optional(v.string()),
  },
  returns: v.object({
    success: v.boolean(),
    checkId: v.string(),
    referenceId: v.string(),
    uploadToken: v.string(),
    errorMessage: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    const { userId, user } = await requireSelf(ctx, args.sessionToken, args.userId);
    if (!user) {
      throw new Error("Unauthorized session.");
    }

    // 1. Rate Limiting: Check attempts in last 24 hours
    const oneDayAgo = Date.now() - 24 * 60 * 60 * 1000;
    const recentAttempts = await ctx.db
      .query("identity_checks")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .filter((q) => q.gte(q.field("createdAt"), oneDayAgo))
      .collect();

    if (recentAttempts.length >= MAX_ATTEMPTS_PER_24H) {
      throw new Error(
        `Rate limit exceeded. Maximum ${MAX_ATTEMPTS_PER_24H} verification attempts per 24 hours. Please contact support.`
      );
    }

    // 2. Anti-Fraud Deduplication: Check if ID number hash is already bound to another verified user
    const idHash = await computeSaltedHash(args.idNumber);
    const existingCheck = await ctx.db
      .query("identity_checks")
      .withIndex("by_id_number_hash", (q) => q.eq("idNumberHash", idHash))
      .filter((q) => q.eq(q.field("status"), "verified"))
      .first();

    if (existingCheck && existingCheck.userId !== userId) {
      throw new Error(
        "This identity document is already registered and verified on an existing Vektolux account. Multiple accounts with the same ID are prohibited."
      );
    }

    // 3. Create Identity Check Record
    const referenceId = `vkt_idv_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`;
    const checkId = await ctx.db.insert("identity_checks", {
      userId,
      referenceId,
      documentType: args.documentType,
      idNumberHash: idHash,
      status: "pending",
      provider: "smile_id",
      attemptNumber: recentAttempts.length + 1,
      ipAddress: args.ipAddress,
      deviceFingerprintHash: args.deviceFingerprint
        ? await computeSaltedHash(args.deviceFingerprint)
        : undefined,
      createdAt: Date.now(),
    });

    // 4. Update User status to PENDING
    await ctx.db.patch(userId, {
      verificationStatus: "pending",
      verificationReferenceId: referenceId,
      updatedAt: Date.now(),
    });

    // 5. Log audit trail
    await ctx.db.insert("verifications_log", {
      idempotencyKey: `init_${referenceId}`,
      checkId,
      userId,
      event: "initiated",
      provider: "smile_id",
      signatureVerified: true,
      createdAt: Date.now(),
    });

    return {
      success: true,
      checkId: checkId as string,
      referenceId,
      uploadToken: `token_${referenceId}`,
    };
  },
});

// ─── SUBMIT AN ID FOR MANUAL REVIEW ───────────────────────────────────
// (Historical name: this approves NOTHING. It records a PENDING_REVIEW check; an administrator or the
// real eIDV provider webhook decides. It is kept under this name so existing app builds keep working.)
export const mockCompleteVerification = mutation({
  args: {
    userId: v.string(),
    sessionToken: v.string(),
    documentType: idDocumentTypeEnum,
    idNumber: v.string(),
  },
  returns: v.object({
    success: v.boolean(),
    status: v.string(),
    badge: v.string(),
    referenceId: v.string(),
  }),
  handler: async (ctx, args) => {
    const { userId, user } = await requireSelf(ctx, args.sessionToken, args.userId);
    if (!user) {
      throw new Error("Unauthorized session.");
    }

    const now = Date.now();
    const idHash = await computeSaltedHash(args.idNumber);
    const referenceId = `vkt_review_${now}_${Math.random().toString(36).substring(2, 8)}`;

    const checkId = await ctx.db.insert("identity_checks", {
      userId,
      referenceId,
      documentType: args.documentType,
      idNumberHash: idHash,
      status: "PENDING_REVIEW",
      provider: "manual_review",
      attemptNumber: 1,
      createdAt: now,
    });

    // NO automatic approval and NO badge: an administrator (admin.verifyUser) or the real eIDV
    // provider webhook decides. (This used to write fabricated liveness/face-match scores and a
    // GREEN_TICK for every caller.)
    await ctx.db.patch(userId, {
      verificationStatus: "pending",
      verificationReferenceId: referenceId,
      updatedAt: now,
    });

    await ctx.db.insert("verifications_log", {
      idempotencyKey: `review_${referenceId}`,
      checkId,
      userId,
      event: "submitted",
      provider: "manual_review",
      signatureVerified: false,
      rawResultCode: "SUBMITTED_FOR_REVIEW",
      diagnosticPayload: JSON.stringify({
        type: "manual_review_request",
        docType: args.documentType,
        timestamp: now,
      }),
      createdAt: now,
    });

    return {
      success: true,
      status: "pending",
      badge: "NONE",
      referenceId,
    };
  },
});

// ─── GET CURRENT USER VERIFICATION STATUS ─────────────────────────────
export const getVerificationStatus = query({
  args: { userId: v.string(), sessionToken: v.optional(v.string()) },
  returns: v.object({
    isVerified: v.boolean(),
    status: verificationStatusEnum,
    badge: verificationBadgeEnum,
    verifiedAt: v.optional(v.number()),
    rejectionReason: v.optional(v.string()),
    recentCheckId: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.userId);
    if (!userId) {
      return {
        isVerified: false,
        status: "unverified" as const,
        badge: "NONE" as const,
      };
    }
    const user = await ctx.db.get(userId);
    if (!user) {
      return {
        isVerified: false,
        status: "unverified" as const,
        badge: "NONE" as const,
      };
    }

    const isVerified = user.isVerified === true;
    const status = (user.verificationStatus as "unverified" | "pending" | "verified" | "rejected" | undefined) ??
      (isVerified ? ("verified" as const) : ("unverified" as const));
    const badge = (user.verificationBadge as "NONE" | "GREEN_TICK" | undefined) ??
      (isVerified ? ("GREEN_TICK" as const) : ("NONE" as const));

    return {
      isVerified,
      status,
      badge,
      verifiedAt: user.verifiedAt,
      // the rejection reason is private to the user
      rejectionReason: (await resolveOptionalUser(ctx, { sessionToken: args.sessionToken }))?.userId === user._id ? user.rejectionReason : undefined,
    };
  },
});

// ─── INTERNAL ATOMIC MUTATION: TRANSITION STATUS ON WEBHOOK ───────────
export const applyWebhookTransition = internalMutation({
  args: {
    referenceId: v.string(),
    idempotencyKey: v.string(),
    provider: v.string(),
    isApproved: v.boolean(),
    livenessScore: v.optional(v.number()),
    faceMatchScore: v.optional(v.number()),
    mrzValidated: v.optional(v.boolean()),
    tamperingPassed: v.optional(v.boolean()),
    rejectionReason: v.optional(v.string()),
    rawResultCode: v.optional(v.string()),
    diagnosticPayload: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // 1. Idempotency Check
    const existingLog = await ctx.db
      .query("verifications_log")
      .withIndex("by_idempotency_key", (q) => q.eq("idempotencyKey", args.idempotencyKey))
      .first();

    if (existingLog) {
      return { processed: true, alreadyHandled: true };
    }

    // 2. Find Identity Check
    const check = await ctx.db
      .query("identity_checks")
      .withIndex("by_reference", (q) => q.eq("referenceId", args.referenceId))
      .first();

    if (!check) {
      throw new Error(`Identity check not found for referenceId: ${args.referenceId}`);
    }

    const newStatus = args.isApproved ? "verified" : "rejected";
    const now = Date.now();

    // 3. Update Identity Check
    await ctx.db.patch(check._id, {
      status: newStatus,
      livenessScore: args.livenessScore,
      faceMatchScore: args.faceMatchScore,
      mrzValidated: args.mrzValidated,
      tamperingPassed: args.tamperingPassed,
      rejectionReason: args.rejectionReason,
      completedAt: now,
    });

    // 4. Update User Profile
    await ctx.db.patch(check.userId, {
      isVerified: args.isApproved,
      verificationStatus: newStatus,
      verificationBadge: args.isApproved ? "GREEN_TICK" : "NONE",
      verifiedAt: args.isApproved ? now : undefined,
      rejectionReason: args.rejectionReason,
      updatedAt: now,
    });

    // 5. Append Immutable Audit Log
    await ctx.db.insert("verifications_log", {
      idempotencyKey: args.idempotencyKey,
      checkId: check._id,
      userId: check.userId,
      event: args.isApproved ? "approved" : "rejected",
      provider: args.provider,
      signatureVerified: true,
      rawResultCode: args.rawResultCode,
      diagnosticPayload: args.diagnosticPayload,
      createdAt: now,
    });

    return { processed: true, alreadyHandled: false, status: newStatus };
  },
});
