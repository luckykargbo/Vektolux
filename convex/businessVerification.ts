// convex/businessVerification.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Manual Business Verification Pipeline & Admin Queue
// Real estate agent onboarding, document proof storage, admin approvals/rejections
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { accountTypeEnum, idTypeEnum } from "./schema";
import { requireAdminSession, requireSelf } from "./lib/auth";
import { markPrivateFile, validateUpload } from "./lib/uploads";

// ═══════════════════════════════════════════════════════════════════════
//                     GENERATE UPLOAD URL (STORAGE)
// ═══════════════════════════════════════════════════════════════════════

// (businessVerification:generateUploadUrl removed — unused and unauthenticated; see files.ts.)


// ═══════════════════════════════════════════════════════════════════════
//            SUBMIT TIERED VENDOR VERIFICATION & BIOMETRICS
// ═══════════════════════════════════════════════════════════════════════

export const submitTieredVerification = mutation({
  args: {
    userId: v.string(),
    sessionToken: v.optional(v.string()),
    accountType: accountTypeEnum,
    idType: idTypeEnum,
    idNumber: v.string(),
    idPhotoStorageId: v.id("_storage"),
    selfieStorageId: v.id("_storage"),
    businessName: v.optional(v.string()),
    tin: v.optional(v.string()),
    // Accepted (older app builds send them) but IGNORED: no liveness / face-match check runs on the
    // device, and a client-asserted result can never decide identity verification.
    livenessScore: v.optional(v.number()),
    faceMatchScore: v.optional(v.number()),
    livenessPassed: v.optional(v.boolean()),
    faceMatchPassed: v.optional(v.boolean()),
  },
  returns: v.object({
    success: v.boolean(),
    status: v.string(),
    errorMessage: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    // The caller must be this user (valid, unexpired session). No session = no access.
    const { userId: userDocId, user } = await requireSelf(ctx, args.sessionToken, args.userId);
    if (!user.isActive) {
      return { success: false, status: "REJECTED", errorMessage: "User account is invalid or inactive." };
    }

    // 1. Validate Business tier requirements
    if (args.accountType === "BUSINESS") {
      if (!args.businessName || !args.businessName.trim()) {
        return { success: false, status: "REJECTED", errorMessage: "Registered business name is required for company verification." };
      }
      if (!args.tin || !args.tin.trim()) {
        return { success: false, status: "REJECTED", errorMessage: "Tax Identification Number (TIN) is required for company verification." };
      }
    }

    // 2. Validate the uploaded files (image/PDF, size) and keep them PRIVATE
    for (const sid of [args.idPhotoStorageId, args.selfieStorageId]) {
      const check = await validateUpload(ctx, sid);
      if (!check.ok) return { success: false, status: "REJECTED", errorMessage: check.reason };
    }
    await markPrivateFile(ctx, args.idPhotoStorageId, "identity_document", userDocId);
    await markPrivateFile(ctx, args.selfieStorageId, "selfie", userDocId);
    const idPhotoUrl = (await ctx.storage.getUrl(args.idPhotoStorageId)) ?? "";
    const selfieUrl = (await ctx.storage.getUrl(args.selfieStorageId)) ?? "";
    const now = Date.now();

    // 3. Every submission goes to MANUAL review (PENDING_REVIEW); an administrator decides.
    const cleanBusinessName = args.accountType === "BUSINESS" ? args.businessName?.trim() : undefined;
    const cleanTin = args.accountType === "BUSINESS" ? args.tin?.trim() : undefined;

    await ctx.db.patch(userDocId, {
      accountType: args.accountType,
      idType: args.idType,
      idNumber: args.idNumber.trim(),
      idPhotoUrl,
      idPhotoStorageId: args.idPhotoStorageId,
      selfieUrl,
      selfieStorageId: args.selfieStorageId,
      documentUrl: idPhotoUrl,
      documentStorageId: args.idPhotoStorageId,
      businessName: cleanBusinessName,
      tin: cleanTin,
      tinNumber: cleanTin,
      verificationStatus: "PENDING_REVIEW",
      isVerified: false,
      rejectionReason: undefined,
      updatedAt: now,
    });

    // 5. Update or create merchant_profile
    const existingMerchantProfile = await ctx.db
      .query("merchant_profiles")
      .withIndex("by_user", (q) => q.eq("userId", userDocId))
      .first();

    if (existingMerchantProfile) {
      await ctx.db.patch(existingMerchantProfile._id, {
        businessName: cleanBusinessName,
        tinNumber: cleanTin,
        documentUrl: idPhotoUrl,
        verificationStatus: "pending",
        reviewNotes: undefined,
        updatedAt: now,
      });
    } else if (user.role === "agent" || user.role === "merchant" || args.accountType === "BUSINESS") {
      await ctx.db.insert("merchant_profiles", {
        userId: userDocId,
        businessName: cleanBusinessName,
        tinNumber: cleanTin,
        documentUrl: idPhotoUrl,
        verificationStatus: "pending",
        updatedAt: now,
      });
    }

    return {
      success: true,
      status: "PENDING_REVIEW",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     SUBMIT AGENT VERIFICATION
// ═══════════════════════════════════════════════════════════════════════

export const submitAgentVerification = mutation({
  args: {
    userId: v.string(),
    sessionToken: v.optional(v.string()),
    businessName: v.string(),
    tinNumber: v.string(),
    documentStorageId: v.id("_storage"),
  },
  returns: v.object({
    success: v.boolean(),
    errorMessage: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    // The caller must be this user (valid, unexpired session). No session = no access.
    const { userId: userDocId, user } = await requireSelf(ctx, args.sessionToken, args.userId);
    if (!user.isActive) {
      return { success: false, errorMessage: "User account is invalid or inactive." };
    }

    if (!args.businessName || !args.businessName.trim()) {
      return { success: false, errorMessage: "Business name is required." };
    }
    if (!args.tinNumber || !args.tinNumber.trim()) {
      return { success: false, errorMessage: "Tax Identification Number (TIN) is required." };
    }

    const docCheck = await validateUpload(ctx, args.documentStorageId);
    if (!docCheck.ok) return { success: false, errorMessage: docCheck.reason };
    await markPrivateFile(ctx, args.documentStorageId, "business_document", userDocId);
    const resolvedDocumentUrl = (await ctx.storage.getUrl(args.documentStorageId)) ?? "";
    const now = Date.now();

    // 1. Update user record: set to pending, reset rejection reason
    await ctx.db.patch(userDocId, {
      businessName: args.businessName.trim(),
      tinNumber: args.tinNumber.trim(),
      documentStorageId: args.documentStorageId,
      documentUrl: resolvedDocumentUrl,
      verificationStatus: "pending",
      isVerified: false,
      rejectionReason: undefined,
      updatedAt: now,
    });

    // 2. Update merchant profile if exists, or create
    const existingMerchantProfile = await ctx.db
      .query("merchant_profiles")
      .withIndex("by_user", (q) => q.eq("userId", userDocId))
      .first();

    if (existingMerchantProfile) {
      await ctx.db.patch(existingMerchantProfile._id, {
        businessName: args.businessName.trim(),
        tinNumber: args.tinNumber.trim(),
        documentUrl: resolvedDocumentUrl,
        verificationStatus: "pending",
        reviewNotes: undefined,
        updatedAt: now,
      });
    } else {
      await ctx.db.insert("merchant_profiles", {
        userId: userDocId,
        businessName: args.businessName.trim(),
        tinNumber: args.tinNumber.trim(),
        documentUrl: resolvedDocumentUrl,
        verificationStatus: "pending",
        updatedAt: now,
      });
    }

    // 3. Record in role_applications for operational audits
    const existingRoleApp = await ctx.db
      .query("role_applications")
      .withIndex("by_user", (q) => q.eq("userId", userDocId))
      .filter((q) => q.eq(q.field("targetRole"), "agent"))
      .first();

    if (existingRoleApp) {
      await ctx.db.patch(existingRoleApp._id, {
        businessName: args.businessName.trim(),
        tinNumber: args.tinNumber.trim(),
        documentUrls: [resolvedDocumentUrl],
        status: "pending",
        reviewNotes: undefined,
        updatedAt: now,
      });
    } else {
      await ctx.db.insert("role_applications", {
        userId: userDocId,
        targetRole: "agent",
        businessName: args.businessName.trim(),
        tinNumber: args.tinNumber.trim(),
        documentUrls: [resolvedDocumentUrl],
        status: "pending",
        updatedAt: now,
      });
    }

    return { success: true };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     GET MY VERIFICATION STATUS (AGENT)
// ═══════════════════════════════════════════════════════════════════════

export const getMyVerificationStatus = query({
  args: {
    userId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { user } = await requireSelf(ctx, args.sessionToken, args.userId);

    let resolvedDocumentUrl = user.documentUrl;
    if (!resolvedDocumentUrl && user.documentStorageId) {
      resolvedDocumentUrl = (await ctx.storage.getUrl(user.documentStorageId)) ?? undefined;
    }

    return {
      userId: user._id as string,
      role: user.role,
      verificationStatus: user.verificationStatus ?? (user.isVerified ? "verified" : "unverified"),
      isVerified: user.isVerified === true,
      businessName: user.businessName,
      tinNumber: user.tinNumber,
      documentUrl: resolvedDocumentUrl,
      rejectionReason: user.rejectionReason,
      verifiedAt: user.verifiedAt,
      updatedAt: user.updatedAt,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     GET VERIFICATION QUEUE (ADMIN)
// ═══════════════════════════════════════════════════════════════════════

export const getVerificationQueue = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    statusFilter: v.optional(
      v.union(
        v.literal("pending"),
        v.literal("approved"),
        v.literal("rejected"),
        v.literal("all")
      )
    ),
  },
  handler: async (ctx, args) => {
    // Administrator session required; a client-supplied adminId is never trusted.
    const { userId: adminDocId } = await requireAdminSession(ctx, args.sessionToken);

    // 2. Fetch users based on filter
    const filter = args.statusFilter ?? "pending";

    const allUsers = await ctx.db.query("users").take(200);

    const filtered = allUsers.filter((u) => {
      const status = (u.verificationStatus as string | undefined) ?? (u.isVerified ? "approved" : "unverified");
      const normStatus = status.toLowerCase();

      // Check if user submitted any verification artifacts
      const hasSubmission = Boolean(
        u.idPhotoStorageId ||
        u.selfieStorageId ||
        u.documentStorageId ||
        u.documentUrl ||
        u.idPhotoUrl ||
        u.selfieUrl ||
        u.tinNumber ||
        u.tin ||
        u.businessName ||
        u.accountType
      );

      if (filter === "all") {
        return hasSubmission || u.role === "agent" || u.role === "merchant";
      }
      if (filter === "pending") {
        return (normStatus === "pending" || normStatus === "pending_review") && hasSubmission;
      }
      if (filter === "approved") {
        return (normStatus === "approved" || normStatus === "verified") && hasSubmission;
      }
      if (filter === "rejected") {
        return normStatus === "rejected";
      }
      return false;
    });

    // Resolve documents and selfies into signed URLs for admin review
    const results = await Promise.all(
      filtered.map(async (u) => {
        let idPhotoUrl: string | undefined = undefined;
        if (u.idPhotoStorageId) {
          try {
            idPhotoUrl = (await ctx.storage.getUrl(u.idPhotoStorageId)) ?? undefined;
          } catch {}
        } else if (u.documentStorageId) {
          try {
            idPhotoUrl = (await ctx.storage.getUrl(u.documentStorageId)) ?? undefined;
          } catch {}
        }
        if (!idPhotoUrl) idPhotoUrl = u.idPhotoUrl || u.documentUrl;

        let selfieUrl: string | undefined = undefined;
        if (u.selfieStorageId) {
          try {
            selfieUrl = (await ctx.storage.getUrl(u.selfieStorageId)) ?? undefined;
          } catch {}
        }
        if (!selfieUrl) selfieUrl = u.selfieUrl;

        const isBusiness = u.accountType === "BUSINESS" || Boolean(u.tinNumber && u.tinNumber !== "N/A" && u.tinNumber.length > 2);
        const accountType = u.accountType ?? (isBusiness ? "BUSINESS" : "INDIVIDUAL");

        return {
          userId: u._id as string,
          name: u.name,
          email: u.email,
          phone: u.phone,
          accountType,
          idType: u.idType ?? (u.idDocumentType as any) ?? "NATIONAL_ID",
          idNumber: u.idNumber || "N/A",
          idPhotoUrl,
          selfieUrl,
          businessName: u.businessName || (accountType === "BUSINESS" ? "Registered Company" : "Individual Agent / Owner"),
          tin: u.tin || u.tinNumber || "N/A",
          tinNumber: u.tinNumber || u.tin || "N/A",
          documentUrl: idPhotoUrl,
          documentStorageId: u.idPhotoStorageId ? (u.idPhotoStorageId as string) : (u.documentStorageId ? (u.documentStorageId as string) : undefined),
          verificationStatus: u.verificationStatus ?? (u.isVerified ? "approved" : "pending"),
          rejectionReason: u.rejectionReason,
          verifiedAt: u.verifiedAt,
          createdAt: u._creationTime,
          updatedAt: u.updatedAt,
        };
      })
    );

    return results;
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     APPROVE AGENT (ADMIN)
// ═══════════════════════════════════════════════════════════════════════

export const approveAgent = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    agentId: v.string(),
  },
  returns: v.object({
    success: v.boolean(),
    errorMessage: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    // Administrator session required; a client-supplied adminId is never trusted.
    const { userId: adminDocId } = await requireAdminSession(ctx, args.sessionToken);

    // 2. Fetch Agent
    const targetAgentId = ctx.db.normalizeId("users", args.agentId);
    if (!targetAgentId) {
      return { success: false, errorMessage: "Agent account not found." };
    }
    const agent = await ctx.db.get(targetAgentId);
    if (!agent) {
      return { success: false, errorMessage: "Agent not found." };
    }

    const now = Date.now();

    // 3. Identity (KYC) approval only. Business roles (agent, dealer, …) are approved separately
    //    through roles:adminDecideRoleApplication; professional badges also need a subscription.
    await ctx.db.patch(targetAgentId, {
      verificationStatus: "approved",
      verificationBadge: "GREEN_TICK",
      isVerified: true,
      verifiedAt: now,
      verifiedBy: adminDocId,
      rejectionReason: undefined,
      updatedAt: now,
    });

    // 4. Update merchant_profile if present
    const merchantProfile = await ctx.db
      .query("merchant_profiles")
      .withIndex("by_user", (q) => q.eq("userId", targetAgentId))
      .first();

    if (merchantProfile) {
      await ctx.db.patch(merchantProfile._id, {
        verificationStatus: "approved",
        verifiedAt: now,
        reviewNotes: undefined,
        updatedAt: now,
      });
    }

    // 5. Audit trail (who decided what, when)
    await ctx.db.insert("audit_logs", {
      adminUserId: adminDocId,
      action: "VERIFICATION_DECISION",
      targetTransactionId: targetAgentId as string,
      snapshot: JSON.stringify({ decision: "identity_approved" }),
      timestamp: now,
    });

    return { success: true };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     REJECT AGENT (ADMIN)
// ═══════════════════════════════════════════════════════════════════════

export const rejectAgent = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    agentId: v.string(),
    reason: v.string(),
  },
  returns: v.object({
    success: v.boolean(),
    errorMessage: v.optional(v.string()),
  }),
  handler: async (ctx, args) => {
    // Administrator session required; a client-supplied adminId is never trusted.
    const { userId: adminDocId } = await requireAdminSession(ctx, args.sessionToken);

    if (!args.reason || !args.reason.trim()) {
      return { success: false, errorMessage: "A rejection reason is required." };
    }

    // 2. Fetch Agent
    const targetAgentId = ctx.db.normalizeId("users", args.agentId);
    if (!targetAgentId) {
      return { success: false, errorMessage: "Agent account not found." };
    }
    const agent = await ctx.db.get(targetAgentId);
    if (!agent) {
      return { success: false, errorMessage: "Agent not found." };
    }

    const now = Date.now();

    // 3. Set rejected status with mandatory reason
    await ctx.db.patch(targetAgentId, {
      verificationStatus: "rejected",
      isVerified: false,
      verificationBadge: "NONE",
      rejectionReason: args.reason.trim(),
      verifiedAt: undefined,
      updatedAt: now,
    });

    // 4. Update merchant_profile if present
    const merchantProfile = await ctx.db
      .query("merchant_profiles")
      .withIndex("by_user", (q) => q.eq("userId", targetAgentId))
      .first();

    if (merchantProfile) {
      await ctx.db.patch(merchantProfile._id, {
        verificationStatus: "rejected",
        reviewNotes: args.reason.trim(),
        updatedAt: now,
      });
    }

    // 5. Audit trail (who decided what, when)
    await ctx.db.insert("audit_logs", {
      adminUserId: adminDocId,
      action: "VERIFICATION_DECISION",
      targetTransactionId: targetAgentId as string,
      snapshot: JSON.stringify({ decision: "identity_rejected", reason: args.reason.trim() }),
      timestamp: now,
    });

    return { success: true };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//               GET SIGNED DOCUMENT URL (ADMIN PREVIEW)
// ═══════════════════════════════════════════════════════════════════════

export const getSignedDocumentUrl = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    storageId: v.id("_storage"),
  },
  handler: async (ctx, args) => {
    // Administrator session required; a client-supplied adminId is never trusted.
    const { userId: adminDocId } = await requireAdminSession(ctx, args.sessionToken);

    return await ctx.storage.getUrl(args.storageId);
  },
});
