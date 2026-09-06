// lib/features/mobility/data/services/location_manager.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Client-Side Location & Geofencing Manager
// Handles GPS permissions, navigator queries, VPN IP-mismatch fallbacks,
// Sierra Leone landmark auto-suggest, and interactive pin placement.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:math';
import 'package:equatable/equatable.dart';
import 'package:logger/logger.dart';
import 'platform_location.dart';

/// Geolocation permission lifecycle states.
enum LocationPermissionState {
  granted,
  prompt,
  denied,
  unsupported,
}

/// A verified local landmark or hub in Sierra Leone for instant auto-suggest.
class LocationLandmark extends Equatable {
  final String name;
  final String neighborhood;
  final double latitude;
  final double longitude;
  final String category;

  const LocationLandmark({
    required this.name,
    required this.neighborhood,
    required this.latitude,
    required this.longitude,
    required this.category,
  });

  String get fullAddress => '$name, $neighborhood, Freetown';

  @override
  List<Object?> get props => [name, neighborhood, latitude, longitude, category];
}

/// Resolved client location package with VPN detection metadata.
class UserLocationResult extends Equatable {
  final double latitude;
  final double longitude;
  final String addressText;
  final bool isGpsActive;
  final bool isVpnMismatch;
  final LocationPermissionState permissionState;
  final LocationLandmark? matchedLandmark;

  const UserLocationResult({
    required this.latitude,
    required this.longitude,
    required this.addressText,
    required this.isGpsActive,
    required this.isVpnMismatch,
    required this.permissionState,
    this.matchedLandmark,
  });

  @override
  List<Object?> get props => [
        latitude,
        longitude,
        addressText,
        isGpsActive,
        isVpnMismatch,
        permissionState,
        matchedLandmark,
      ];
}

class LocationManager {
  static final LocationManager _instance = LocationManager._internal();
  factory LocationManager() => _instance;
  LocationManager._internal();

  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  // Default Freetown Central coordinates
  static const double defaultLat = 8.4844;
  static const double defaultLng = -13.2344;
  static const String defaultAddress = 'Central Freetown, Siaka Stevens St';

  // ─── Sierra Leone Geofence Bounding Box ─────────────────────────────
  // West coast to east border, south coast to north border
  static const double slMinLat = 6.85;
  static const double slMaxLat = 10.15;
  static const double slMinLng = -13.45;
  static const double slMaxLng = -10.20;

