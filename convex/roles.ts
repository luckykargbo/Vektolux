// convex/roles.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Business-role applications (admin review).
// A business role (Real Estate Agent / Owner, Car Dealer, Hotel Owner) is granted ONLY here, by an
// administrator. Approval sets users.role + roleApprovedAt; subscriptions (agents, hotels) are a
// separate requirement checked by lib/permissions.ts.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireAdmin } from "./lib/auth";
import { businessRole, isRoleApproved, roleForApplication } from "./lib/permissions";

const statusValidator = v.union(
  v.literal("pending"),
  v.literal("approved"),
  v.literal("rejected"),
  v.literal("suspended")
);

const ROLE_LABEL: Record<string, string> = {
  agent: "Real Estate Agent",
  property_owner: "Real Estate Owner",
  dealer: "Car Dealer / Vehicle Owner",
  merchant: "Car Dealer / Vehicle Owner",
  hotel_operator: "Hotel / Guest House Owner",
  driver: "Driver (discontinued)",
};

export const adminListRoleApplications = query({
  args: {
    sessionToken: v.optional(v.string()),
    status: v.optional(statusValidator),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx, { sessionToken: args.sessionToken });
    const rows = await ctx.db.query("role_applications").order("desc").take(300);
    const filtered = args.status ? rows.filter((r) => r.status === args.status) : rows;
    return await Promise.all(
      filtered.slice(0, 200).map(async (r) => {
        const u = await ctx.db.get(r.userId);
        return {
          id: r._id as string,
          userId: r.userId as string,
          userName: u?.name ?? "Unknown",
          userEmail: u?.email ?? null,
          currentRole: u?.role ?? null,
          identityStatus: u?.verificationStatus ?? "unverified",
          targetRole: r.targetRole,
          targetRoleLabel: ROLE_LABEL[r.targetRole] ?? r.targetRole,
          businessName: r.businessName ?? null,
          tinNumber: r.tinNumber ?? null,
          licenseNumber: r.licenseNumber ?? null,
          documentCount: r.documentUrls.length,
          status: r.status,
          reviewNotes: r.reviewNotes ?? null,
          reviewedAt: r.reviewedAt ?? null,
          submittedAt: r._creationTime,
        };
      })
    );
  },
});

/**
 * approve  → users.role = mapped role, roleApprovedAt/By set (privileges then follow permissions.ts)
 * reject   → application closed, role unchanged
 * suspend  → an approved role is withdrawn: users.role back to client; history kept
 */
