// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_driver_profiles_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedDriverProfilesDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedDriverProfilesTableTable get cachedDriverProfilesTable =>
      attachedDatabase.cachedDriverProfilesTable;
  $CachedDriverVehiclesTableTable get cachedDriverVehiclesTable =>
      attachedDatabase.cachedDriverVehiclesTable;
  CachedDriverProfilesDaoManager get managers =>
      CachedDriverProfilesDaoManager(this);
}

class CachedDriverProfilesDaoManager {
  final _$CachedDriverProfilesDaoMixin _db;
  CachedDriverProfilesDaoManager(this._db);
  $$CachedDriverProfilesTableTableTableManager get cachedDriverProfilesTable =>
      $$CachedDriverProfilesTableTableTableManager(
          _db.attachedDatabase, _db.cachedDriverProfilesTable);
  $$CachedDriverVehiclesTableTableTableManager get cachedDriverVehiclesTable =>
      $$CachedDriverVehiclesTableTableTableManager(
          _db.attachedDatabase, _db.cachedDriverVehiclesTable);
}