  // ─── Curated Sierra Leone Landmark Database ─────────────────────────
  static const List<LocationLandmark> sierraLeoneLandmarks = [
    LocationLandmark(
      name: 'Lumley Beach Road',
      neighborhood: 'Aberdeen Peninsula',
      latitude: 8.4728,
      longitude: -13.2798,
      category: 'Beach & Tourism',
    ),
    LocationLandmark(
      name: 'Aberdeen Cape Club & Helipad',
      neighborhood: 'Aberdeen',
      latitude: 8.4985,
      longitude: -13.2915,
      category: 'Waterfront',
    ),
    LocationLandmark(
      name: 'Cotton Tree & National Museum',
      neighborhood: 'Central Freetown',
      latitude: 8.4844,
      longitude: -13.2344,
      category: 'Historic Landmark',
    ),
    LocationLandmark(
      name: 'Wilberforce Village & Barracks',
      neighborhood: 'Wilberforce',
      latitude: 8.4682,
      longitude: -13.2530,
      category: 'Residential & Military',
    ),
    LocationLandmark(
      name: 'Hill Station Government Complex',
      neighborhood: 'Hill Station',
      latitude: 8.4485,
      longitude: -13.2390,
      category: 'Commercial & Government',
    ),
    LocationLandmark(
      name: 'Brookfields Stadium',
      neighborhood: 'Brookfields',
      latitude: 8.4750,
      longitude: -13.2435,
      category: 'Sports & Entertainment',
    ),
    LocationLandmark(
      name: 'Congo Cross Junction',
      neighborhood: 'Congo Cross',
      latitude: 8.4795,
      longitude: -13.2625,
      category: 'Major Transit Hub',
    ),
    LocationLandmark(
      name: 'Goderich Beach & Atlantic Hub',
      neighborhood: 'Goderich',
      latitude: 8.4310,
      longitude: -13.2840,
      category: 'Coastal Residential',
    ),
    LocationLandmark(
      name: 'Juba Hill Junction',
      neighborhood: 'Juba',
      latitude: 8.4480,
      longitude: -13.2780,
      category: 'Residential',
    ),
    LocationLandmark(
      name: 'Fourah Bay College (FBC)',
      neighborhood: 'Mount Aureol',
      latitude: 8.4785,
      longitude: -13.2215,
      category: 'University Campus',
    ),
    LocationLandmark(
      name: 'Kissy Shell / Old Ferry',
      neighborhood: 'Kissy',
      latitude: 8.4780,
      longitude: -13.2010,
      category: 'Transit Hub',
    ),
    LocationLandmark(
      name: 'Government Wharf (Lungi Ferry)',
      neighborhood: 'Cline Town',
      latitude: 8.4910,
      longitude: -13.2180,
      category: 'Maritime Transit',
    ),
    LocationLandmark(
      name: 'Lungi International Airport',
      neighborhood: 'Lungi Port Loko',
      latitude: 8.6160,
      longitude: -13.1950,
      category: 'Airport Hub',
    ),
    LocationLandmark(
      name: 'Waterloo Central Station',
      neighborhood: 'Waterloo',
      latitude: 8.3380,
      longitude: -13.0720,
      category: 'Suburban Hub',
    ),
    LocationLandmark(
      name: 'Bo Clock Tower & Central Market',
      neighborhood: 'Bo Central',
      latitude: 7.9644,
      longitude: -11.7383,
      category: 'Provincial Commercial Hub (Southern Province)',
    ),
    LocationLandmark(
      name: 'Kenema Government Hospital & Hub',
      neighborhood: 'Kenema Town',
      latitude: 7.8767,
      longitude: -11.1875,
      category: 'Provincial Commercial Hub (Eastern Province)',
    ),
    LocationLandmark(
      name: 'Makeni Central Clock Tower',
      neighborhood: 'Makeni',
      latitude: 8.8833,
      longitude: -12.0500,
      category: 'Provincial Commercial Hub (Northern Province)',
    ),
    LocationLandmark(
      name: 'Koidu City Mining Hub',
      neighborhood: 'Koidu Kono',
      latitude: 8.6439,
      longitude: -10.9717,
      category: 'Mining & Commercial Hub',
    ),
    LocationLandmark(
      name: 'Port Loko Central Market',
      neighborhood: 'Port Loko',
      latitude: 8.7667,
      longitude: -12.7833,
      category: 'North West Province Hub',
    ),
  ];

  /// Check whether coordinates are inside Sierra Leone territory.
  bool isInsideSierraLeone(double lat, double lng) {
    return lat >= slMinLat && lat <= slMaxLat && lng >= slMinLng && lng <= slMaxLng;
  }

  /// Query navigator.permissions.query({ name: 'geolocation' })
  Future<LocationPermissionState> queryPermissionState() async {
    try {
      final stateStr = await PlatformLocationDelegate.queryPermissionState();
      return switch (stateStr.toLowerCase()) {
        'granted' => LocationPermissionState.granted,
        'prompt' => LocationPermissionState.prompt,
        'denied' => LocationPermissionState.denied,
        _ => LocationPermissionState.prompt,
      };
    } catch (e) {
      _log.w('Could not query permission state: $e');
      return LocationPermissionState.prompt;
    }
  }

