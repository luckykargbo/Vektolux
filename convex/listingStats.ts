// convex/listingStats.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Listing statistics the owner / agent sees (all server-derived):
//   viewCount            one per signed-in viewer, listing and UTC day (recordPropertyView);
//                        guests, the owner and the listing's authorised agent are not counted
//   saveCount            savedListings.ts (same transaction as the save)
//   inquiryCount         adminPortal.submitContactRequest (first message about the listing)
//   viewingRequestCount  free site-visit requests (bookings.ts) + paid inspection passes
// A client can never set or inflate any of these.
// ═══════════════════════════════════════════════════════════════════════

import { internalMutation, mutation } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { resolveOptionalUser } from "./lib/auth";
import { isListingPublic } from "./lib/publicListing";
import { activeListingAgent } from "./listingAgents";

const DAY_MS = 86_400_000;

/** Adds one to a listing counter (used by the mutations that create the underlying records). */
export async function bumpListingCounter(
  ctx: { db: any },
  listingId: Id<"realEstateListings"> | string,
  field: "inquiryCount" | "viewingRequestCount"
): Promise<void> {
  const id = typeof listingId === "string" ? ctx.db.normalizeId("realEstateListings", listingId) : listingId;
  if (!id) return;
  const listing = await ctx.db.get(id);
  if (!listing) return;
  await ctx.db.patch(id, { [field]: (listing[field] ?? 0) + 1 });
}

/** Records a property page view by a signed-in user (at most once per listing per day). */
export const recordPropertyView = mutation({
  args: { sessionToken: v.optional(v.string()), listingId: v.string() },
  returns: v.object({ counted: v.boolean() }),
  handler: async (ctx, args) => {
    const viewer = await resolveOptionalUser(ctx, { sessionToken: args.sessionToken });
    if (!viewer) return { counted: false }; // guests are not counted
    const id = ctx.db.normalizeId("realEstateListings", args.listingId);
    const listing = id ? await ctx.db.get(id) : null;
    if (!listing || !isListingPublic(listing)) return { counted: false };
    if (listing.ownerId === viewer.userId) return { counted: false };
    const agent = await activeListingAgent(ctx, "property", listing._id as string);
    if (agent?.agentId === viewer.userId) return { counted: false };

    const day = Math.floor(Date.now() / DAY_MS);
    const seen = await ctx.db
      .query("listing_views")
      .withIndex("by_listingId_and_viewerId_and_day", (q) =>
        q.eq("listingId", listing._id).eq("viewerId", viewer.userId).eq("day", day)
      )
      .first();
    if (seen) return { counted: false };
    await ctx.db.insert("listing_views", { listingId: listing._id, viewerId: viewer.userId, day });
    await ctx.db.patch(listing._id, { viewCount: (listing.viewCount ?? 0) + 1 });
    return { counted: true };
  },
});

/**
 * ONE-OFF, run once after the deploy that introduces the counters (no money moves):
 *   npx convex run listingStats:backfillListingCounters
 * Counts the inquiries, site-visit requests and paid inspection passes that existed before the
 * counters did. Processes 50 listings per transaction and schedules itself for the rest.
 */
export const backfillListingCounters = internalMutation({
  args: { cursor: v.optional(v.union(v.string(), v.null())) },
  handler: async (ctx, args) => {
    const page = await ctx.db
      .query("realEstateListings")
      .paginate({ numItems: 50, cursor: args.cursor ?? null });
    for (const listing of page.page) {
      const id = listing._id as string;
      const inquiries = await ctx.db
        .query("contact_requests")
        .filter((q) => q.eq(q.field("listingId"), id))
        .take(1000);
      const visits = await ctx.db
        .query("bookings")
        .withIndex("by_listing", (q) => q.eq("listingId", id))
        .take(1000);
      const passes = await ctx.db
        .query("re_inspection_passes")
        .withIndex("by_property", (q) => q.eq("propertyListingId", listing._id))
        .take(1000);
      const saves = await ctx.db
        .query("saved_listings")
        .withIndex("by_listingId", (q) => q.eq("listingId", id))
        .take(5000);
      await ctx.db.patch(listing._id, {
        inquiryCount: inquiries.filter((r) => r.listingType === "property").length,
        viewingRequestCount: visits.filter((b) => b.bookingType === "property_inspection").length + passes.length,
        saveCount: saves.length,
      });
    }
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.listingStats.backfillListingCounters, { cursor: page.continueCursor });
    }
    return { processed: page.page.length, done: page.isDone };
  },
});