export const adminDecideRoleApplication = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    applicationId: v.id("role_applications"),
    decision: v.union(v.literal("approve"), v.literal("reject"), v.literal("suspend")),
    notes: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdmin(ctx, { sessionToken: args.sessionToken });
    const app = await ctx.db.get(args.applicationId);
    if (!app) throw new Error("Application not found.");
    const user = await ctx.db.get(app.userId);
    if (!user) throw new Error("Applicant account not found.");
    if (user.role === "admin") throw new Error("Administrator accounts cannot be changed here.");
    const notes = args.notes?.trim().slice(0, 1000);
    const now = Date.now();

    if (args.decision === "approve" || args.decision === "reject") {
      if (app.status !== "pending") throw new Error(`This application is already ${app.status}.`);
    } else if (app.status !== "approved") {
      throw new Error("Only an approved role can be suspended.");
    }
    if ((args.decision === "reject" || args.decision === "suspend") && !notes) {
      throw new Error("Please give a reason.");
    }

    let title: string;
    let body: string;
    let action: "ROLE_APPROVED" | "ROLE_REJECTED" | "ROLE_SUSPENDED";
    const label = ROLE_LABEL[app.targetRole] ?? app.targetRole;

    const userIsApprovedAgent = businessRole(user) === "real_estate_agent" && isRoleApproved(user);
    const userIsApprovedDealer = businessRole(user) === "vehicle_dealer" && isRoleApproved(user);
    const isDealerApp = app.targetRole === "dealer" || app.targetRole === "merchant";

    if (args.decision === "approve") {
      const role = roleForApplication(app.targetRole);
      if (!role) throw new Error("This role is no longer offered and cannot be approved.");
      if (isDealerApp && userIsApprovedAgent) {
        // Real Estate Agent + Car Dealer: the dealer capability is ADDED; the agent role, its
        // workspace and its subscription rules are untouched.
        await ctx.db.patch(user._id, { vehicleDealerApprovedAt: now, vehicleDealerApprovedBy: adminId, updatedAt: now });
      } else if (app.targetRole === "agent" && userIsApprovedDealer) {
        // An approved Car Dealer becomes Real Estate Agent & Car Dealer: the agent role is primary
        // and the earlier dealer approval is kept as the add-on capability.
        await ctx.db.patch(user._id, {
          role,
          activeRole: role,
          roleApprovedAt: now,
          roleApprovedBy: adminId,
          vehicleDealerApprovedAt: user.roleApprovedAt ?? now,
          vehicleDealerApprovedBy: user.roleApprovedBy ?? adminId,
          businessName: app.businessName ?? user.businessName,
          tinNumber: app.tinNumber ?? user.tinNumber,
          updatedAt: now,
        });
      } else {
        await ctx.db.patch(user._id, {
          role,
          activeRole: role,
          roleApprovedAt: now,
          roleApprovedBy: adminId,
          // a different primary role replaces any add-on capability
          vehicleDealerApprovedAt: undefined,
          vehicleDealerApprovedBy: undefined,
          businessName: app.businessName ?? user.businessName,
          tinNumber: app.tinNumber ?? user.tinNumber,
          updatedAt: now,
        });
      }
      await ctx.db.patch(app._id, { status: "approved", reviewNotes: notes, reviewedBy: adminId, reviewedAt: now, updatedAt: now });
      action = "ROLE_APPROVED";
      title = "Application approved";
      body =
        app.targetRole === "agent" || app.targetRole === "hotel_operator"
          ? `You are approved as a ${label}. Activate a subscription to get your verified badge and start posting.`
          : `You are approved as a ${label}. You can now post listings.`;
    } else if (args.decision === "reject") {
      await ctx.db.patch(app._id, { status: "rejected", reviewNotes: notes, reviewedBy: adminId, reviewedAt: now, updatedAt: now });
      action = "ROLE_REJECTED";
      title = "Application not approved";
      body = `Your ${label} application was not approved: ${notes}`;
    } else if (isDealerApp && userIsApprovedAgent) {
      // Suspending only the Car Dealer add-on: the Real Estate Agent role stays.
      await ctx.db.patch(user._id, { vehicleDealerApprovedAt: undefined, vehicleDealerApprovedBy: undefined, updatedAt: now });
      await ctx.db.patch(app._id, { status: "suspended", reviewNotes: notes, reviewedBy: adminId, reviewedAt: now, updatedAt: now });
      action = "ROLE_SUSPENDED";
      title = "Business role suspended";
      body = `Your ${label} role has been suspended: ${notes}. Your listings and history are kept.`;
    } else if (app.targetRole === "agent" && userIsApprovedAgent && typeof user.vehicleDealerApprovedAt === "number") {
      // Suspending the agent role of an Agent & Car Dealer: the separately approved dealer role stays.
      await ctx.db.patch(user._id, {
        role: "dealer",
        activeRole: "dealer",
        roleApprovedAt: user.vehicleDealerApprovedAt,
        roleApprovedBy: user.vehicleDealerApprovedBy,
        vehicleDealerApprovedAt: undefined,
        vehicleDealerApprovedBy: undefined,
        isVerifiedAgent: false,
        updatedAt: now,
      });
      await ctx.db.patch(app._id, { status: "suspended", reviewNotes: notes, reviewedBy: adminId, reviewedAt: now, updatedAt: now });
      action = "ROLE_SUSPENDED";
      title = "Business role suspended";
      body = `Your ${label} role has been suspended: ${notes}. Your Car Dealer role and your history are kept.`;
    } else {
      await ctx.db.patch(user._id, {
        role: "client",
        activeRole: "client",
        roleApprovedAt: undefined,
        roleApprovedBy: undefined,
        vehicleDealerApprovedAt: undefined,
        vehicleDealerApprovedBy: undefined,
        // legacy flags would otherwise keep the role "approved"
        isVerifiedAgent: false,
        isVerifiedMerchant: false,
        isVerifiedSeller: false,
        updatedAt: now,
      });
      await ctx.db.patch(app._id, { status: "suspended", reviewNotes: notes, reviewedBy: adminId, reviewedAt: now, updatedAt: now });
      action = "ROLE_SUSPENDED";
      title = "Business role suspended";
      body = `Your ${label} role has been suspended: ${notes}. Your listings and history are kept.`;
    }

    await ctx.db.insert("audit_logs", {
      adminUserId: adminId,
      action,
      targetTransactionId: app._id as string,
      snapshot: JSON.stringify({ userId: user._id, targetRole: app.targetRole, notes: notes ?? null }),
      timestamp: now,
    });
    await ctx.db.insert("user_notifications", {
      userId: user._id as string,
      targetType: "single_user",
      title,
      body,
      read: false,
      createdAt: now,
    });
    return { success: true, status: args.decision === "approve" ? "approved" : args.decision === "reject" ? "rejected" : "suspended" };
  },
});
