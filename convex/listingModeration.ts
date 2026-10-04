// convex/listingModeration.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Admin review of real-estate listings.
//
// Lifecycle (server-controlled; see lib/publicListing.ts):
//   agent submits → pending_review → approve → approved (public while published)
//                                  → reject  → rejected (reason; the agent edits & resubmits)
//   any listing   → remove  → removed (reason; never public again)
//                 → archive → archived (off the marketplace; the owner may restore it as a draft)
// Every decision is admin-only, needs a reason when it hides a listing, is written to audit_logs
// and is notified to the owner (and the listing's authorised agent). Nothing here moves money.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query, MutationCtx } from "./_generated/server";
import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { requireAdmin } from "./lib/auth";
import { isRoleApproved, professionalTitle } from "./lib/permissions";
import { isListingPublic, listingLifecycle } from "./lib/publicListing";
import { publicLocation } from "./lib/slLocations";
import { activeListingAgent } from "./listingAgents";

export type ModerationDecision = "approve" | "reject" | "remove" | "archive";

const decisionValidator = v.union(v.literal("approve"), v.literal("reject"), v.literal("remove"), v.literal("archive"));
const filterValidator = v.union(
  v.literal("pending_review"),
  v.literal("approved"),
  v.literal("rejected"),
  v.literal("removed"),
  v.literal("all")
);

const AUDIT_ACTION = {
  approve: "LISTING_APPROVED",
  reject: "LISTING_REJECTED",
  remove: "LISTING_REMOVED",
  archive: "LISTING_ARCHIVED",
} as const;

/**
 * Applies an admin decision to a listing (validates the transition, audits, notifies).
 * Shared by adminModerateListing and the legacy admin:takeDownListing.
 */
export async function applyListingModeration(
  ctx: MutationCtx,
  adminId: Id<"users">,
  listing: Doc<"realEstateListings">,
  decision: ModerationDecision,
  rawReason: string | undefined
): Promise<{ status: string }> {
  const reason = rawReason?.trim().slice(0, 1000) || undefined;
  if ((decision === "reject" || decision === "remove") && (!reason || reason.length < 5)) {
    throw new Error("Please give a reason (at least 5 characters).");
  }
  if (listing.isDeleted === true) throw new Error("This listing was deleted.");
  const previous = listingLifecycle(listing);
  const now = Date.now();
  let patch: Record<string, unknown>;
  let title: string;
  let body: string;

  switch (decision) {
    case "approve":
      if (listing.moderationStatus !== "pending_review") throw new Error("Only a listing waiting for review can be approved.");
      patch = { moderationStatus: "approved", isPublished: true, moderationReason: undefined };
      title = "Listing approved";
      body = `"${listing.title}" is now live on Vektolux.`;
      break;
    case "reject":
      if (listing.moderationStatus !== "pending_review") throw new Error("Only a listing waiting for review can be rejected.");
      patch = { moderationStatus: "rejected", moderationReason: reason };
      title = "Listing not approved";
      body = `"${listing.title}" was not approved: ${reason}`;
      break;
    case "remove":
      if (listing.moderationStatus === "removed") throw new Error("This listing was already removed.");
      patch = { moderationStatus: "removed", isPublished: false, moderationReason: reason };
      title = "Listing removed by Vektolux";
      body = `"${listing.title}" was removed: ${reason}`;
      break;
    case "archive":
      if (typeof listing.archivedAt === "number") throw new Error("This listing is already archived.");
      if (listing.moderationStatus === "removed") throw new Error("A removed listing cannot be archived.");
      patch = {
        archivedAt: now,
        isPublished: false,
        ...(listing.moderationStatus === "pending_review" ? { moderationStatus: undefined, submittedForReviewAt: undefined } : {}),
        ...(reason ? { moderationReason: reason } : {}),
      };
      title = "Listing archived by Vektolux";
      body = reason ? `"${listing.title}" was archived: ${reason}` : `"${listing.title}" was archived.`;
      break;
    default:
      throw new Error("Unknown decision.");
  }

  await ctx.db.patch(listing._id, { ...patch, moderatedAt: now, moderatedBy: adminId, updatedAt: now });
  await ctx.db.insert("audit_logs", {
    adminUserId: adminId,
    action: AUDIT_ACTION[decision],
    targetTransactionId: listing._id as string,
    snapshot: JSON.stringify({
      listingId: listing._id,
      ownerId: listing.ownerId,
      title: listing.title,
      decision,
      reason: reason ?? null,
      previousStatus: previous,
    }),
    timestamp: now,
  });

  // The owner and, when the owner authorised one, the listing agent are told what happened.
  const recipients = new Set<string>([listing.ownerId as string]);
  const agent = await activeListingAgent(ctx, "property", listing._id as string, now);
  if (agent) recipients.add(agent.agentId as string);
  for (const userId of recipients) {
    await ctx.db.insert("user_notifications", {
      userId,
      targetType: "single_user",
      title,
      body,
      deepLinkScreen: "listings",
      deepLinkId: listing._id as string,
      read: false,
      createdAt: now,
    });
  }
  const updated = await ctx.db.get(listing._id);
  return { status: updated ? listingLifecycle(updated) : "removed" };
}

