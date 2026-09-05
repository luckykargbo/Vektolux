// lib/core/database/tables/sync_queue_table.dart
// ═══════════════════════════════════════════════════════════════════════
// Transactional Outbox Queue Table — Drift Definition
// Stores pending mutations that need to be pushed to Convex backend.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';

/// Status of a sync queue entry.
enum SyncStatus {
  pending,  // Queued, awaiting network
  syncing,  // Currently being transmitted
  synced,   // Successfully pushed to Convex
  failed,   // Failed after max retries
  conflict, // Conflict detected, needs resolution
}

/// Type of mutation operation.
enum OperationType {
  create,
  update,
  delete,
}

/// The sync_queue outbox table. Every local write that needs to reach
/// Convex creates a row here inside the same atomic Drift transaction.
@DataClassName('SyncQueueEntry')
class SyncQueueTable extends Table {
  /// UUIDv4 primary key, generated client-side.
  TextColumn get id => text()();

  /// Idempotency key to prevent duplicate execution on Convex.
  TextColumn get idempotencyKey => text().unique()();

  /// The Convex mutation path to invoke (e.g., "rides:requestRide").
  TextColumn get mutationPath => text()();

  /// The type of operation: create, update, or delete.
  TextColumn get operationType => textEnum<OperationType>()();

  /// Target entity type (e.g., "rideRequests", "realEstateBookings").
  TextColumn get entityType => text()();

  /// Client-generated ID of the entity being mutated.
  TextColumn get entityId => text()();

  /// JSON-serialized mutation arguments (the full payload).
  TextColumn get payloadJson => text()();

  /// Current sync status.
  TextColumn get status => textEnum<SyncStatus>()
      .withDefault(Constant(SyncStatus.pending.name))();

  /// Number of times sync has been attempted.
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Maximum allowed retries before marking as failed.
  IntColumn get maxRetries => integer().withDefault(const Constant(5))();

  /// Timestamp when the entry was created (milliseconds since epoch).
  IntColumn get createdAt => integer()();

  /// Timestamp of the last sync attempt.
  IntColumn get lastAttemptAt => integer().nullable()();

  /// Error message from the last failed attempt.
  TextColumn get errorMessage => text().nullable()();

  /// Priority: lower number = higher priority (rides > property inquiries).
  IntColumn get priority => integer().withDefault(const Constant(5))();

  @override
  Set<Column> get primaryKey => {id};
}
