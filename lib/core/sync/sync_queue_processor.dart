// lib/core/sync/sync_queue_processor.dart
// ═══════════════════════════════════════════════════════════════════════
// Outbox Queue Processor — Reads pending sync entries and pushes
// mutations to Convex backend with exponential backoff retry logic.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:logger/logger.dart';

import '../database/app_database.dart';
import '../database/daos/sync_queue_dao.dart';
import '../network/convex_client_wrapper.dart';

/// Processes the transactional outbox queue by sending pending mutations
/// to the Convex backend sequentially.
///
/// Design decisions:
/// - Sequential processing (not parallel) to preserve operation ordering
/// - Exponential backoff between retries: delay = 200ms × 2^retryCount
/// - Failed entries stay in queue until max retries exhausted
/// - Idempotency keys ensure safe re-execution on Convex side
class SyncQueueProcessor {
  final SyncQueueDao _syncQueueDao;
  final ConvexClientWrapper _convexClient;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// Whether the processor is currently running.
  bool _isProcessing = false;

  /// Callback invoked after each successful sync (for entity status updates).
  final Future<void> Function(String entityType, String entityId)?
      onEntitySynced;

  SyncQueueProcessor({
    required SyncQueueDao syncQueueDao,
    required ConvexClientWrapper convexClient,
    this.onEntitySynced,
  })  : _syncQueueDao = syncQueueDao,
        _convexClient = convexClient;

  /// Whether the processor is currently running a batch.
  bool get isProcessing => _isProcessing;

  // ═══════════════════════════════════════════════════════════════════
  //                     MAIN PROCESSING LOOP
  // ═══════════════════════════════════════════════════════════════════

  /// Process all pending entries in the outbox queue.
  ///
  /// Returns a [SyncBatchResult] with counts of successful, failed,
  /// and skipped entries.
  Future<SyncBatchResult> processQueue() async {
    if (_isProcessing) {
      _log.d('SyncQueueProcessor: already processing — skipping');
      return const SyncBatchResult(processed: 0, failed: 0, skipped: 1);
    }

    _isProcessing = true;
    int processed = 0;
    int failed = 0;

    try {
      // Fetch pending entries ordered by priority then creation time
      final pendingEntries = await _syncQueueDao.getPendingEntries(limit: 50);

      if (pendingEntries.isEmpty) {
        _log.d('SyncQueueProcessor: no pending entries');
        return const SyncBatchResult(processed: 0, failed: 0, skipped: 0);
      }

      _log.i(
        'SyncQueueProcessor: processing ${pendingEntries.length} entries',
      );

      for (final entry in pendingEntries) {
        final success = await _processEntry(entry);
        if (success) {
          processed++;
        } else {
          failed++;
          // Add exponential backoff delay between failed entries
          final delay = _calculateBackoff(entry.retryCount);
          await Future.delayed(delay);
        }
      }

      _log.i(
        'SyncQueueProcessor: batch complete — '
        '$processed synced, $failed failed',
      );

      // Housekeeping: purge synced entries older than 24 hours
      final purged = await _syncQueueDao.purgeSyncedOlderThan(
        const Duration(hours: 24),
      );
      if (purged > 0) {
        _log.d('SyncQueueProcessor: purged $purged old synced entries');
      }

      return SyncBatchResult(
        processed: processed,
        failed: failed,
        skipped: 0,
      );
    } catch (e, stack) {
      _log.e('SyncQueueProcessor: fatal error', error: e, stackTrace: stack);
      return SyncBatchResult(processed: processed, failed: failed, skipped: 0);
    } finally {
      _isProcessing = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                   SINGLE ENTRY PROCESSING
  // ═══════════════════════════════════════════════════════════════════

  /// Process a single outbox entry.
  Future<bool> _processEntry(SyncQueueEntry entry) async {
    try {
      // Mark as syncing
      await _syncQueueDao.markSyncing(entry.id);

      // Parse the mutation payload
      final payload = jsonDecode(entry.payloadJson) as Map<String, dynamic>;

      // Inject idempotency key into payload for server-side dedup
      payload['idempotencyKey'] = entry.idempotencyKey;

      // Execute the Convex mutation
      _log.d(
        'SyncQueueProcessor: sending ${entry.mutationPath} '
        'for ${entry.entityType}/${entry.entityId}',
      );

      final result = await _convexClient.mutation(
        entry.mutationPath,
        args: payload,
      );

      if (result.success) {
        // ── SUCCESS ─────────────────────────────────────────────
        await _syncQueueDao.markSynced(entry.id);

        // Notify that this entity has been synced
        if (onEntitySynced != null) {
          await onEntitySynced!(entry.entityType, entry.entityId);
        }

        _log.d(
          'SyncQueueProcessor: ✓ synced ${entry.entityType}/${entry.entityId}',
        );
        return true;
      } else {
        // ── MUTATION FAILED ─────────────────────────────────────
        await _syncQueueDao.recordFailure(
          entry.id,
          result.errorMessage ?? 'Convex mutation failed',
        );

        _log.w(
          'SyncQueueProcessor: ✗ failed ${entry.entityType}/${entry.entityId}: '
          '${result.errorMessage}',
        );
        return false;
      }
    } catch (e) {
      // ── NETWORK / PARSE ERROR ─────────────────────────────────
      await _syncQueueDao.recordFailure(entry.id, e.toString());
      _log.w(
        'SyncQueueProcessor: ✗ error ${entry.entityType}/${entry.entityId}: $e',
      );
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                   EXPONENTIAL BACKOFF
  // ═══════════════════════════════════════════════════════════════════

  /// Calculate exponential backoff delay: 200ms × 2^retryCount.
  /// Capped at 30 seconds.
  Duration _calculateBackoff(int retryCount) {
    final ms = 200 * (1 << retryCount.clamp(0, 7)); // Max 25,600ms
    return Duration(milliseconds: ms.clamp(200, 30000));
  }
}

/// Result of processing a batch of outbox entries.
class SyncBatchResult {
  final int processed;
  final int failed;
  final int skipped;

  const SyncBatchResult({
    required this.processed,
    required this.failed,
    required this.skipped,
  });

  bool get hasFailures => failed > 0;
  int get total => processed + failed + skipped;

  @override
  String toString() =>
      'SyncBatchResult(processed=$processed, failed=$failed, skipped=$skipped)';
}
