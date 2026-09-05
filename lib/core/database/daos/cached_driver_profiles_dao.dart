// lib/core/database/daos/cached_driver_profiles_dao.dart
// ═══════════════════════════════════════════════════════════════════════
// DAO for CachedDriverProfilesTable and CachedDriverVehiclesTable
// Local offline cache for nearby drivers and fleet vehicles.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/cached_entities_table.dart';

part 'cached_driver_profiles_dao.g.dart';

@DriftAccessor(tables: [CachedDriverProfilesTable, CachedDriverVehiclesTable])
class CachedDriverProfilesDao extends DatabaseAccessor<AppDatabase>
    with _$CachedDriverProfilesDaoMixin {
  CachedDriverProfilesDao(super.db);

  /// Watch all online & available drivers.
  Stream<List<CachedDriverProfile>> watchAvailableDrivers() {
    return (select(cachedDriverProfilesTable)
          ..where((t) => t.isOnline.equals(true) & t.isAvailable.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.lastLocationUpdate)]))
        .watch();
  }

  /// Get driver profile by ID.
  Future<CachedDriverProfile?> getDriverById(String id) {
    return (select(cachedDriverProfilesTable)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Get driver profile by user ID.
  Future<CachedDriverProfile?> getDriverByUserId(String userId) {
    return (select(cachedDriverProfilesTable)..where((t) => t.userId.equals(userId)))
        .getSingleOrNull();
  }

  /// Upsert driver profile.
  Future<void> insertOrUpdateDriver(CachedDriverProfilesTableCompanion driver) async {
    await into(cachedDriverProfilesTable).insertOnConflictUpdate(driver);
  }

  /// Batch upsert driver profiles.
  Future<void> insertAllDrivers(List<CachedDriverProfilesTableCompanion> drivers) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(cachedDriverProfilesTable, drivers);
    });
  }

  /// Update driver location.
  Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
    required String geohash,
  }) async {
    await (update(cachedDriverProfilesTable)..where((t) => t.id.equals(driverId))).write(
      CachedDriverProfilesTableCompanion(
        currentLat: Value(lat),
        currentLng: Value(lng),
        currentGeohash: Value(geohash),
        lastLocationUpdate: Value(DateTime.now().millisecondsSinceEpoch),
        cachedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Update driver online/available status.
  Future<void> updateDriverStatus({
    required String driverId,
    required bool isOnline,
    bool? isAvailable,
  }) async {
    await (update(cachedDriverProfilesTable)..where((t) => t.id.equals(driverId))).write(
      CachedDriverProfilesTableCompanion(
        isOnline: Value(isOnline),
        isAvailable: isAvailable != null ? Value(isAvailable) : const Value.absent(),
        cachedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Get vehicles for a driver.
  Future<List<CachedDriverVehicle>> getVehiclesForDriver(String driverId) {
    return (select(cachedDriverVehiclesTable)
          ..where((t) => t.driverId.equals(driverId)))
        .get();
  }

  /// Upsert a driver vehicle.
  Future<void> insertOrUpdateVehicle(CachedDriverVehiclesTableCompanion vehicle) async {
    await into(cachedDriverVehiclesTable).insertOnConflictUpdate(vehicle);
  }

  /// Clear all drivers and vehicles.
  Future<void> clearAll() async {
    await delete(cachedDriverVehiclesTable).go();
    await delete(cachedDriverProfilesTable).go();
  }
}
