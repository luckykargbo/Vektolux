// convex/savedListings.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Saved listings (the heart button).
// A save is a server record owned by the authenticated account (the session decides who; a client
// never names the user), so it survives logout, reinstalling and other devices. Saving and
// un-saving keep the listing's saveCount in the same transaction, so the count an agent sees is
// the number of real saves. Only public listings can be saved; un-saving always works.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireSelf } from "./lib/auth";
import { isListingPublic, toPublicProperty, toPublicVehicle } from "./lib/publicListing";

const listingType = v.union(v.literal("property"), v.literal("vehicle"));

function vehicleIsPublic(doc: any): boolean {
  return !!doc && doc.isDeleted !== true && doc.isPublished !== false && doc.status !== "TAKEN_DOWN";
}

async function loadListing(ctx: { db: any }, type: "property" | "vehicle", listingId: string) {
  const table = type === "property" ? "realEstateListings" : "vehicleListings";
  const id = ctx.db.normalizeId(table, listingId);
  return id ? await ctx.db.get(id) : null;
}

/** Saves or un-saves a listing for the signed-in account. Returns the new state. */
export const toggleSavedListing = mutation({
  args: { sessionToken: v.optional(v.string()), listingType, listingId: v.string() },
  returns: v.object({ saved: v.boolean() }),
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const existing = await ctx.db
      .query("saved_listings")
      .withIndex("by_userId_and_listingId", (q) => q.eq("userId", userId).eq("listingId", args.listingId))
      .first();
    const listing = await loadListing(ctx, args.listingType, args.listingId);

    if (existing) {
      await ctx.db.delete(existing._id);
      if (listing && args.listingType === "property") {
        await ctx.db.patch(listing._id, { saveCount: Math.max(0, (listing.saveCount ?? 0) - 1) });
      }
      return { saved: false };
    }

    const isPublic = args.listingType === "property" ? isListingPublic(listing) : vehicleIsPublic(listing);
    if (!listing || !isPublic) throw new Error("This listing is no longer available.");
    if (String(listing.ownerId) === String(userId)) throw new Error("You cannot save your own listing.");
    const count = await ctx.db
      .query("saved_listings")
      .withIndex("by_userId_and_createdAt", (q) => q.eq("userId", userId))
      .take(501);
    if (count.length >= 500) throw new Error("You can save up to 500 listings. Remove some first.");

    await ctx.db.insert("saved_listings", {
      userId,
      listingType: args.listingType,
      listingId: args.listingId,
      createdAt: Date.now(),
    });
    if (args.listingType === "property") {
      await ctx.db.patch(listing._id, { saveCount: (listing.saveCount ?? 0) + 1 });
    }
    return { saved: true };
  },
});

/** The ids the signed-in account has saved (for the hearts). */
export const getMySavedListingIds = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const rows = await ctx.db
      .query("saved_listings")
      .withIndex("by_userId_and_createdAt", (q) => q.eq("userId", userId))
      .order("desc")
      .take(500);
    return rows.map((r) => ({ listingType: r.listingType, listingId: r.listingId }));
  },
});

/** The signed-in account's saved listings as public cards, newest save first. */
export const getMySavedListings = query({
  args: { sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { userId } = await requireSelf(ctx, args.sessionToken);
    const rows = await ctx.db
      .query("saved_listings")
      .withIndex("by_userId_and_createdAt", (q) => q.eq("userId", userId))
      .order("desc")
      .take(100);
    const out = [];
    for (const r of rows) {
      const doc: any = await loadListing(ctx, r.listingType, r.listingId);
      const available = r.listingType === "property" ? isListingPublic(doc) : vehicleIsPublic(doc);
      if (!doc || !available) {
        // Kept so the user can remove it; no details of a listing that is not public.
        out.push({ listingType: r.listingType, listingId: r.listingId, savedAt: r.createdAt, available: false });
        continue;
      }
      const pub: any = r.listingType === "property" ? toPublicProperty(doc) : toPublicVehicle(doc);
      const images: string[] = (doc.imageUrls ?? doc.images ?? []).filter((u: unknown) => typeof u === "string" && u.startsWith("http"));
      out.push({
        listingType: r.listingType,
        listingId: r.listingId,
        savedAt: r.createdAt,
        available: true,
        title: doc.title ?? "Listing",
        category: doc.category ?? null,
        price: doc.price ?? doc.salePrice ?? doc.pricePerDay ?? 0,
        hourlyRate: doc.hourlyRate ?? null,
        currency: doc.currency ?? "SLE",
        location: pub.publicLocation ?? "Sierra Leone",
        imageUrl: images[0] ?? null,
        bedrooms: doc.bedrooms ?? null,
        bathrooms: doc.bathrooms ?? null,
        areaSqM: doc.areaSqM ?? null,
        ownerId: String(doc.ownerId),
      });
    }
    return out;
  },
});
