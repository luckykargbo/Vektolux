// lib/core/database/tables/cached_entities_table.dart
// ═══════════════════════════════════════════════════════════════════════
// Generic entity cache tables for offline-first local storage.
// Each table mirrors a Convex document collection with sync metadata.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';

/// Sync state of a locally cached entity relative to the Convex backend.
enum EntitySyncStatus {
  synced,       // Matches Convex document exactly
  pendingSync,  // Local changes not yet pushed
  conflict,     // Local and remote both changed
  deletedLocal, // Soft-deleted locally, pending remote delete
}

/// Generic cache table for real estate listings.
@DataClassName('CachedProperty')
class CachedPropertiesTable extends Table {
  TextColumn get id => text()();             // Convex _id
  TextColumn get ownerId => text()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get category => text()();        // sale, long_term_rent, hourly_guesthouse
  RealColumn get price => real()();
  RealColumn get hourlyRate => real().nullable()();
  TextColumn get currency => text().withDefault(const Constant('SLE'))();
  TextColumn get address => text()();
  TextColumn get city => text()();
  TextColumn get country => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get geohash => text()();
  TextColumn get availabilityStatus => text()();
  TextColumn get imageUrlsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isFeatured => boolean().withDefault(const Constant(false))();
  IntColumn get viewCount => integer().withDefault(const Constant(0))();

  // ── Sync metadata ─────────────────────────────────────────────
  TextColumn get syncStatus => textEnum<EntitySyncStatus>()
      .withDefault(Constant(EntitySyncStatus.synced.name))();
  IntColumn get localUpdatedAt => integer()();   // Local modification timestamp
  IntColumn get remoteUpdatedAt => integer()();  // Convex _creationTime or updatedAt
  IntColumn get lastSyncedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache table for ride requests.
@DataClassName('CachedRide')
class CachedRidesTable extends Table {
  TextColumn get id => text()();              // Convex _id or client-generated UUID
  TextColumn get passengerId => text()();
  TextColumn get driverId => text().nullable()();
  TextColumn get vehicleId => text().nullable()();
  RealColumn get pickupLat => real()();
  RealColumn get pickupLng => real()();
  TextColumn get pickupAddress => text().nullable()();
  RealColumn get dropoffLat => real()();
  RealColumn get dropoffLng => real()();
  TextColumn get dropoffAddress => text().nullable()();
  RealColumn get distanceKm => real()();
  IntColumn get estimatedDurationMin => integer()();
  RealColumn get fareAmount => real()();
  TextColumn get currency => text().withDefault(const Constant('SLE'))();
  RealColumn get platformFee => real()();
  RealColumn get driverPayout => real()();
  TextColumn get status => text()();           // requested, accepted, in_transit, etc.
  TextColumn get paymentStatus => text()();
  TextColumn get paymentReference => text().nullable()();
  TextColumn get blockchainLogHash => text().nullable()();
  IntColumn get acceptedAt => integer().nullable()();
  IntColumn get startedAt => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get cancelledAt => integer().nullable()();
  TextColumn get cancelReason => text().nullable()();

  // ── Sync metadata ─────────────────────────────────────────────
  TextColumn get syncStatus => textEnum<EntitySyncStatus>()
      .withDefault(Constant(EntitySyncStatus.synced.name))();
  IntColumn get localUpdatedAt => integer()();
  IntColumn get remoteUpdatedAt => integer()();
  IntColumn get lastSyncedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache table for wallet balances.
@DataClassName('CachedWallet')
class CachedWalletsTable extends Table {
  TextColumn get id => text()();              // Convex wallet _id
  TextColumn get userId => text()();
  RealColumn get availableBalance => real()();
  RealColumn get pendingBalance => real()();
  TextColumn get currency => text()();

