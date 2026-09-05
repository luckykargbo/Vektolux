// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_vehicle_listings_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedVehicleListingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedVehicleListingsTableTable get cachedVehicleListingsTable =>
      attachedDatabase.cachedVehicleListingsTable;
  CachedVehicleListingsDaoManager get managers =>
      CachedVehicleListingsDaoManager(this);
}

class CachedVehicleListingsDaoManager {
  final _$CachedVehicleListingsDaoMixin _db;
  CachedVehicleListingsDaoManager(this._db);
  $$CachedVehicleListingsTableTableTableManager
      get cachedVehicleListingsTable =>
          $$CachedVehicleListingsTableTableTableManager(
              _db.attachedDatabase, _db.cachedVehicleListingsTable);
}
