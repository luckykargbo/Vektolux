// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_bookings_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedBookingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedBookingsTableTable get cachedBookingsTable =>
      attachedDatabase.cachedBookingsTable;
  CachedBookingsDaoManager get managers => CachedBookingsDaoManager(this);
}

class CachedBookingsDaoManager {
  final _$CachedBookingsDaoMixin _db;
  CachedBookingsDaoManager(this._db);
  $$CachedBookingsTableTableTableManager get cachedBookingsTable =>
      $$CachedBookingsTableTableTableManager(
          _db.attachedDatabase, _db.cachedBookingsTable);
}