  /// Attempt to fetch user's live GPS position with fallback handling.
  Future<UserLocationResult> requestDevicePosition({
    int timeoutMs = 10000,
  }) async {
    final permissionState = await queryPermissionState();

    if (permissionState == LocationPermissionState.denied) {
      return const UserLocationResult(
        latitude: defaultLat,
        longitude: defaultLng,
        addressText: defaultAddress,
        isGpsActive: false,
        isVpnMismatch: false,
        permissionState: LocationPermissionState.denied,
      );
    }

    try {
      final rawCoords = await PlatformLocationDelegate.getCurrentPosition(
        timeoutMs: timeoutMs,
      );

      if (rawCoords != null) {
        final lat = rawCoords['latitude']!;
        final lng = rawCoords['longitude']!;

        // Check if GPS/IP points outside Sierra Leone (VPN detected)
        final insideSL = isInsideSierraLeone(lat, lng);
        if (!insideSL) {
          _log.w('VPN or foreign IP detected ($lat, $lng). Applying Sierra Leone fallback.');
          return const UserLocationResult(
            latitude: defaultLat,
            longitude: defaultLng,
            addressText: 'VPN / International IP (Defaulted to Freetown)',
            isGpsActive: true,
            isVpnMismatch: true,
            permissionState: LocationPermissionState.granted,
          );
        }

        // Inside Sierra Leone: Match nearest landmark
        final nearest = findNearestLandmark(lat, lng);
        final address = nearest != null
            ? 'Near ${nearest.name}, ${nearest.neighborhood}'
            : 'Freetown Coordinates (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';

        return UserLocationResult(
          latitude: lat,
          longitude: lng,
          addressText: address,
          isGpsActive: true,
          isVpnMismatch: false,
          permissionState: LocationPermissionState.granted,
          matchedLandmark: nearest,
        );
      }
    } catch (e) {
      _log.e('Failed to obtain GPS position: $e');
    }

    // Default fallback if GPS timed out or was unavailable
    return const UserLocationResult(
      latitude: defaultLat,
      longitude: defaultLng,
      addressText: defaultAddress,
      isGpsActive: false,
      isVpnMismatch: false,
      permissionState: LocationPermissionState.prompt,
    );
  }

  /// Search local Sierra Leone landmarks by text query.
  List<LocationLandmark> searchLandmarks(String query) {
    if (query.trim().isEmpty) return sierraLeoneLandmarks;
    final q = query.trim().toLowerCase();
    return sierraLeoneLandmarks.where((l) {
      return l.name.toLowerCase().contains(q) ||
          l.neighborhood.toLowerCase().contains(q) ||
          l.category.toLowerCase().contains(q);
    }).toList();
  }

  /// Find the geographically nearest landmark to arbitrary lat/lng coordinates.
  LocationLandmark? findNearestLandmark(double lat, double lng) {
    if (sierraLeoneLandmarks.isEmpty) return null;

    LocationLandmark? closest;
    double minDistance = double.infinity;

    for (final landmark in sierraLeoneLandmarks) {
      final d = _computeDistance(lat, lng, landmark.latitude, landmark.longitude);
      if (d < minDistance) {
        minDistance = d;
        closest = landmark;
      }
    }
    return closest;
  }

  /// Reverse geocode coordinates to human-readable Sierra Leone street/area names.
  String reverseGeocode(double lat, double lng) {
    final nearest = findNearestLandmark(lat, lng);
    if (nearest != null) {
      final approxDistKm = _computeDistance(lat, lng, nearest.latitude, nearest.longitude) * 111.0;
      if (approxDistKm < 0.35) {
        return '${nearest.name}, ${nearest.neighborhood}';
      } else if (approxDistKm < 2.5) {
        return 'Near ${nearest.name}, ${nearest.neighborhood}';
      } else {
        return '${nearest.neighborhood} Area';
      }
    }
    return 'Pinned Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
  }

  /// Euclidean distance approximation for small regional distances.
  double _computeDistance(double lat1, double lng1, double lat2, double lng2) {
    final dLat = lat2 - lat1;
    final dLng = lng2 - lng1;
    return sqrt(dLat * dLat + dLng * dLng);
  }
}
