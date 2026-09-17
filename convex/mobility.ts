// convex/mobility.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Commercial Vehicle & Logistics Vertical Engine
// Exclusively supports:
// 1. Car for Sale / Car Rental (Dealership / Private Auto Seller)
// 2. Cargo & Delivery Van (Light & Medium Freight Logistics)
// 3. Sand / Dump Tipper Truck (Quarry Aggregate & Construction Haulage)
// 4. Container / Flatbed Cargo Truck (Port Containers & Heavy Industrial Freight)
// ═══════════════════════════════════════════════════════════════════════

import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import {
  commercialVehicleCategory,
  commercialPricingType,
  commercialVehicleStatus,
} from "./schema";
import { encodeGeohash } from "./lib/geo";

// ═══════════════════════════════════════════════════════════════════════
//                 REGISTER COMMERCIAL VEHICLE LISTING
// ═══════════════════════════════════════════════════════════════════════

export const registerVehicleListing = mutation({
  args: {
    ownerId: v.string(),
    sessionToken: v.optional(v.string()),
    title: v.string(),
    category: commercialVehicleCategory,
    price: v.number(),
    pricingType: commercialPricingType,
    capacity: v.optional(v.string()), // e.g. "20 Tons", "12 Cubic Meters", "2 Tons Cargo"
    location: v.string(),
    images: v.array(v.string()),
    
    // Optional vehicle specifications
    make: v.optional(v.string()),
    model: v.optional(v.string()),
    year: v.optional(v.number()),
    color: v.optional(v.string()),
    licensePlate: v.optional(v.string()),
    mileage: v.optional(v.string()),
    transmission: v.optional(v.string()), // "Automatic" | "Manual"
    fuelType: v.optional(v.string()), // "Petrol" | "Diesel" | "Electric" | "Hybrid"
    serviceArea: v.optional(v.string()),
    description: v.optional(v.string()),
    contactPhone: v.optional(v.string()),
    currency: v.optional(v.string()),
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
  },
  returns: v.object({
    success: v.boolean(),
    listingId: v.string(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.ownerId);
    if (!userId) {
      throw new Error("Invalid owner user ID.");
    }
    const user = await ctx.db.get(userId);
    if (!user || !user.isActive) {
      throw new Error("User account not found or deactivated.");
    }

    // Resolve storage IDs to public URLs if needed
    const resolvedImageUrls: string[] = [];
    for (const item of args.images) {
      if (item.startsWith("http://") || item.startsWith("https://")) {
        resolvedImageUrls.push(item);
      } else {
        try {
          const url = await ctx.storage.getUrl(item as Id<"_storage">);
          resolvedImageUrls.push(url ?? item);
        } catch {
          resolvedImageUrls.push(item);
        }
      }
    }

    const lat = args.latitude ?? 8.4840;
    const lng = args.longitude ?? -13.2344;
    const geohash = encodeGeohash(lat, lng, 7);
    const now = Date.now();

    const listingId = await ctx.db.insert("vehicleListings", {
      ownerId: userId,
      title: args.title.trim(),
      category: args.category,
      price: args.price,
      pricingType: args.pricingType,
      capacity: args.capacity,
      location: args.location.trim(),
      images: resolvedImageUrls,
      status: "AVAILABLE",
      createdAt: now,
      updatedAt: now,

      make: args.make?.trim(),
      model: args.model?.trim(),
      year: args.year,
      color: args.color?.trim(),
      licensePlate: args.licensePlate?.trim().toUpperCase(),
      mileage: args.mileage?.trim(),
      transmission: args.transmission,
      fuelType: args.fuelType,
      serviceArea: args.serviceArea?.trim(),
      description: args.description?.trim(),
      contactPhone: args.contactPhone?.trim(),
      currency: args.currency ?? "SLE",

      // Backwards compatibility mappings
      imageUrls: resolvedImageUrls,
      pricePerDay: args.pricingType === "per_day" ? args.price : undefined,
      salePrice: args.pricingType === "total_sale" ? args.price : undefined,
      latitude: lat,
      longitude: lng,
      geohash,
      availabilityStatus: "available",
      isPublished: true,
      isDeleted: false,
    });

    return {
      success: true,
      listingId: listingId as string,
      message: "Commercial vehicle registered successfully",
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 GET VEHICLES BY COMMERCIAL CATEGORY
// ═══════════════════════════════════════════════════════════════════════

export const getVehiclesByCategory = query({
  args: {
    category: v.optional(v.string()),
    status: v.optional(v.string()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    let queryBuilder = ctx.db.query("vehicleListings");

    let vehicles;
    if (args.category && args.category !== "all") {
      vehicles = await queryBuilder
        .withIndex("by_category", (q) => q.eq("category", args.category as any))
        .order("desc")
        .take(args.limit ?? 50);
    } else {
      vehicles = await queryBuilder.order("desc").take(args.limit ?? 50);
    }

    const targetStatus = args.status ?? "AVAILABLE";
    const filtered = vehicles.filter(
      (v) =>
        v.isDeleted !== true &&
        v.isPublished !== false &&
        (args.status === "all" || v.status === targetStatus)
    );

    return filtered.map((v) => ({
      _id: v._id as string,
      id: v._id as string,
      ownerId: String(v.ownerId),
      title: v.title,
      category: v.category,
      price: v.price,
      pricingType: v.pricingType,
      capacity: v.capacity,
      location: v.location,
      images: v.images ?? v.imageUrls ?? [],
      imageUrls: v.images ?? v.imageUrls ?? [],
      status: v.status,
      make: v.make,
      model: v.model,
      year: v.year,
      color: v.color,
      licensePlate: v.licensePlate,
      mileage: v.mileage,
      transmission: v.transmission,
      fuelType: v.fuelType,
      serviceArea: v.serviceArea,
      description: v.description,
      currency: v.currency ?? "SLE",
      createdAt: v.createdAt ?? v._creationTime,
    }));
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    GET USER VEHICLES (OWNER LISTINGS)
// ═══════════════════════════════════════════════════════════════════════

export const getUserVehicles = query({
  args: {
    ownerId: v.string(),
  },
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.ownerId);
    if (!userId) return [];

    const listings = await ctx.db
      .query("vehicleListings")
      .withIndex("by_owner", (q) => q.eq("ownerId", userId))
      .order("desc")
      .collect();

    return listings
      .filter((v) => v.isDeleted !== true)
      .map((v) => ({
        _id: v._id as string,
        id: v._id as string,
        ownerId: String(v.ownerId),
        title: v.title,
        category: v.category,
        price: v.price,
        pricingType: v.pricingType,
        capacity: v.capacity,
        location: v.location,
        images: v.images ?? v.imageUrls ?? [],
        imageUrls: v.images ?? v.imageUrls ?? [],
        status: v.status,
        make: v.make,
        model: v.model,
        year: v.year,
        mileage: v.mileage,
        transmission: v.transmission,
        fuelType: v.fuelType,
        serviceArea: v.serviceArea,
        description: v.description,
        currency: v.currency ?? "SLE",
        isPublished: v.isPublished ?? true,
        createdAt: v.createdAt ?? v._creationTime,
      }));
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                      LIST VEHICLES (DISCOVERY)
// ═══════════════════════════════════════════════════════════════════════

export const listVehicles = query({
  args: {
    category: v.optional(v.string()),
    searchQuery: v.optional(v.string()),
    limit: v.optional(v.number()),
    // Legacy filters kept for compatibility
    listingIntent: v.optional(v.string()),
    vehicleType: v.optional(v.string()),
    availabilityStatus: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    let vehicles = await ctx.db
      .query("vehicleListings")
      .order("desc")
      .take(args.limit ?? 50);

    let filtered = vehicles.filter(
      (v) => v.isPublished !== false && v.isDeleted !== true && v.status !== "TAKEN_DOWN"
    );

    if (args.category && args.category !== "all") {
      filtered = filtered.filter((v) => v.category === args.category);
    }

    if (args.searchQuery && args.searchQuery.trim().length > 0) {
      const q = args.searchQuery.toLowerCase();
      filtered = filtered.filter((v) =>
        (v.title && v.title.toLowerCase().includes(q)) ||
        (v.make && v.make.toLowerCase().includes(q)) ||
        (v.model && v.model.toLowerCase().includes(q)) ||
        (v.location && v.location.toLowerCase().includes(q)) ||
        (v.serviceArea && v.serviceArea.toLowerCase().includes(q))
      );
    }

    return filtered.map((v) => ({
      _id: v._id as string,
      id: v._id as string,
      ownerId: String(v.ownerId),
      title: v.title,
      category: v.category,
      price: v.price,
      pricingType: v.pricingType,
      capacity: v.capacity,
      location: v.location,
      images: v.images ?? v.imageUrls ?? [],
      imageUrls: v.images ?? v.imageUrls ?? [],
      status: v.status,
      make: v.make ?? "Commercial Vehicle",
      model: v.model ?? "",
      year: v.year ?? 2024,
      mileage: v.mileage,
      transmission: v.transmission,
      fuelType: v.fuelType,
      serviceArea: v.serviceArea,
      description: v.description,
      currency: v.currency ?? "SLE",
      pricePerDay: v.pricingType === "per_day" ? v.price : v.pricePerDay,
      salePrice: v.pricingType === "total_sale" ? v.price : v.salePrice,
      availabilityStatus: v.status === "AVAILABLE" ? "available" : "unavailable",
      createdAt: v.createdAt ?? v._creationTime,
    }));
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                         GET VEHICLE BY ID
// ═══════════════════════════════════════════════════════════════════════

export const getVehicleById = query({
  args: {
    listingId: v.string(),
  },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("vehicleListings", args.listingId);
    if (!id) return null;

    const listing = await ctx.db.get(id);
    if (!listing || listing.isDeleted) return null;

    // Fetch owner details
    const owner = await ctx.db.get(listing.ownerId);

    return {
      ...listing,
      _id: listing._id as string,
      id: listing._id as string,
      images: listing.images ?? listing.imageUrls ?? [],
      imageUrls: listing.images ?? listing.imageUrls ?? [],
      owner: owner
        ? {
            id: owner._id as string,
            name: owner.name,
            phone: owner.phone,
            avatarUrl: owner.avatarUrl,
            role: owner.role,
            isVerified: owner.isVerified,
          }
        : null,
    };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                 TAKE DOWN LISTING (ADMIN / MODERATOR)
// ═══════════════════════════════════════════════════════════════════════

export const takeDownListing = mutation({
  args: {
    listingId: v.string(),
    reason: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("vehicleListings", args.listingId);
    if (!id) throw new Error("Vehicle listing not found");

    await ctx.db.patch(id, {
      status: "TAKEN_DOWN",
      isPublished: false,
      isDeleted: true,
      updatedAt: Date.now(),
    });

    return { success: true, message: "Listing taken down successfully" };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//                    UPDATE VEHICLE LISTING STATUS
// ═══════════════════════════════════════════════════════════════════════

export const updateVehicleListingStatus = mutation({
  args: {
    listingId: v.string(),
    status: commercialVehicleStatus,
  },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("vehicleListings", args.listingId);
    if (!id) throw new Error("Vehicle listing not found");

    await ctx.db.patch(id, {
      status: args.status,
      availabilityStatus: args.status === "AVAILABLE" ? "available" : "unavailable",
      updatedAt: Date.now(),
    });

    return { success: true, status: args.status };
  },
});

// ═══════════════════════════════════════════════════════════════════════
//               CREATE VEHICLE LISTING (LEGACY COMPATIBILITY)
// ═══════════════════════════════════════════════════════════════════════

export const createVehicleListing = mutation({
  args: {
    ownerId: v.string(),
    sessionToken: v.optional(v.string()),
    vehicleType: v.optional(v.string()),
    listingIntent: v.optional(v.string()),
    category: v.optional(commercialVehicleCategory),
    title: v.optional(v.string()),
    make: v.string(),
    model: v.string(),
    year: v.number(),
    color: v.optional(v.string()),
    licensePlate: v.optional(v.string()),
    pricePerKm: v.optional(v.number()),
    pricePerDay: v.optional(v.number()),
    salePrice: v.optional(v.number()),
    currency: v.optional(v.string()),
    latitude: v.number(),
    longitude: v.number(),
    imageStorageIds: v.array(v.string()),
    privateContactPhone: v.optional(v.string()),
    isPublished: v.optional(v.boolean()),
    capacity: v.optional(v.string()),
    location: v.optional(v.string()),
  },
  returns: v.string(),
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.ownerId);
    if (!userId) throw new Error("Invalid owner user ID.");

    // Map to commercial category if omitted
    let category: "car_sale" | "car_rental" | "delivery_van" | "sand_dump_truck" | "container_freight_truck" =
      args.category ?? "car_sale";

    if (!args.category) {
      if (args.listingIntent === "rental") category = "car_rental";
      else if (args.vehicleType === "delivery_van") category = "delivery_van";
      else if (args.vehicleType === "truck") category = "sand_dump_truck";
      else category = "car_sale";
    }

    const pricingType =
      category === "car_sale"
        ? "total_sale"
        : category === "sand_dump_truck" || category === "container_freight_truck"
        ? "per_trip"
        : "per_day";

    const price = args.salePrice ?? args.pricePerDay ?? args.pricePerKm ?? 0;
    const title = args.title ?? `${args.year} ${args.make} ${args.model}`;
    const location = args.location ?? "Freetown, Sierra Leone";

    const resolvedUrls: string[] = [];
    for (const item of args.imageStorageIds) {
      if (item.startsWith("http://") || item.startsWith("https://")) {
        resolvedUrls.push(item);
      } else {
        try {
          const url = await ctx.storage.getUrl(item as Id<"_storage">);
          resolvedUrls.push(url ?? item);
        } catch {
          resolvedUrls.push(item);
        }
      }
    }

    const now = Date.now();
    const listingId = await ctx.db.insert("vehicleListings", {
      ownerId: userId,
      title,
      category,
      price,
      pricingType,
      capacity: args.capacity,
      location,
      images: resolvedUrls,
      imageUrls: resolvedUrls,
      status: "AVAILABLE",
      createdAt: now,
      updatedAt: now,
      make: args.make,
      model: args.model,
      year: args.year,
      color: args.color,
      licensePlate: args.licensePlate,
      pricePerDay: args.pricePerDay,
      salePrice: args.salePrice,
      currency: args.currency ?? "SLE",
      latitude: args.latitude,
      longitude: args.longitude,
      geohash: encodeGeohash(args.latitude, args.longitude, 7),
      privateContactPhone: args.privateContactPhone,
      availabilityStatus: "available",
      isPublished: args.isPublished ?? true,
      isDeleted: false,
    });

    return listingId as string;
  },
});

export const getMyVehicleListings = query({
  args: {
    ownerId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const userId = ctx.db.normalizeId("users", args.ownerId);
    if (!userId) return [];

    const listings = await ctx.db
      .query("vehicleListings")
      .withIndex("by_owner", (q) => q.eq("ownerId", userId))
      .order("desc")
      .collect();

    return listings
      .filter((v) => v.isDeleted !== true)
      .map((v) => ({
        ...v,
        _id: v._id as string,
        id: v._id as string,
        ownerId: String(v.ownerId),
        images: v.images ?? v.imageUrls ?? [],
        imageUrls: v.images ?? v.imageUrls ?? [],
      }));
  },
});

export const updateVehicleListing = mutation({
  args: {
    listingId: v.string(),
    ownerId: v.string(),
    sessionToken: v.optional(v.string()),
    title: v.optional(v.string()),
    price: v.optional(v.number()),
    capacity: v.optional(v.string()),
    location: v.optional(v.string()),
    make: v.optional(v.string()),
    model: v.optional(v.string()),
    year: v.optional(v.number()),
    color: v.optional(v.string()),
    pricePerDay: v.optional(v.number()),
    salePrice: v.optional(v.number()),
    isPublished: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("vehicleListings", args.listingId);
    if (!id) throw new Error("Vehicle listing not found");

    const listing = await ctx.db.get(id);
    if (!listing) throw new Error("Vehicle listing not found");

    const userId = ctx.db.normalizeId("users", args.ownerId);
    if (!userId || listing.ownerId !== userId) {
      throw new Error("You do not have permission to edit this listing");
    }

    const updates: Record<string, any> = { updatedAt: Date.now() };
    if (args.title !== undefined) updates.title = args.title;
    if (args.price !== undefined) updates.price = args.price;
    if (args.capacity !== undefined) updates.capacity = args.capacity;
    if (args.location !== undefined) updates.location = args.location;
    if (args.make !== undefined) updates.make = args.make;
    if (args.model !== undefined) updates.model = args.model;
    if (args.year !== undefined) updates.year = args.year;
    if (args.color !== undefined) updates.color = args.color;
    if (args.pricePerDay !== undefined) updates.pricePerDay = args.pricePerDay;
    if (args.salePrice !== undefined) updates.salePrice = args.salePrice;
    if (args.isPublished !== undefined) updates.isPublished = args.isPublished;

    await ctx.db.patch(id, updates);
    return { success: true, message: "Vehicle listing updated successfully" };
  },
});

export const deleteVehicleListing = mutation({
  args: {
    listingId: v.string(),
    ownerId: v.string(),
    sessionToken: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const id = ctx.db.normalizeId("vehicleListings", args.listingId);
    if (!id) throw new Error("Vehicle listing not found");

    const listing = await ctx.db.get(id);
    if (!listing) throw new Error("Vehicle listing not found");

    const userId = ctx.db.normalizeId("users", args.ownerId);
    if (!userId || listing.ownerId !== userId) {
      throw new Error("You do not have permission to delete this listing");
    }

    await ctx.db.delete(id);

    return {
      success: true,
      message: "Vehicle listing permanently removed",
    };
  },
});
