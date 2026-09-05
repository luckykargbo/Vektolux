// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_property_listings_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedPropertyListingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedPropertyListingsTableTable get cachedPropertyListingsTable =>
      attachedDatabase.cachedPropertyListingsTable;
  CachedPropertyListingsDaoManager get managers =>
      CachedPropertyListingsDaoManager(this);
}

class CachedPropertyListingsDaoManager {
  final _$CachedPropertyListingsDaoMixin _db;
  CachedPropertyListingsDaoManager(this._db);
  $$CachedPropertyListingsTableTableTableManager
      get cachedPropertyListingsTable =>
          $$CachedPropertyListingsTableTableTableManager(
              _db.attachedDatabase, _db.cachedPropertyListingsTable);
}
