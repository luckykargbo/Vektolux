// lib/core/database/daos/cached_vehicle_listings_dao.dart
// ═══════════════════════════════════════════════════════════════════════
// DAO for CachedVehicleListingsTable — Mobility & fleet marketplace cache.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/cached_entities_table.dart';

part 'cached_vehicle_listings_dao.g.dart';

@DriftAccessor(tables: [CachedVehicleListingsTable])
class CachedVehicleListingsDao extends DatabaseAccessor<AppDatabase>
    with _$CachedVehicleListingsDaoMixin {
  CachedVehicleListingsDao(super.db);

  /// Watch all cached vehicle listings, newest first.
  Stream<List<CachedVehicleListing>> watchAll() {
    return (select(cachedVehicleListingsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]))
        .watch();
  }

  /// Watch cached vehicle listings filtered by intent (ride_hailing, rental, sale).
  Stream<List<CachedVehicleListing>> watchByIntent(String intent) {
    return (select(cachedVehicleListingsTable)
          ..where((t) => t.listingIntent.equals(intent))
          ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]))
        .watch();
  }

  /// Watch cached vehicle listings filtered by type (bike, taxi, delivery_van, truck).
  Stream<List<CachedVehicleListing>> watchByType(String type) {
    return (select(cachedVehicleListingsTable)
          ..where((t) => t.vehicleType.equals(type))
          ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]))
        .watch();
  }

  /// Get all cached vehicles.
  Future<List<CachedVehicleListing>> getAll() {
    return (select(cachedVehicleListingsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]))
        .get();
  }

  /// Upsert a single vehicle listing into the cache.
  Future<void> insertOrUpdate(
      CachedVehicleListingsTableCompanion vehicle) async {
    await into(cachedVehicleListingsTable).insertOnConflictUpdate(vehicle);
  }

  /// Batch upsert multiple vehicle listings into the cache.
  Future<void> insertAll(
      List<CachedVehicleListingsTableCompanion> vehicles) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(cachedVehicleListingsTable, vehicles);
    });
  }

  /// Delete a single vehicle by ID.
  Future<void> deleteById(String id) async {
    await (delete(cachedVehicleListingsTable)..where((t) => t.id.equals(id)))
        .go();
  }

  /// Clear the entire vehicle cache.
  Future<void> clearAll() async {
    await delete(cachedVehicleListingsTable).go();
  }
}
