// lib/core/sync/conflict_resolver.dart
// ═══════════════════════════════════════════════════════════════════════
// Last-Write-Wins (LWW) Conflict Resolution Engine
// Compares local and remote timestamps to determine which version wins.
// ═══════════════════════════════════════════════════════════════════════

import 'package:logger/logger.dart';

/// Result of a conflict resolution comparison.
enum ConflictResolution {
  /// Local version is newer — push local to remote.
  localWins,

  /// Remote version is newer — overwrite local with remote.
  remoteWins,

  /// Both have the same timestamp — keep remote (server authority).
  identical,
}

/// Detailed result of conflict resolution with metadata.
class ConflictResult {
  final ConflictResolution resolution;
  final String entityType;
  final String entityId;
  final int localTimestamp;
  final int remoteTimestamp;
  final int deltaMs;

  const ConflictResult({
    required this.resolution,
    required this.entityType,
    required this.entityId,
    required this.localTimestamp,
    required this.remoteTimestamp,
    required this.deltaMs,
  });

  @override
  String toString() =>
      'ConflictResult($entityType/$entityId: $resolution, delta=${deltaMs}ms)';
}

/// Last-Write-Wins conflict resolver.
///
/// Strategy:
/// - Compare `localUpdatedAt` vs `remoteUpdatedAt` timestamps (ms since epoch)
/// - The version with the LATER timestamp wins
/// - On exact tie, remote (server) wins (server authority principle)
/// - A configurable grace window handles clock skew between client and server
///
/// Usage:
/// ```dart
/// final resolver = ConflictResolver();
/// final result = resolver.resolve(
///   entityType: 'rideRequests',
///   entityId: 'abc123',
///   localUpdatedAt: localRide.localUpdatedAt,
///   remoteUpdatedAt: remoteRide.updatedAt,
///   localHasPendingSync: true,
/// );
///
/// switch (result.resolution) {
///   case ConflictResolution.localWins:
///     // Keep local, outbox will push to Convex
///     break;
///   case ConflictResolution.remoteWins:
///     // Overwrite local with remote data
///     await dao.upsert(remoteData);
///     break;
///   case ConflictResolution.identical:
///     // No action needed
///     break;
/// }
/// ```
class ConflictResolver {
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// Grace window in milliseconds to account for clock skew.
  /// If timestamps are within this window, remote wins (server authority).
  final int clockSkewToleranceMs;

  ConflictResolver({this.clockSkewToleranceMs = 1000});

  // ═══════════════════════════════════════════════════════════════════
  //                     CORE RESOLUTION
  // ═══════════════════════════════════════════════════════════════════

  /// Resolve a conflict between local and remote versions of an entity.
  ///
  /// [localUpdatedAt] — Local modification timestamp (ms since epoch).
  /// [remoteUpdatedAt] — Remote Convex document updatedAt (ms since epoch).
  /// [localHasPendingSync] — Whether the local version has unsynced changes
  ///   in the outbox. If false, remote always wins regardless of timestamp.
  ConflictResult resolve({
    required String entityType,
    required String entityId,
    required int localUpdatedAt,
    required int remoteUpdatedAt,
    bool localHasPendingSync = false,
  }) {
    final delta = localUpdatedAt - remoteUpdatedAt;
    final absDelta = delta.abs();

    ConflictResolution resolution;

    if (!localHasPendingSync) {
      // No local changes pending — remote always wins
      resolution = ConflictResolution.remoteWins;
    } else if (absDelta <= clockSkewToleranceMs) {
      // Within clock skew tolerance — server authority wins
      resolution = ConflictResolution.identical;
      _log.d(
        'Conflict: $entityType/$entityId within clock skew tolerance '
        '(delta=${delta}ms) — server authority wins',
      );
    } else if (delta > 0) {
      // Local is newer
      resolution = ConflictResolution.localWins;
      _log.d(
        'Conflict: $entityType/$entityId LOCAL wins '
        '(local=$localUpdatedAt, remote=$remoteUpdatedAt, delta=${delta}ms)',
      );
    } else {
      // Remote is newer
      resolution = ConflictResolution.remoteWins;
      _log.d(
        'Conflict: $entityType/$entityId REMOTE wins '
        '(local=$localUpdatedAt, remote=$remoteUpdatedAt, delta=${delta}ms)',
      );
    }

    return ConflictResult(
      resolution: resolution,
      entityType: entityType,
      entityId: entityId,
      localTimestamp: localUpdatedAt,
      remoteTimestamp: remoteUpdatedAt,
      deltaMs: delta,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                   BATCH RESOLUTION
  // ═══════════════════════════════════════════════════════════════════

  /// Resolve conflicts for a batch of entities.
  /// Returns separate lists for entities to update locally vs keep local.
  BatchConflictResult resolveBatch({
    required String entityType,
    required List<EntityTimestampPair> pairs,
  }) {
    final updateLocal = <String>[];   // Remote wins — overwrite local
    final keepLocal = <String>[];     // Local wins — push via outbox
    final noAction = <String>[];      // Identical — skip

    for (final pair in pairs) {
      final result = resolve(
        entityType: entityType,
        entityId: pair.entityId,
        localUpdatedAt: pair.localUpdatedAt,
        remoteUpdatedAt: pair.remoteUpdatedAt,
        localHasPendingSync: pair.hasPendingSync,
      );

      switch (result.resolution) {
        case ConflictResolution.remoteWins:
          updateLocal.add(pair.entityId);
          break;
        case ConflictResolution.localWins:
          keepLocal.add(pair.entityId);
          break;
        case ConflictResolution.identical:
          noAction.add(pair.entityId);
          break;
      }
    }

    _log.i(
      'Batch conflict resolution for $entityType: '
      '${updateLocal.length} remote wins, '
      '${keepLocal.length} local wins, '
      '${noAction.length} no action',
    );

    return BatchConflictResult(
      updateLocal: updateLocal,
      keepLocal: keepLocal,
      noAction: noAction,
    );
  }
}

/// Timestamp pair for batch conflict resolution.
class EntityTimestampPair {
  final String entityId;
  final int localUpdatedAt;
  final int remoteUpdatedAt;
  final bool hasPendingSync;

  const EntityTimestampPair({
    required this.entityId,
    required this.localUpdatedAt,
    required this.remoteUpdatedAt,
    this.hasPendingSync = false,
  });
}

/// Result of batch conflict resolution.
class BatchConflictResult {
  /// Entity IDs where remote version should overwrite local.
  final List<String> updateLocal;

  /// Entity IDs where local version should be preserved (pending outbox push).
  final List<String> keepLocal;

  /// Entity IDs where no action is needed.
  final List<String> noAction;

  const BatchConflictResult({
    required this.updateLocal,
    required this.keepLocal,
    required this.noAction,
  });
}
