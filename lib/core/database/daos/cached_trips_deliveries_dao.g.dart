// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_trips_deliveries_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedTripsDeliveriesDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedTripsDeliveriesTableTable get cachedTripsDeliveriesTable =>
      attachedDatabase.cachedTripsDeliveriesTable;
  CachedTripsDeliveriesDaoManager get managers =>
      CachedTripsDeliveriesDaoManager(this);
}

class CachedTripsDeliveriesDaoManager {
  final _$CachedTripsDeliveriesDaoMixin _db;
  CachedTripsDeliveriesDaoManager(this._db);
  $$CachedTripsDeliveriesTableTableTableManager
      get cachedTripsDeliveriesTable =>
          $$CachedTripsDeliveriesTableTableTableManager(
              _db.attachedDatabase, _db.cachedTripsDeliveriesTable);
}
