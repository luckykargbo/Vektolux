// convex/businessVerification.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Manual Business Verification Pipeline & Admin Queue
// Real estate agent onboarding, document proof storage, admin approvals/rejections
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";

// ═══════════════════════════════════════════════════════════════════════
//                     GENERATE UPLOAD URL (STORAGE)
// ═══════════════════════════════════════════════════════════════════════

export const generateUploadUrl = mutation({
  args: {},
  handler: async (ctx) => {
    return await ctx.storage.generateUploadUrl();
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
    const userDocId = ctx.db.normalizeId("users", args.userId);
    if (!userDocId) {
      return { success: false, errorMessage: "User not found." };
    }

    const user = await ctx.db.get(userDocId);
    if (!user || !user.isActive) {
      return { success: false, errorMessage: "User account is invalid or inactive." };
    }

    if (args.sessionToken && user.sessionToken && user.sessionToken !== args.sessionToken) {
      return { success: false, errorMessage: "Invalid session. Please authenticate again." };
    }

    if (!args.businessName || !args.businessName.trim()) {
      return { success: false, errorMessage: "Business name is required." };
    }
    if (!args.tinNumber || !args.tinNumber.trim()) {
      return { success: false, errorMessage: "Tax Identification Number (TIN) is required." };
    }

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
    const userDocId = ctx.db.normalizeId("users", args.userId);
    if (!userDocId) return null;

    const user = await ctx.db.get(userDocId);
    if (!user) return null;

    if (args.sessionToken && user.sessionToken && user.sessionToken !== args.sessionToken) {
      return null;
    }

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
    // 1. Authenticate admin
    const adminDocId = ctx.db.normalizeId("users", args.adminId);
    if (!adminDocId) {
      throw new Error("Unauthorized: Invalid administrator credentials.");
    }
    const adminUser = await ctx.db.get(adminDocId);
    if (!adminUser || adminUser.role !== "admin") {
      throw new Error("Forbidden: Access restricted to platform administrators.");
    }
    if (args.sessionToken && adminUser.sessionToken && adminUser.sessionToken !== args.sessionToken) {
      throw new Error("Unauthorized: Invalid session token.");
    }

    // 2. Fetch users with role 'agent' (or agents and merchants)
    const filter = args.statusFilter ?? "pending";

    let agentsQuery;
    if (filter !== "all") {
      agentsQuery = await ctx.db
        .query("users")
        .withIndex("by_role_verification", (q) =>
          q.eq("role", "agent").eq("verificationStatus", filter as any)
        )
        .take(100);
    } else {
      agentsQuery = await ctx.db
        .query("users")
        .withIndex("by_role", (q) => q.eq("role", "agent"))
        .take(100);
    }

    // Also include any user who has businessName or documentStorageId submitted if filter matches
    const allMatching = agentsQuery;

    // Resolve documents into short-lived signed URLs for admin review
    const results = await Promise.all(
      allMatching.map(async (agent) => {
        let signedUrl: string | undefined = undefined;
        if (agent.documentStorageId) {
          try {
            signedUrl = (await ctx.storage.getUrl(agent.documentStorageId)) ?? undefined;
          } catch {
            signedUrl = agent.documentUrl;
          }
        } else if (agent.documentUrl) {
          signedUrl = agent.documentUrl;
        }

        return {
          userId: agent._id as string,
          name: agent.name,
          email: agent.email,
          phone: agent.phone,
          businessName: agent.businessName || "Unnamed Business",
          tinNumber: agent.tinNumber || "N/A",
          documentUrl: signedUrl,
          documentStorageId: agent.documentStorageId ? (agent.documentStorageId as string) : undefined,
          verificationStatus: agent.verificationStatus ?? (agent.isVerified ? "verified" : "unverified"),
          rejectionReason: agent.rejectionReason,
          verifiedAt: agent.verifiedAt,
          createdAt: agent._creationTime,
          updatedAt: agent.updatedAt,
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
    // 1. Verify Admin
    const adminDocId = ctx.db.normalizeId("users", args.adminId);
    if (!adminDocId) {
      return { success: false, errorMessage: "Unauthorized: Admin account not found." };
    }
    const adminUser = await ctx.db.get(adminDocId);
    if (!adminUser || adminUser.role !== "admin") {
      return { success: false, errorMessage: "Forbidden: Only administrators can approve verifications." };
    }
    if (args.sessionToken && adminUser.sessionToken && adminUser.sessionToken !== args.sessionToken) {
      return { success: false, errorMessage: "Session expired." };
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

    // 3. Set approved status and log audit metadata
    await ctx.db.patch(targetAgentId, {
      verificationStatus: "approved",
      isVerified: true,
      isVerifiedAgent: true,
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

    // 5. Update role_applications
    const roleApp = await ctx.db
      .query("role_applications")
      .withIndex("by_user", (q) => q.eq("userId", targetAgentId))
      .filter((q) => q.eq(q.field("targetRole"), "agent"))
      .first();

    if (roleApp) {
      await ctx.db.patch(roleApp._id, {
        status: "approved",
        reviewedAt: now,
        reviewNotes: "Approved by administrator",
        updatedAt: now,
      });
    }

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
    // 1. Verify Admin
    const adminDocId = ctx.db.normalizeId("users", args.adminId);
    if (!adminDocId) {
      return { success: false, errorMessage: "Unauthorized: Admin account not found." };
    }
    const adminUser = await ctx.db.get(adminDocId);
    if (!adminUser || adminUser.role !== "admin") {
      return { success: false, errorMessage: "Forbidden: Only administrators can reject verifications." };
    }
    if (args.sessionToken && adminUser.sessionToken && adminUser.sessionToken !== args.sessionToken) {
      return { success: false, errorMessage: "Session expired." };
    }

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
      isVerifiedAgent: false,
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

    // 5. Update role_applications
    const roleApp = await ctx.db
      .query("role_applications")
      .withIndex("by_user", (q) => q.eq("userId", targetAgentId))
      .filter((q) => q.eq(q.field("targetRole"), "agent"))
      .first();

    if (roleApp) {
      await ctx.db.patch(roleApp._id, {
        status: "rejected",
        reviewedAt: now,
        reviewNotes: args.reason.trim(),
        updatedAt: now,
      });
    }

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
    const adminDocId = ctx.db.normalizeId("users", args.adminId);
    if (!adminDocId) throw new Error("Unauthorized.");
    const adminUser = await ctx.db.get(adminDocId);
    if (!adminUser || adminUser.role !== "admin") {
      throw new Error("Forbidden: Administrator access required.");
    }
    if (args.sessionToken && adminUser.sessionToken && adminUser.sessionToken !== args.sessionToken) {
      throw new Error("Invalid session.");
    }

    return await ctx.storage.getUrl(args.storageId);
  },
});
