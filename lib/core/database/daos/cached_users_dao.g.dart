// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_users_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedUsersDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedUsersTableTable get cachedUsersTable =>
      attachedDatabase.cachedUsersTable;
  CachedUsersDaoManager get managers => CachedUsersDaoManager(this);
}

class CachedUsersDaoManager {
  final _$CachedUsersDaoMixin _db;
  CachedUsersDaoManager(this._db);
  $$CachedUsersTableTableTableManager get cachedUsersTable =>
      $$CachedUsersTableTableTableManager(
          _db.attachedDatabase, _db.cachedUsersTable);
}
