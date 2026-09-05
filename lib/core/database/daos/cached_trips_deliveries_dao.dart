// lib/core/database/daos/cached_trips_deliveries_dao.dart
// ═══════════════════════════════════════════════════════════════════════
// DAO for CachedTripsDeliveriesTable
// Local offline cache for passenger trips and package deliveries.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/cached_entities_table.dart';

part 'cached_trips_deliveries_dao.g.dart';

@DriftAccessor(tables: [CachedTripsDeliveriesTable])
class CachedTripsDeliveriesDao extends DatabaseAccessor<AppDatabase>
    with _$CachedTripsDeliveriesDaoMixin {
  CachedTripsDeliveriesDao(super.db);

  /// Watch trips & deliveries for a passenger, newest first.
  Stream<List<CachedTripDelivery>> watchPassengerTrips(String passengerId) {
    return (select(cachedTripsDeliveriesTable)
          ..where((t) => t.passengerId.equals(passengerId))
          ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]))
        .watch();
  }

  /// Watch active trips & deliveries for a passenger.
  Stream<List<CachedTripDelivery>> watchActivePassengerTrips(String passengerId) {
    return (select(cachedTripsDeliveriesTable)
          ..where((t) =>
              t.passengerId.equals(passengerId) &
              t.status.isIn(['searching', 'accepted', 'arrived', 'in_progress']))
          ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]))
        .watch();
  }

  /// Watch trips & deliveries assigned to a driver.
  Stream<List<CachedTripDelivery>> watchDriverTrips(String driverId) {
    return (select(cachedTripsDeliveriesTable)
          ..where((t) => t.driverId.equals(driverId))
          ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]))
        .watch();
  }

  /// Get trip by ID.
  Future<CachedTripDelivery?> getById(String id) {
    return (select(cachedTripsDeliveriesTable)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Upsert a trip/delivery record.
  Future<void> insertOrUpdate(CachedTripsDeliveriesTableCompanion trip) async {
    await into(cachedTripsDeliveriesTable).insertOnConflictUpdate(trip);
  }

  /// Batch upsert trips.
  Future<void> insertAll(List<CachedTripsDeliveriesTableCompanion> trips) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(cachedTripsDeliveriesTable, trips);
    });
  }

  /// Update trip status.
  Future<void> updateStatus({
    required String tripId,
    required String status,
    String? driverId,
    String? vehicleId,
  }) async {
    await (update(cachedTripsDeliveriesTable)..where((t) => t.id.equals(tripId))).write(
      CachedTripsDeliveriesTableCompanion(
        status: Value(status),
        driverId: driverId != null ? Value(driverId) : const Value.absent(),
        vehicleId: vehicleId != null ? Value(vehicleId) : const Value.absent(),
        cachedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Delete a trip by ID.
  Future<void> deleteById(String id) async {
    await (delete(cachedTripsDeliveriesTable)..where((t) => t.id.equals(id))).go();
  }

  /// Clear all cached trips.
  Future<void> clearAll() async {
    await delete(cachedTripsDeliveriesTable).go();
  }
}
