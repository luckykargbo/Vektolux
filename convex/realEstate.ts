// convex/realEstate.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Listings & Marketplace Queries
// Handles property creation with media storage and discovery queries.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { realEstateCategory } from "./schema";
import { encodeGeohash } from "./lib/geo";
import { requireVerifiedSeller } from "./middleware";
import { requireOwnedDoc, requireSelf, resolveOptionalUser } from "./lib/auth";
import { businessRole, postingPermission } from "./lib/permissions";
import { isListingPublic, listingLifecycle, toPublicProperty } from "./lib/publicListing";
import { activeListingAgent } from "./listingAgents";
import { findDistrict, findTown } from "./lib/slLocations";
import { isAcceptableContentType, isListingVideoContentType } from "./lib/uploads";

export const MAX_LISTING_VIDEOS = 3;
export const MAX_LISTING_VIDEO_BYTES = 150 * 1024 * 1024;

async function storageUrl(ctx: { storage: any }, id: string): Promise<string | null> {
  try {
    return await ctx.storage.getUrl(id as Id<"_storage">);
  } catch {
    return null;
  }
}

async function storageMeta(ctx: { db: any }, id: string): Promise<{ contentType?: string; size?: number } | null> {
  try {
    return await ctx.db.system.get("_storage", id as Id<"_storage">);
  } catch {
    return null;
  }
}

/** A real uploaded photo (an image type when storage metadata has one) → its URL. */
async function listingImageUrl(ctx: { db: any; storage: any }, id: string): Promise<string> {
  const meta = await storageMeta(ctx, id);
  const type = meta?.contentType?.toLowerCase();
  if (type && !(type.startsWith("image/") && isAcceptableContentType(type))) {
    throw new Error("Only photos (JPEG, PNG, WebP or HEIC) can be added as listing photos.");
  }
  const url = await storageUrl(ctx, id);
  if (!url) throw new Error("A photo did not finish uploading. Remove it or upload it again.");
  return url;
}

/** A real uploaded video (type/size checked when storage metadata is available) → its URL. */
async function listingVideoUrl(ctx: { db: any; storage: any }, id: string): Promise<string> {
  const meta = await storageMeta(ctx, id);
  if (meta?.contentType && !isListingVideoContentType(meta.contentType)) {
    throw new Error("Only MP4, MOV, WebM or 3GP videos can be added as property videos.");
  }
  if (typeof meta?.size === "number" && meta.size > MAX_LISTING_VIDEO_BYTES) {
    throw new Error("Each property video can be at most 150 MB.");
  }
  const url = await storageUrl(ctx, id);
  if (!url) throw new Error("A video did not finish uploading. Remove it or upload it again.");
  return url;
}

/** Listings by Real Estate Agents are reviewed by an administrator before they go live. */
function requiresReview(user: { role?: unknown }): boolean {
  return businessRole(user as any) === "real_estate_agent";
}

/** Fields that send a listing to the admin review queue. */
function reviewFields(now: number) {
  return {
    isPublished: true,
    moderationStatus: "pending_review" as const,
    submittedForReviewAt: now,
    moderationReason: undefined,
    moderatedAt: undefined,
    moderatedBy: undefined,
  };
}

// ═══════════════════════════════════════════════════════════════════════
//                     CREATE PROPERTY LISTING
// ═══════════════════════════════════════════════════════════════════════

