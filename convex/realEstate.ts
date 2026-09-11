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
    country: v.optional(v.string()),
    latitude: v.number(),
    longitude: v.number(),
    imageStorageIds: v.array(v.string()),
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
    await requireVerifiedSeller(ctx, args.ownerId, args.sessionToken);

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

    // 3. Resolve image storage IDs to public URLs
    const resolvedImageUrls: string[] = [];
    for (const item of args.imageStorageIds) {
      if (item.startsWith("http://") || item.startsWith("https://")) {
        resolvedImageUrls.push(item);
      } else {
        try {
          const url = await ctx.storage.getUrl(item as Id<"_storage">);
          if (url) {
            resolvedImageUrls.push(url);
          } else {
            resolvedImageUrls.push(item);
          }
        } catch {
          resolvedImageUrls.push(item);
        }
      }
    }

    // 4. Calculate geohash for spatial indexing
    const geohash = encodeGeohash(args.latitude, args.longitude, 7);
    const now = Date.now();

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
      country: args.country ?? "Sierra Leone",
      latitude: args.latitude,
      longitude: args.longitude,
      geohash,
      bedrooms: args.bedrooms,
      bathrooms: args.bathrooms,
      areaSqM: args.areaSqM,
      amenities: args.amenities ?? [],
      imageUrls: resolvedImageUrls,
      privateContactPhone: args.privateContactPhone,
      isDeleted: false,
      availabilityStatus: "available",
      isFeatured: false,
      isPublished: args.isPublished ?? true,
      viewCount: 0,
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

    // Exclude unpublished / draft / deleted listings from public discovery
    let filtered = listings.filter(
      (l) => l.isPublished !== false && l.isDeleted !== true
    );

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

        // Privacy Guard: Strip privateContactPhone from public response
        const { privateContactPhone: _strip, ...cleanListing } = listing;

        return {
          ...cleanListing,
          _id: listing._id as string,
          ownerId: String(listing.ownerId ?? ""),
          title: listing.title || "Untitled Property",
          address: listing.address || "Location Unavailable",
          city: listing.city || "Freetown",
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
    const userId = ctx.db.normalizeId("users", args.ownerId);
    if (!userId) return [];

    const listings = await ctx.db
      .query("realEstateListings")
      .withIndex("by_owner", (q) => q.eq("ownerId", userId))
      .order("desc")
      .collect();

    return listings
      .filter((l) => l.isDeleted !== true)
      .map((l) => ({
        ...l,
        _id: l._id as string,
        ownerId: String(l.ownerId),
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
    const id = ctx.db.normalizeId("realEstateListings", args.listingId);
    if (!id) throw new Error("Listing not found");

    const listing = await ctx.db.get(id);
    if (!listing) throw new Error("Listing not found");

    const userId = ctx.db.normalizeId("users", args.ownerId);
    if (!userId || listing.ownerId !== userId) {
      throw new Error("You do not have permission to edit this listing");
    }

    const updates: Record<string, any> = { updatedAt: Date.now() };
    if (args.title !== undefined) updates.title = args.title;
    if (args.description !== undefined) updates.description = args.description;
    if (args.price !== undefined) updates.price = args.price;
    if (args.hourlyRate !== undefined) updates.hourlyRate = args.hourlyRate;
    if (args.bedrooms !== undefined) updates.bedrooms = args.bedrooms;
    if (args.bathrooms !== undefined) updates.bathrooms = args.bathrooms;
    if (args.isPublished !== undefined) updates.isPublished = args.isPublished;

    await ctx.db.patch(id, updates);
    return { success: true, message: "Listing updated successfully" };
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
    const id = ctx.db.normalizeId("realEstateListings", args.listingId);
    if (!id) throw new Error("Listing not found");

    const listing = await ctx.db.get(id);
    if (!listing) throw new Error("Listing not found");

    const userId = ctx.db.normalizeId("users", args.ownerId);
    if (!userId || listing.ownerId !== userId) {
      throw new Error("You do not have permission to delete this listing");
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
