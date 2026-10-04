// convex/explore.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Explore Discovery Feed & Search Backend
// Scalable queries powering the unified Explore screen:
// Recommended for you, Properties near you, Vehicles for sale/hire,
// and Top Agents & Dealers.
// ═══════════════════════════════════════════════════════════════════════

import { query } from "./_generated/server";
import { v } from "convex/values";
import { publicLocation } from "./lib/slLocations";
import { Doc } from "./_generated/dataModel";
import { businessRole, hasCarDealerCapability, isRoleApproved, professionalBadge, professionalTitle } from "./lib/permissions";
import { isListingPublic } from "./lib/publicListing";

/**
 * Public professional card for discovery. Only APPROVED professionals are listed; a Real Estate
 * Agent / Hotel Owner is shown only while their subscription is active (computed, never a flag).
 */
async function publicProfessional(ctx: { db: any }, u: Doc<"users">): Promise<{ label: string; verified: boolean } | null> {
  if (u.isActive === false || !isRoleApproved(u)) return null;
  const role = businessRole(u);
  if (role === "vehicle_dealer") return { label: "Vehicle Dealer", verified: true };
  if (role === "real_estate_owner") return { label: "Property Owner", verified: true };
  if (role === "real_estate_agent" || role === "hotel_owner") {
    const b = await professionalBadge(ctx, u);
    if (role === "real_estate_agent" && b.verifiedAgent) return { label: professionalTitle(u), verified: true };
    // An agent without an active subscription who is also an approved Car Dealer still sells cars.
    if (role === "real_estate_agent" && hasCarDealerCapability(u)) return { label: "Vehicle Dealer", verified: true };
    if (role === "hotel_owner" && b.verifiedHotel) return { label: "Hotel / Guest House", verified: true };
  }
  return null;
}

