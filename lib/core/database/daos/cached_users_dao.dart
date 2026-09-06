// lib/core/database/daos/cached_users_dao.dart
// ═══════════════════════════════════════════════════════════════════════
// DAO for CachedUsersTable — User session and profile local storage.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/cached_entities_table.dart';

part 'cached_users_dao.g.dart';

@DriftAccessor(tables: [CachedUsersTable])
class CachedUsersDao extends DatabaseAccessor<AppDatabase>
    with _$CachedUsersDaoMixin {
  CachedUsersDao(super.db);

  /// Get the currently active user session, if any.
  Future<CachedUser?> getActiveSession() {
    return (select(cachedUsersTable)
          ..where((t) => t.isActiveSession.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Watch active session reactively.
  Stream<CachedUser?> watchActiveSession() {
    return (select(cachedUsersTable)
          ..where((t) => t.isActiveSession.equals(true))
          ..limit(1))
        .watchSingleOrNull();
  }

  /// Save or update user session. Deactivates previous sessions first.
  Future<void> saveUserSession(CachedUsersTableCompanion user) async {
    await transaction(() async {
      // Deactivate any previous active sessions
      await (update(cachedUsersTable)
            ..where((t) => t.isActiveSession.equals(true)))
          .write(const CachedUsersTableCompanion(isActiveSession: Value(false)));

      // Upsert current user as active session
      await into(cachedUsersTable).insertOnConflictUpdate(user);
    });
  }

  /// Clear the active user session on logout.
  Future<void> clearSession() async {
    await (update(cachedUsersTable)
          ..where((t) => t.isActiveSession.equals(true)))
        .write(const CachedUsersTableCompanion(isActiveSession: Value(false)));
  }

  /// Update user verification status in local cache.
  Future<void> updateVerificationStatus({
    required String userId,
    required bool isVerified,
  }) async {
    await (update(cachedUsersTable)..where((t) => t.id.equals(userId))).write(
      CachedUsersTableCompanion(
        isVerified: Value(isVerified),
        cachedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Delete all cached users (complete reset).
  Future<void> deleteAll() async {
    await delete(cachedUsersTable).go();
  }
}
