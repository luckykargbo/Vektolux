// lib/features/mobility/data/services/platform_location_stub.dart
// ═══════════════════════════════════════════════════════════════════════
// Native (Android/iOS/Desktop) geolocation using geolocator package.
// Conditional export replaces this on web with dart:html variant.
// ═══════════════════════════════════════════════════════════════════════

import 'package:geolocator/geolocator.dart';

class PlatformLocationDelegate {
  /// Query native GPS permission state via geolocator.
  static Future<String> queryPermissionState() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return 'denied';

      final permission = await Geolocator.checkPermission();
      return switch (permission) {
        LocationPermission.always => 'granted',
        LocationPermission.whileInUse => 'granted',
        LocationPermission.denied => 'prompt',
        LocationPermission.deniedForever => 'denied',
        _ => 'prompt',
      };
    } catch (_) {
      return 'prompt';
    }
  }

  /// Fetch live GPS coordinates with enableHighAccuracy, timeout, and
  /// automatic permission request if currently in 'prompt' state.
  static Future<Map<String, double>?> getCurrentPosition({
    int timeoutMs = 10000,
  }) async {
    try {
      // Check & request permission if needed
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      // Verify location service is enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
      };
    } catch (_) {
      // Timeout, denied, or hardware failure — graceful fallback
      return null;
    }
  }
}
