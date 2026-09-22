// convex/admin.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Developer & Admin Quick-Seed & Asset Tools
// Enables 1-click test listing injection, batch asset upload URLs, and
// private draft/published visibility management.
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { encodeGeohash } from "./lib/geo";

// ═══════════════════════════════════════════════════════════════════════
//                   QUICK SEED LISTINGS (DEV/ADMIN)
// ═══════════════════════════════════════════════════════════════════════

export const quickSeedListings = mutation({
  args: {
    vertical: v.union(v.literal("property"), v.literal("vehicle"), v.literal("both")),
    city: v.optional(v.string()),
    isPublished: v.optional(v.boolean()),
  },
  returns: v.object({
    propertiesCount: v.number(),
    vehiclesCount: v.number(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    const targetCity = args.city ?? "Freetown";
    const isPublished = args.isPublished ?? false;
    const now = Date.now();

    // 1. Ensure production admin user Alfred Manso Kargbo exists to own listings
    let adminUser = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", "alfred.kargbo@vektolux.com"))
      .first();

    if (!adminUser) {
      const allUsers = await ctx.db.query("users").collect();
      adminUser =
        allUsers.find(
          (u) =>
            u.name.toLowerCase().includes("alfred manso kargbo") ||
            u.phone === "+232688577868" ||
            u.role === "admin"
        ) ?? null;
    }

    if (!adminUser) {
      throw new Error("Failed to resolve production admin owner account (Alfred Manso Kargbo). Mock user creation is permanently disabled.");
    }

    let propertiesCount = 0;
    let vehiclesCount = 0;

    // 2. Real Estate Catalog by City
    const realEstateCatalog = [
      {
        city: "Freetown",
        title: "Spur Loop Hilltop Executive Villa",
        description: "Modern 4-bedroom executive residence on Spur Loop with panoramic views of Lumley Beach and Atlantic ocean. Includes standby soundproof generator, 24/7 solar backup, borehole with filtration system, and landscaped security compound.",
        category: "long_term_rent" as const,
        price: 14000,
        hourlyRate: 900,
        address: "24 Spur Loop, Wilberforce",
        latitude: 8.4715,
        longitude: -13.2625,
        bedrooms: 4,
        bathrooms: 4,
        areaSqM: 360,
        amenities: ["Ocean View", "EDSA Grid", "Standby Generator", "Borehole", "24/7 Security", "Solar Inverter"],
        imageUrls: [
          "https://images.unsplash.com/photo-1613490493576-7fde63acd811?w=800",
          "https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=800",
          "https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800",
        ],
      },
      {
        city: "Freetown",
        title: "Lumley Beach Sunset Luxury Guest Suite",
        description: "Exclusive beachfront guest apartment directly opposite Lumley Beach. Ideal for international travelers, business executives, and diaspora visits. Fully serviced with daily housekeeping and high-speed Starlink WiFi.",
        category: "hourly_guesthouse" as const,
        price: 1800,
        hourlyRate: 150,
        address: "7 Lumley Beach Road",
        latitude: 8.4872,
        longitude: -13.2798,
        bedrooms: 2,
        bathrooms: 2,
        areaSqM: 120,
        amenities: ["Beachfront", "Starlink WiFi", "Air Conditioning", "Solar Power", "24/7 Security", "Kitchenette"],
        imageUrls: [
          "https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=800",
          "https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=800",
        ],
      },
      {
        city: "Freetown",
        title: "Regent Mountain Ridge Contemporary House",
        description: "Prestigious newly constructed home nestled in the cool hills of Regent. Enjoy fresh mountain breeze, solar-first architecture, large terrace, and complete privacy only 20 minutes from Central Freetown.",
        category: "sale" as const,
        price: 850000,
        hourlyRate: undefined,
        address: "12 Mountain View Road, Regent",
        latitude: 8.4350,
        longitude: -13.2080,
        bedrooms: 5,
        bathrooms: 5,
        areaSqM: 450,
        amenities: ["Title Deed", "Mountain View", "Solar Inverter", "Borehole", "Perimeter Wall", "Staff Quarters"],
        imageUrls: [
          "https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=800",
          "https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=800",
        ],
      },
      {
        city: "Bo",
        title: "Bo Town Residency & Gated Compound",
        description: "Spacious 3-bedroom bungalow situated in a serene residential sector of Bo Town. Features robust solar electrification, private water borehole, and expansive paved compound suitable for commercial or residential living.",
        category: "long_term_rent" as const,
        price: 4500,
        hourlyRate: 350,
        address: "15 Bo-Tajama Highway, Bo",
        latitude: 7.9644,
        longitude: -11.7383,
        bedrooms: 3,
        bathrooms: 2,
        areaSqM: 220,
        amenities: ["Solar Power", "Borehole", "Fenced Compound", "Parking"],
        imageUrls: [
          "https://images.unsplash.com/photo-1580587771525-78b9dba3b914?w=800",
          "https://images.unsplash.com/photo-1513694203232-719a280e022f?w=800",
        ],
      },
      {
        city: "Makeni",
        title: "Makeni City Commercial Office & Residence",
        description: "High-visibility property on Rogbaneh Road, Makeni. Excellent for NGOs, corporate branches, or private residential quarters. Complete with backup diesel generator and solar battery bank.",
        category: "long_term_rent" as const,
        price: 5000,
        hourlyRate: 400,
        address: "42 Rogbaneh Road, Makeni",
        latitude: 8.8833,
        longitude: -12.0444,
        bedrooms: 4,
        bathrooms: 3,
        areaSqM: 280,
        amenities: ["Generator", "Solar System", "Paved Parking", "High Visibility"],
        imageUrls: [
          "https://images.unsplash.com/photo-1568605117036-5fe5e7bab0b7?w=800",
          "https://images.unsplash.com/photo-1570129477492-45c003edd2be?w=800",
        ],
      },
      {
        city: "Waterloo",
        title: "Waterloo Highway Family Compound",
        description: "Sprawling 4-bedroom gated family estate located along the Newton-Waterloo corridor. Fully surveyed and titled. High-capacity water well and ample land for expansion.",
        category: "sale" as const,
        price: 480000,
        hourlyRate: undefined,
        address: "8 Newton Road, Waterloo",
        latitude: 8.3386,
        longitude: -13.0708,
        bedrooms: 4,
        bathrooms: 3,
        areaSqM: 320,
        amenities: ["Freehold Title", "Water Well", "Perimeter Wall", "Large Compound"],
        imageUrls: [
          "https://images.unsplash.com/photo-1598228723793-52759bba239c?w=800",
          "https://images.unsplash.com/photo-1576941089067-2de3c901e126?w=800",
        ],
      },
    ];

    // 3. Vehicle Catalog by City
    const vehicleCatalog = [
      {
        city: "Freetown",
        make: "Toyota",
        model: "Land Cruiser Prado TX",
        year: 2021,
        color: "Pearl White",
        licensePlate: "ARE 412",
        vehicleType: "truck" as const,
        listingIntent: "sale" as const,
        salePrice: 650000,
        pricePerDay: undefined,
        latitude: 8.4840,
        longitude: -13.2450,
        imageUrls: [
          "https://images.unsplash.com/photo-1594502184342-2e12f877aa73?w=800",
          "https://images.unsplash.com/photo-1549399542-7e3f8b79c341?w=800",
        ],
      },
      {
        city: "Freetown",
        make: "TVS",
        model: "King Deluxe 4S (Keke)",
        year: 2023,
        color: "Sunny Yellow",
        licensePlate: "KKE 891",
        vehicleType: "bike" as const,
        listingIntent: "sale" as const,
        salePrice: 88000,
        pricePerDay: 400,
        latitude: 8.4720,
        longitude: -13.2500,
        imageUrls: [
          "https://images.unsplash.com/photo-1568605117036-5fe5e7bab0b7?w=800",
        ],
      },
      {
        city: "Freetown",
        make: "Hyundai",
        model: "Santa Fe 4WD",
        year: 2020,
        color: "Silver Metallic",
        licensePlate: "ARE 903",
        vehicleType: "taxi" as const,
        listingIntent: "rental" as const,
        salePrice: undefined,
        pricePerDay: 1200,
        latitude: 8.4780,
        longitude: -13.2600,
        imageUrls: [
          "https://images.unsplash.com/photo-1533473359331-0135ef1b58bf?w=800",
        ],
      },
      {
        city: "Bo",
        make: "TVS",
        model: "Star HLX 125 (Okada)",
        year: 2023,
        color: "Flame Red",
        licensePlate: "BO 2041",
        vehicleType: "bike" as const,
        listingIntent: "sale" as const,
        salePrice: 32000,
        pricePerDay: 150,
        latitude: 7.9644,
        longitude: -11.7383,
        imageUrls: [
          "https://images.unsplash.com/photo-1558981403-c5f9899a28bc?w=800",
        ],
      },
      {
        city: "Makeni",
        make: "Toyota",
        model: "Hilux Double Cabin 4x4",
        year: 2019,
        color: "Arctic White",
        licensePlate: "MAK 782",
        vehicleType: "delivery_van" as const,
        listingIntent: "rental" as const,
        salePrice: undefined,
        pricePerDay: 1600,
        latitude: 8.8833,
        longitude: -12.0444,
        imageUrls: [
          "https://images.unsplash.com/photo-1559416523-140ddc3d238c?w=800",
        ],
      },
    ];

    // Seed Properties
    if (args.vertical === "property" || args.vertical === "both") {
      const filteredProperties = realEstateCatalog.filter(
        (p) => !args.city || p.city.toLowerCase() === targetCity.toLowerCase()
      );
      const itemsToSeed = filteredProperties.length > 0 ? filteredProperties : realEstateCatalog;

      for (const item of itemsToSeed) {
        const geohash = encodeGeohash(item.latitude, item.longitude, 7);
        await ctx.db.insert("realEstateListings", {
          ownerId: adminUser._id,
          title: item.title,
          description: item.description,
          category: item.category,
          price: item.price,
          hourlyRate: item.hourlyRate,
          currency: "SLE",
          address: item.address,
          city: item.city,
          country: "Sierra Leone",
          latitude: item.latitude,
          longitude: item.longitude,
          geohash,
          bedrooms: item.bedrooms,
          bathrooms: item.bathrooms,
          areaSqM: item.areaSqM,
          amenities: item.amenities,
          imageUrls: item.imageUrls,
          availabilityStatus: "available",
          isFeatured: true,
          isPublished,
          viewCount: Math.floor(Math.random() * 50) + 5,
          updatedAt: now,
        });
        propertiesCount++;
      }
    }

    // Seed Vehicles
    if (args.vertical === "vehicle" || args.vertical === "both") {
      const filteredVehicles = vehicleCatalog.filter(
        (v) => !args.city || v.city.toLowerCase() === targetCity.toLowerCase()
      );
      const itemsToSeed = filteredVehicles.length > 0 ? filteredVehicles : vehicleCatalog;

      for (const item of itemsToSeed) {
        const geohash = encodeGeohash(item.latitude, item.longitude, 7);
        const category = (item.listingIntent === "rental" ? "car_rental" :
          (item.vehicleType as string) === "delivery_van" ? "delivery_van" :
          (item.vehicleType as string) === "truck" ? "sand_dump_truck" : "car_sale") as
          "car_sale" | "car_rental" | "delivery_van" | "sand_dump_truck" | "container_freight_truck";
        const pricingType = category === "car_sale" ? "total_sale" : category === "car_rental" ? "per_day" : "per_trip";
        const price = item.salePrice ?? item.pricePerDay ?? 50000;
        const title = `${item.year} ${item.make} ${item.model}`;

        await ctx.db.insert("vehicleListings", {
          ownerId: adminUser._id,
          title,
          category,
          price,
          pricingType,
          capacity: item.vehicleType === "delivery_van" ? "2 Tons Payload" : item.vehicleType === "truck" ? "20 Tons Tipper" : undefined,
          location: `${targetCity}, Sierra Leone`,
          images: item.imageUrls,
          status: "AVAILABLE",
          createdAt: now,
          vehicleType: item.vehicleType,
          listingIntent: item.listingIntent,
          make: item.make,
          model: item.model,
          year: item.year,
          color: item.color,
          licensePlate: item.licensePlate,
          imageUrls: item.imageUrls,
          pricePerKm: undefined,
          pricePerDay: item.pricePerDay,
          salePrice: item.salePrice,
          currency: "SLE",
          latitude: item.latitude,
          longitude: item.longitude,
          geohash,
          availabilityStatus: "available",
          isPublished,
          updatedAt: now,
        });
        vehiclesCount++;
      }
    }

    return {
      propertiesCount,
      vehiclesCount,
      message: `Injected ${propertiesCount} properties and ${vehiclesCount} vehicles in ${targetCity} (isPublished: ${isPublished})`,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 GET ADMIN LISTINGS (ALL VISIBILITY STATES)
// ═══════════════════════════════════════════════════════════════════════

export const getAdminListings = query({
  args: {
    vertical: v.optional(v.string()),
  },
  returns: v.array(
    v.object({
      id: v.string(),
      type: v.string(),
      title: v.string(),
      subtitle: v.string(),
      price: v.number(),
      currency: v.string(),
      city: v.string(),
      isPublished: v.boolean(),
      imageUrl: v.string(),
      createdAt: v.number(),
    })
  ),
  handler: async (ctx, args) => {
    const results: Array<{
      id: string;
      type: string;
      title: string;
      subtitle: string;
      price: number;
      currency: string;
      city: string;
      isPublished: boolean;
      imageUrl: string;
      createdAt: number;
    }> = [];

    const fetchProperties = !args.vertical || args.vertical === "property" || args.vertical === "all";
    const fetchVehicles = !args.vertical || args.vertical === "vehicle" || args.vertical === "all" ||
      args.vertical === "car_sale" || args.vertical === "car_rental" || args.vertical === "delivery_van" ||
      args.vertical === "sand_dump_truck" || args.vertical === "container_freight_truck";

    if (fetchProperties) {
      const properties = await ctx.db.query("realEstateListings").order("desc").take(50);
      for (const p of properties) {
        results.push({
          id: p._id as string,
          type: "property",
          title: p.title,
          subtitle: `${p.category.replace(/_/g, " ")} • ${p.address}`,
          price: p.price,
          currency: p.currency ?? "SLE",
          city: p.city ?? "Sierra Leone",
          isPublished: p.isPublished ?? true,
          imageUrl: p.imageUrls[0] ?? "",
          createdAt: p._creationTime,
        });
      }
    }

    if (fetchVehicles) {
      const vehicles = await ctx.db.query("vehicleListings").order("desc").take(50);
      for (const v of vehicles) {
        if (args.vertical && ["car_sale", "car_rental", "delivery_van", "sand_dump_truck", "container_freight_truck"].includes(args.vertical)) {
          if (v.category !== args.vertical) continue;
        }
        const img = (v.images && v.images[0]) || (v.imageUrls && v.imageUrls[0]) || "";
        const categoryLabel = (v.category ?? v.vehicleType ?? "commercial")
          .replace(/_/g, " ")
          .replace(/\b\w/g, (c: string) => c.toUpperCase());
        const pricingLabel = v.pricingType ? ` • ${v.pricingType.replace(/_/g, " ")}` : "";
        const capacityLabel = v.capacity ? ` • ${v.capacity}` : "";

        results.push({
          id: v._id as string,
          type: "vehicle",
          title: v.title || `${v.year ?? 2024} ${v.make ?? ""} ${v.model ?? ""}`.trim(),
          subtitle: `${categoryLabel}${capacityLabel}${pricingLabel}`,
          price: v.price ?? v.salePrice ?? v.pricePerDay ?? 0,
          currency: v.currency ?? "SLE",
          city: v.location || "Sierra Leone",
          isPublished: v.isPublished ?? (v.status === "AVAILABLE"),
          imageUrl: img,
          createdAt: v.createdAt ?? v._creationTime,
        });
      }
    }

    // Sort newest first
    results.sort((a, b) => b.createdAt - a.createdAt);
    return results;
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                   TOGGLE LISTING PUBLISHED STATUS
// ═══════════════════════════════════════════════════════════════════════

export const toggleListingPublished = mutation({
  args: {
    listingType: v.union(v.literal("property"), v.literal("vehicle")),
    listingId: v.string(),
    isPublished: v.boolean(),
  },
  returns: v.object({
    success: v.boolean(),
    isPublished: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const now = Date.now();

    if (args.listingType === "property") {
      const id = ctx.db.normalizeId("realEstateListings", args.listingId);
      if (!id) throw new Error("Invalid property listing ID");
      await ctx.db.patch(id, { isPublished: args.isPublished, updatedAt: now });
      return { success: true, isPublished: args.isPublished };
    } else {
      const id = ctx.db.normalizeId("vehicleListings", args.listingId);
      if (!id) throw new Error("Invalid vehicle listing ID");
      await ctx.db.patch(id, { isPublished: args.isPublished, updatedAt: now });
      return { success: true, isPublished: args.isPublished };
    }
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                      DELETE ADMIN TEST LISTING
// ═══════════════════════════════════════════════════════════════════════

export const deleteAdminListing = mutation({
  args: {
    listingType: v.union(v.literal("property"), v.literal("vehicle")),
    listingId: v.string(),
  },
  returns: v.object({
    success: v.boolean(),
  }),
  handler: async (ctx, args) => {
    if (args.listingType === "property") {
      const id = ctx.db.normalizeId("realEstateListings", args.listingId);
      if (!id) throw new Error("Invalid property listing ID");
      await ctx.db.delete(id);
      return { success: true };
    } else {
      const id = ctx.db.normalizeId("vehicleListings", args.listingId);
      if (!id) throw new Error("Invalid vehicle listing ID");
      await ctx.db.delete(id);
      return { success: true };
    }
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                   CLEAR ALL IMAGE POSTS & LISTINGS
// ═══════════════════════════════════════════════════════════════════════

export const clearAllListings = mutation({
  args: {},
  returns: v.object({
    success: v.boolean(),
    propertiesCleared: v.number(),
    vehiclesCleared: v.number(),
    message: v.string(),
  }),
  handler: async (ctx) => {
    const properties = await ctx.db.query("realEstateListings").collect();
    let propCount = 0;
    for (const p of properties) {
      await ctx.db.delete(p._id);
      propCount++;
    }

    const vehicles = await ctx.db.query("vehicleListings").collect();
    let vehCount = 0;
    for (const v of vehicles) {
      await ctx.db.delete(v._id);
      vehCount++;
    }

    return {
      success: true,
      propertiesCleared: propCount,
      vehiclesCleared: vehCount,
      message: `Successfully cleared ${propCount} properties and ${vehCount} vehicles from Convex.`,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    BATCH GENERATE UPLOAD URLS
// ═══════════════════════════════════════════════════════════════════════

export const batchGenerateUploadUrls = mutation({
  args: {
    count: v.number(),
  },
  returns: v.array(v.string()),
  handler: async (ctx, args) => {
    const count = Math.min(Math.max(args.count, 1), 10);
    const urls: string[] = [];
    for (let i = 0; i < count; i++) {
      urls.push(await ctx.storage.generateUploadUrl());
    }
    return urls;
  },
});

/**
 * Helper to validate admin authorization.
 * Resolves user, confirms role === "admin", and safely checks session token if provided.
 */
async function validateAdminSession(ctx: any, adminId: string, sessionToken?: string) {
  const adminDocId = ctx.db.normalizeId("users", adminId);
  if (!adminDocId) {
    throw new Error("Unauthorized: Invalid administrator credentials.");
  }
  const adminUser = await ctx.db.get(adminDocId);
  if (!adminUser || adminUser.role !== "admin") {
    throw new Error("Forbidden: Access restricted to platform administrators.");
  }
  if (sessionToken && adminUser.sessionToken && adminUser.sessionToken !== sessionToken) {
    throw new Error("Unauthorized: Session token expired. Please sign in again.");
  }
  return { adminDocId, adminUser };
}

// ═══════════════════════════════════════════════════════════════════════
//                 GET ALL USERS (ADMIN DIRECTORY)
// ═══════════════════════════════════════════════════════════════════════

export const getAllUsers = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    roleFilter: v.optional(v.string()),
    searchQuery: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    let usersQuery;
    if (args.roleFilter && args.roleFilter !== "all") {
      usersQuery = await ctx.db
        .query("users")
        .withIndex("by_role", (q) => q.eq("role", args.roleFilter as any))
        .take(200);
    } else {
      usersQuery = await ctx.db
        .query("users")
        .order("desc")
        .take(200);
    }

    let results = usersQuery;
    if (args.searchQuery && args.searchQuery.trim()) {
      const q = args.searchQuery.toLowerCase().trim();
      results = results.filter((u) =>
        (u.name && u.name.toLowerCase().includes(q)) ||
        (u.email && u.email.toLowerCase().includes(q)) ||
        (u.phone && u.phone.includes(q)) ||
        (u.businessName && u.businessName.toLowerCase().includes(q))
      );
    }

    return results.map((u) => ({
      id: u._id as string,
      name: u.name,
      email: u.email,
      phone: u.phone,
      role: u.role,
      activeRole: u.activeRole,
      isVerified: u.isVerified === true,
      verificationStatus: u.verificationStatus ?? (u.isVerified ? "verified" : "unverified"),
      isActive: u.isActive !== false,
      businessName: u.businessName,
      tinNumber: u.tinNumber,
      avatarUrl: u.avatarUrl,
      walletAddress: u.walletAddress,
      createdAt: u._creationTime,
      updatedAt: u.updatedAt,
    }));
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 TOGGLE USER ACTIVE STATUS (ADMIN)
// ═══════════════════════════════════════════════════════════════════════

export const toggleUserActiveStatus = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    userId: v.string(),
    isActive: v.boolean(),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const targetDocId = ctx.db.normalizeId("users", args.userId);
    if (!targetDocId) throw new Error("User not found.");

    await ctx.db.patch(targetDocId, {
      isActive: args.isActive,
      updatedAt: Date.now(),
    });

    return { success: true };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 TAKE DOWN LISTING (ADMIN)
// ═══════════════════════════════════════════════════════════════════════

export const takeDownListing = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    listingId: v.string(),
    listingType: v.union(v.literal("property"), v.literal("vehicle")),
    reason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    if (args.listingType === "property") {
      const id = ctx.db.normalizeId("realEstateListings", args.listingId);
      if (!id) throw new Error("Invalid property listing ID");
      await ctx.db.patch(id, { isPublished: false, isDeleted: true, updatedAt: Date.now() });
    } else {
      const id = ctx.db.normalizeId("vehicleListings", args.listingId);
      if (!id) throw new Error("Invalid vehicle listing ID");
      await ctx.db.patch(id, { isPublished: false, isDeleted: true, updatedAt: Date.now() });
    }

    return { success: true };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 GET USER FULL DETAILS (ADMIN INSPECT)
// ═══════════════════════════════════════════════════════════════════════

export const getUserFullDetails = query({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const targetDocId = ctx.db.normalizeId("users", args.userId);
    if (!targetDocId) return null;
    const user = await ctx.db.get(targetDocId);
    if (!user) return null;

    // Fetch listings
    const properties = await ctx.db
      .query("realEstateListings")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .filter((q) => q.neq(q.field("isDeleted"), true))
      .collect();

    const vehicles = await ctx.db
      .query("vehicleListings")
      .withIndex("by_owner", (q) => q.eq("ownerId", user._id))
      .filter((q) => q.neq(q.field("isDeleted"), true))
      .collect();

    // Merchant profile
    const merchantProfile = await ctx.db
      .query("merchant_profiles")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .first();

    // User sessions (Audit Log)
    const userSessions = await ctx.db
      .query("user_sessions")
      .withIndex("by_userId", (q) => q.eq("userId", user._id))
      .order("desc")
      .take(15);

    // Wallet balances
    const wallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", user._id).eq("currency", "SLE")
      )
      .first();

    // User transactions (Full Ledger History)
    const userTransactions = await ctx.db
      .query("transactions")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .order("desc")
      .take(30);

    // Fallback session if none explicitly recorded yet
    const sessions =
      userSessions.length > 0
        ? userSessions.map((s) => ({
            id: s._id as string,
            deviceModel: s.deviceModel ?? "Mobile Client",
            osVersion: s.osVersion ?? "iOS / Android",
            appVersion: s.appVersion ?? "1.0.4",
            isActive: s.isActive,
            loginAt: s.loginAt,
            logoutAt: s.logoutAt,
            lastActiveAt: s.lastActiveAt,
          }))
        : [
            {
              id: "session_primary",
              deviceModel: "Apple iPhone 15 Pro",
              osVersion: "iOS 18.2",
              appVersion: "1.0.4",
              isActive: user.isActive,
              loginAt: user._creationTime,
              logoutAt: user.isActive ? undefined : user.updatedAt,
              lastActiveAt: user.updatedAt || user._creationTime,
            },
          ];

    return {
      user: {
        id: user._id as string,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role,
        kycStatus:
          user.kycStatus ?? (user.isVerified ? "VERIFIED" : "PENDING_VERIFICATION"),
        verificationStatus: user.verificationStatus ?? "unverified",
        verificationBadge: user.verificationBadge ?? "NONE",
        isActive: user.isActive,
        bio: user.bio,
        avatarUrl: user.avatarUrl,
        businessName: user.businessName ?? merchantProfile?.businessName,
        tinNumber: user.tinNumber ?? merchantProfile?.tinNumber,
        documentUrl: user.documentUrl ?? merchantProfile?.documentUrl,
        rejectionReason: user.rejectionReason,
        createdAt: user._creationTime,
        updatedAt: user.updatedAt,
      },
      wallet: wallet
        ? {
            availableBalance: wallet.availableBalance,
            escrowBalance: wallet.escrowBalance ?? 0,
            pendingBalance: wallet.pendingBalance,
            currency: wallet.currency,
          }
        : {
            availableBalance: 0,
            escrowBalance: 0,
            pendingBalance: 0,
            currency: "SLE",
          },
      sessions,
      transactions: userTransactions.map((tx) => ({
        id: tx._id as string,
        type: tx.type,
        amount: tx.amount,
        currency: tx.currency ?? "SLE",
        status: tx.status,
        description: tx.description || `${tx.type} transaction`,
        counterpartyPhone: tx.counterpartyPhone,
        counterpartyName: tx.counterpartyName,
        createdAt: tx._creationTime,
      })),
      properties: properties.map((p) => ({
        id: p._id as string,
        title: p.title,
        category: p.category,
        price: p.price,
        city: p.city,
        isPublished: p.isPublished,
        imageUrls: p.imageUrls,
        createdAt: p.updatedAt ?? p._creationTime,
      })),
      vehicles: vehicles.map((v) => ({
        id: v._id as string,
        make: v.make,
        model: v.model,
        year: v.year,
        vehicleType: v.vehicleType,
        listingIntent: v.listingIntent,
        salePrice: v.salePrice,
        pricePerDay: v.pricePerDay,
        isPublished: v.isPublished,
        imageUrls: v.imageUrls,
        createdAt: v.updatedAt ?? v._creationTime,
      })),
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    VERIFY USER (ADMIN)
// ═══════════════════════════════════════════════════════════════════════

export const verifyUser = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const targetDocId = ctx.db.normalizeId("users", args.userId);
    if (!targetDocId) throw new Error("User not found.");

    await ctx.db.patch(targetDocId, {
      kycStatus: "VERIFIED",
      isVerified: true,
      verificationStatus: "verified",
      verificationBadge: "GREEN_TICK",
      verifiedAt: Date.now(),
      updatedAt: Date.now(),
    });

    return { success: true, message: "User verified successfully." };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                  SET USER STATUS (SUSPEND / BAN / ACTIVATE)
// ═══════════════════════════════════════════════════════════════════════

export const setUserStatus = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    userId: v.string(),
    status: v.union(v.literal("ACTIVE"), v.literal("SUSPENDED"), v.literal("BANNED")),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const targetDocId = ctx.db.normalizeId("users", args.userId);
    if (!targetDocId) throw new Error("User not found.");

    const isActive = args.status === "ACTIVE";
    const verificationStatus = args.status === "ACTIVE" ? "verified" : "suspended";
    const kycStatus = args.status === "ACTIVE" ? "VERIFIED" : args.status;

    if (!isActive) {
      await ctx.db.patch(targetDocId, {
        isActive: false,
        sessionToken: undefined,
        kycStatus,
        verificationStatus,
        updatedAt: Date.now(),
      });
      // Immediately invalidate active user sessions
      const activeSessions = await ctx.db
        .query("user_sessions")
        .withIndex("by_userId", (q) => q.eq("userId", targetDocId))
        .filter((q) => q.eq(q.field("isActive"), true))
        .collect();
      for (const s of activeSessions) {
        await ctx.db.patch(s._id, {
          isActive: false,
          logoutAt: Date.now(),
        });
      }
    } else {
      await ctx.db.patch(targetDocId, {
        isActive: true,
        kycStatus: "VERIFIED",
        verificationStatus: "verified",
        updatedAt: Date.now(),
      });
    }

    return { success: true, status: args.status };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    DELETE USER (ADMIN)
// ═══════════════════════════════════════════════════════════════════════

export const deleteUser = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
    userId: v.string(),
  },
  handler: async (ctx, args) => {
    await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const targetDocId = ctx.db.normalizeId("users", args.userId);
    if (!targetDocId) throw new Error("User not found.");

    // Archive user's property listings
    const props = await ctx.db
      .query("realEstateListings")
      .withIndex("by_owner", (q) => q.eq("ownerId", targetDocId))
      .collect();
    for (const p of props) {
      await ctx.db.patch(p._id, { isDeleted: true, isPublished: false });
    }

    // Archive user's vehicle listings
    const vechs = await ctx.db
      .query("vehicleListings")
      .withIndex("by_owner", (q) => q.eq("ownerId", targetDocId))
      .collect();
    for (const v of vechs) {
      await ctx.db.patch(v._id, { isDeleted: true, isPublished: false });
    }

    // Remove follows
    const follows = await ctx.db
      .query("follows")
      .withIndex("by_follower", (q) => q.eq("followerId", targetDocId))
      .collect();
    for (const f of follows) {
      await ctx.db.delete(f._id);
    }

    // Delete user
    await ctx.db.delete(targetDocId);

    return { success: true, message: "User and associated content removed." };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                  PURGE MOCK / SEED USERS (ADMIN)
// ═══════════════════════════════════════════════════════════════════════

export const purgeMockUsers = mutation({
  args: {
    adminId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const { adminDocId } = await validateAdminSession(ctx, args.adminId, args.sessionToken);

    const mockEmails = ["demo@vektolux.sl", "driver@vektolux.sl", "agent@vektolux.sl"];
    const mockNames = ["Fatmatta Bangura", "Abu Kamara", "Lamin Sesay"];

    let purgedCount = 0;

    const allUsers = await ctx.db.query("users").collect();
    for (const u of allUsers) {
      const isMock =
        mockEmails.includes(u.email) ||
        mockNames.includes(u.name) ||
        (u.email === "admin@vektolux.sl" && u.name === "Vektolux Administrator");

      if (isMock) {
        if (u._id === adminDocId) {
          await ctx.db.patch(u._id, {
            name: "Platform Administrator",
            updatedAt: Date.now(),
          });
          continue;
        }

        const wallets = await ctx.db
          .query("walletBalances")
          .withIndex("by_user", (q) => q.eq("userId", u._id))
          .collect();
        for (const w of wallets) {
          await ctx.db.delete(w._id);
        }

        await ctx.db.delete(u._id);
        purgedCount++;
      }
    }

    return { success: true, purgedCount, message: `Successfully purged ${purgedCount} mock user accounts.` };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//      PURGE ALL MOCK USERS & ENFORCE SINGLE PRODUCTION USER
// ═══════════════════════════════════════════════════════════════════════

export const purgeAllMockUsersAndEnforceSingleUser = mutation({
  args: {
    adminId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.adminId) {
      await validateAdminSession(ctx, args.adminId, args.sessionToken);
    }

    const now = Date.now();
    const TARGET_EMAIL = "alfred.kargbo@vektolux.com";
    const TARGET_NAME = "Alfred Manso Kargbo";
    const TARGET_PHONE = "+232688577868";
    const TARGET_PASSWORD_HASH =
      "8f26796073cec5b2d34a862b351b7c15:519b4b98224792d0f7e3236126d0993b05b4f4b701da3f0d63d2661d8366f4bd"; // password123

    // 1. Locate primary production user
    let primaryUser = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", TARGET_EMAIL))
      .first();

    if (!primaryUser) {
      primaryUser = await ctx.db
        .query("users")
        .withIndex("by_phone", (q) => q.eq("phone", TARGET_PHONE))
        .first();
    }

    if (!primaryUser) {
      const newId = await ctx.db.insert("users", {
        name: TARGET_NAME,
        email: TARGET_EMAIL,
        phone: TARGET_PHONE,
        role: "admin",
        activeRole: "admin",
        passwordHash: TARGET_PASSWORD_HASH,
        sessionToken: `vktlx_session_${now}`,
        isVerified: true,
        isVerifiedAgent: true,
        isVerifiedMerchant: true,
        isVerifiedDriver: true,
        verificationBadge: "GREEN_TICK",
        verificationStatus: "verified",
        kycStatus: "VERIFIED",
        isActive: true,
        updatedAt: now,
      });
      primaryUser = (await ctx.db.get(newId))!;
    } else {
      await ctx.db.patch(primaryUser._id, {
        name: TARGET_NAME,
        email: TARGET_EMAIL,
        phone: TARGET_PHONE,
        role: "admin",
        activeRole: "admin",
        passwordHash: TARGET_PASSWORD_HASH,
        isVerified: true,
        isVerifiedAgent: true,
        isVerifiedMerchant: true,
        isVerifiedDriver: true,
        verificationBadge: "GREEN_TICK",
        verificationStatus: "verified",
        kycStatus: "VERIFIED",
        isActive: true,
        updatedAt: now,
      });
      primaryUser = (await ctx.db.get(primaryUser._id))!;
    }

    const primaryUserId = primaryUser._id;

    // 2. Re-assign all existing properties and vehicles to primary user so they are NOT orphaned
    const allProperties = await ctx.db.query("realEstateListings").collect();
    let reallocatedProperties = 0;
    for (const prop of allProperties) {
      if (prop.ownerId !== primaryUserId) {
        await ctx.db.patch(prop._id, {
          ownerId: primaryUserId,
          updatedAt: now,
        });
        reallocatedProperties++;
      }
    }

    const allVehicles = await ctx.db.query("vehicleListings").collect();
    let reallocatedVehicles = 0;
    for (const veh of allVehicles) {
      if (veh.ownerId !== primaryUserId) {
        await ctx.db.patch(veh._id, {
          ownerId: primaryUserId,
          updatedAt: now,
        });
        reallocatedVehicles++;
      }
    }

    // 3. Purge all other users from the database
    const allUsers = await ctx.db.query("users").collect();
    let deletedUsersCount = 0;

    for (const u of allUsers) {
      if (u._id === primaryUserId) continue;

      const wallets = await ctx.db
        .query("walletBalances")
        .withIndex("by_user", (q) => q.eq("userId", u._id))
        .collect();
      for (const w of wallets) {
        await ctx.db.delete(w._id);
      }

      const follows = await ctx.db
        .query("follows")
        .withIndex("by_follower", (q) => q.eq("followerId", u._id))
        .collect();
      for (const f of follows) {
        await ctx.db.delete(f._id);
      }

      const merchantProfiles = await ctx.db
        .query("merchant_profiles")
        .withIndex("by_user", (q) => q.eq("userId", u._id))
        .collect();
      for (const mp of merchantProfiles) {
        await ctx.db.delete(mp._id);
      }

      await ctx.db.delete(u._id);
      deletedUsersCount++;
    }

    // 4. Ensure primary user has a valid active wallet balance
    let primaryWallet = await ctx.db
      .query("walletBalances")
      .withIndex("by_user_currency", (q) =>
        q.eq("userId", primaryUserId).eq("currency", "SLE")
      )
      .first();

    if (!primaryWallet) {
      await ctx.db.insert("walletBalances", {
        userId: primaryUserId,
        availableBalance: 50000,
        pendingBalance: 0,
        escrowBalance: 0,
        currency: "SLE",
        updatedAt: now,
      });
    }

    return {
      success: true,
      preservedUser: {
        id: primaryUserId as string,
        name: primaryUser.name,
        email: primaryUser.email,
        phone: primaryUser.phone,
        role: primaryUser.role,
      },
      deletedUsersCount,
      reallocatedProperties,
      reallocatedVehicles,
      message: `Successfully enforced single-user mode. Purged ${deletedUsersCount} mock/demo accounts. Retained ${primaryUser.name} (${primaryUser.email}).`,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//               CLEAN MOCK DATA (ONE-TIME PURGE & SINGLE-USER)
// ═══════════════════════════════════════════════════════════════════════

export const cleanMockData = mutation({
  args: {
    dryRun: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const isDryRun = args.dryRun ?? false;

    // 1. Inspect table 'users' -> keep ONLY Alfred Manso Kargbo
    const allUsers = await ctx.db.query("users").collect();
    let primaryUser = allUsers.find(
      (u) =>
        u.email.toLowerCase() === "alfred.kargbo@vektolux.com" ||
        u.phone === "+232688577868" ||
        u.name.toLowerCase().includes("alfred manso kargbo")
    );

    if (!primaryUser) {
      if (!isDryRun) {
        const primaryId = await ctx.db.insert("users", {
          name: "Alfred Manso Kargbo",
          email: "alfred.kargbo@vektolux.com",
          phone: "+232688577868",
          role: "admin",
          activeRole: "admin",
          isVerified: true,
          isActive: true,
          isVerifiedAgent: true,
          isVerifiedMerchant: true,
          isVerifiedDriver: true,
          verificationStatus: "verified",
          verificationBadge: "GREEN_TICK",
          kycStatus: "VERIFIED",
          updatedAt: now,
        });
        primaryUser = (await ctx.db.get(primaryId))!;
      } else {
        primaryUser = {
          _id: "placeholder" as any,
          _creationTime: now,
          name: "Alfred Manso Kargbo",
          email: "alfred.kargbo@vektolux.com",
          phone: "+232688577868",
          role: "admin",
          isVerified: true,
          isActive: true,
          updatedAt: now,
        };
      }
    } else if (!isDryRun) {
      await ctx.db.patch(primaryUser._id, {
        name: "Alfred Manso Kargbo",
        email: "alfred.kargbo@vektolux.com",
        phone: "+232688577868",
        role: "admin",
        activeRole: "admin",
        isVerified: true,
        isActive: true,
        isVerifiedAgent: true,
        isVerifiedMerchant: true,
        isVerifiedDriver: true,
        verificationStatus: "verified",
        verificationBadge: "GREEN_TICK",
        kycStatus: "VERIFIED",
        updatedAt: now,
      });
    }

    const primaryUserId = primaryUser._id;

    // Delete all other users and their related records
    let deletedUsersCount = 0;
    const deletedUserSummaries: string[] = [];

    for (const u of allUsers) {
      if (u._id === primaryUserId) continue;

      if (!isDryRun) {
        // walletBalances
        const wallets = await ctx.db
          .query("walletBalances")
          .withIndex("by_user", (q) => q.eq("userId", u._id))
          .collect();
        for (const w of wallets) {
          await ctx.db.delete(w._id);
        }

        // follows
        const f1 = await ctx.db
          .query("follows")
          .withIndex("by_follower", (q) => q.eq("followerId", u._id))
          .collect();
        for (const f of f1) await ctx.db.delete(f._id);
        const f2 = await ctx.db
          .query("follows")
          .withIndex("by_following", (q) => q.eq("followingId", u._id))
          .collect();
        for (const f of f2) await ctx.db.delete(f._id);

        // merchant_profiles
        const mps = await ctx.db
          .query("merchant_profiles")
          .withIndex("by_user", (q) => q.eq("userId", u._id))
          .collect();
        for (const mp of mps) await ctx.db.delete(mp._id);

        // user_payment_accounts
        const upas = await ctx.db
          .query("user_payment_accounts")
          .withIndex("by_user", (q) => q.eq("userId", u._id))
          .collect();
        for (const upa of upas) await ctx.db.delete(upa._id);

        // user_fcm_tokens
        const tokens = await ctx.db
          .query("user_fcm_tokens")
          .withIndex("by_user", (q) => q.eq("userId", u._id as string))
          .collect();
        for (const tk of tokens) await ctx.db.delete(tk._id);

        // role_applications
        const apps = await ctx.db
          .query("role_applications")
          .withIndex("by_user", (q) => q.eq("userId", u._id))
          .collect();
        for (const app of apps) await ctx.db.delete(app._id);

        // identity_checks
        const checks = await ctx.db
          .query("identity_checks")
          .withIndex("by_user", (q) => q.eq("userId", u._id))
          .collect();
        for (const chk of checks) await ctx.db.delete(chk._id);

        await ctx.db.delete(u._id);
      }
      deletedUsersCount++;
      deletedUserSummaries.push(`${u.name} (${u.email}) [${u.role}]`);
    }

    // 2. Inspect table 'transactions' -> delete all fake/mock entries
    const allTransactions = await ctx.db.query("transactions").collect();
    let deletedTransactionsCount = 0;
    for (const t of allTransactions) {
      const isFake =
        t.agentNumber === "001" ||
        t.amount === 250 ||
        t.amount === 1796 ||
        t.userId !== primaryUserId ||
        (t.description && t.description.toLowerCase().includes("mock")) ||
        (t.description && t.description.toLowerCase().includes("test")) ||
        (t.gatewayReference && t.gatewayReference.startsWith("MOCK-"));

      if (isFake) {
        if (!isDryRun) {
          await ctx.db.delete(t._id);
        }
        deletedTransactionsCount++;
      }
    }

    // 3. Inspect table 'walletBalances' -> reset Alfred to 0, delete others
    const allWallets = await ctx.db.query("walletBalances").collect();
    let resetWalletsCount = 0;
    let deletedWalletsCount = 0;

    for (const w of allWallets) {
      if (w.userId === primaryUserId) {
        if (!isDryRun) {
          await ctx.db.patch(w._id, {
            availableBalance: 0,
            pendingBalance: 0,
            escrowBalance: 0,
            updatedAt: now,
          });
        }
        resetWalletsCount++;
      } else {
        if (!isDryRun) {
          await ctx.db.delete(w._id);
        }
        deletedWalletsCount++;
      }
    }

    if (resetWalletsCount === 0 && !isDryRun) {
      await ctx.db.insert("walletBalances", {
        userId: primaryUserId,
        availableBalance: 0,
        pendingBalance: 0,
        escrowBalance: 0,
        currency: "SLE",
        updatedAt: now,
      });
      resetWalletsCount = 1;
    }

    // 4. Inspect table 'bookings' -> clear mock records
    const allBookings = await ctx.db.query("bookings").collect();
    let deletedBookingsCount = 0;
    for (const b of allBookings) {
      const isMockBooking =
        b.buyerId !== (primaryUserId as string) ||
        (b.txRef && b.txRef.startsWith("MOCK-")) ||
        (b.notes && b.notes.toLowerCase().includes("mock")) ||
        (b.listingTitle && b.listingTitle.toLowerCase().includes("test"));

      if (isMockBooking) {
        if (!isDryRun) {
          await ctx.db.delete(b._id);
        }
        deletedBookingsCount++;
      }
    }

    // Also clear mock realEstateBookings if any
    const allREBookings = await ctx.db.query("realEstateBookings").collect();
    let deletedREBookingsCount = 0;
    for (const reb of allREBookings) {
      if (reb.buyerId !== primaryUserId && reb.ownerId !== primaryUserId) {
        if (!isDryRun) {
          await ctx.db.delete(reb._id);
        }
        deletedREBookingsCount++;
      }
    }

    // 5. Inspect 'rideRequests' and 'trips_deliveries' (safely handled)
    let deletedRideRequests = 0;
    try {
      const rideRequests = await ctx.db.query("rideRequests" as any).collect();
      for (const rr of rideRequests) {
        if (!isDryRun) await ctx.db.delete(rr._id);
        deletedRideRequests++;
      }
    } catch {
      // Table does not exist in schema
    }

    let deletedTripsDeliveries = 0;
    try {
      const trips = await ctx.db.query("trips_deliveries" as any).collect();
      for (const tr of trips) {
        if (!isDryRun) await ctx.db.delete(tr._id);
        deletedTripsDeliveries++;
      }
    } catch {
      // Table does not exist in schema
    }

    // 6. Inspect 'telco_webhook_logs' -> clear mock webhook records
    const allWebhookLogs = await ctx.db.query("telco_webhook_logs").collect();
    let deletedWebhookLogsCount = 0;
    for (const wh of allWebhookLogs) {
      if (!isDryRun) {
        await ctx.db.delete(wh._id);
      }
      deletedWebhookLogsCount++;
    }

    // 6.5. Inspect 'user_notifications' -> clear dummy/mock notification history
    const allNotifications = await ctx.db.query("user_notifications").collect();
    let deletedNotificationsCount = 0;
    for (const notif of allNotifications) {
      if (!isDryRun) {
        await ctx.db.delete(notif._id);
      }
      deletedNotificationsCount++;
    }

    // 6.6. Inspect 'escrow_payment_claims' -> clear mock/dummy test claims
    const allClaims = await ctx.db.query("escrow_payment_claims").collect();
    let deletedClaimsCount = 0;
    for (const cl of allClaims) {
      const isMockClaim =
        cl.amount === 250 ||
        cl.amount === 50 ||
        cl.amount === 25 ||
        (cl.transactionReference && cl.transactionReference.includes("mock")) ||
        (cl.rejectionReason && cl.rejectionReason.includes("merchant portal"));
      if (isMockClaim) {
        if (!isDryRun) {
          await ctx.db.delete(cl._id);
        }
        deletedClaimsCount++;
      }
    }

    // 7. Reallocate orphaned real estate and vehicle listings to Alfred
    const allProps = await ctx.db.query("realEstateListings").collect();
    let reallocatedProps = 0;
    for (const p of allProps) {
      if (p.ownerId !== primaryUserId) {
        if (!isDryRun) {
          await ctx.db.patch(p._id, {
            ownerId: primaryUserId,
            updatedAt: now,
          });
        }
        reallocatedProps++;
      }
    }

    const allVehs = await ctx.db.query("vehicleListings").collect();
    let reallocatedVehs = 0;
    for (const v of allVehs) {
      if (v.ownerId !== primaryUserId) {
        if (!isDryRun) {
          await ctx.db.patch(v._id, {
            ownerId: primaryUserId,
            updatedAt: now,
          });
        }
        reallocatedVehs++;
      }
    }

    // 8. Count remaining documents
    const remainingUsers = await ctx.db.query("users").collect();
    const remainingTransactions = await ctx.db.query("transactions").collect();
    const remainingWallets = await ctx.db.query("walletBalances").collect();
    const remainingBookings = await ctx.db.query("bookings").collect();
    const remainingWebhookLogs = await ctx.db.query("telco_webhook_logs").collect();
    const remainingNotifications = await ctx.db.query("user_notifications").collect();

    return {
      success: true,
      dryRun: isDryRun,
      preservedUser: {
        id: primaryUserId as string,
        name: primaryUser.name,
        email: primaryUser.email,
        phone: primaryUser.phone,
        role: primaryUser.role,
      },
      purged: {
        deletedUsersCount,
        deletedUserSummaries,
        deletedTransactionsCount,
        deletedWalletsCount,
        resetWalletsCount,
        deletedBookingsCount,
        deletedREBookingsCount,
        deletedRideRequests,
        deletedTripsDeliveries,
        deletedWebhookLogsCount,
        deletedNotificationsCount,
        deletedClaimsCount,
        reallocatedProps,
        reallocatedVehs,
      },
      verification: {
        remainingUsersCount: remainingUsers.length,
        remainingTransactionsCount: remainingTransactions.length,
        remainingWalletsCount: remainingWallets.length,
        remainingBookingsCount: remainingBookings.length,
        remainingWebhookLogsCount: remainingWebhookLogs.length,
        remainingNotificationsCount: remainingNotifications.length,
      },
      message: isDryRun
        ? `[DRY RUN] Would purge ${deletedUsersCount} users, ${deletedTransactionsCount} transactions, ${deletedNotificationsCount} notifications, reset Alfred's wallet to 0.`
        : `Successfully purged ${deletedUsersCount} mock users, ${deletedTransactionsCount} mock transactions, and ${deletedNotificationsCount} mock notifications. Reset Alfred's wallet to 0 SLE. Retained 1 production user: ${primaryUser.name} (${primaryUser.email}).`,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//               PURGE MOCK NOTIFICATIONS (STANDALONE)
// ═══════════════════════════════════════════════════════════════════════

export const purgeMockNotifications = mutation({
  args: {
    adminId: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    if (args.adminId) {
      await validateAdminSession(ctx, args.adminId, args.sessionToken);
    }

    const allNotifications = await ctx.db.query("user_notifications").collect();
    let deletedCount = 0;
    for (const notif of allNotifications) {
      await ctx.db.delete(notif._id);
      deletedCount++;
    }

    return {
      success: true,
      deletedCount,
      message: `Purged ${deletedCount} notification history records from the database.`,
    };
  },
});

