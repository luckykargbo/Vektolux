// convex/agentVerification.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Agent & Dealer Verification Pipeline Backend
// Handles multi-step KYC submission, document reviews, fraud flags,
// admin approval/rejection queues, and verification badge activation.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";

// ═══════════════════════════════════════════════════════════════════════
// 1. SUBMIT VERIFICATION APPLICATION (Mobile Client)
// ═══════════════════════════════════════════════════════════════════════

export const submitVerification = mutation({
  args: {
    userId: v.id("users"),
    roleCategory: v.string(), // "real_estate_agent" | "vehicle_dealer" | "dual"
    businessName: v.string(),
    tinNumber: v.optional(v.string()),
    officeAddress: v.string(),
    officeCity: v.string(),
    officeCoordinates: v.optional(
      v.object({
        lat: v.number(),
        lng: v.number(),
      })
    ),
    publicPhone: v.string(),
    publicWhatsApp: v.optional(v.string()),
    documents: v.array(
      v.object({
        documentType: v.string(),
        fileUrl: v.string(),
        fileStorageId: v.optional(v.id("_storage")),
        fileMimeType: v.string(),
        fileSizeBytes: v.number(),
      })
    ),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user) {
      throw new Error("User does not exist.");
    }

    const now = Date.now();

    // 1. Upsert Agent Profile
    let agentProfile = await ctx.db
      .query("agent_profiles")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .first();

    let agentProfileId: Id<"agent_profiles">;
    if (agentProfile) {
      await ctx.db.patch(agentProfile._id, {
        businessName: args.businessName,
        businessType: args.roleCategory,
        tinNumber: args.tinNumber,
        officeAddress: args.officeAddress,
        officeCity: args.officeCity,
        officeLatitude: args.officeCoordinates?.lat,
        officeLongitude: args.officeCoordinates?.lng,
        publicContactPhone: args.publicPhone,
        publicWhatsAppPhone: args.publicWhatsApp,
        updatedAt: now,
      });
      agentProfileId = agentProfile._id;
    } else {
      agentProfileId = await ctx.db.insert("agent_profiles", {
        userId: args.userId,
        businessName: args.businessName,
        businessType: args.roleCategory,
        tinNumber: args.tinNumber,
        officeAddress: args.officeAddress,
        officeCity: args.officeCity,
        officeLatitude: args.officeCoordinates?.lat,
        officeLongitude: args.officeCoordinates?.lng,
        publicContactPhone: args.publicPhone,
        publicWhatsAppPhone: args.publicWhatsApp,
        isVerified: false,
        allowDirectBuyerLeads: false,
        updatedAt: now,
      });
    }

    // 2. Check for existing pending/draft request
    const existingReq = await ctx.db
      .query("verification_requests")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .filter((q) =>
        q.or(
          q.eq(q.field("status"), "pending_review"),
          q.eq(q.field("status"), "action_required"),
          q.eq(q.field("status"), "draft")
        )
      )
      .first();

    let requestId: Id<"verification_requests">;
    if (existingReq) {
      await ctx.db.patch(existingReq._id, {
        agentProfileId,
        roleCategory: args.roleCategory,
        businessName: args.businessName,
        tinNumber: args.tinNumber,
        officeAddress: args.officeAddress,
        officeCity: args.officeCity,
        officeCoordinates: args.officeCoordinates,
        publicPhone: args.publicPhone,
        publicWhatsApp: args.publicWhatsApp,
        status: "pending_review",
        submittedAt: now,
        attemptCount: existingReq.attemptCount + 1,
        updatedAt: now,
      });
      requestId = existingReq._id;

      // Clean up previous documents for fresh re-submission
      const oldDocs = await ctx.db
        .query("verification_documents")
        .withIndex("by_verificationRequestId", (q) =>
          q.eq("verificationRequestId", requestId)
        )
        .collect();
      for (const d of oldDocs) {
        await ctx.db.delete(d._id);
      }
    } else {
      requestId = await ctx.db.insert("verification_requests", {
        userId: args.userId,
        agentProfileId,
        status: "pending_review",
        roleCategory: args.roleCategory,
        businessName: args.businessName,
        tinNumber: args.tinNumber,
        officeAddress: args.officeAddress,
        officeCity: args.officeCity,
        officeCoordinates: args.officeCoordinates,
        publicPhone: args.publicPhone,
        publicWhatsApp: args.publicWhatsApp,
        submittedAt: now,
        attemptCount: 1,
        createdAt: now,
        updatedAt: now,
      });
    }

    // 3. Insert Documents
    for (const doc of args.documents) {
      await ctx.db.insert("verification_documents", {
        verificationRequestId: requestId,
        documentType: doc.documentType,
        fileUrl: doc.fileUrl,
        fileStorageId: doc.fileStorageId,
        fileMimeType: doc.fileMimeType,
        fileSizeBytes: doc.fileSizeBytes,
        status: "pending",
        createdAt: now,
        updatedAt: now,
      });
    }

    // 4. Log Audit
    await ctx.db.insert("verification_audit_logs", {
      verificationRequestId: requestId,
      adminId: args.userId,
      action: "SUBMITTED",
      previousStatus: existingReq?.status ?? "draft",
      newStatus: "pending_review",
      note: "Application and KYC documents submitted by agent.",
      createdAt: now,
    });

    return {
      success: true,
      requestId,
      status: "pending_review",
      message: "Application submitted successfully. Compliance review turnaround is typically 4-24 hours.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 2. GET VERIFICATION STATUS (Mobile Client Tracker)
// ═══════════════════════════════════════════════════════════════════════

export const getVerificationStatus = query({
  args: {
    userId: v.id("users"),
  },
  handler: async (ctx, args) => {
    const request = await ctx.db
      .query("verification_requests")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .order("desc")
      .first();

    if (!request) {
      return {
        hasApplied: false,
        status: "unapplied",
        documents: [],
        agentProfile: null,
      };
    }

    const documents = await ctx.db
      .query("verification_documents")
      .withIndex("by_verificationRequestId", (q) =>
        q.eq("verificationRequestId", request._id)
      )
      .collect();

    let agentProfile = null;
    if (request.agentProfileId) {
      agentProfile = await ctx.db.get(request.agentProfileId);
    } else {
      agentProfile = await ctx.db
        .query("agent_profiles")
        .withIndex("by_userId", (q) => q.eq("userId", args.userId))
        .first();
    }

    return {
      hasApplied: true,
      requestId: request._id,
      status: request.status,
      roleCategory: request.roleCategory,
      businessName: request.businessName,
      tinNumber: request.tinNumber,
      submittedAt: request.submittedAt,
      reviewedAt: request.reviewedAt,
      reviewerNotes: request.reviewerNotes,
      rejectionReasons: request.rejectionReasons ?? [],
      documents: documents.map((d) => ({
        id: d._id,
        documentType: d.documentType,
        fileUrl: d.fileUrl,
        status: d.status,
        rejectionComment: d.rejectionComment,
      })),
      agentProfile: agentProfile
        ? {
            id: agentProfile._id,
            isVerified: agentProfile.isVerified,
            allowDirectBuyerLeads: agentProfile.allowDirectBuyerLeads,
            verifiedAt: agentProfile.verifiedAt,
          }
        : null,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 3. RE-UPLOAD REJECTED DOCUMENT (Mobile Action Required)
// ═══════════════════════════════════════════════════════════════════════

export const reuploadDocument = mutation({
  args: {
    documentId: v.id("verification_documents"),
    fileUrl: v.string(),
    fileStorageId: v.optional(v.id("_storage")),
    fileMimeType: v.string(),
    fileSizeBytes: v.number(),
  },
  handler: async (ctx, args) => {
    const doc = await ctx.db.get(args.documentId);
    if (!doc) throw new Error("Document not found.");

    const now = Date.now();
    await ctx.db.patch(args.documentId, {
      fileUrl: args.fileUrl,
      fileStorageId: args.fileStorageId,
      fileMimeType: args.fileMimeType,
      fileSizeBytes: args.fileSizeBytes,
      status: "pending",
      rejectionComment: undefined,
      updatedAt: now,
    });

    // Check if all rejected documents on this request are now re-uploaded
    const allDocs = await ctx.db
      .query("verification_documents")
      .withIndex("by_verificationRequestId", (q) =>
        q.eq("verificationRequestId", doc.verificationRequestId)
      )
      .collect();

    const stillRejected = allDocs.some((d) => d.status === "rejected");
    if (!stillRejected) {
      await ctx.db.patch(doc.verificationRequestId, {
        status: "pending_review",
        updatedAt: now,
      });
    }

    return {
      success: true,
      message: "Document re-uploaded successfully.",
      requestStatus: stillRejected ? "action_required" : "pending_review",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 4. ADMIN VERIFICATION QUEUE
// ═══════════════════════════════════════════════════════════════════════

export const adminGetVerificationQueue = query({
  args: {
    statusFilter: v.optional(
      v.union(
        v.literal("pending_review"),
        v.literal("action_required"),
        v.literal("approved_pending_payment"),
        v.literal("active"),
        v.literal("rejected"),
        v.literal("revoked")
      )
    ),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const max = args.limit ?? 25;
    const requests = await ctx.db
      .query("verification_requests")
      .order("desc")
      .take(max * 2);

    const filtered = requests.filter((r) => {
      if (args.statusFilter) return r.status === args.statusFilter;
      return r.status === "pending_review" || r.status === "action_required";
    });

    const queueItems = [];

    for (const req of filtered.slice(0, max)) {
      const user = await ctx.db.get(req.userId);
      const docs = await ctx.db
        .query("verification_documents")
        .withIndex("by_verificationRequestId", (q) =>
          q.eq("verificationRequestId", req._id)
        )
        .collect();

      // Duplicate Check (Fraud Detection Signal)
      let duplicateTinFound = false;
      if (req.tinNumber) {
        const matchingTin = await ctx.db
          .query("agent_profiles")
          .withIndex("by_tinNumber", (q) => q.eq("tinNumber", req.tinNumber))
          .filter((q) => q.neq(q.field("userId"), req.userId))
          .first();
        if (matchingTin) duplicateTinFound = true;
      }

      queueItems.push({
        id: req._id,
        userId: req.userId,
        applicantName: user?.name ?? "Unknown",
        applicantEmail: user?.email ?? "",
        applicantPhone: user?.phone ?? req.publicPhone,
        businessName: req.businessName,
        roleCategory: req.roleCategory,
        tinNumber: req.tinNumber,
        officeAddress: req.officeAddress,
        officeCity: req.officeCity,
        status: req.status,
        submittedAt: req.submittedAt,
        attemptCount: req.attemptCount,
        duplicateRiskFlag: duplicateTinFound,
        documentsCount: docs.length,
        documents: docs.map((d) => ({
          id: d._id,
          documentType: d.documentType,
          fileUrl: d.fileUrl,
          fileMimeType: d.fileMimeType,
          status: d.status,
          rejectionComment: d.rejectionComment,
        })),
      });
    }

    return {
      total: queueItems.length,
      queue: queueItems,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 5. ADMIN REVIEW DOCUMENT (Approve / Reject single doc)
// ═══════════════════════════════════════════════════════════════════════

export const adminReviewDocument = mutation({
  args: {
    documentId: v.id("verification_documents"),
    status: v.union(v.literal("approved"), v.literal("rejected")),
    rejectionComment: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const doc = await ctx.db.get(args.documentId);
    if (!doc) throw new Error("Document not found.");

    const now = Date.now();
    await ctx.db.patch(args.documentId, {
      status: args.status,
      rejectionComment: args.rejectionComment,
      reviewedAt: now,
      updatedAt: now,
    });

    return { success: true };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 6. ADMIN REQUEST ACTION (Action Required Re-upload)
// ═══════════════════════════════════════════════════════════════════════

export const adminRequestAction = mutation({
  args: {
    requestId: v.id("verification_requests"),
    adminUserId: v.id("users"),
    notes: v.string(),
    rejectedDocuments: v.array(
      v.object({
        documentId: v.id("verification_documents"),
        reason: v.string(),
      })
    ),
  },
  handler: async (ctx, args) => {
    const request = await ctx.db.get(args.requestId);
    if (!request) throw new Error("Request not found.");

    const now = Date.now();

    // Mark individual documents rejected
    for (const item of args.rejectedDocuments) {
      await ctx.db.patch(item.documentId, {
        status: "rejected",
        rejectionComment: item.reason,
        reviewedAt: now,
        updatedAt: now,
      });
    }

    await ctx.db.patch(args.requestId, {
      status: "action_required",
      reviewerUserId: args.adminUserId,
      reviewerNotes: args.notes,
      reviewedAt: now,
      updatedAt: now,
    });

    await ctx.db.insert("verification_audit_logs", {
      verificationRequestId: args.requestId,
      adminId: args.adminUserId,
      action: "MARKED_ACTION_REQUIRED",
      previousStatus: request.status,
      newStatus: "action_required",
      note: args.notes,
      createdAt: now,
    });

    return { success: true, status: "action_required" };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 7. ADMIN APPROVE APPLICATION (Unlocks Payment)
// ═══════════════════════════════════════════════════════════════════════

export const adminApproveApplication = mutation({
  args: {
    requestId: v.id("verification_requests"),
    adminUserId: v.id("users"),
    reviewerNotes: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const request = await ctx.db.get(args.requestId);
    if (!request) throw new Error("Request not found.");

    const now = Date.now();

    // Check all documents approved
    const docs = await ctx.db
      .query("verification_documents")
      .withIndex("by_verificationRequestId", (q) =>
        q.eq("verificationRequestId", args.requestId)
      )
      .collect();

    for (const d of docs) {
      if (d.status !== "approved") {
        await ctx.db.patch(d._id, {
          status: "approved",
          reviewedAt: now,
          updatedAt: now,
        });
      }
    }

    await ctx.db.patch(args.requestId, {
      status: "approved_pending_payment",
      reviewerUserId: args.adminUserId,
      reviewerNotes: args.reviewerNotes ?? "All credentials approved.",
      reviewedAt: now,
      updatedAt: now,
    });

    await ctx.db.insert("verification_audit_logs", {
      verificationRequestId: args.requestId,
      adminId: args.adminUserId,
      action: "APPROVED",
      previousStatus: request.status,
      newStatus: "approved_pending_payment",
      note: "Approved by admin. Ready for subscription activation.",
      createdAt: now,
    });

    return {
      success: true,
      status: "approved_pending_payment",
      message: "Application approved. Agent can now activate verified subscription badge.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 8. ADMIN REVOKE VERIFICATION
// ═══════════════════════════════════════════════════════════════════════

export const adminRevokeVerification = mutation({
  args: {
    agentProfileId: v.id("agent_profiles"),
    adminUserId: v.id("users"),
    reason: v.string(),
  },
  handler: async (ctx, args) => {
    const profile = await ctx.db.get(args.agentProfileId);
    if (!profile) throw new Error("Agent profile not found.");

    const now = Date.now();

    // 1. Strip Verified Status & Direct Leads
    await ctx.db.patch(args.agentProfileId, {
      isVerified: false,
      allowDirectBuyerLeads: false,
      verificationRevokedAt: now,
      updatedAt: now,
    });

    // 2. Find and update active verification request
    const activeReq = await ctx.db
      .query("verification_requests")
      .withIndex("by_userId", (q) => q.eq("userId", profile.userId))
      .filter((q) => q.eq(q.field("status"), "active"))
      .first();

    if (activeReq) {
      await ctx.db.patch(activeReq._id, {
        status: "revoked",
        reviewerNotes: args.reason,
        updatedAt: now,
      });

      await ctx.db.insert("verification_audit_logs", {
        verificationRequestId: activeReq._id,
        adminId: args.adminUserId,
        action: "REVOKED",
        previousStatus: "active",
        newStatus: "revoked",
        note: args.reason,
        createdAt: now,
      });
    }

    return {
      success: true,
      message: "Agent verification revoked. Listings reverted to masked concierge mode.",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
// 9. ACTIVATE VERIFIED BADGE (After Paid Subscription)
// ═══════════════════════════════════════════════════════════════════════

export const activateVerifiedBadge = mutation({
  args: {
    userId: v.id("users"),
    subscriptionId: v.id("vendor_subscriptions"),
  },
  handler: async (ctx, args) => {
    const profile = await ctx.db
      .query("agent_profiles")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .first();

    if (!profile) throw new Error("Agent profile not found.");

    const now = Date.now();

    // 1. Turn on verified badge & direct lead receiving
    await ctx.db.patch(profile._id, {
      isVerified: true,
      allowDirectBuyerLeads: true,
      verifiedAt: now,
      updatedAt: now,
    });

    // 2. Update user record
    await ctx.db.patch(args.userId, {
      isVerified: true,
      isVerifiedSeller: true,
      updatedAt: now,
    });

    // 3. Update verification request status to active
    const req = await ctx.db
      .query("verification_requests")
      .withIndex("by_userId", (q) => q.eq("userId", args.userId))
      .order("desc")
      .first();

    if (req) {
      await ctx.db.patch(req._id, {
        status: "active",
        updatedAt: now,
      });
    }

    return {
      success: true,
      isVerified: true,
      message: "Verified badge is now active! Direct buyer leads enabled.",
    };
  },
});
