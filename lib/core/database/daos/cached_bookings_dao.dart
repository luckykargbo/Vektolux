// lib/core/database/daos/cached_bookings_dao.dart
// ═══════════════════════════════════════════════════════════════════════
// DAO for CachedBookingsTable — Universal booking & trip offline cache.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/cached_entities_table.dart';

part 'cached_bookings_dao.g.dart';

@DriftAccessor(tables: [CachedBookingsTable])
class CachedBookingsDao extends DatabaseAccessor<AppDatabase>
    with _$CachedBookingsDaoMixin {
  CachedBookingsDao(super.db);

  /// Watch all cached bookings for a buyer, newest first.
  Stream<List<CachedBooking>> watchUserBookings(String buyerId) {
    return (select(cachedBookingsTable)
          ..where((t) => t.buyerId.equals(buyerId))
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)]))
        .watch();
  }

  /// Watch all active / upcoming bookings for a buyer.
  Stream<List<CachedBooking>> watchActiveUserBookings(String buyerId) {
    return (select(cachedBookingsTable)
          ..where((t) =>
              t.buyerId.equals(buyerId) &
              t.bookingStatus.isIn(['pending_payment', 'confirmed', 'in_progress']))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .watch();
  }

  /// Watch past / completed / cancelled bookings for a buyer.
  Stream<List<CachedBooking>> watchHistoricalUserBookings(String buyerId) {
    return (select(cachedBookingsTable)
          ..where((t) =>
              t.buyerId.equals(buyerId) &
              t.bookingStatus.isIn(['completed', 'cancelled']))
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)]))
        .watch();
  }

  /// Watch incoming bookings for a vendor.
  Stream<List<CachedBooking>> watchVendorBookings(String vendorId) {
    return (select(cachedBookingsTable)
          ..where((t) => t.vendorId.equals(vendorId))
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)]))
        .watch();
  }

  /// Get booking by ID.
  Future<CachedBooking?> getById(String id) {
    return (select(cachedBookingsTable)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Upsert a single booking into local cache.
  Future<void> insertOrUpdate(CachedBookingsTableCompanion booking) async {
    await into(cachedBookingsTable).insertOnConflictUpdate(booking);
  }

  /// Batch upsert multiple bookings.
  Future<void> insertAll(List<CachedBookingsTableCompanion> bookings) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(cachedBookingsTable, bookings);
    });
  }

  /// Update booking status and payment status locally.
  Future<void> updateStatus({
    required String id,
    required String bookingStatus,
    required String paymentStatus,
  }) async {
    await (update(cachedBookingsTable)..where((t) => t.id.equals(id))).write(
      CachedBookingsTableCompanion(
        bookingStatus: Value(bookingStatus),
        paymentStatus: Value(paymentStatus),
        cachedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Delete a single booking by ID.
  Future<void> deleteById(String id) async {
    await (delete(cachedBookingsTable)..where((t) => t.id.equals(id))).go();
  }

  /// Clear all cached bookings.
  Future<void> clearAll() async {
    await delete(cachedBookingsTable).go();
  }
}
