// convex/seedData.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Authentic Sierra Leone Discovery Seed Engine
// Seeds properties across Freetown, Waterloo, Bo & vehicles for sale/rent.
// ═══════════════════════════════════════════════════════════════════════

import { mutation } from "./_generated/server";
import { v } from "convex/values";
import { encodeGeohash } from "./lib/geo";

export const seedDiscoveryData = mutation({
  args: {
    force: v.optional(v.boolean()),
  },
  returns: v.object({
    propertiesSeeded: v.number(),
    vehiclesSeeded: v.number(),
    message: v.string(),
  }),
  handler: async (ctx, args) => {
    // 1. Find or create a demo agent user
    let agentUser = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", "agent@vektolux.sl"))
      .first();

    const now = Date.now();

    if (!agentUser) {
      const agentId = await ctx.db.insert("users", {
        name: "Ibrahim Conteh (Vektolux Real Estate)",
        email: "agent@vektolux.sl",
        phone: "+232 76 998 877",
        role: "agent",
        activeRole: "agent",
        isVerified: true,
        isVerifiedAgent: true,
        isActive: true,
        avatarUrl: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400",
        verificationStatus: "verified",
        verificationBadge: "GREEN_TICK",
        updatedAt: now,
      });
      agentUser = await ctx.db.get(agentId);
    }

    // 2. Find or create a demo dealer user
    let dealerUser = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", "dealer@vektolux.sl"))
      .first();

    if (!dealerUser) {
      const dealerId = await ctx.db.insert("users", {
        name: "Mohamed Sesay Motors",
        email: "dealer@vektolux.sl",
        phone: "+232 77 445 566",
        role: "merchant",
        activeRole: "merchant",
        isVerified: true,
        isVerifiedMerchant: true,
        isActive: true,
        avatarUrl: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400",
        verificationStatus: "verified",
        verificationBadge: "GREEN_TICK",
        updatedAt: now,
      });
      dealerUser = await ctx.db.get(dealerId);
    }

    if (!agentUser || !dealerUser) {
      return { propertiesSeeded: 0, vehiclesSeeded: 0, message: "Failed to initialize owners" };
    }

    // 3. Seed Properties if none exist or force == true
    const existingProperties = await ctx.db.query("realEstateListings").take(5);
    let propertiesSeeded = 0;

    if (existingProperties.length === 0 || args.force) {
      const propertyItems = [
        {
          title: "Luxury 4-Bedroom Oceanview Villa",
          description: "Stunning modern villa overlooking the Atlantic. Includes infinity pool, standby soundproof generator, 24/7 solar inverter, CCTV, and expansive landscaped compound on Wilkinson Road.",
          category: "long_term_rent" as const,
          price: 12000,
          hourlyRate: 800,
          currency: "SLE",
          address: "18 Wilkinson Road",
          city: "Freetown",
          country: "Sierra Leone",
          latitude: 8.4795,
          longitude: -13.2562,
          bedrooms: 4,
          bathrooms: 4,
          areaSqM: 350,
          amenities: ["EDSA Power", "Standby Generator", "Guma Water", "Borehole", "24/7 Security", "Swimming Pool", "Solar Inverter"],
          imageUrls: [
            "https://images.unsplash.com/photo-1613490493576-7fde63acd811?w=800",
            "https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=800",
            "https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=800",
          ],
          isFeatured: true,
        },
        {
          title: "Modern Executive 2-Bed Beach Apartment",
          description: "Fully furnished 2-bedroom seaside residence near Aberdeen Peninsula. High-speed fiber internet, modern European kitchen, elevator access, and rooftop terrace.",
          category: "long_term_rent" as const,
          price: 5500,
          hourlyRate: 350,
          currency: "SLE",
          address: "Sir Samuel Lewis Road, Aberdeen",
          city: "Freetown",
          country: "Sierra Leone",
          latitude: 8.4983,
          longitude: -13.2878,
          bedrooms: 2,
          bathrooms: 2,
          areaSqM: 120,
          amenities: ["EDSA Power", "Backup Inverter", "Guma Water", "High-Speed WiFi", "Furnished", "Sea View Balcony"],
          imageUrls: [
            "https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=800",
            "https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=800",
          ],
          isFeatured: true,
        },
        {
          title: "Lumley Beach Luxury Hourly Guest House",
          description: "Chic boutique beachfront suite ideal for private meetings, relaxing staycations, and international travelers. Flexible hourly booking with instant access.",
          category: "hourly_guesthouse" as const,
          price: 2500,
          hourlyRate: 250,
          currency: "SLE",
          address: "Lumley Beach Promenade",
          city: "Freetown",
          country: "Sierra Leone",
          latitude: 8.4682,
          longitude: -13.2794,
          bedrooms: 1,
          bathrooms: 1,
          areaSqM: 55,
          amenities: ["EDSA + Generator", "Air Conditioning", "Smart TV with DSTV", "Mini Bar", "Keycard Entry"],
          imageUrls: [
            "https://images.unsplash.com/photo-1590490360182-c33d57733427?w=800",
            "https://images.unsplash.com/photo-1566665797739-1674de7a421a?w=800",
          ],
          isFeatured: true,
        },
        {
          title: "Prime Commercial Development Land",
          description: "4 Town Lots of dry flat commercial land right on Waterloo Highway. Direct road frontage, verified Ministry of Lands survey plan, clear freehold title.",
          category: "sale" as const,
          price: 450000,
          currency: "SLE",
          address: "Waterloo Highway Junction",
          city: "Waterloo",
          country: "Sierra Leone",
          latitude: 8.3385,
          longitude: -13.0721,
          bedrooms: 0,
          bathrooms: 0,
          areaSqM: 1800,
          amenities: ["Main Road Frontage", "Surveyed Plan", "Freehold Title", "Electricity Grid Adjacent"],
          imageUrls: [
            "https://images.unsplash.com/photo-1500382017468-9049fed747ef?w=800",
          ],
          isFeatured: false,
        },
        {
          title: "Serene 3-Bedroom Family Home in Bo",
          description: "Solid newly painted bungalow in central Bo City. Large compound with fruit trees, perimeter fencing, private well, and solar lighting.",
          category: "long_term_rent" as const,
          price: 3200,
          currency: "SLE",
          address: "Tikonko Road",
          city: "Bo",
          country: "Sierra Leone",
          latitude: 7.9647,
          longitude: -11.7383,
          bedrooms: 3,
          bathrooms: 2,
          areaSqM: 200,
          amenities: ["Private Well", "Solar Lighting", "Secure Fencing", "Car Garage"],
          imageUrls: [
            "https://images.unsplash.com/photo-1580587771525-78b9dba3b914?w=800",
            "https://images.unsplash.com/photo-1570129477492-45c003edd2be?w=800",
          ],
          isFeatured: false,
        },
        {
          title: "Panoramic Hill Station Diplomatic Residence",
          description: "Spacious residence nestled in the cool hills of Hill Station. Features marble tiling, chef kitchen, master penthouse, and guardhouse.",
          category: "long_term_rent" as const,
          price: 8500,
          currency: "SLE",
          address: "Hill Station Main Road",
          city: "Freetown",
          country: "Sierra Leone",
          latitude: 8.4552,
          longitude: -13.2389,
          bedrooms: 4,
          bathrooms: 3,
          areaSqM: 280,
          amenities: ["Mountain Breeze", "Standby Generator", "EDSA Power", "Guardhouse", "CCTV"],
          imageUrls: [
            "https://images.unsplash.com/photo-1518780664697-55e3ad937233?w=800",
          ],
          isFeatured: true,
        },
      ];

      for (const p of propertyItems) {
        const geohash = encodeGeohash(p.latitude, p.longitude, 7);
        await ctx.db.insert("realEstateListings", {
          ownerId: agentUser._id,
          title: p.title,
          description: p.description,
          category: p.category,
          price: p.price,
          hourlyRate: p.hourlyRate,
          currency: p.currency,
          address: p.address,
          city: p.city,
          country: p.country,
          latitude: p.latitude,
          longitude: p.longitude,
          geohash,
          bedrooms: p.bedrooms,
          bathrooms: p.bathrooms,
          areaSqM: p.areaSqM,
          amenities: p.amenities,
          imageUrls: p.imageUrls,
          availabilityStatus: "available",
          isFeatured: p.isFeatured,
          viewCount: 48,
          updatedAt: now,
        });
        propertiesSeeded++;
      }
    }

    // 4. Seed Vehicles if none exist or force == true
    const existingVehicles = await ctx.db.query("vehicleListings").take(5);
    let vehiclesSeeded = 0;

    if (existingVehicles.length === 0 || args.force) {
      const vehicleItems = [
        {
          make: "Toyota",
          model: "RAV4 AWD",
          year: 2021,
          vehicleType: "taxi" as const,
          listingIntent: "sale" as const,
          salePrice: 145000,
          pricePerDay: 450,
          color: "Silver",
          licensePlate: "SL-849-AC",
          latitude: 8.484,
          longitude: -13.234,
          imageUrls: [
            "https://images.unsplash.com/photo-1568605117036-5fe5e7bab0b7?w=800",
            "https://images.unsplash.com/photo-1552519507-da3b142c6e3d?w=800",
          ],
        },
        {
          make: "Toyota",
          model: "Land Cruiser Prado TX",
          year: 2020,
          vehicleType: "taxi" as const,
          listingIntent: "sale" as const,
          salePrice: 380000,
          pricePerDay: 950,
          color: "Black",
          licensePlate: "SL-102-TX",
          latitude: 8.478,
          longitude: -13.245,
          imageUrls: [
            "https://images.unsplash.com/photo-1533473359331-0135ef1b58bf?w=800",
          ],
        },
        {
          make: "Bajaj",
          model: "RE 4S (Keke)",
          year: 2023,
          vehicleType: "bike" as const,
          listingIntent: "sale" as const,
          salePrice: 42000,
          pricePerDay: 150,
          color: "Yellow",
          licensePlate: "SL-492-KE",
          latitude: 8.481,
          longitude: -13.228,
          imageUrls: [
            "https://images.unsplash.com/photo-1558981403-c5f9899a28bc?w=800",
          ],
        },
        {
          make: "TVS",
          model: "Boxer 150 (Okada)",
          year: 2022,
          vehicleType: "bike" as const,
          listingIntent: "sale" as const,
          salePrice: 18500,
          pricePerDay: 80,
          color: "Blue",
          licensePlate: "SL-771-BK",
          latitude: 8.485,
          longitude: -13.231,
          imageUrls: [
            "https://images.unsplash.com/photo-1558981806-ec527fa84c39?w=800",
          ],
        },
        {
          make: "Hyundai",
          model: "Elantra GLS",
          year: 2019,
          vehicleType: "taxi" as const,
          listingIntent: "rental" as const,
          salePrice: 88000,
          pricePerDay: 350,
          color: "White",
          licensePlate: "SL-319-EL",
          latitude: 8.491,
          longitude: -13.24,
          imageUrls: [
            "https://images.unsplash.com/photo-1549399542-7e3f8b79c341?w=800",
          ],
        },
        {
          make: "Toyota",
          model: "HiAce Commuter Van",
          year: 2020,
          vehicleType: "delivery_van" as const,
          listingIntent: "rental" as const,
          salePrice: 210000,
          pricePerDay: 750,
          color: "Silver",
          licensePlate: "SL-550-VN",
          latitude: 8.465,
          longitude: -13.255,
          imageUrls: [
            "https://images.unsplash.com/photo-1541899481282-d53bffe3c35d?w=800",
          ],
        },
      ];

      for (const v of vehicleItems) {
        const geohash = encodeGeohash(v.latitude, v.longitude, 7);
        await ctx.db.insert("vehicleListings", {
          ownerId: dealerUser._id,
          vehicleType: v.vehicleType,
          listingIntent: v.listingIntent,
          make: v.make,
          model: v.model,
          year: v.year,
          color: v.color,
          licensePlate: v.licensePlate,
          imageUrls: v.imageUrls,
          salePrice: v.salePrice,
          pricePerDay: v.pricePerDay,
          currency: "SLE",
          latitude: v.latitude,
          longitude: v.longitude,
          geohash,
          availabilityStatus: "available",
          updatedAt: now,
        });
        vehiclesSeeded++;
      }
    }

    return {
      propertiesSeeded,
      vehiclesSeeded,
      message: `Seeded ${propertiesSeeded} properties and ${vehiclesSeeded} vehicles successfully.`,
    };
  },
});
