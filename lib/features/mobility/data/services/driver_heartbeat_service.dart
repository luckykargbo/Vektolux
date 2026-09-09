// lib/features/mobility/data/services/driver_heartbeat_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Location Heartbeat & Background Service
// Periodically updates driver coordinates in Convex Cloud and local Drift SQLite
// every 5-10 seconds while the driver is toggled online.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/database/daos/cached_driver_profiles_dao.dart';

class DriverHeartbeatService {
  final ConvexClientWrapper _convexClient;
  final CachedDriverProfilesDao _driverDao;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Timer? _heartbeatTimer;
  StreamSubscription<Position>? _positionStreamSub;
  bool _isOnline = false;
  String? _activeDriverProfileId;
  double _currentLat = 8.484;
  double _currentLng = -13.229;
  double _currentHeading = 0.0;
  double _currentSpeed = 0.0;
  final Random _random = Random();

  /// Optional listener for live GPS updates inside BLoCs / views.
  void Function(double lat, double lng, double heading, double speed)? onLocationUpdated;

  DriverHeartbeatService({
    required ConvexClientWrapper convexClient,
    required CachedDriverProfilesDao driverDao,
  })  : _convexClient = convexClient,
        _driverDao = driverDao;

  bool get isOnline => _isOnline;
  String? get activeDriverProfileId => _activeDriverProfileId;
  double get currentLat => _currentLat;
  double get currentLng => _currentLng;
  double get currentHeading => _currentHeading;
  double get currentSpeed => _currentSpeed;

  /// Start background heartbeat loop and GPS stream (3-5 second interval).
  void startHeartbeat({
    required String driverProfileId,
    required double initialLat,
    required double initialLng,
    Duration interval = const Duration(seconds: 4),
  }) {
    stopHeartbeat();

    _isOnline = true;
    _activeDriverProfileId = driverProfileId;
    _currentLat = initialLat;
    _currentLng = initialLng;

    _log.i('Starting driver live GPS telemetry heartbeat for $driverProfileId');

    // 1. Subscribe to real device GPS position stream
    try {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // Update on 3 meters movement
      );
      _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (Position pos) {
          _currentLat = pos.latitude;
          _currentLng = pos.longitude;
          if (pos.heading >= 0) _currentHeading = pos.heading;
          if (pos.speed >= 0) _currentSpeed = pos.speed;
          onLocationUpdated?.call(_currentLat, _currentLng, _currentHeading, _currentSpeed);
          _sendLocationHeartbeat();
        },
        onError: (e) {
          _log.w('Geolocator stream error (falling back to timer): $e');
        },
      );
    } catch (e) {
      _log.w('Could not initialize GPS stream: $e');
    }

    // 2. Initial immediate ping
    _sendLocationHeartbeat();

    // 3. Periodic fallback timer (guarantees ping every 4s even if stationary)
    _heartbeatTimer = Timer.periodic(interval, (_) {
      if (!_isOnline || _activeDriverProfileId == null) {
        stopHeartbeat();
        return;
      }
      _sendLocationHeartbeat();
    });
  }

  /// Update driver's live GPS coordinates when on the move.
  void updateCoordinates(double lat, double lng, {double? heading, double? speed}) {
    _currentLat = lat;
    _currentLng = lng;
    if (heading != null) _currentHeading = heading;
    if (speed != null) _currentSpeed = speed;
    onLocationUpdated?.call(_currentLat, _currentLng, _currentHeading, _currentSpeed);
  }

  /// Stop heartbeat when driver goes offline.
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
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

    // Subtle micro-movement simulation fallback if vehicle is simulated on emulator
    if (_currentSpeed == 0 && _positionStreamSub == null) {
      final latDelta = (_random.nextDouble() - 0.5) * 0.00012;
      final lngDelta = (_random.nextDouble() - 0.5) * 0.00012;
      _currentLat += latDelta;
      _currentLng += lngDelta;
    }

    try {
      // 1. Send update with heading & speed telemetry to Convex Cloud backend
      await _convexClient.mutation(
        'mobility:updateDriverLocation',
        args: {
          'driverProfileId': _activeDriverProfileId!,
          'lat': _currentLat,
          'lng': _currentLng,
          'heading': _currentHeading,
          'speed': _currentSpeed,
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