export const getExploreFeed = query({
  args: {
    userId: v.optional(v.string()),
    category: v.optional(v.string()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = args.limit ?? 10;
    const cat = args.category?.toLowerCase() ?? "all";

    // ── 1. Fetch Real Estate Listings ─────────────────────────────────
    let properties: Array<{
      id: string;
      title: string;
      category: string;
      price: number;
      currency: string;
      imageUrl?: string;
      videoUrls?: string[];
      city: string;
      bedrooms?: number;
      bathrooms?: number;
      areaSqM?: number;
      ownerId: string;
      ownerName: string;
      ownerAvatar?: string;
      isVerified: boolean;
      createdAt: number;
    }> = [];

    if (cat === "all" || cat === "properties" || cat === "rentals") {
      const reDocs = await ctx.db
        .query("realEstateListings")
        .order("desc")
        .take(limit * 2);

      const publishedRe = reDocs.filter(
        (doc) => isListingPublic(doc) && doc.availabilityStatus === "available"
      );

      for (const p of publishedRe.slice(0, limit)) {
        // No account behind the listing: say so (it is not a "verified agent").
        let ownerName = "Property owner";
        let ownerAvatar: string | undefined;
        let isVerified = false;

        const owner = await ctx.db.get(p.ownerId);
        if (owner) {
          ownerName = owner.name;
          ownerAvatar = owner.avatarUrl;
          isVerified = (await publicProfessional(ctx, owner))?.verified === true;
        }

        const firstImage =
          p.imageUrls && p.imageUrls.length > 0 ? p.imageUrls[0] : undefined;

        properties.push({
          id: p._id as string,
          title: p.title,
          category: p.category,
          price: p.price,
          currency: p.currency ?? "SLE",
          imageUrl: firstImage,
          videoUrls: p.videoUrls,
          city: p.city ?? "Sierra Leone",
          bedrooms: p.bedrooms,
          bathrooms: p.bathrooms,
          areaSqM: p.areaSqM,
          ownerId: p.ownerId as string,
          ownerName,
          ownerAvatar,
          isVerified,
          createdAt: p._creationTime,
        });
      }
    }

    // ── 2. Fetch Vehicle Listings ─────────────────────────────────────
    let vehicles: Array<{
      id: string;
      title: string;
      make?: string;
      model?: string;
      year?: number;
      category: string;
      price: number;
      pricingType: string;
      currency: string;
      imageUrl?: string;
      location: string;
      fuelType?: string;
      transmission?: string;
      ownerId: string;
      ownerName: string;
      ownerAvatar?: string;
      isVerified: boolean;
      createdAt: number;
    }> = [];

    if (cat === "all" || cat === "vehicles" || cat === "dealers" || cat === "rentals") {
      const vDocs = await ctx.db
        .query("vehicleListings")
        .order("desc")
        .take(limit * 2);

      const publishedVehicles = vDocs.filter(
        (doc) =>
          doc.isDeleted !== true &&
          doc.isPublished !== false &&
          doc.status === "AVAILABLE"
      );

      for (const vDoc of publishedVehicles.slice(0, limit)) {
        let ownerName = "Verified Dealer";
        let ownerAvatar: string | undefined;
        let isVerified = false;

        const owner = await ctx.db.get(vDoc.ownerId);
        if (owner) {
          ownerName = owner.name;
          ownerAvatar = owner.avatarUrl;
          isVerified = owner.isVerified || owner.isVerifiedMerchant === true;
        }

        const imageList = vDoc.images ?? vDoc.imageUrls ?? [];
        const firstImage = imageList.length > 0 ? imageList[0] : undefined;

        vehicles.push({
          id: vDoc._id as string,
          title: vDoc.title,
          make: vDoc.make,
          model: vDoc.model,
          year: vDoc.year,
          category: vDoc.category,
          price: vDoc.price,
          pricingType: vDoc.pricingType,
          currency: vDoc.currency ?? "SLE",
          imageUrl: firstImage,
          location: publicLocation(vDoc.location),
          fuelType: vDoc.fuelType,
          transmission: vDoc.transmission,
          ownerId: vDoc.ownerId as string,
          ownerName,
          ownerAvatar,
          isVerified,
          createdAt: vDoc._creationTime,
        });
      }
    }

    // ── 3. Fetch Top Agents & Dealers ─────────────────────────────────
    let topAgents: Array<{
      id: string;
      name: string;
      role: string;
      businessName?: string;
      avatarUrl?: string;
      isVerified: boolean;
      listingsCount: number;
      rating?: number;
    }> = [];

    if (cat === "all" || cat === "agents" || cat === "dealers") {
      const allUsers = await ctx.db
        .query("users")
        .order("desc")
        .take(50);

      const agentUsers: Array<{ u: Doc<"users">; pro: { label: string; verified: boolean } }> = [];
      for (const u of allUsers) {
        const pro = await publicProfessional(ctx, u);
        if (pro) agentUsers.push({ u, pro });
      }

      for (const { u, pro } of agentUsers.slice(0, limit)) {
        // Count listings
        const reCount = await ctx.db
          .query("realEstateListings")
          .withIndex("by_owner", (q) => q.eq("ownerId", u._id))
          .take(20);
        const vCount = await ctx.db
          .query("vehicleListings")
          .withIndex("by_owner", (q) => q.eq("ownerId", u._id))
          .take(20);

        // public listings only (no drafts, listings under review, rejected, archived or removed)
        const totalListings =
          reCount.filter((l) => isListingPublic(l)).length +
          vCount.filter((x) => x.isDeleted !== true && x.isPublished !== false && x.status !== "TAKEN_DOWN").length;

        topAgents.push({
          id: u._id as string,
          name: u.name,
          role: pro.label,
          businessName: u.businessName,
          avatarUrl: u.avatarUrl,
          isVerified: pro.verified,
          listingsCount: totalListings,
          // no rating system exists yet — never show an invented score
        });
      }
    }

    // ── 4. Generate Recommended for You ──────────────────────────────
    // Personalized if user follows creators or has interactions;
    // otherwise composed of most recent featured/verified real listings.
    const recommended: Array<{
      id: string;
      type: "property" | "vehicle";
      title: string;
      subtitle: string;
      price: number;
      currency: string;
      imageUrl?: string;
      location: string;
      ownerName: string;
      ownerAvatar?: string;
      isVerified: boolean;
      // real card details (absent when the listing does not have them; the app never invents them)
      category?: string;
      pricingType?: string;
      bedrooms?: number;
      bathrooms?: number;
      areaSqM?: number;
      year?: number;
      fuelType?: string;
      transmission?: string;
    }> = [];

    // Combine top real items into recommendation stream
    for (const p of properties.slice(0, 5)) {
      recommended.push({
        id: p.id,
        type: "property",
        title: p.title,
        subtitle: `${p.category} • ${p.city}`,
        price: p.price,
        currency: p.currency,
        imageUrl: p.imageUrl,
        location: publicLocation(p.city),
        ownerName: p.ownerName,
        ownerAvatar: p.ownerAvatar,
        isVerified: p.isVerified,
        category: p.category,
        bedrooms: p.bedrooms,
        bathrooms: p.bathrooms,
        areaSqM: p.areaSqM,
      });
    }

    for (const vItem of vehicles.slice(0, 5)) {
      recommended.push({
        id: vItem.id,
        type: "vehicle",
        title: vItem.title,
        subtitle: `${vItem.make ?? ""} ${vItem.model ?? ""} • ${vItem.category}`.trim(),
        price: vItem.price,
        currency: vItem.currency,
        imageUrl: vItem.imageUrl,
        location: publicLocation(vItem.location),
        ownerName: vItem.ownerName,
        ownerAvatar: vItem.ownerAvatar,
        isVerified: vItem.isVerified,
        category: vItem.category,
        pricingType: vItem.pricingType,
        year: vItem.year,
        fuelType: vItem.fuelType,
        transmission: vItem.transmission,
      });
    }

    return {
      recommended,
      propertiesNearYou: properties,
      vehiclesForSaleAndHire: vehicles,
      topAgentsAndDealers: topAgents,
    };
  },
});

export const searchExplore = query({
  args: {
    searchQuery: v.string(),
    category: v.optional(v.string()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const q = args.searchQuery.trim().toLowerCase();
    if (!q) {
      return { properties: [], vehicles: [], agents: [] };
    }

    const maxItems = args.limit ?? 15;

    // Search properties
    const reDocs = await ctx.db
      .query("realEstateListings")
      .order("desc")
      .take(50);
    const properties = reDocs
      .filter(
        (p) =>
          isListingPublic(p) &&
          (p.title.toLowerCase().includes(q) ||
            (p.city && p.city.toLowerCase().includes(q)) ||
            // (Street addresses are private and are NOT searchable.)
            p.category.toLowerCase().includes(q))
      )
      .slice(0, maxItems)
      .map((p) => ({
        id: p._id as string,
        title: p.title,
        category: p.category,
        price: p.price,
        currency: p.currency ?? "SLE",
        imageUrl: p.imageUrls && p.imageUrls.length > 0 ? p.imageUrls[0] : undefined,
        city: p.city ?? "Sierra Leone",
      }));

    // Search vehicles
    const vDocs = await ctx.db
      .query("vehicleListings")
      .order("desc")
      .take(50);
    const vehicles = vDocs
      .filter(
        (vDoc) =>
          vDoc.isDeleted !== true &&
          vDoc.isPublished !== false &&
          (vDoc.title.toLowerCase().includes(q) ||
            (vDoc.make && vDoc.make.toLowerCase().includes(q)) ||
            (vDoc.model && vDoc.model.toLowerCase().includes(q)) ||
            (vDoc.location && vDoc.location.toLowerCase().includes(q)) ||
            vDoc.category.toLowerCase().includes(q))
      )
      .slice(0, maxItems)
      .map((vDoc) => ({
        id: vDoc._id as string,
        title: vDoc.title,
        category: vDoc.category,
        price: vDoc.price,
        currency: vDoc.currency ?? "SLE",
        imageUrl:
          vDoc.images && vDoc.images.length > 0
            ? vDoc.images[0]
            : vDoc.imageUrls && vDoc.imageUrls.length > 0
              ? vDoc.imageUrls[0]
              : undefined,
        location: publicLocation(vDoc.location),
      }));

    // Search agents / dealers
    const users = await ctx.db
      .query("users")
      .order("desc")
      .take(50);
    const agents: Array<{ id: string; name: string; role: string; businessName?: string; avatarUrl?: string; isVerified: boolean }> = [];
    for (const u of users) {
      if (agents.length >= maxItems) break;
      if (!(u.name.toLowerCase().includes(q) || (u.businessName && u.businessName.toLowerCase().includes(q)))) continue;
      const pro = await publicProfessional(ctx, u);
      if (!pro) continue;
      agents.push({
        id: u._id as string,
        name: u.name,
        role: pro.label,
        businessName: u.businessName,
        avatarUrl: u.avatarUrl,
        isVerified: pro.verified,
      });
    }

    return { properties, vehicles, agents };
  },
});
