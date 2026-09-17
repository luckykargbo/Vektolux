// convex/schema.ts
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Complete Convex Database Schema
// Multi-vertical Marketplace: Real Estate + Mobility/Transportation
// ═══════════════════════════════════════════════════════════════════════

import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// ─── Reusable Validators (Enum-like unions) ──────────────────────────

export const userRole = v.union(
  v.literal("client"),
  v.literal("agent"),
  v.literal("merchant"),
  v.literal("driver"),
  v.literal("buyer"),
  v.literal("seller"),
  v.literal("property_owner"),
  v.literal("admin")
);

export const verificationStatusEnum = v.union(
  v.literal("unverified"),
  v.literal("pending"),
  v.literal("verified"),
  v.literal("approved"),
  v.literal("rejected"),
  v.literal("suspended")
);

export const idDocumentTypeEnum = v.union(
  v.literal("national_id"),
  v.literal("ecowas_card"),
  v.literal("passport")
);

export const verificationBadgeEnum = v.union(
  v.literal("NONE"),
  v.literal("GREEN_TICK")
);

export const realEstateCategory = v.union(
  v.literal("sale"),
  v.literal("long_term_rent"),
  v.literal("hourly_guesthouse")
);

export const bookingType = v.union(
  v.literal("inspection"),
  v.literal("instant_stay")
);

export const universalBookingType = v.union(
  v.literal("hourly_guesthouse"),
  v.literal("vehicle_rental"),
  v.literal("property_inspection"),
  v.literal("vehicle_inspection")
);

export const universalBookingStatus = v.union(
  v.literal("pending_payment"),
  v.literal("confirmed"),
  v.literal("in_progress"),
  v.literal("completed"),
  v.literal("cancelled")
);

export const vehicleType = v.union(
  v.literal("bike"),
  v.literal("taxi"),
  v.literal("delivery_van"),
  v.literal("truck")
);

export const listingIntent = v.union(
  v.literal("ride_hailing"),
  v.literal("rental"),
  v.literal("sale")
);

export const commercialVehicleCategory = v.union(
  v.literal("car_sale"),
  v.literal("car_rental"),
  v.literal("delivery_van"),
  v.literal("sand_dump_truck"),
  v.literal("container_freight_truck")
);

export const commercialPricingType = v.union(
  v.literal("total_sale"),
  v.literal("per_day"),
  v.literal("per_trip")
);

export const commercialVehicleStatus = v.union(
  v.literal("AVAILABLE"),
  v.literal("BOOKED"),
  v.literal("SOLD"),
  v.literal("TAKEN_DOWN")
);

export const rideStatus = v.union(
  v.literal("requested"),
  v.literal("accepted"),
  v.literal("driver_arriving"),
  v.literal("arrived"),
  v.literal("in_transit"),
  v.literal("completed"),
  v.literal("cancelled")
);

export const paymentStatus = v.union(
  v.literal("pending"),
  v.literal("processing"),
  v.literal("completed"),
  v.literal("failed"),
  v.literal("refunded")
);

export const paymentMethod = v.union(
  v.literal("card"),
  v.literal("mobile_money"),
  v.literal("wallet"),
  v.literal("crypto")
);

export const availabilityStatus = v.union(
  v.literal("available"),
  v.literal("unavailable"),
  v.literal("booked"),
  v.literal("maintenance")
);

export const transactionType = v.union(
  v.literal("payment"),
  v.literal("payout"),
  v.literal("commission"),
  v.literal("refund"),
  v.literal("top_up"),
  v.literal("transfer"),
  v.literal("escrow_lock"),
  v.literal("escrow_release")
);

export const transactionStatus = v.union(
  v.literal("pending"),
  v.literal("completed"),
  v.literal("failed"),
  v.literal("reversed")
);

export const serviceTypeEnum = v.union(
  v.literal("ride"),
  v.literal("delivery"),
  v.literal("both")
);

export const vehicleCategoryEnum = v.union(
  v.literal("standard"),
  v.literal("comfort"),
  v.literal("kekeh_tricycle"),
  v.literal("delivery_bike"),
  v.literal("delivery_van")
);

export const tripDeliveryStatusEnum = v.union(
  v.literal("searching"),
  v.literal("accepted"),
  v.literal("arrived"),
  v.literal("in_progress"),
  v.literal("completed"),
  v.literal("cancelled")
);

