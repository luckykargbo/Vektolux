// lib/features/mobility/data/services/driver_heartbeat_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Location Heartbeat & Background Service
// Periodically updates driver coordinates in Convex Cloud and local Drift SQLite
// every 5-10 seconds while the driver is toggled online.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math';
import 'package:logger/logger.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/database/daos/cached_driver_profiles_dao.dart';

class DriverHeartbeatService {
  final ConvexClientWrapper _convexClient;
  final CachedDriverProfilesDao _driverDao;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Timer? _heartbeatTimer;
  bool _isOnline = false;
  String? _activeDriverProfileId;
  double _currentLat = 8.484;
  double _currentLng = -13.229;
  final Random _random = Random();

  DriverHeartbeatService({
    required ConvexClientWrapper convexClient,
    required CachedDriverProfilesDao driverDao,
  })  : _convexClient = convexClient,
        _driverDao = driverDao;

  bool get isOnline => _isOnline;
  String? get activeDriverProfileId => _activeDriverProfileId;
  double get currentLat => _currentLat;
  double get currentLng => _currentLng;

  /// Start background heartbeat loop (every 7 seconds).
  void startHeartbeat({
    required String driverProfileId,
    required double initialLat,
    required double initialLng,
    Duration interval = const Duration(seconds: 7),
  }) {
    stopHeartbeat();

    _isOnline = true;
    _activeDriverProfileId = driverProfileId;
    _currentLat = initialLat;
    _currentLng = initialLng;

    _log.i('Starting driver location heartbeat for $driverProfileId');

    // 1. Initial immediate ping
    _sendLocationHeartbeat();

    // 2. Scheduled periodic heartbeat
    _heartbeatTimer = Timer.periodic(interval, (_) {
      if (!_isOnline || _activeDriverProfileId == null) {
        stopHeartbeat();
        return;
      }
      _sendLocationHeartbeat();
    });
  }

  /// Update driver's live GPS coordinates when on the move.
  void updateCoordinates(double lat, double lng) {
    _currentLat = lat;
    _currentLng = lng;
  }

  /// Stop heartbeat when driver goes offline.
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isOnline = false;

    if (_activeDriverProfileId != null) {
      final profileId = _activeDriverProfileId!;
      _convexClient
          .mutation(
            'mobility:setDriverOnlineStatus',
            args: {
              'driverProfileId': profileId,
              'isOnline': false,
              'isAvailable': false,
            },
          )
          .ignore();

      _driverDao
          .updateDriverStatus(
            driverId: profileId,
            isOnline: false,
            isAvailable: false,
          )
          .ignore();
    }

    _log.i('Driver location heartbeat stopped');
  }

  /// Execute a single location ping to Convex & SQLite.
  Future<void> _sendLocationHeartbeat() async {
    if (_activeDriverProfileId == null) return;

    // Simulate subtle micro-movement if vehicle is in motion (±0.00015 ≈ 15 meters)
    final latDelta = (_random.nextDouble() - 0.5) * 0.00015;
    final lngDelta = (_random.nextDouble() - 0.5) * 0.00015;
    _currentLat += latDelta;
    _currentLng += lngDelta;

    try {
      // 1. Send update to Convex Cloud backend
      await _convexClient.mutation(
        'mobility:updateDriverLocation',
        args: {
          'driverProfileId': _activeDriverProfileId!,
          'lat': _currentLat,
          'lng': _currentLng,
        },
      );

      // 2. Persist to local Drift SQLite cache
      await _driverDao.updateDriverLocation(
        driverId: _activeDriverProfileId!,
        lat: _currentLat,
        lng: _currentLng,
        geohash: '', // Handled by server or query
      );
    } catch (e) {
      _log.w('Driver heartbeat ping failed: $e');
    }
  }

  void dispose() {
    stopHeartbeat();
  }
}
