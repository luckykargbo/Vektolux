// lib/core/database/daos/sync_queue_dao.dart
// ═══════════════════════════════════════════════════════════════════════
// DAO for the Transactional Outbox (sync_queue) table.
// Provides atomic insert, status transitions, retry tracking,
// and reactive streams for the sync engine.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/sync_queue_table.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncQueueTable])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  // ═══════════════════════════════════════════════════════════════════
  //                        INSERT OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Insert a new outbox entry. Called within an atomic transaction
  /// alongside the domain table write.
  Future<void> enqueue(SyncQueueEntry entry) async {
    await into(syncQueueTable).insertOnConflictUpdate(
      SyncQueueTableCompanion.insert(
        id: entry.id,
        idempotencyKey: entry.idempotencyKey,
        mutationPath: entry.mutationPath,
        operationType: entry.operationType,
        entityType: entry.entityType,
        entityId: entry.entityId,
        payloadJson: entry.payloadJson,
        status: Value(entry.status),
        retryCount: Value(entry.retryCount),
        maxRetries: Value(entry.maxRetries),
        createdAt: entry.createdAt,
        priority: Value(entry.priority),
      ),
    );
  }

  /// Convenience: insert from raw parameters.
  Future<void> enqueueRaw({
    required String id,
    required String idempotencyKey,
    required String mutationPath,
    required OperationType operationType,
    required String entityType,
    required String entityId,
    required String payloadJson,
    int priority = 5,
    int maxRetries = 5,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(syncQueueTable).insert(
      SyncQueueTableCompanion.insert(
        id: id,
        idempotencyKey: idempotencyKey,
        mutationPath: mutationPath,
        operationType: operationType,
        entityType: entityType,
        entityId: entityId,
        payloadJson: payloadJson,
        status: const Value(SyncStatus.pending),
        retryCount: const Value(0),
        maxRetries: Value(maxRetries),
        createdAt: now,
        priority: Value(priority),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                        QUERY OPERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Get all pending entries ordered by priority (ascending) then creation time.
  Future<List<SyncQueueEntry>> getPendingEntries({int limit = 50}) async {
    return (select(syncQueueTable)
          ..where((t) => t.status.equals(SyncStatus.pending.name))
          ..orderBy([
            (t) => OrderingTerm.asc(t.priority),
            (t) => OrderingTerm.asc(t.createdAt),
          ])
          ..limit(limit))
        .get();
  }

  /// Watch pending entries as a reactive stream (triggers sync engine).
  Stream<List<SyncQueueEntry>> watchPendingEntries() {
    return (select(syncQueueTable)
          ..where((t) => t.status.equals(SyncStatus.pending.name))
          ..orderBy([
            (t) => OrderingTerm.asc(t.priority),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  /// Get count of pending entries.
  Future<int> getPendingCount() async {
    final count = countAll();
    final query = selectOnly(syncQueueTable)
      ..where(syncQueueTable.status.equals(SyncStatus.pending.name))
      ..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Watch count of pending entries (for UI badge).
  Stream<int> watchPendingCount() {
    final count = countAll();
    final query = selectOnly(syncQueueTable)
      ..where(syncQueueTable.status.equals(SyncStatus.pending.name))
      ..addColumns([count]);
    return query.watchSingle().map((row) => row.read(count) ?? 0);
  }

  /// Get all failed entries.
  Future<List<SyncQueueEntry>> getFailedEntries() async {
    return (select(syncQueueTable)
          ..where((t) => t.status.equals(SyncStatus.failed.name))
          ..orderBy([(t) => OrderingTerm.desc(t.lastAttemptAt)]))
        .get();
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     STATUS TRANSITIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Mark an entry as currently syncing.
  Future<void> markSyncing(String entryId) async {
    await (update(syncQueueTable)..where((t) => t.id.equals(entryId))).write(
      SyncQueueTableCompanion(
        status: const Value(SyncStatus.syncing),
        lastAttemptAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Mark an entry as successfully synced.
  Future<void> markSynced(String entryId) async {
    await (update(syncQueueTable)..where((t) => t.id.equals(entryId))).write(
      SyncQueueTableCompanion(
        status: const Value(SyncStatus.synced),
        lastAttemptAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Record a sync attempt failure and increment retry count.
  Future<void> recordFailure(String entryId, String errorMessage) async {
    // First fetch current entry to check retry count
    final entry = await (select(syncQueueTable)
          ..where((t) => t.id.equals(entryId)))
        .getSingleOrNull();

    if (entry == null) return;

    final newRetryCount = entry.retryCount + 1;
    final newStatus = newRetryCount >= entry.maxRetries
        ? SyncStatus.failed
        : SyncStatus.pending; // Back to pending for retry

    await (update(syncQueueTable)..where((t) => t.id.equals(entryId))).write(
      SyncQueueTableCompanion(
        status: Value(newStatus),
        retryCount: Value(newRetryCount),
        lastAttemptAt: Value(DateTime.now().millisecondsSinceEpoch),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  /// Mark an entry as having a conflict.
  Future<void> markConflict(String entryId, String details) async {
    await (update(syncQueueTable)..where((t) => t.id.equals(entryId))).write(
      SyncQueueTableCompanion(
        status: const Value(SyncStatus.conflict),
        errorMessage: Value(details),
        lastAttemptAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                        CLEANUP
  // ═══════════════════════════════════════════════════════════════════

  /// Delete all synced entries (housekeeping).
  Future<int> purgeSyncedEntries() async {
    return (delete(syncQueueTable)
          ..where((t) => t.status.equalsValue(SyncStatus.synced)))
        .go();
  }

  /// Delete synced entries older than the specified duration.
  Future<int> purgeSyncedOlderThan(Duration age) async {
    final cutoff =
        DateTime.now().subtract(age).millisecondsSinceEpoch;
    return (delete(syncQueueTable)
          ..where((t) =>
              t.status.equalsValue(SyncStatus.synced) &
              t.createdAt.isSmallerThanValue(cutoff)))
        .go();
  }

  /// Reset a failed entry back to pending for manual retry.
  Future<void> retryFailed(String entryId) async {
    await (update(syncQueueTable)..where((t) => t.id.equals(entryId))).write(
      const SyncQueueTableCompanion(
        status: Value(SyncStatus.pending),
        retryCount: Value(0),
        errorMessage: Value(null),
      ),
    );
  }

  /// Reset ALL stuck "syncing" entries back to "pending" on app startup.
  /// This handles the case where the app was killed mid-sync.
  Future<int> resetStuckEntries() async {
    return (update(syncQueueTable)
          ..where((t) => t.status.equalsValue(SyncStatus.syncing)))
        .write(
      const SyncQueueTableCompanion(
        status: Value(SyncStatus.pending),
      ),
    );
  }
}
