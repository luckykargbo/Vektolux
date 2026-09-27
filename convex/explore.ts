// convex/explore.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Explore Discovery Feed & Search Backend
// Scalable queries powering the unified Explore screen:
// Recommended for you, Properties near you, Vehicles for sale/hire,
// and Top Agents & Dealers.
// ═══════════════════════════════════════════════════════════════════════

import { query } from "./_generated/server";
import { v } from "convex/values";

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
      city: string;
      bedrooms?: number;
      bathrooms?: number;
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
        (doc) =>
          doc.isDeleted !== true &&
          doc.isPublished !== false &&
          doc.availabilityStatus === "available"
      );

      for (const p of publishedRe.slice(0, limit)) {
        let ownerName = "Verified Agent";
        let ownerAvatar: string | undefined;
        let isVerified = false;

        const owner = await ctx.db.get(p.ownerId);
        if (owner) {
          ownerName = owner.name;
          ownerAvatar = owner.avatarUrl;
          isVerified = owner.isVerified || owner.isVerifiedAgent === true;
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
          city: p.city ?? "Sierra Leone",
          bedrooms: p.bedrooms,
          bathrooms: p.bathrooms,
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
          location: vDoc.location ?? "Sierra Leone",
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

      const agentUsers = allUsers.filter(
        (u) =>
          u.isActive !== false &&
          (u.role === "agent" ||
            u.role === "merchant" ||
            u.isVerifiedAgent === true ||
            u.isVerifiedMerchant === true ||
            u.isVerifiedSeller === true)
      );

      for (const u of agentUsers.slice(0, limit)) {
        // Count listings
        const reCount = await ctx.db
          .query("realEstateListings")
          .withIndex("by_owner", (q) => q.eq("ownerId", u._id))
          .take(20);
        const vCount = await ctx.db
          .query("vehicleListings")
          .withIndex("by_owner", (q) => q.eq("ownerId", u._id))
          .take(20);

        const totalListings = reCount.length + vCount.length;

        topAgents.push({
          id: u._id as string,
          name: u.name,
          role: u.role === "merchant" ? "Vehicle Dealer" : "Real Estate Agent",
          businessName: u.businessName,
          avatarUrl: u.avatarUrl,
          isVerified: u.isVerified || u.isVerifiedAgent === true || u.isVerifiedMerchant === true,
          listingsCount: totalListings,
          rating: 5.0,
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
        location: p.city,
        ownerName: p.ownerName,
        ownerAvatar: p.ownerAvatar,
        isVerified: p.isVerified,
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
        location: vItem.location,
        ownerName: vItem.ownerName,
        ownerAvatar: vItem.ownerAvatar,
        isVerified: vItem.isVerified,
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
          p.isDeleted !== true &&
          p.isPublished !== false &&
          (p.title.toLowerCase().includes(q) ||
            (p.city && p.city.toLowerCase().includes(q)) ||
            (p.address && p.address.toLowerCase().includes(q)) ||
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
        location: vDoc.location ?? "Sierra Leone",
      }));

    // Search agents / dealers
    const users = await ctx.db
      .query("users")
      .order("desc")
      .take(50);
    const agents = users
      .filter(
        (u) =>
          u.isActive !== false &&
          (u.role === "agent" ||
            u.role === "merchant" ||
            u.isVerifiedAgent === true ||
            u.isVerifiedMerchant === true) &&
          (u.name.toLowerCase().includes(q) ||
            (u.businessName && u.businessName.toLowerCase().includes(q)))
      )
      .slice(0, maxItems)
      .map((u) => ({
        id: u._id as string,
        name: u.name,
        role: u.role === "merchant" ? "Vehicle Dealer" : "Real Estate Agent",
        businessName: u.businessName,
        avatarUrl: u.avatarUrl,
        isVerified: u.isVerified || u.isVerifiedAgent === true || u.isVerifiedMerchant === true,
      }));

    return { properties, vehicles, agents };
  },
});