/** Admin: listings by moderation state (the review queue is oldest first). */
export const adminListListings = query({
  args: {
    sessionToken: v.optional(v.string()),
    moderation: v.optional(filterValidator),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx, { sessionToken: args.sessionToken });
    const limit = Math.max(1, Math.min(200, Math.floor(args.limit ?? 100)));
    const filter = args.moderation ?? "pending_review";
    let rows: Doc<"realEstateListings">[];
    if (filter === "all") {
      rows = await ctx.db.query("realEstateListings").order("desc").take(limit);
    } else if (filter === "approved") {
      // approved = reviewed & approved, plus listings that never needed review (public right now)
      const recent = await ctx.db.query("realEstateListings").order("desc").take(400);
      rows = recent.filter((l) => l.isDeleted !== true && (l.moderationStatus === "approved" || l.moderationStatus === undefined)).slice(0, limit);
    } else {
      rows = await ctx.db
        .query("realEstateListings")
        .withIndex("by_moderationStatus_and_submittedForReviewAt", (q) => q.eq("moderationStatus", filter))
        .order(filter === "pending_review" ? "asc" : "desc")
        .take(limit);
    }
    return await Promise.all(
      rows.map(async (l) => {
        const owner = await ctx.db.get(l.ownerId);
        return {
          id: l._id as string,
          title: l.title,
          category: l.category,
          price: l.price,
          hourlyRate: l.hourlyRate ?? null,
          currency: l.currency,
          publicLocation: publicLocation(l.city, l.district),
          coverImage: l.imageUrls[0] ?? null,
          photoCount: l.imageUrls.length,
          videoCount: l.videoUrls?.length ?? 0,
          ownerId: l.ownerId as string,
          ownerName: owner?.name ?? "Unknown",
          ownerTitle: owner ? professionalTitle(owner) : "Unknown",
          moderationStatus: l.moderationStatus ?? null,
          lifecycleStatus: listingLifecycle(l),
          isPublic: isListingPublic(l),
          moderationReason: l.moderationReason ?? null,
          submittedForReviewAt: l.submittedForReviewAt ?? null,
          moderatedAt: l.moderatedAt ?? null,
          createdAt: l._creationTime,
        };
      })
    );
  },
});

/** Admin: one listing in full for review (includes the PRIVATE address — admin use only). */
export const adminGetListing = query({
  args: { sessionToken: v.optional(v.string()), listingId: v.string() },
  handler: async (ctx, args) => {
    await requireAdmin(ctx, { sessionToken: args.sessionToken });
    const id = ctx.db.normalizeId("realEstateListings", args.listingId);
    const l = id ? await ctx.db.get(id) : null;
    if (!l) return null;
    const owner = await ctx.db.get(l.ownerId);
    const agentLink = await activeListingAgent(ctx, "property", l._id as string);
    const agent = agentLink ? await ctx.db.get(agentLink.agentId) : null;
    const history = await ctx.db
      .query("audit_logs")
      .withIndex("by_target", (q) => q.eq("targetTransactionId", l._id as string))
      .order("desc")
      .take(20);
    return {
      id: l._id as string,
      title: l.title,
      description: l.description,
      category: l.category,
      price: l.price,
      hourlyRate: l.hourlyRate ?? null,
      currency: l.currency,
      bedrooms: l.bedrooms ?? null,
      bathrooms: l.bathrooms ?? null,
      areaSqM: l.areaSqM ?? null,
      amenities: l.amenities ?? [],
      imageUrls: l.imageUrls,
      videoUrls: l.videoUrls ?? [],
      publicLocation: publicLocation(l.city, l.district),
      privateAddress: l.address,
      privateContactPhone: l.privateContactPhone ?? null,
      owner: owner
        ? { id: owner._id as string, name: owner.name, title: professionalTitle(owner), roleApproved: isRoleApproved(owner) }
        : null,
      agent: agent ? { id: agent._id as string, name: agent.name } : null,
      moderationStatus: l.moderationStatus ?? null,
      lifecycleStatus: listingLifecycle(l),
      isPublic: isListingPublic(l),
      moderationReason: l.moderationReason ?? null,
      submittedForReviewAt: l.submittedForReviewAt ?? null,
      moderatedAt: l.moderatedAt ?? null,
      createdAt: l._creationTime,
      history: history.map((h) => {
        let detail: any = null;
        try {
          detail = JSON.parse(h.snapshot);
        } catch {
          detail = null;
        }
        return { action: h.action, at: h.timestamp, reason: detail?.reason ?? null };
      }),
    };
  },
});

/** Admin: approve / reject / remove / archive a listing. */
export const adminModerateListing = mutation({
  args: {
    sessionToken: v.optional(v.string()),
    listingId: v.string(),
    decision: decisionValidator,
    reason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { userId: adminId } = await requireAdmin(ctx, { sessionToken: args.sessionToken });
    const id = ctx.db.normalizeId("realEstateListings", args.listingId);
    const listing = id ? await ctx.db.get(id) : null;
    if (!listing) throw new Error("Listing not found.");
    return await applyListingModeration(ctx, adminId, listing, args.decision, args.reason);
  },
});
