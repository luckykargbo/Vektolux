// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_entities_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedPropertiesDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedPropertiesTableTable get cachedPropertiesTable =>
      attachedDatabase.cachedPropertiesTable;
  CachedPropertiesDaoManager get managers => CachedPropertiesDaoManager(this);
}

class CachedPropertiesDaoManager {
  final _$CachedPropertiesDaoMixin _db;
  CachedPropertiesDaoManager(this._db);
  $$CachedPropertiesTableTableTableManager get cachedPropertiesTable =>
      $$CachedPropertiesTableTableTableManager(
          _db.attachedDatabase, _db.cachedPropertiesTable);
}

mixin _$CachedRidesDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedRidesTableTable get cachedRidesTable =>
      attachedDatabase.cachedRidesTable;
  CachedRidesDaoManager get managers => CachedRidesDaoManager(this);
}

class CachedRidesDaoManager {
  final _$CachedRidesDaoMixin _db;
  CachedRidesDaoManager(this._db);
  $$CachedRidesTableTableTableManager get cachedRidesTable =>
      $$CachedRidesTableTableTableManager(
          _db.attachedDatabase, _db.cachedRidesTable);
}

mixin _$CachedWalletsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedWalletsTableTable get cachedWalletsTable =>
      attachedDatabase.cachedWalletsTable;
  $CachedTransactionsTableTable get cachedTransactionsTable =>
      attachedDatabase.cachedTransactionsTable;
  CachedWalletsDaoManager get managers => CachedWalletsDaoManager(this);
}

class CachedWalletsDaoManager {
  final _$CachedWalletsDaoMixin _db;
  CachedWalletsDaoManager(this._db);
  $$CachedWalletsTableTableTableManager get cachedWalletsTable =>
      $$CachedWalletsTableTableTableManager(
          _db.attachedDatabase, _db.cachedWalletsTable);
  $$CachedTransactionsTableTableTableManager get cachedTransactionsTable =>
      $$CachedTransactionsTableTableTableManager(
          _db.attachedDatabase, _db.cachedTransactionsTable);
}