export const createPropertyListing = mutation({
  args: {
    ownerId: v.string(),
    sessionToken: v.optional(v.string()),
    title: v.string(),
    description: v.string(),
    category: realEstateCategory,
    price: v.number(),
    hourlyRate: v.optional(v.number()),
    currency: v.optional(v.string()),
    address: v.string(),
    city: v.optional(v.string()),
    district: v.optional(v.string()),
    country: v.optional(v.string()),
    // Optional & PRIVATE (never returned publicly). Absent = unknown (stored as 0 / empty geohash).
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
    imageStorageIds: v.array(v.string()),
    // Uploaded property videos (storage ids only; public media like the photos).
    videoStorageIds: v.optional(v.array(v.string())),
    bedrooms: v.optional(v.number()),
    bathrooms: v.optional(v.number()),
    areaSqM: v.optional(v.number()),
    amenities: v.optional(v.array(v.string())),
    privateContactPhone: v.optional(v.string()),
    isPublished: v.optional(v.boolean()),
  },
  returns: v.string(), // Returns listing _id
  handler: async (ctx, args) => {
    // 1. Seller Trust Guard: Enforce identity verification before listing
    await requireVerifiedSeller(ctx, args.ownerId, args.sessionToken, "property");

    // 2. Verify user exists and is active
    const userId = ctx.db.normalizeId("users", args.ownerId);
    if (!userId) {
      throw new Error("Invalid owner user ID.");
    }
    const user = await ctx.db.get(userId);
    if (!user || !user.isActive) {
      throw new Error("User account not found or inactive.");
    }

    // 2. Validate session token if provided
    if (args.sessionToken && user.sessionToken !== args.sessionToken) {
      throw new Error("Invalid or expired session. Please log in again.");
    }

    // 3. Resolve media to public URLs. Only real uploads are stored: a photo or video that never
    //    reached storage (e.g. a failed upload) is refused, never saved as a fake local path.
    const resolvedImageUrls: string[] = [];
    for (const item of args.imageStorageIds) {
      if (item.startsWith("http://") || item.startsWith("https://")) {
        resolvedImageUrls.push(item);
        continue;
      }
      resolvedImageUrls.push(await listingImageUrl(ctx, item));
    }
    const videoIds = args.videoStorageIds ?? [];
    if (videoIds.length > MAX_LISTING_VIDEOS) {
      throw new Error(`A listing can have at most ${MAX_LISTING_VIDEOS} videos.`);
    }
    const videoUrls: string[] = [];
    for (const item of videoIds) videoUrls.push(await listingVideoUrl(ctx, item));

    // 4. Calculate geohash for spatial indexing
    const hasCoords = args.latitude !== undefined && args.longitude !== undefined;
    const geohash = hasCoords ? encodeGeohash(args.latitude!, args.longitude!, 7) : "";
    const now = Date.now();

    // An agent's submitted listing waits for admin review; a draft stays private. Owners' listings
    // are not reviewed (unchanged).
    const publish = args.isPublished ?? true;
    const publication = requiresReview(user)
      ? publish
        ? { isPublished: true, moderationStatus: "pending_review" as const, submittedForReviewAt: now }
        : { isPublished: false }
      : { isPublished: publish };

    // 5. Insert listing record
    const listingId = await ctx.db.insert("realEstateListings", {
      ownerId: userId,
      title: args.title,
      description: args.description,
      category: args.category,
      price: args.price,
      hourlyRate: args.hourlyRate,
      currency: args.currency ?? "SLE",
      address: args.address,
      city: args.city ?? "Freetown",
      // Store a recognised district when given (public location is derived from the allow-list).
      district: findDistrict(args.district)?.district ?? findTown(args.city)?.district,
      country: args.country ?? "Sierra Leone",
      latitude: args.latitude ?? 0,
      longitude: args.longitude ?? 0,
      geohash,
      bedrooms: args.bedrooms,
      bathrooms: args.bathrooms,
      areaSqM: args.areaSqM,
      amenities: args.amenities ?? [],
      imageUrls: resolvedImageUrls,
      ...(videoUrls.length > 0 ? { videoUrls } : {}),
      privateContactPhone: args.privateContactPhone,
      isDeleted: false,
      availabilityStatus: "available",
      isFeatured: false,
      ...publication,
      viewCount: 0,
      saveCount: 0,
      inquiryCount: 0,
      viewingRequestCount: 0,
      updatedAt: now,
    });

    return listingId as string;
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                      LIST PROPERTIES (DISCOVERY)
// ═══════════════════════════════════════════════════════════════════════

export const listProperties = query({
  args: {
    category: v.optional(realEstateCategory),
    minPrice: v.optional(v.number()),
    maxPrice: v.optional(v.number()),
    city: v.optional(v.string()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const listings = args.category
      ? await ctx.db
          .query("realEstateListings")
          .withIndex("by_category_status", (q) =>
            q.eq("category", args.category!).eq("availabilityStatus", "available")
          )
          .order("desc")
          .take(args.limit ?? 50)
      : await ctx.db
          .query("realEstateListings")
          .order("desc")
          .take(args.limit ?? 50);

    // Only public listings: no drafts, unpublished, archived, deleted, pending or rejected ones.
    let filtered = listings.filter((l) => isListingPublic(l));

    // Apply price and city filters in-memory if requested
    if (args.minPrice !== undefined) {
      filtered = filtered.filter((l) => l.price >= args.minPrice!);
    }
    if (args.maxPrice !== undefined) {
      filtered = filtered.filter((l) => l.price <= args.maxPrice!);
    }
    if (args.city !== undefined && args.city.length > 0) {
      filtered = filtered.filter(
        (l) => l.city && l.city.toLowerCase() === args.city!.toLowerCase()
      );
    }

    // Resolve any remaining storage IDs in imageUrls and provide resilient defaults
    const resolvedListings = await Promise.all(
      filtered.map(async (listing) => {
        const rawImages = Array.isArray(listing.imageUrls) ? listing.imageUrls : [];
        const resolvedUrls = (
          await Promise.all(
            rawImages.map(async (url) => {
              if (typeof url !== "string") return null;
              if (url.startsWith("http://") || url.startsWith("https://")) {
                return url;
              }
              try {
                const publicUrl = await ctx.storage.getUrl(url as Id<"_storage">);
                return publicUrl ?? url;
              } catch {
                return url;
              }
            })
          )
        ).filter((u): u is string => Boolean(u));

        // Privacy: no private phone, street address, coordinates or geohash in public responses.
        const cleanListing = toPublicProperty(listing);

        return {
          ...cleanListing,
          _id: listing._id as string,
          ownerId: String(listing.ownerId ?? ""),
          title: listing.title || "Untitled Property",
          price: listing.price ?? 0,
          currency: listing.currency ?? "SLE",
          imageUrls: resolvedUrls,
        };
      })
    );

    return resolvedListings;
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    MY PROPERTY LISTINGS (OWNER)
// ═══════════════════════════════════════════════════════════════════════

export const getMyPropertyListings = query({
  args: {
    ownerId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    // Owner only: this returns private fields (street address, coordinates, contact phone).
    const { userId } = await requireSelf(ctx, args.sessionToken, args.ownerId);

    const listings = await ctx.db
      .query("realEstateListings")
      .withIndex("by_owner", (q) => q.eq("ownerId", userId))
      .order("desc")
      .take(500);

    return listings
      .filter((l) => l.isDeleted !== true)
      .map((l) => ({
        ...l,
        _id: l._id as string,
        ownerId: String(l.ownerId),
        // Server-derived state and statistics (the app never computes or stores these).
        lifecycleStatus: listingLifecycle(l),
        moderationReason: l.moderationReason ?? null,
        viewCount: l.viewCount ?? 0,
        saveCount: l.saveCount ?? 0,
        inquiryCount: l.inquiryCount ?? 0,
        viewingRequestCount: l.viewingRequestCount ?? 0,
      }));
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    UPDATE PROPERTY LISTING (EDIT)
// ═══════════════════════════════════════════════════════════════════════

export const updatePropertyListing = mutation({
  args: {
    listingId: v.string(),
    ownerId: v.string(),
    sessionToken: v.optional(v.string()),
    title: v.optional(v.string()),
    description: v.optional(v.string()),
    price: v.optional(v.number()),
    hourlyRate: v.optional(v.number()),
    bedrooms: v.optional(v.number()),
    bathrooms: v.optional(v.number()),
    isPublished: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const { doc: listing, auth } = await requireOwnedDoc(
      ctx, "realEstateListings", args.listingId, args.sessionToken
    );
    const id = listing._id;
    if (listing.moderationStatus === "removed") {
      throw new Error("This listing was removed by Vektolux and can no longer be changed.");
    }
    const now = Date.now();
    const updates: Record<string, any> = { updatedAt: now };
    if (args.title !== undefined) updates.title = args.title;
    if (args.description !== undefined) updates.description = args.description;
    if (args.price !== undefined) updates.price = args.price;
    if (args.hourlyRate !== undefined) updates.hourlyRate = args.hourlyRate;
    if (args.bedrooms !== undefined) updates.bedrooms = args.bedrooms;
    if (args.bathrooms !== undefined) updates.bathrooms = args.bathrooms;

    let message = "Listing updated successfully";
    // (Re)publishing — including resubmitting a rejected listing — is publishing: it needs the same
    // server-side permission as creating one, and an agent's listing goes back to admin review.
    const publishing =
      args.isPublished === true && (listing.isPublished === false || listing.moderationStatus === "rejected");
    if (publishing) {
      if (typeof listing.archivedAt === "number") throw new Error("Restore this listing from the archive first.");
      const permission = await postingPermission(ctx, auth.user, "property");
      if (!permission.allowed) throw new Error(permission.reason);
      if (requiresReview(auth.user)) {
        Object.assign(updates, reviewFields(now));
        message = "Submitted for review";
      } else {
        updates.isPublished = true;
      }
    } else if (args.isPublished === false && listing.isPublished !== false) {
      updates.isPublished = false;
      // Taking a listing out of the review queue turns it back into a draft.
      if (listing.moderationStatus === "pending_review") {
        updates.moderationStatus = undefined;
        updates.submittedForReviewAt = undefined;
      }
    }

    await ctx.db.patch(id, updates);
    return { success: true, message };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    ARCHIVE / RESTORE (OWNER)
// ═══════════════════════════════════════════════════════════════════════

/** Takes a listing off the marketplace and keeps it (with its history) in the owner's archive. */
export const archivePropertyListing = mutation({
  args: { listingId: v.string(), sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { doc: listing } = await requireOwnedDoc(ctx, "realEstateListings", args.listingId, args.sessionToken);
    if (listing.moderationStatus === "removed") throw new Error("This listing was removed by Vektolux.");
    if (typeof listing.archivedAt === "number") return { success: true };
    const now = Date.now();
    await ctx.db.patch(listing._id, {
      archivedAt: now,
      isPublished: false,
      // a listing waiting for review leaves the queue
      ...(listing.moderationStatus === "pending_review" ? { moderationStatus: undefined, submittedForReviewAt: undefined } : {}),
      updatedAt: now,
    });
    return { success: true };
  },
});

/** Brings an archived listing back as a private draft (publishing it again goes through review). */
export const restorePropertyListing = mutation({
  args: { listingId: v.string(), sessionToken: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { doc: listing } = await requireOwnedDoc(ctx, "realEstateListings", args.listingId, args.sessionToken);
    if (typeof listing.archivedAt !== "number") throw new Error("This listing is not archived.");
    await ctx.db.patch(listing._id, { archivedAt: undefined, isPublished: false, updatedAt: Date.now() });
    return { success: true };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    DELETE PROPERTY LISTING (DELETE & ARCHIVE)
// ═══════════════════════════════════════════════════════════════════════

export const deletePropertyListing = mutation({
  args: {
    listingId: v.string(),
    ownerId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { doc: listing } = await requireOwnedDoc(
      ctx, "realEstateListings", args.listingId, args.sessionToken
    );
    const id = listing._id;
    // A listing an administrator removed stays on record (with its reason): it cannot be deleted.
    if (listing.moderationStatus === "removed") {
      throw new Error("This listing was removed by Vektolux and cannot be deleted.");
    }

    // Capture full data payload for local SQLite archival
    const archivedSnapshot = {
      id: listing._id as string,
      postType: "property",
      ownerId: String(listing.ownerId),
      title: listing.title,
      description: listing.description,
      category: listing.category,
      price: listing.price,
      currency: listing.currency,
      location: `${listing.address}, ${listing.city}`,
      bedrooms: listing.bedrooms ?? null,
      bathrooms: listing.bathrooms ?? null,
      privateContactPhone: listing.privateContactPhone ?? null,
      imageUrls: listing.imageUrls,
      originalCreatedAt: listing.updatedAt,
      archivedAt: Date.now(),
    };

    // Remove from Convex database completely as requested
    await ctx.db.delete(id);

    return {
      success: true,
      message: "Listing permanently removed from Convex and archived",
      archivedData: archivedSnapshot,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                     GET PROPERTY BY ID (PRIVACY SAFE)
// ═══════════════════════════════════════════════════════════════════════

export const getPropertyById = query({
  args: {
    listingId: v.string(),
    // Optional: lets the owner or the listing's authorised agent open a listing that is not public
    // (draft, under review, rejected, archived). Everyone else only ever sees public listings.
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("realEstateListings", args.listingId);
    if (!id) return null;

    const listing = await ctx.db.get(id);
    if (!listing || listing.isDeleted) return null;
    if (!isListingPublic(listing)) {
      const viewer = args.sessionToken ? await resolveOptionalUser(ctx, { sessionToken: args.sessionToken }) : null;
      if (!viewer) return null;
      const isOwner = viewer.userId === listing.ownerId;
      const agent = isOwner ? null : await activeListingAgent(ctx, "property", listing._id as string);
      if (!isOwner && agent?.agentId !== viewer.userId) return null;
    }

    // Fetch owner details
    const owner = await ctx.db.get(listing.ownerId);

    // Privacy: no private phone, street address, coordinates or geohash in public responses.
    const cleanListing = toPublicProperty(listing) as typeof listing;

    // Resolve media storage URLs
    const rawImages = Array.isArray(cleanListing.imageUrls) ? cleanListing.imageUrls : [];
    const resolvedUrls = (
      await Promise.all(
        rawImages.map(async (url) => {
          if (typeof url !== "string") return null;
          if (url.startsWith("http://") || url.startsWith("https://")) {
            return url;
          }
          try {
            const publicUrl = await ctx.storage.getUrl(url as Id<"_storage">);
            return publicUrl ?? url;
          } catch {
            return url;
          }
        })
      )
    ).filter((u): u is string => Boolean(u));

    return {
      ...cleanListing,
      _id: listing._id as string,
      imageUrls: resolvedUrls,
      // Derived state only (a non-public listing is returned just to its owner / authorised agent).
      lifecycleStatus: listingLifecycle(listing),
      contactAction: "in_app_request",
      owner: owner
        ? {
            id: owner._id as string,
            name: owner.name,
            avatarUrl: owner.avatarUrl,
            role: owner.role,
            isVerified: owner.isVerified,
            hasVerifiedPhone: !!owner.phone,
          }
        : null,
    };
  },
});

