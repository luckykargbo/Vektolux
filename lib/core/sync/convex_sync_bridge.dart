// lib/core/sync/convex_sync_bridge.dart
// ═══════════════════════════════════════════════════════════════════════
// Convex → Drift Sync Bridge
// Subscribes to Convex query results and upserts incoming records into
// local SQLite (Drift) tables with LWW conflict resolution.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:logger/logger.dart';

import '../database/app_database.dart';
import '../database/daos/cached_entities_dao.dart';
import '../database/tables/cached_entities_table.dart';
import '../network/convex_client_wrapper.dart';
import 'conflict_resolver.dart';

/// Bridges Convex real-time subscriptions to local Drift cache tables.
///
/// For each entity type, it:
/// 1. Subscribes to a Convex query (via polling)
/// 2. Receives updated documents from the server
/// 3. Runs LWW conflict resolution against local versions
/// 4. Upserts winning versions into Drift
/// 5. Drift's .watch() automatically notifies BLoCs/UI
class ConvexSyncBridge {
  final ConvexClientWrapper _convex;
  final CachedPropertiesDao _propertiesDao;
  final CachedRidesDao _ridesDao;
  final CachedWalletsDao _walletsDao;
  final ConflictResolver _conflictResolver;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  /// Active subscription streams (keyed by query path).
  final Map<String, StreamSubscription> _subscriptions = {};

  ConvexSyncBridge({
    required ConvexClientWrapper convex,
    required CachedPropertiesDao propertiesDao,
    required CachedRidesDao ridesDao,
    required CachedWalletsDao walletsDao,
    ConflictResolver? conflictResolver,
  })  : _convex = convex,
        _propertiesDao = propertiesDao,
        _ridesDao = ridesDao,
        _walletsDao = walletsDao,
        _conflictResolver = conflictResolver ?? ConflictResolver();

  // ═══════════════════════════════════════════════════════════════════
  //                   SUBSCRIPTION MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════

  /// Start all entity subscriptions.
  void startAll({required String userId}) {
    _log.i('ConvexSyncBridge: starting all subscriptions for user $userId');

    subscribeToProperties();
    subscribeToActiveRide(userId);
    subscribeToWallet(userId);
    subscribeToTransactions(userId);
  }

