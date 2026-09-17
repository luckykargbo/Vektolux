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

export const escrowOrderType = v.union(
  v.literal("VEHICLE_RENTAL"),
  v.literal("VEHICLE_PURCHASE")
);

export const escrowOrderStatus = v.union(
  v.literal("INITIATED"),
  v.literal("PENDING_PAYMENT"),
  v.literal("HELD_IN_ESCROW"),
  v.literal("PARTIALLY_RELEASED"),
  v.literal("POST_INSPECTION_PENDING"),
  v.literal("SETTLED"),
  v.literal("DISPUTED"),
  v.literal("REFUNDED"),
  v.literal("CANCELLED")
);

export const escrowPurchaseStage = v.union(
  v.literal("EARNEST_PENDING"),
  v.literal("EARNEST_HELD"),
  v.literal("INSPECTION_PASSED"),
  v.literal("FULL_FUNDS_HELD"),
  v.literal("SLRSA_DOCS_SUBMITTED"),
  v.literal("TRANSFER_CONFIRMED"),
  v.literal("SETTLED")
);

export const inspectionTypeEnum = v.union(
  v.literal("PRE_TRIP_RENTAL"),
  v.literal("POST_TRIP_RENTAL"),
  v.literal("PURCHASE_MECHANIC_INSPECTION")
);

export const inspectionStatusEnum = v.union(
  v.literal("PENDING"),
  v.literal("COMPLETED_CLEAN"),
  v.literal("COMPLETED_WITH_DAMAGE"),
  v.literal("REJECTED")
);

export const ledgerAccountTypeEnum = v.union(
  v.literal("CLIENT_AVAILABLE"),
  v.literal("CLIENT_ESCROW_LOCKED"),
  v.literal("OWNER_AVAILABLE"),
  v.literal("OWNER_ESCROW_PENDING"),
  v.literal("PLATFORM_REVENUE_REALIZED"),
  v.literal("DAMAGE_DEPOSIT_CUSTODY"),
  v.literal("TELCO_CLEARING_LIABILITY")
);

export const ledgerEntryDirectionEnum = v.union(
  v.literal("DEBIT"),
  v.literal("CREDIT")
);

export const escrowDisputeStatusEnum = v.union(
  v.literal("OPENED"),
  v.literal("UNDER_REVIEW"),
  v.literal("RESOLVED_MUTUAL"),
  v.literal("RESOLVED_ADJUDICATED"),
  v.literal("REJECTED")
);

export const reContractType = v.union(
  v.literal("INSPECTION_PASS"),
  v.literal("SHORT_STAY_BOOKING"),
  v.literal("LONG_TERM_LEASE"),
  v.literal("LAND_PURCHASE_MILESTONE")
);

export const reMilestoneState = v.union(
  v.literal("CREATED"),
  v.literal("FUNDS_LOCKED"),
  v.literal("AGENT_DISPATCHED"),
  v.literal("CHECKED_IN"),
  v.literal("MILESTONE_VERIFIED"),
  v.literal("FULLY_SETTLED"),
  v.literal("UNDER_ARBITRATION"),
  v.literal("REFUNDED"),
  v.literal("CANCELLED")
);

