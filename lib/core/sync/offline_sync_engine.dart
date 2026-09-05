// lib/core/sync/offline_sync_engine.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Offline-First Sync Engine (Master Orchestrator)
//
// Coordinates all sync components:
//   1. ConnectivityMonitor  → detects online/offline transitions
//   2. SyncQueueProcessor   → pushes outbox mutations to Convex
//   3. ConvexSyncBridge     → pulls Convex subscriptions into Drift
//   4. ConflictResolver     → LWW resolution on collisions
//
// Lifecycle:
//   initialize() → start() → [automatic sync] → stop() → dispose()
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/daos/sync_queue_dao.dart';
import '../database/daos/cached_entities_dao.dart';
import '../database/tables/sync_queue_table.dart';
import '../network/connectivity_monitor.dart';
import '../network/convex_client_wrapper.dart';
import 'sync_queue_processor.dart';
import 'convex_sync_bridge.dart';
import 'conflict_resolver.dart';

/// Current state of the sync engine.
enum SyncEngineState {
  idle,           // Not started
  syncing,        // Actively pushing/pulling
  listening,      // Online, subscriptions active, outbox empty
  offline,        // No connectivity, operating locally
  error,          // Fatal error state
  disposed,       // Engine has been disposed
}

/// Emitted when the sync engine state changes.
class SyncEngineStatus {
  final SyncEngineState state;
  final int pendingCount;
  final int failedCount;
  final DateTime lastSyncAt;
  final String? errorMessage;

  const SyncEngineStatus({
    required this.state,
    this.pendingCount = 0,
    this.failedCount = 0,
    required this.lastSyncAt,
    this.errorMessage,
  });
}

/// Master orchestrator for the offline-first sync system.
///
/// Usage in main.dart or DI container:
/// ```dart
/// final syncEngine = OfflineSyncEngine(
///   database: appDatabase,
///   convexClient: convexClient,
///   connectivityMonitor: connectivityMonitor,
/// );
/// await syncEngine.initialize();
/// syncEngine.start(userId: currentUser.id);
/// ```
class OfflineSyncEngine {
  final AppDatabase _database;
  final ConvexClientWrapper _convexClient;
  final ConnectivityMonitor _connectivityMonitor;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final Uuid _uuid = const Uuid();

  // ── Internal components ─────────────────────────────────────────
  late final SyncQueueDao _syncQueueDao;
  late final CachedPropertiesDao _propertiesDao;
  late final CachedRidesDao _ridesDao;
  late final CachedWalletsDao _walletsDao;
  late final SyncQueueProcessor _queueProcessor;
  late final ConvexSyncBridge _syncBridge;
  late final ConflictResolver _conflictResolver;

  // ── State ───────────────────────────────────────────────────────
  SyncEngineState _state = SyncEngineState.idle;
  String? _currentUserId;
  Timer? _periodicSyncTimer;
  StreamSubscription? _reconnectSubscription;
  StreamSubscription? _queueWatchSubscription;

  // ── Status stream ───────────────────────────────────────────────
  final StreamController<SyncEngineStatus> _statusController =
      StreamController<SyncEngineStatus>.broadcast();

  DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);

  OfflineSyncEngine({
    required AppDatabase database,
    required ConvexClientWrapper convexClient,
    required ConnectivityMonitor connectivityMonitor,
  })  : _database = database,
        _convexClient = convexClient,
        _connectivityMonitor = connectivityMonitor;

  // ═══════════════════════════════════════════════════════════════════
  //                       PUBLIC API
  // ═══════════════════════════════════════════════════════════════════

  /// Current engine state.
  SyncEngineState get state => _state;

  /// Reactive stream of engine status updates.
  Stream<SyncEngineStatus> get statusStream => _statusController.stream;

  /// Whether the engine is currently syncing.
  bool get isSyncing => _state == SyncEngineState.syncing;

  // ═══════════════════════════════════════════════════════════════════
  //                     LIFECYCLE: INITIALIZE
  // ═══════════════════════════════════════════════════════════════════

  /// Initialize all internal components. Call once at app startup.
  Future<void> initialize() async {
    _log.i('OfflineSyncEngine: initializing...');

    // Initialize DAOs
    _syncQueueDao = _database.syncQueueDao;
    _propertiesDao = _database.cachedPropertiesDao;
    _ridesDao = _database.cachedRidesDao;
    _walletsDao = _database.cachedWalletsDao;

    // Initialize conflict resolver
    _conflictResolver = ConflictResolver(clockSkewToleranceMs: 1000);

    // Initialize queue processor
    _queueProcessor = SyncQueueProcessor(
      syncQueueDao: _syncQueueDao,
      convexClient: _convexClient,
      onEntitySynced: _onEntitySynced,
    );

    // Initialize sync bridge
    _syncBridge = ConvexSyncBridge(
      convex: _convexClient,
      propertiesDao: _propertiesDao,
      ridesDao: _ridesDao,
      walletsDao: _walletsDao,
      conflictResolver: _conflictResolver,
    );

    // Initialize connectivity monitor
    await _connectivityMonitor.initialize();

    // Reset any entries stuck in "syncing" state from a previous crash
    final resetCount = await _syncQueueDao.resetStuckEntries();
    if (resetCount > 0) {
      _log.w('OfflineSyncEngine: reset $resetCount stuck entries');
    }

    _log.i('OfflineSyncEngine: initialized successfully');
  }

  // ═══════════════════════════════════════════════════════════════════
  //                      LIFECYCLE: START
  // ═══════════════════════════════════════════════════════════════════

  /// Start the sync engine for a specific user.
  /// Sets up connectivity listeners, periodic sync, and subscriptions.
  void start({required String userId}) {
    if (_state == SyncEngineState.disposed) {
      _log.e('OfflineSyncEngine: cannot start — already disposed');
      return;
    }

    _currentUserId = userId;
    _log.i('OfflineSyncEngine: starting for user $userId');

    // ── 1. Listen for network reconnection ────────────────────────
    _reconnectSubscription?.cancel();
    _reconnectSubscription = _connectivityMonitor.onReconnected.listen((_) {
      _log.i('OfflineSyncEngine: network reconnected — triggering sync');
      _onReconnected();
    });

    // ── 2. Watch outbox queue for new entries ─────────────────────
    _queueWatchSubscription?.cancel();
    _queueWatchSubscription =
        _syncQueueDao.watchPendingEntries().listen((entries) {
      if (entries.isNotEmpty && _connectivityMonitor.isOnline) {
        // New outbox entries detected while online — sync immediately
        triggerSync();
      }
    });

    // ── 3. Start periodic sync (every 30s while online) ──────────
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_connectivityMonitor.isOnline) {
          triggerSync();
        }
      },
    );

    // ── 4. Start Convex subscriptions if online ──────────────────
    if (_connectivityMonitor.isOnline) {
      _syncBridge.startAll(userId: userId);
      _updateState(SyncEngineState.listening);
      // Immediate sync on start
      triggerSync();
    } else {
      _updateState(SyncEngineState.offline);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     LIFECYCLE: STOP
  // ═══════════════════════════════════════════════════════════════════

  /// Stop the sync engine. Call on logout or app background.
  void stop() {
    _log.i('OfflineSyncEngine: stopping');

    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;

    _reconnectSubscription?.cancel();
    _reconnectSubscription = null;

    _queueWatchSubscription?.cancel();
    _queueWatchSubscription = null;

    _syncBridge.stopAll();

    _updateState(SyncEngineState.idle);
    _currentUserId = null;
  }

  /// Dispose all resources. Call on app termination.
  void dispose() {
    stop();
    _statusController.close();
    _connectivityMonitor.dispose();
    _state = SyncEngineState.disposed;
  }

  // ═══════════════════════════════════════════════════════════════════
  //                    LOCAL WRITE + QUEUE
  // ═══════════════════════════════════════════════════════════════════

  /// Execute a local write and enqueue for sync — the core offline-first pattern.
  ///
  /// This method:
  /// 1. Writes to the local Drift entity table (immediate UI update)
  /// 2. Enqueues a sync_queue entry for Convex mutation (background push)
  /// Both writes happen in a single atomic Drift transaction.
  ///
  /// Example — requesting a ride offline:
  /// ```dart
  /// await syncEngine.writeAndQueue(
  ///   entityType: 'rideRequests',
  ///   entityId: clientRideId,
  ///   mutationPath: 'rides:requestRide',
  ///   payload: {'pickupLat': 8.484, 'pickupLng': -13.229, ...},
  ///   localWrite: () async {
  ///     await ridesDao.upsert(localRideRecord);
  ///   },
  ///   priority: 1, // Rides are high priority
  /// );
  /// ```
  Future<String> writeAndQueue({
    required String entityType,
    required String entityId,
    required String mutationPath,
    required Map<String, dynamic> payload,
    required Future<void> Function() localWrite,
    OperationType operationType = OperationType.create,
    int priority = 5,
    int maxRetries = 5,
  }) async {
    final queueEntryId = _uuid.v4();
    final idempotencyKey = '${entityType}_${entityId}_${DateTime.now().millisecondsSinceEpoch}';

    // ── Atomic transaction: entity write + outbox enqueue ──────────
    await _database.transaction(() async {
      // 1. Execute the local entity write (instant UI update via .watch())
      await localWrite();

      // 2. Enqueue the sync entry
      await _syncQueueDao.enqueueRaw(
        id: queueEntryId,
        idempotencyKey: idempotencyKey,
        mutationPath: mutationPath,
        operationType: operationType,
        entityType: entityType,
        entityId: entityId,
        payloadJson: _safeJsonEncode(payload),
        priority: priority,
        maxRetries: maxRetries,
      );
    });

    _log.d(
      'OfflineSyncEngine: queued $operationType for '
      '$entityType/$entityId → $mutationPath',
    );

    // ── Trigger sync if online ────────────────────────────────────
    if (_connectivityMonitor.isOnline) {
      // Don't await — fire and forget for non-blocking UI
      triggerSync();
    }

    return queueEntryId;
  }

  /// Convenience: write-and-queue for a ride request.
  Future<String> queueRideRequest({
    required String rideId,
    required Map<String, dynamic> payload,
    required Future<void> Function() localWrite,
  }) {
    return writeAndQueue(
      entityType: 'rideRequests',
      entityId: rideId,
      mutationPath: 'rides:requestRide',
      payload: payload,
      localWrite: localWrite,
      priority: 1, // High priority
    );
  }

  /// Convenience: write-and-queue for a property booking.
  Future<String> queuePropertyBooking({
    required String bookingId,
    required Map<String, dynamic> payload,
    required Future<void> Function() localWrite,
  }) {
    return writeAndQueue(
      entityType: 'realEstateBookings',
      entityId: bookingId,
      mutationPath: 'realEstateBookings:createBooking',
      payload: payload,
      localWrite: localWrite,
      priority: 3,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     MANUAL SYNC TRIGGER
  // ═══════════════════════════════════════════════════════════════════

  /// Manually trigger a sync cycle. Safe to call multiple times —
  /// concurrent calls are deduplicated by the processor.
  Future<void> triggerSync() async {
    if (!_connectivityMonitor.isOnline) {
      _log.d('OfflineSyncEngine: cannot sync — offline');
      return;
    }

    if (_queueProcessor.isProcessing) {
      _log.d('OfflineSyncEngine: sync already in progress');
      return;
    }

    _updateState(SyncEngineState.syncing);

    try {
      final result = await _queueProcessor.processQueue();
      _lastSyncAt = DateTime.now();

      _log.i('OfflineSyncEngine: sync complete — $result');

      // Update state based on result
      final pendingCount = await _syncQueueDao.getPendingCount();
      if (pendingCount > 0) {
        _emitStatus(pendingCount: pendingCount);
      }

      _updateState(SyncEngineState.listening);
    } catch (e) {
      _log.e('OfflineSyncEngine: sync error — $e');
      _updateState(SyncEngineState.error);
      _emitStatus(errorMessage: e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                      STATUS QUERIES
  // ═══════════════════════════════════════════════════════════════════

  /// Get the current number of pending sync entries.
  Future<int> getPendingCount() => _syncQueueDao.getPendingCount();

  /// Watch the pending count as a reactive stream (for UI badges).
  Stream<int> watchPendingCount() => _syncQueueDao.watchPendingCount();

  /// Get all failed sync entries for manual retry or inspection.
  Future<List<SyncQueueEntry>> getFailedEntries() =>
      _syncQueueDao.getFailedEntries();

  /// Retry a specific failed entry.
  Future<void> retryFailedEntry(String entryId) async {
    await _syncQueueDao.retryFailed(entryId);
    if (_connectivityMonitor.isOnline) {
      triggerSync();
    }
  }

  /// Retry all failed entries.
  Future<void> retryAllFailed() async {
    final failed = await _syncQueueDao.getFailedEntries();
    for (final entry in failed) {
      await _syncQueueDao.retryFailed(entry.id);
    }
    if (_connectivityMonitor.isOnline) {
      triggerSync();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                    INTERNAL HANDLERS
  // ═══════════════════════════════════════════════════════════════════

  /// Called when the device reconnects to the network.
  void _onReconnected() {
    // Start subscriptions
    if (_currentUserId != null) {
      _syncBridge.startAll(userId: _currentUserId!);
    }

    // Flush the outbox
    triggerSync();
  }

  /// Called when a sync queue entry is successfully pushed to Convex.
  /// Updates the local entity's sync status.
  Future<void> _onEntitySynced(String entityType, String entityId) async {
    switch (entityType) {
      case 'realEstateListings':
        await _propertiesDao.markSynced(entityId);
        break;
      case 'rideRequests':
        await _ridesDao.markSynced(entityId);
        break;
      // Add other entity types as needed
    }
  }

  void _updateState(SyncEngineState newState) {
    if (_state != newState) {
      _state = newState;
      _emitStatus();
    }
  }

  void _emitStatus({
    int? pendingCount,
    int? failedCount,
    String? errorMessage,
  }) {
    if (_statusController.isClosed) return;

    _statusController.add(SyncEngineStatus(
      state: _state,
      pendingCount: pendingCount ?? 0,
      failedCount: failedCount ?? 0,
      lastSyncAt: _lastSyncAt,
      errorMessage: errorMessage,
    ));
  }

  String _safeJsonEncode(Map<String, dynamic> data) {
    try {
      return jsonEncode(data);
    } catch (e) {
      _log.e('JSON encode error: $e');
      return '{}';
    }
  }
}
