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

    // 1. Ensure a demo admin/agent user exists to own these listings
    let adminUser = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", "admin@vektolux.sl"))
      .first();

    if (!adminUser) {
      const adminId = await ctx.db.insert("users", {
        name: "Vektolux Dev/Admin",
        email: "admin@vektolux.sl",
        phone: "+232 76 000 999",
        role: "admin",
        activeRole: "admin",
        isVerified: true,
        isActive: true,
        avatarUrl: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400",
        verificationStatus: "verified",
        verificationBadge: "GREEN_TICK",
        updatedAt: now,
      });
      adminUser = await ctx.db.get(adminId);
    }

    if (!adminUser) {
      throw new Error("Failed to resolve admin owner account.");
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
        await ctx.db.insert("vehicleListings", {
          ownerId: adminUser._id,
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
    vertical: v.optional(v.union(v.literal("property"), v.literal("vehicle"), v.literal("all"))),
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
    const fetchVehicles = !args.vertical || args.vertical === "vehicle" || args.vertical === "all";

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
        results.push({
          id: v._id as string,
          type: "vehicle",
          title: `${v.year} ${v.make} ${v.model}`,
          subtitle: `${v.vehicleType} • ${v.listingIntent}`,
          price: v.salePrice ?? v.pricePerDay ?? 0,
          currency: v.currency ?? "SLE",
          city: "Sierra Leone",
          isPublished: v.isPublished ?? true,
          imageUrl: v.imageUrls[0] ?? "",
          createdAt: v._creationTime,
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