export const reDisputeStatus = v.union(
  v.literal("OPENED"),
  v.literal("EVIDENCE_SUBMITTED"),
  v.literal("IN_CONCILIATION"),
  v.literal("RESOLVED_MUTUAL"),
  v.literal("ADJUDICATED_ADMIN"),
  v.literal("REJECTED")
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
    escrowBalance: v.optional(v.number()),
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

  // ─── ESCROW ORDERS ────────────────────────────────────────────────
  escrow_orders: defineTable({
    orderCode: v.string(), // e.g. VK-ESC-2026-98124
    orderType: escrowOrderType,
    renterOrBuyerId: v.id("users"),
    ownerOrSellerId: v.id("users"),
    vehicleListingId: v.id("vehicleListings"),
    currency: v.string(), // "SLE"

    // Rental Breakdown
    baseRentalAmount: v.number(),
    refundableDepositAmount: v.number(),

    // Purchase Breakdown
    earnestFeeAmount: v.number(),
    fullPurchaseAmount: v.number(),

    // Financial Totals
    grossEscrowAmount: v.number(),
    platformFeeAmount: v.number(),
    netMerchantExpected: v.number(),

    // Split Releases (60/40)
    split60ReleasedAmount: v.number(),
    split40ReleasedAmount: v.number(),
    depositRefundedAmount: v.number(),
    depositDamageDeductedAmount: v.number(),

    status: escrowOrderStatus,
    purchaseStage: v.optional(escrowPurchaseStage),

    // Schedule
    rentalStartDate: v.optional(v.number()),
    rentalEndDate: v.optional(v.number()),
    numberOfDays: v.optional(v.number()),

    // Payment Info
    paymentProvider: v.optional(v.string()),
    paymentPhone: v.optional(v.string()),

    metadata: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_order_code", ["orderCode"])
    .index("by_renter_or_buyer", ["renterOrBuyerId"])
    .index("by_owner_or_seller", ["ownerOrSellerId"])
    .index("by_vehicle", ["vehicleListingId"])
    .index("by_status", ["status"])
    .index("by_type_status", ["orderType", "status"]),

  // ─── VEHICLE INSPECTIONS ──────────────────────────────────────────
  vehicle_inspections: defineTable({
    escrowOrderId: v.id("escrow_orders"),
    inspectorId: v.id("users"),
    inspectionType: inspectionTypeEnum,
    odometerReadingKm: v.number(),
    fuelTankPercentage: v.number(),

    // 6 Directional Photos
    photoFrontUrl: v.string(),
    photoRearUrl: v.string(),
    photoLeftSideUrl: v.string(),
    photoRightSideUrl: v.string(),
    photoInteriorUrl: v.string(),
    photoDashboardOdometerUrl: v.string(),
    additionalPhotos: v.optional(v.array(v.string())),

    damagesDetected: v.optional(v.array(v.string())),
    notes: v.optional(v.string()),

    // Dual QR Authentication Token & Signature
    qrTokenHash: v.string(),
    counterpartySignatureUrl: v.optional(v.string()),

    status: inspectionStatusEnum,
    createdAt: v.number(),
    completedAt: v.optional(v.number()),
  })
    .index("by_order", ["escrowOrderId"])
    .index("by_order_type", ["escrowOrderId", "inspectionType"])
    .index("by_inspector", ["inspectorId"]),

  // ─── SLRSA TRANSFER RECORDS ───────────────────────────────────────
  slrsa_transfer_records: defineTable({
    escrowOrderId: v.id("escrow_orders"),
    vehicleVinOrChassis: v.string(),
    slrsaLicensePlate: v.string(),
    logbookBlueBookFrontUrl: v.string(),
    logbookBlueBookEndorsementUrl: v.string(),
    slrsaFormCUrl: v.string(),
    buyerNationalIdUrl: v.string(),
    sellerNationalIdUrl: v.string(),
    verifiedByAdminId: v.optional(v.id("users")),
    verificationNotes: v.optional(v.string()),
    isVerified: v.boolean(),
    verifiedAt: v.optional(v.number()),
    submittedAt: v.number(),
  })
    .index("by_order", ["escrowOrderId"])
    .index("by_verified", ["isVerified"]),

  // ─── DOUBLE-ENTRY LEDGER: TRANSACTIONS & ENTRIES ───────────────────
  ledger_transactions: defineTable({
    transactionCode: v.string(),
    escrowOrderId: v.optional(v.id("escrow_orders")),
    description: v.string(),
    createdAt: v.number(),
  })
    .index("by_code", ["transactionCode"])
    .index("by_order", ["escrowOrderId"]),

  ledger_entries: defineTable({
    transactionId: v.id("ledger_transactions"),
    accountType: ledgerAccountTypeEnum,
    userId: v.optional(v.id("users")),
    direction: ledgerEntryDirectionEnum,
    amount: v.number(),
    currency: v.string(),
    createdAt: v.number(),
  })
    .index("by_tx", ["transactionId"])
    .index("by_user", ["userId"])
    .index("by_user_account", ["userId", "accountType"]),

  // ─── ESCROW DISPUTES ──────────────────────────────────────────────
  escrow_disputes: defineTable({
    escrowOrderId: v.id("escrow_orders"),
    openedByUserId: v.id("users"),
    reason: v.string(),
    claimedRepairCost: v.number(),
    approvedRepairCost: v.optional(v.number()),
    evidenceMediaUrls: v.array(v.string()),
    status: escrowDisputeStatusEnum,
    adjudicatedByAdminId: v.optional(v.id("users")),
    adjudicationNotes: v.optional(v.string()),
    openedAt: v.number(),
    resolvedAt: v.optional(v.number()),
  })
    .index("by_order", ["escrowOrderId"])
    .index("by_status", ["status"]),

  // ─── TELCO WEBHOOK AUDIT & IDEMPOTENCY LOGS ───────────────────────
  telco_webhook_logs: defineTable({
    provider: v.string(),
    externalTransactionId: v.string(),
    idempotencyKey: v.string(),
    requestPayload: v.string(),
    isProcessed: v.boolean(),
    errorMessage: v.optional(v.string()),
    receivedAt: v.number(),
    processedAt: v.optional(v.number()),
  })
    .index("by_idempotency", ["idempotencyKey"])
    .index("by_prov_ext_id", ["provider", "externalTransactionId"]),

  // ─── REAL ESTATE ESCROW: INSPECTION PASSES (ANTI-BYPASS TOURS) ────
  re_inspection_passes: defineTable({
    propertyListingId: v.id("realEstateListings"),
    clientId: v.id("users"),
    agentId: v.id("users"),
    tourFee: v.number(),
    platformFee: v.number(),
    agentNetFee: v.number(),
    qrHash: v.string(),
    otpCode: v.string(),
    otpExpiresAt: v.number(),
    status: reMilestoneState,
    scheduledAt: v.number(),
    verifiedAt: v.optional(v.number()),
    agentGpsLat: v.optional(v.number()),
    agentGpsLng: v.optional(v.number()),
    isAddressUnmasked: v.boolean(),
    createdAt: v.number(),
  })
    .index("by_client", ["clientId"])
    .index("by_agent", ["agentId"])
    .index("by_property", ["propertyListingId"])
    .index("by_qr", ["qrHash"])
    .index("by_status", ["status"]),

  // ─── REAL ESTATE ESCROW: MASTER CONTRACTS & VAULTS ────────────────
  re_escrow_contracts: defineTable({
    contractCode: v.string(),
    contractType: reContractType,
    propertyListingId: v.id("realEstateListings"),
    clientId: v.id("users"),
    beneficiaryId: v.id("users"),
    agentId: v.optional(v.id("users")),
    grossAmount: v.number(),
    cautionDepositAmount: v.number(),
    platformFeeAmount: v.number(),
    agentCommissionAmount: v.number(),
    netBeneficiaryExpected: v.number(),
    releasedBeneficiaryAmount: v.number(),
    refundedClientAmount: v.number(),
    paymentRail: v.string(),
    currentState: reMilestoneState,
    stayCheckInTimestamp: v.optional(v.number()),
    stay24hAutoReleaseTimestamp: v.optional(v.number()),
    leaseDurationMonths: v.optional(v.number()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_contract_code", ["contractCode"])
    .index("by_client", ["clientId"])
    .index("by_beneficiary", ["beneficiaryId"])
    .index("by_property", ["propertyListingId"])
    .index("by_state", ["currentState"]),

  // ─── REAL ESTATE ESCROW: LAND & PROPERTY MILESTONES (10/40/50) ────
  re_escrow_milestones: defineTable({
    contractId: v.id("re_escrow_contracts"),
    milestoneIndex: v.number(), // 1 (Title Search), 2 (Survey & Deed), 3 (OARG Conveyance)
    title: v.string(),
    targetPercentage: v.number(),
    amount: v.number(),
    verificationRequirement: v.string(),
    proofDocumentUrls: v.array(v.string()),
    isVerified: v.boolean(),
    verifiedByLegalAgentId: v.optional(v.id("users")),
    state: reMilestoneState,
    releasedAt: v.optional(v.number()),
    createdAt: v.number(),
  })
    .index("by_contract", ["contractId"])
    .index("by_state", ["state"]),

  // ─── REAL ESTATE ESCROW: CAUTION DEPOSITS IN VAULT ─────────────────
  re_caution_deposits: defineTable({
    contractId: v.id("re_escrow_contracts"),
    originalDepositAmount: v.number(),
    heldAmount: v.number(),
    deductionClaimAmount: v.number(),
    refundedAmount: v.number(),
    status: v.union(
      v.literal("LOCKED"),
      v.literal("REFUND_INITIATED"),
      v.literal("REFUNDED_CLEAN"),
      v.literal("DEDUCTED_PARTIAL"),
      v.literal("FORFEITED_FULL"),
      v.literal("IN_DISPUTE")
    ),
    inventoryChecklistSigned: v.boolean(),
    checkoutNotes: v.optional(v.string()),
    settledAt: v.optional(v.number()),
    createdAt: v.number(),
  })
    .index("by_contract", ["contractId"])
    .index("by_status", ["status"]),

  // ─── REAL ESTATE ESCROW: PROPERTY DISPUTES & ARBITRATION ──────────
  re_escrow_disputes: defineTable({
    contractId: v.id("re_escrow_contracts"),
    openedByUserId: v.id("users"),
    claimantRole: v.string(),
    reason: v.string(),
    claimedRepairCost: v.number(),
    approvedRepairCost: v.optional(v.number()),
    evidenceMediaUrls: v.array(v.string()),
    status: reDisputeStatus,
    adjudicatedByAdminId: v.optional(v.id("users")),
    adjudicationNotes: v.optional(v.string()),
    openedAt: v.number(),
    resolvedAt: v.optional(v.number()),
  })
    .index("by_contract", ["contractId"])
    .index("by_status", ["status"]),
});