  /// Stop all active subscriptions.
  void stopAll() {
    _log.i('ConvexSyncBridge: stopping ${_subscriptions.length} subscriptions');
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  /// Stop a specific subscription by query path.
  void stop(String queryPath) {
    _subscriptions[queryPath]?.cancel();
    _subscriptions.remove(queryPath);
  }

  // ═══════════════════════════════════════════════════════════════════
  //                  PROPERTY SUBSCRIPTIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Subscribe to real estate listings and sync into local cache.
  void subscribeToProperties({
    String? category,
    Duration pollInterval = const Duration(seconds: 10),
  }) {
    const queryPath = 'rides:findNearbyProperties'; // Or a dedicated list query

    _cancelExisting(queryPath);

    final args = <String, dynamic>{
      'lat': 0, // Will be updated with user's location
      'lng': 0,
      'radiusKm': 50,
      if (category != null) 'category': category,
    };

    final subscription = _convex
        .subscribe(queryPath, args: args, interval: pollInterval)
        .listen(
      (data) async {
        try {
          await _ingestProperties(data);
        } catch (e) {
          _log.e('Property sync ingestion error: $e');
        }
      },
      onError: (e) => _log.e('Property subscription error: $e'),
    );

    _subscriptions[queryPath] = subscription;
  }

  /// Ingest remote properties into Drift with LWW conflict resolution.
  Future<void> _ingestProperties(dynamic data) async {
    if (data is! Map || data['listings'] is! List) return;

    final listings = data['listings'] as List;
    if (listings.isEmpty) return;

    _log.d('ConvexSyncBridge: ingesting ${listings.length} properties');

    final propertiesToUpsert = <CachedProperty>[];

    for (final item in listings) {
      if (item is! Map<String, dynamic>) continue;

      final remoteId = item['_id']?.toString() ?? '';
      if (remoteId.isEmpty) continue;

      final remoteUpdatedAt =
          (item['updatedAt'] as num?)?.toInt() ??
          (item['_creationTime'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;

      // Check local version for conflict
      final localVersion = await _propertiesDao.getById(remoteId);

      if (localVersion != null) {
        final hasPending =
            localVersion.syncStatus == EntitySyncStatus.pendingSync;

        final result = _conflictResolver.resolve(
          entityType: 'realEstateListings',
          entityId: remoteId,
          localUpdatedAt: localVersion.localUpdatedAt,
          remoteUpdatedAt: remoteUpdatedAt,
          localHasPendingSync: hasPending,
        );

        if (result.resolution == ConflictResolution.localWins) {
          continue; // Skip — local version is newer and will be pushed
        }
      }

      // Remote wins (or new entry) — upsert
      propertiesToUpsert.add(CachedProperty(
        id: remoteId,
        ownerId: item['ownerId']?.toString() ?? '',
        title: item['title']?.toString() ?? '',
        description: item['description']?.toString() ?? '',
        category: item['category']?.toString() ?? 'sale',
        price: (item['price'] as num?)?.toDouble() ?? 0,
        hourlyRate: (item['hourlyRate'] as num?)?.toDouble(),
        currency: item['currency']?.toString() ?? 'SLE',
        address: item['address']?.toString() ?? '',
        city: item['city']?.toString() ?? '',
        country: item['country']?.toString() ?? '',
        latitude: (item['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (item['longitude'] as num?)?.toDouble() ?? 0,
        geohash: item['geohash']?.toString() ?? '',
        availabilityStatus: item['availabilityStatus']?.toString() ?? 'available',
        imageUrlsJson: jsonEncode(item['imageUrls'] ?? []),
        isFeatured: item['isFeatured'] == true,
        viewCount: (item['viewCount'] as num?)?.toInt() ?? 0,
        syncStatus: EntitySyncStatus.synced,
        localUpdatedAt: remoteUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
        lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }

    if (propertiesToUpsert.isNotEmpty) {
      await _propertiesDao.upsertBatch(propertiesToUpsert);
      _log.d(
        'ConvexSyncBridge: upserted ${propertiesToUpsert.length} properties',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                    RIDE SUBSCRIPTIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Subscribe to the user's active ride (real-time driver tracking).
  void subscribeToActiveRide(
    String userId, {
    Duration pollInterval = const Duration(seconds: 3),
  }) {
    // For active ride, we poll more frequently (every 3s)
    // In production, replace with WebSocket via convex_flutter FFI
    _cancelExisting('activeRide:$userId');

    // First, find the active ride ID
    final subscription = _convex
        .subscribe(
          'rides:getPassengerRideHistory',
          args: {'passengerId': userId, 'limit': 1},
          interval: pollInterval,
        )
        .listen(
      (data) async {
        try {
          await _ingestRide(data);
        } catch (e) {
          _log.e('Ride sync ingestion error: $e');
        }
      },
      onError: (e) => _log.e('Ride subscription error: $e'),
    );

    _subscriptions['activeRide:$userId'] = subscription;
  }

  /// Ingest remote ride data into Drift with LWW conflict resolution.
  Future<void> _ingestRide(dynamic data) async {
    if (data == null) return;

    // Handle both single ride and list of rides
    final rides = data is List ? data : [data];

    for (final item in rides) {
      if (item is! Map<String, dynamic>) continue;

      final remoteId = item['_id']?.toString() ?? '';
      if (remoteId.isEmpty) continue;

      final remoteUpdatedAt =
          (item['updatedAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;

      // Check local version for conflict
      final localVersion = await _ridesDao.getById(remoteId);

      if (localVersion != null) {
        final hasPending =
            localVersion.syncStatus == EntitySyncStatus.pendingSync;

        final result = _conflictResolver.resolve(
          entityType: 'rideRequests',
          entityId: remoteId,
          localUpdatedAt: localVersion.localUpdatedAt,
          remoteUpdatedAt: remoteUpdatedAt,
          localHasPendingSync: hasPending,
        );

        if (result.resolution == ConflictResolution.localWins) {
          continue; // Local is newer
        }
      }

      await _ridesDao.upsert(CachedRide(
        id: remoteId,
        passengerId: item['passengerId']?.toString() ?? '',
        driverId: item['driverId']?.toString(),
        vehicleId: item['vehicleId']?.toString(),
        pickupLat: (item['pickupLat'] as num?)?.toDouble() ?? 0,
        pickupLng: (item['pickupLng'] as num?)?.toDouble() ?? 0,
        pickupAddress: item['pickupAddress']?.toString(),
        dropoffLat: (item['dropoffLat'] as num?)?.toDouble() ?? 0,
        dropoffLng: (item['dropoffLng'] as num?)?.toDouble() ?? 0,
        dropoffAddress: item['dropoffAddress']?.toString(),
        distanceKm: (item['distanceKm'] as num?)?.toDouble() ?? 0,
        estimatedDurationMin: (item['estimatedDurationMin'] as num?)?.toInt() ?? 0,
        fareAmount: (item['fareAmount'] as num?)?.toDouble() ?? 0,
        currency: item['currency']?.toString() ?? 'SLE',
        platformFee: (item['platformFee'] as num?)?.toDouble() ?? 0,
        driverPayout: (item['driverPayout'] as num?)?.toDouble() ?? 0,
        status: item['status']?.toString() ?? 'requested',
        paymentStatus: item['paymentStatus']?.toString() ?? 'pending',
        paymentReference: item['paymentReference']?.toString(),
        blockchainLogHash: item['blockchainLogHash']?.toString(),
        acceptedAt: (item['acceptedAt'] as num?)?.toInt(),
        startedAt: (item['startedAt'] as num?)?.toInt(),
        completedAt: (item['completedAt'] as num?)?.toInt(),
        cancelledAt: (item['cancelledAt'] as num?)?.toInt(),
        cancelReason: item['cancelReason']?.toString(),
        syncStatus: EntitySyncStatus.synced,
        localUpdatedAt: remoteUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
        lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                   WALLET SUBSCRIPTIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Subscribe to wallet balance updates.
  void subscribeToWallet(
    String userId, {
    Duration pollInterval = const Duration(seconds: 15),
  }) {
    const queryPath = 'payments:getWalletBalance';

    _cancelExisting('wallet:$userId');

    final subscription = _convex
        .subscribe(queryPath, args: {'userId': userId}, interval: pollInterval)
        .listen(
      (data) async {
        try {
          if (data is Map<String, dynamic> && data['exists'] == true) {
            await _walletsDao.upsertWallet(CachedWallet(
              id: data['walletId']?.toString() ?? userId,
              userId: userId,
              availableBalance:
                  (data['availableBalance'] as num?)?.toDouble() ?? 0,
              pendingBalance:
                  (data['pendingBalance'] as num?)?.toDouble() ?? 0,
              currency: data['currency']?.toString() ?? 'SLE',
              localUpdatedAt: DateTime.now().millisecondsSinceEpoch,
              remoteUpdatedAt:
                  (data['updatedAt'] as num?)?.toInt() ??
                  DateTime.now().millisecondsSinceEpoch,
              lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
            ));
          }
        } catch (e) {
          _log.e('Wallet sync ingestion error: $e');
        }
      },
      onError: (e) => _log.e('Wallet subscription error: $e'),
    );

    _subscriptions['wallet:$userId'] = subscription;
  }

  /// Subscribe to transaction history updates.
  void subscribeToTransactions(
    String userId, {
    Duration pollInterval = const Duration(seconds: 30),
  }) {
    const queryPath = 'payments:getTransactionHistory';

    _cancelExisting('transactions:$userId');

    final subscription = _convex
        .subscribe(queryPath, args: {'userId': userId, 'limit': 50},
            interval: pollInterval)
        .listen(
      (data) async {
        try {
          if (data is Map && data['transactions'] is List) {
            final txns = (data['transactions'] as List)
                .whereType<Map<String, dynamic>>()
                .map<CachedTransaction>((t) => CachedTransaction(
                      id: t['_id']?.toString() ?? '',
                      walletId: t['walletId']?.toString() ?? '',
                      userId: t['userId']?.toString() ?? '',
                      type: t['type']?.toString() ?? '',
                      amount: (t['amount'] as num?)?.toDouble() ?? 0,
                      currency: t['currency']?.toString() ?? 'SLE',
                      referenceType: t['referenceType']?.toString(),
                      referenceId: t['referenceId']?.toString(),
                      status: t['status']?.toString() ?? 'completed',
                      description: t['description']?.toString(),
                      blockchainTxHash: t['blockchainTxHash']?.toString(),
                      remoteCreatedAt:
                          (t['_creationTime'] as num?)?.toInt() ??
                          DateTime.now().millisecondsSinceEpoch,
                    ))
                .where((t) => t.id.isNotEmpty)
                .toList();

            if (txns.isNotEmpty) {
              await _walletsDao.upsertTransactions(txns);
            }
          }
        } catch (e) {
          _log.e('Transactions sync ingestion error: $e');
        }
      },
      onError: (e) => _log.e('Transactions subscription error: $e'),
    );

    _subscriptions['transactions:$userId'] = subscription;
  }

  // ═══════════════════════════════════════════════════════════════════
  //                       HELPERS
  // ═══════════════════════════════════════════════════════════════════

  void _cancelExisting(String key) {
    _subscriptions[key]?.cancel();
    _subscriptions.remove(key);
  }
}