export const paymentMethodEnum = v.union(
  v.literal("cash"),
  v.literal("wallet"),
  v.literal("mobile_money"),
  v.literal("card")
);

// ═══════════════════════════════════════════════════════════════════════

export default defineSchema({
  // ─── USERS ─────────────────────────────────────────────────────────
  users: defineTable({
    // Identity
    email: v.string(),
    phone: v.string(),
    name: v.string(),
    role: userRole,
    avatarUrl: v.optional(v.string()),

    // Blockchain
    walletAddress: v.optional(v.string()),

    // Verification
    isVerified: v.boolean(),
    isActive: v.boolean(),
    verifiedAt: v.optional(v.number()),
    verifiedBy: v.optional(v.id("users")),
    verificationStatus: v.optional(verificationStatusEnum),
    verificationBadge: v.optional(verificationBadgeEnum),
    idDocumentType: v.optional(idDocumentTypeEnum),
    verificationReferenceId: v.optional(v.string()),
    rejectionReason: v.optional(v.string()),
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
    documentUrl: v.optional(v.string()),
    documentStorageId: v.optional(v.id("_storage")),

    // Auth
    passwordHash: v.optional(v.string()),
    sessionToken: v.optional(v.string()),
    walletPinHash: v.optional(v.string()),
    authProvider: v.optional(v.string()),
    externalAuthId: v.optional(v.string()),

    // Geolocation (for drivers)
    currentLat: v.optional(v.number()),
    currentLng: v.optional(v.number()),
    currentGeohash: v.optional(v.string()),
    locationUpdatedAt: v.optional(v.number()),

    // Multi-Role & Operator State
    activeRole: v.optional(
      v.union(
        v.literal("client"),
        v.literal("driver"),
        v.literal("agent"),
        v.literal("merchant"),
        v.literal("admin")
      )
    ),
    isVerifiedDriver: v.optional(v.boolean()),
    is_driver_verified: v.optional(v.boolean()),
    active_mode: v.optional(v.union(v.literal("passenger"), v.literal("driver"))),
    driver_status: v.optional(v.union(v.literal("offline"), v.literal("online"), v.literal("busy"))),
    isVerifiedAgent: v.optional(v.boolean()),
    isVerifiedMerchant: v.optional(v.boolean()),
    driverVehicleId: v.optional(v.string()),

    // Social & Profile
    bio: v.optional(v.string()),
    followersCount: v.optional(v.number()),
    followingCount: v.optional(v.number()),
    kycStatus: v.optional(v.union(
      v.literal("pending"),
      v.literal("approved"),
      v.literal("rejected"),
      v.literal("verified"),
      v.literal("suspended"),
      v.literal("banned"),
      v.literal("PENDING_VERIFICATION"),
      v.literal("VERIFIED"),
      v.literal("SUSPENDED"),
      v.literal("BANNED")
    )),

    // Metadata
    updatedAt: v.number(),
  })
    .index("by_email", ["email"])
    .index("by_phone", ["phone"])
    .index("by_role", ["role"])
    .index("by_role_active", ["role", "isActive"])
    .index("by_external_auth", ["authProvider", "externalAuthId"])
    .index("by_geohash", ["currentGeohash"])
    .index("by_verification_status", ["verificationStatus"])
    .index("by_role_verification", ["role", "verificationStatus"])
    .searchIndex("search_name", {
      searchField: "name",
      filterFields: ["role", "isActive"],
    }),

  // ─── FOLLOWS ───────────────────────────────────────────────────────
  follows: defineTable({
    followerId: v.id("users"),
    followingId: v.id("users"),
    createdAt: v.number(),
  })
    .index("by_follower", ["followerId"])
    .index("by_following", ["followingId"])
    .index("by_follower_following", ["followerId", "followingId"]),

  // ─── REAL ESTATE LISTINGS ─────────────────────────────────────────
  realEstateListings: defineTable({
    ownerId: v.id("users"),
    title: v.string(),
    description: v.string(),
    category: realEstateCategory,

    // Pricing
    price: v.number(),
    hourlyRate: v.optional(v.number()),
    currency: v.string(),

    // Location
    address: v.string(),
    city: v.string(),
    country: v.string(),
    latitude: v.number(),
    longitude: v.number(),
    geohash: v.string(),

    // Details
    bedrooms: v.optional(v.number()),
    bathrooms: v.optional(v.number()),
    areaSqM: v.optional(v.number()),
    amenities: v.optional(v.array(v.string())),
    imageUrls: v.array(v.string()),

    // Privacy & Moderation
    privateContactPhone: v.optional(v.string()),
    isDeleted: v.optional(v.boolean()),

    // Status
    availabilityStatus: availabilityStatus,
    isFeatured: v.boolean(),
    isPublished: v.optional(v.boolean()),
    viewCount: v.number(),

    // Metadata
    updatedAt: v.number(),
  })
    .index("by_owner", ["ownerId"])
    .index("by_category_status", ["category", "availabilityStatus"])
    .index("by_geohash", ["geohash"])
    .index("by_category_price", ["category", "price"])
    .index("by_city_category", ["city", "category"])
    .index("by_featured", ["isFeatured", "availabilityStatus"])
    .index("by_published", ["isPublished", "availabilityStatus"])
    .searchIndex("search_title", {
      searchField: "title",
      filterFields: ["category", "availabilityStatus", "city"],
    }),

  // ─── REAL ESTATE BOOKINGS ─────────────────────────────────────────
  realEstateBookings: defineTable({
    listingId: v.id("realEstateListings"),
    buyerId: v.id("users"),
    ownerId: v.id("users"),
    bookingType: bookingType,

    // Schedule
    startTime: v.number(),
    endTime: v.number(),

    // Financials
    totalAmount: v.number(),
    platformFee: v.number(),
    currency: v.string(),
    paymentStatus: paymentStatus,
    paymentReference: v.optional(v.string()),

    // Blockchain
    blockchainTxHash: v.optional(v.string()),
    escrowId: v.optional(v.string()),

    // Status
    notes: v.optional(v.string()),
    cancelledAt: v.optional(v.number()),
    cancelReason: v.optional(v.string()),

    // Metadata
    updatedAt: v.number(),
  })
    .index("by_listing", ["listingId"])
    .index("by_buyer", ["buyerId"])
    .index("by_owner", ["ownerId"])
    .index("by_payment_status", ["paymentStatus"])
    .index("by_listing_time", ["listingId", "startTime"])
    .index("by_buyer_status", ["buyerId", "paymentStatus"]),

  // ─── VEHICLE LISTINGS (COMMERCIAL FLEET & DEALERSHIP) ──────────────
  vehicleListings: defineTable({
    ownerId: v.id("users"),
    title: v.string(),
    category: commercialVehicleCategory,
    price: v.number(),
    pricingType: commercialPricingType,
    capacity: v.optional(v.string()), // e.g. "20 Tons", "12 Cubic Meters", "2.5 Tons Payload"
    location: v.string(),
    images: v.array(v.string()),
    status: commercialVehicleStatus,
    createdAt: v.number(),

    // Detailed vehicle specs & options
    make: v.optional(v.string()),
    model: v.optional(v.string()),
    year: v.optional(v.number()),
    color: v.optional(v.string()),
    licensePlate: v.optional(v.string()),
    mileage: v.optional(v.string()),
    transmission: v.optional(v.string()), // Automatic | Manual
    fuelType: v.optional(v.string()), // Petrol | Diesel | Electric | Hybrid
    serviceArea: v.optional(v.string()),
    description: v.optional(v.string()),
    contactPhone: v.optional(v.string()),
    privateContactPhone: v.optional(v.string()),
    currency: v.optional(v.string()),

    // Backwards compatibility fields
    vehicleType: v.optional(v.string()),
    listingIntent: v.optional(v.string()),
    imageUrls: v.optional(v.array(v.string())),
    pricePerKm: v.optional(v.number()),
    pricePerDay: v.optional(v.number()),
    salePrice: v.optional(v.number()),
    latitude: v.optional(v.number()),
    longitude: v.optional(v.number()),
    geohash: v.optional(v.string()),
    availabilityStatus: v.optional(v.string()),
    isPublished: v.optional(v.boolean()),
    isDeleted: v.optional(v.boolean()),

    // Metadata
    updatedAt: v.number(),
  })
    .index("by_owner", ["ownerId"])
    .index("by_category", ["category"])
    .index("by_status", ["status"])
    .index("by_category_status", ["category", "status"])
    .index("by_published", ["isPublished", "status"])
    .searchIndex("search_vehicle", {
      searchField: "title",
      filterFields: ["category", "status"],
    }),

  // ─── WALLET BALANCES ──────────────────────────────────────────────
  walletBalances: defineTable({
    userId: v.id("users"),
    availableBalance: v.number(),
    pendingBalance: v.number(),
    currency: v.string(),
    updatedAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_user_currency", ["userId", "currency"]),

  // ─── TRANSACTIONS (LEDGER) ────────────────────────────────────────
  transactions: defineTable({
    walletId: v.id("walletBalances"),
    userId: v.id("users"),
    type: transactionType,
    amount: v.number(),
    currency: v.string(),

    // References
    referenceType: v.optional(v.string()),
    referenceId: v.optional(v.string()),
    counterpartyId: v.optional(v.id("users")),

    // Payment gateway
    gatewayProvider: v.optional(v.string()),
    gatewayReference: v.optional(v.string()),

    // Blockchain & Escrow Split Ledger
    blockchainTxHash: v.optional(v.string()),
    partnerSplitPercent: v.optional(v.number()),
    partnerAmount: v.optional(v.number()),
    platformFeeAmount: v.optional(v.number()),
    agentNumber: v.optional(v.string()),
    escrowStatus: v.optional(
      v.union(
        v.literal("locked"),
        v.literal("released"),
        v.literal("refunded")
      )
    ),

    // Status
    status: transactionStatus,
    description: v.optional(v.string()),

    // Metadata
    updatedAt: v.number(),
  })
    .index("by_wallet", ["walletId"])
    .index("by_user", ["userId"])
    .index("by_user_type", ["userId", "type"])
    .index("by_reference", ["referenceType", "referenceId"])
    .index("by_status", ["status"])
    .index("by_gateway_ref", ["gatewayProvider", "gatewayReference"]),

  // ─── PAYMENT INTENTS ──────────────────────────────────────────────
  paymentIntents: defineTable({
    userId: v.id("users"),
    amount: v.number(),
    currency: v.string(),
    paymentMethod: paymentMethod,

    // Gateway
    gatewayProvider: v.string(),
    gatewayReference: v.optional(v.string()),
    gatewayPaymentLink: v.optional(v.string()),

    // Reference to what is being paid for
    referenceType: v.string(),
    referenceId: v.string(),

    // Commission
    platformFeeBps: v.number(),
    platformFeeAmount: v.number(),
    vendorPayoutAmount: v.number(),
    vendorId: v.id("users"),

    // Status
    status: paymentStatus,
    paidAt: v.optional(v.number()),
    failureReason: v.optional(v.string()),

    // Security
    idempotencyKey: v.string(),
    webhookVerified: v.boolean(),

    // Blockchain
    blockchainTxHash: v.optional(v.string()),

    // Metadata
    updatedAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_status", ["status"])
    .index("by_gateway_ref", ["gatewayProvider", "gatewayReference"])
    .index("by_idempotency", ["idempotencyKey"])
    .index("by_reference", ["referenceType", "referenceId"]),

  // ─── MERCHANT / AGENT PROFILES ──────────────────────────────────
  merchant_profiles: defineTable({
    userId: v.id("users"),
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
    documentUrl: v.optional(v.string()),
    verificationStatus: v.union(
      v.literal("pending"),
      v.literal("submitted"),
      v.literal("verified"),
      v.literal("approved"),
      v.literal("rejected"),
      v.literal("suspended")
    ),
    verifiedAt: v.optional(v.number()),
    reviewNotes: v.optional(v.string()),
    updatedAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_status", ["verificationStatus"]),

  // ─── UNIVERSAL BOOKINGS (Stays, Rentals, Inspections) ─────────────
  bookings: defineTable({
    listingId: v.string(),
    listingType: v.union(v.literal("property"), v.literal("vehicle")),
    listingTitle: v.string(),
    buyerId: v.string(),
    buyerName: v.optional(v.string()),
    buyerPhone: v.optional(v.string()),
    vendorId: v.string(),
    bookingType: universalBookingType,
    status: universalBookingStatus,
    startTime: v.number(),
    endTime: v.number(),
    hours: v.optional(v.number()),
    days: v.optional(v.number()),
    subtotal: v.number(),
    serviceFee: v.number(),
    totalAmount: v.number(),
    currency: v.string(),
    paymentStatus: paymentStatus,
    paymentMethod: v.optional(paymentMethod),
    paymentReference: v.optional(v.string()),
    txRef: v.optional(v.string()),
    flwRef: v.optional(v.string()),
    notes: v.optional(v.string()),
    escrowId: v.optional(v.string()),
    blockchainTxHash: v.optional(v.string()),
    cancelledAt: v.optional(v.number()),
    cancelReason: v.optional(v.string()),
    updatedAt: v.number(),
  })
    .index("by_buyer", ["buyerId"])
    .index("by_vendor", ["vendorId"])
    .index("by_listing", ["listingId"])
    .index("by_status", ["status"])
    .index("by_listing_dates", ["listingId", "startTime", "endTime"])
    .index("by_tx_ref", ["txRef"]),

  // ─── IDEMPOTENCY KEYS ─────────────────────────────────────────────
  idempotencyKeys: defineTable({
    key: v.string(),
    result: v.optional(v.string()),
    createdAt: v.number(),
    expiresAt: v.number(),
  }).index("by_key", ["key"]),

  // ─── IDENTITY VERIFICATION CHECKS ──────────────────────────────────
  identity_checks: defineTable({
    userId: v.id("users"),
    referenceId: v.string(),
    documentType: idDocumentTypeEnum,
    idNumberHash: v.string(),
    status: verificationStatusEnum,
    provider: v.string(),
    livenessScore: v.optional(v.number()),
    faceMatchScore: v.optional(v.number()),
    mrzValidated: v.optional(v.boolean()),
    tamperingPassed: v.optional(v.boolean()),
    rejectionReason: v.optional(v.string()),
    ipAddress: v.optional(v.string()),
    deviceFingerprintHash: v.optional(v.string()),
    attemptNumber: v.number(),
    createdAt: v.number(),
    completedAt: v.optional(v.number()),
  })
    .index("by_user", ["userId"])
    .index("by_reference", ["referenceId"])
    .index("by_id_number_hash", ["idNumberHash"])
    .index("by_status", ["status"])
    .index("by_created", ["createdAt"]),

  // ─── VERIFICATIONS AUDIT & WEBHOOK IDEMPOTENCY LOG ─────────────────
  verifications_log: defineTable({
    idempotencyKey: v.string(),
    checkId: v.optional(v.id("identity_checks")),
    userId: v.id("users"),
    event: v.string(),
    provider: v.string(),
    signatureVerified: v.boolean(),
    rawResultCode: v.optional(v.string()),
    diagnosticPayload: v.optional(v.string()),
    createdAt: v.number(),
  })
    .index("by_idempotency_key", ["idempotencyKey"])
    .index("by_user", ["userId"])
    .index("by_check", ["checkId"]),
  // ─── ROLE & OPERATOR APPLICATIONS ──────────────────────────────
  role_applications: defineTable({
    userId: v.id("users"),
    targetRole: v.union(v.literal("driver"), v.literal("agent"), v.literal("merchant")),
    businessName: v.optional(v.string()),
    tinNumber: v.optional(v.string()),
    licenseNumber: v.optional(v.string()),
    documentUrls: v.array(v.string()),
    status: v.union(v.literal("pending"), v.literal("approved"), v.literal("rejected")),
    reviewNotes: v.optional(v.string()),
    reviewedAt: v.optional(v.number()),
    updatedAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_role_status", ["targetRole", "status"]),

  // ─── PASSWORD RESET OTPS (SMS, WHATSAPP, EMAIL) ─────────────────
  password_resets: defineTable({
    identifier: v.string(), // phone or email
    deliveryChannel: v.union(v.literal("sms"), v.literal("whatsapp"), v.literal("email")),
    otpCode: v.string(),
    expiresAt: v.number(),
    isUsed: v.boolean(),
    createdAt: v.number(),
  })
    .index("by_identifier", ["identifier"])
    .index("by_identifier_code", ["identifier", "otpCode"]),
});