  // ── Sync metadata ─────────────────────────────────────────────
  IntColumn get localUpdatedAt => integer()();
  IntColumn get remoteUpdatedAt => integer()();
  IntColumn get lastSyncedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache table for transaction ledger entries.
@DataClassName('CachedTransaction')
class CachedTransactionsTable extends Table {
  TextColumn get id => text()();
  TextColumn get walletId => text()();
  TextColumn get userId => text()();
  TextColumn get type => text()();             // payment, payout, commission, etc.
  RealColumn get amount => real()();
  TextColumn get currency => text()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get status => text()();
  TextColumn get description => text().nullable()();
  TextColumn get blockchainTxHash => text().nullable()();
  IntColumn get remoteCreatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache table for user session & profile.
@DataClassName('CachedUser')
class CachedUsersTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get email => text()();
  TextColumn get phone => text()();
  TextColumn get role => text()();
  BoolColumn get isVerified => boolean().withDefault(const Constant(false))();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get walletAddress => text().nullable()();
  TextColumn get sessionToken => text().nullable()();
  BoolColumn get isActiveSession => boolean().withDefault(const Constant(true))();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache table for real estate discovery feed listings.
@DataClassName('CachedPropertyListing')
class CachedPropertyListingsTable extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get category => text()();
  RealColumn get price => real()();
  RealColumn get hourlyRate => real().nullable()();
  TextColumn get address => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get primaryImageUrl => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(true))();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache table for vehicle / mobility discovery feed listings.
@DataClassName('CachedVehicleListing')
class CachedVehicleListingsTable extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get vehicleType => text()();
  TextColumn get listingIntent => text()();
  TextColumn get make => text()();
  TextColumn get model => text()();
  IntColumn get year => integer()();
  RealColumn get pricePerKm => real().nullable()();
  RealColumn get pricePerDay => real().nullable()();
  RealColumn get salePrice => real().nullable()();
  TextColumn get primaryImageUrl => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(true))();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache table for universal bookings (hourly guest houses, vehicle rentals, inspections).
@DataClassName('CachedBooking')
class CachedBookingsTable extends Table {
  TextColumn get id => text()();              // Convex document _id
  TextColumn get listingId => text()();
  TextColumn get listingTitle => text().withDefault(const Constant(''))();
  TextColumn get buyerId => text()();
  TextColumn get vendorId => text()();
  TextColumn get bookingType => text()();     // hourly_guesthouse, vehicle_rental, property_inspection, vehicle_inspection
  IntColumn get startTime => integer()();
  IntColumn get endTime => integer()();
  RealColumn get totalAmount => real()();
  TextColumn get currency => text().withDefault(const Constant('SLE'))();
  TextColumn get paymentStatus => text()();   // pending, completed
  TextColumn get bookingStatus => text().withDefault(const Constant('pending_payment'))(); // pending_payment, confirmed, cancelled
  BoolColumn get isSynced => boolean().withDefault(const Constant(true))();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache table for on-demand driver profiles (nearby drivers, availability).
@DataClassName('CachedDriverProfile')
class CachedDriverProfilesTable extends Table {
  TextColumn get id => text()();              // Convex document _id
  TextColumn get userId => text()();
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();
  BoolColumn get isAvailable => boolean().withDefault(const Constant(false))();
  TextColumn get serviceType => text()();     // ride, delivery, both
  RealColumn get currentLat => real()();
  RealColumn get currentLng => real()();
  TextColumn get currentGeohash => text()();
  IntColumn get lastLocationUpdate => integer()();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache table for on-demand driver vehicles.
@DataClassName('CachedDriverVehicle')
class CachedDriverVehiclesTable extends Table {
  TextColumn get id => text()();              // Convex document _id
  TextColumn get driverId => text()();
  TextColumn get make => text()();
  TextColumn get model => text()();
  IntColumn get year => integer()();
  TextColumn get color => text()();
  TextColumn get licensePlate => text()();
  TextColumn get category => text()();        // standard, comfort, kekeh_tricycle, delivery_bike
  BoolColumn get isVerified => boolean().withDefault(const Constant(false))();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cache table for trip and package delivery requests.
@DataClassName('CachedTripDelivery')
class CachedTripsDeliveriesTable extends Table {
  TextColumn get id => text()();              // Convex document _id
  TextColumn get passengerId => text()();
  TextColumn get driverId => text().nullable()();
  TextColumn get vehicleId => text().nullable()();
  TextColumn get serviceType => text()();     // ride, delivery
  RealColumn get pickupLat => real()();
  RealColumn get pickupLng => real()();
  TextColumn get pickupAddressText => text()();
  TextColumn get pickupGeohash => text()();
  RealColumn get dropoffLat => real()();
  RealColumn get dropoffLng => real()();
  TextColumn get dropoffAddressText => text()();
  TextColumn get status => text()();           // searching, accepted, arrived, in_progress, completed, cancelled
  RealColumn get fareAmount => real()();
  TextColumn get currency => text().withDefault(const Constant('SLE'))();
  TextColumn get paymentMethod => text()();    // cash, wallet, mobile_money, card
  RealColumn get distanceKm => real()();
  IntColumn get durationMins => integer()();
  TextColumn get deliveryPackageJson => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(true))();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
