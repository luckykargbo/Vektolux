// lib/core/database/daos/cached_entities_dao.dart
// ═══════════════════════════════════════════════════════════════════════
// DAOs for cached entity tables — Properties, Rides, Wallets.
// Provides reactive watch() streams and upsert methods for sync bridge.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/cached_entities_table.dart';

part 'cached_entities_dao.g.dart';

// ═══════════════════════════════════════════════════════════════════════
//                     PROPERTIES DAO
// ═══════════════════════════════════════════════════════════════════════

@DriftAccessor(tables: [CachedPropertiesTable])
class CachedPropertiesDao extends DatabaseAccessor<AppDatabase>
    with _$CachedPropertiesDaoMixin {
  CachedPropertiesDao(super.db);

  /// Watch all available properties, ordered by most recently updated.
  Stream<List<CachedProperty>> watchAll() {
    return (select(cachedPropertiesTable)
          ..where((t) =>
              t.syncStatus.equals(EntitySyncStatus.deletedLocal.name).not())
          ..orderBy([(t) => OrderingTerm.desc(t.localUpdatedAt)]))
        .watch();
  }

  /// Watch properties filtered by category and price range.
  Stream<List<CachedProperty>> watchFiltered({
    String? category,
    double? minPrice,
    double? maxPrice,
    String? city,
    String? searchQuery,
  }) {
    var query = select(cachedPropertiesTable)
      ..where((t) =>
          t.syncStatus.equals(EntitySyncStatus.deletedLocal.name).not());

    if (category != null) {
      query = query..where((t) => t.category.equals(category));
    }
    if (minPrice != null) {
      query = query..where((t) => t.price.isBiggerOrEqualValue(minPrice));
    }
    if (maxPrice != null) {
      query = query..where((t) => t.price.isSmallerOrEqualValue(maxPrice));
    }
    if (city != null) {
      query = query..where((t) => t.city.equals(city));
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query
        ..where((t) =>
            t.title.like('%$searchQuery%') | t.city.like('%$searchQuery%'));
    }

    query = query..orderBy([(t) => OrderingTerm.desc(t.localUpdatedAt)]);
    return query.watch();
  }

  /// Get a single property by ID.
  Future<CachedProperty?> getById(String id) {
    return (select(cachedPropertiesTable)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Watch a single property by ID as a reactive stream.
  Stream<CachedProperty?> watchById(String id) {
    return (select(cachedPropertiesTable)
          ..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  /// Upsert a single property (insert or update on conflict).
  Future<void> upsert(CachedProperty property) async {
    await into(cachedPropertiesTable).insertOnConflictUpdate(property);
  }

  /// Batch upsert multiple properties from Convex sync.
  Future<void> upsertBatch(List<CachedProperty> properties) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(cachedPropertiesTable, properties);
    });
  }

  /// Mark a property as locally modified (pending sync).
  Future<void> markPendingSync(String id) async {
    await (update(cachedPropertiesTable)..where((t) => t.id.equals(id)))
        .write(CachedPropertiesTableCompanion(
      syncStatus: const Value(EntitySyncStatus.pendingSync),
      localUpdatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Mark a property as synced after successful Convex push.
  Future<void> markSynced(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(cachedPropertiesTable)..where((t) => t.id.equals(id)))
        .write(CachedPropertiesTableCompanion(
      syncStatus: const Value(EntitySyncStatus.synced),
      lastSyncedAt: Value(now),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════
//                       RIDES DAO
// ═══════════════════════════════════════════════════════════════════════

@DriftAccessor(tables: [CachedRidesTable])
class CachedRidesDao extends DatabaseAccessor<AppDatabase>
    with _$CachedRidesDaoMixin {
  CachedRidesDao(super.db);

  /// Watch the active ride for a passenger (if any).
  Stream<CachedRide?> watchActiveRide(String passengerId) {
    return (select(cachedRidesTable)
          ..where((t) =>
              t.passengerId.equals(passengerId) &
              t.status.isIn(['requested', 'accepted', 'driver_arriving', 'in_transit']))
          ..orderBy([(t) => OrderingTerm.desc(t.localUpdatedAt)])
          ..limit(1))
        .watchSingleOrNull();
  }

  /// Watch ride history for a passenger.
  Stream<List<CachedRide>> watchHistory(String passengerId, {int limit = 20}) {
    return (select(cachedRidesTable)
          ..where((t) => t.passengerId.equals(passengerId))
          ..orderBy([(t) => OrderingTerm.desc(t.localUpdatedAt)])
          ..limit(limit))
        .watch();
  }

  /// Get a single ride by ID.
  Future<CachedRide?> getById(String id) {
    return (select(cachedRidesTable)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Upsert a ride (from local creation or Convex sync).
  Future<void> upsert(CachedRide ride) async {
    await into(cachedRidesTable).insertOnConflictUpdate(ride);
  }

  /// Batch upsert rides from Convex subscription.
  Future<void> upsertBatch(List<CachedRide> rides) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(cachedRidesTable, rides);
    });
  }

  /// Mark a ride as pending sync.
  Future<void> markPendingSync(String id) async {
    await (update(cachedRidesTable)..where((t) => t.id.equals(id)))
        .write(CachedRidesTableCompanion(
      syncStatus: const Value(EntitySyncStatus.pendingSync),
      localUpdatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Mark a ride as synced.
  Future<void> markSynced(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(cachedRidesTable)..where((t) => t.id.equals(id)))
        .write(CachedRidesTableCompanion(
      syncStatus: const Value(EntitySyncStatus.synced),
      lastSyncedAt: Value(now),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════
//                      WALLETS DAO
// ═══════════════════════════════════════════════════════════════════════

@DriftAccessor(tables: [CachedWalletsTable, CachedTransactionsTable])
class CachedWalletsDao extends DatabaseAccessor<AppDatabase>
    with _$CachedWalletsDaoMixin {
  CachedWalletsDao(super.db);

  /// Watch wallet balance for a user.
  Stream<CachedWallet?> watchBalance(String userId, {String currency = 'SLE'}) {
    return (select(cachedWalletsTable)
          ..where((t) => t.userId.equals(userId) & t.currency.equals(currency)))
        .watchSingleOrNull();
  }

  /// Upsert wallet balance from Convex sync.
  Future<void> upsertWallet(CachedWallet wallet) async {
    await into(cachedWalletsTable).insertOnConflictUpdate(wallet);
  }

  /// Watch transaction history for a user.
  Stream<List<CachedTransaction>> watchTransactions(String userId,
      {int limit = 50}) {
    return (select(cachedTransactionsTable)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.remoteCreatedAt)])
          ..limit(limit))
        .watch();
  }

  /// Batch upsert transactions from Convex sync.
  Future<void> upsertTransactions(List<CachedTransaction> txns) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(cachedTransactionsTable, txns);
    });
  }
}
