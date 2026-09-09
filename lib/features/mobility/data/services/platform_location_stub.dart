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
      if (!serviceEnabled) return 'serviceDisabled';

      final permission = await Geolocator.checkPermission();
      return switch (permission) {
        LocationPermission.always => 'granted',
        LocationPermission.whileInUse => 'granted',
        LocationPermission.denied => 'prompt',
        LocationPermission.deniedForever => 'deniedForever',
        _ => 'prompt',
      };
    } catch (_) {
      return 'prompt';
    }
  }

  /// Check whether OS level location services are enabled.
  static Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }

  /// Prompt native OS permission request.
  static Future<String> requestPermission() async {
    try {
      final perm = await Geolocator.requestPermission();
      return switch (perm) {
        LocationPermission.always => 'granted',
        LocationPermission.whileInUse => 'granted',
        LocationPermission.denied => 'denied',
        LocationPermission.deniedForever => 'deniedForever',
        _ => 'denied',
      };
    } catch (_) {
      return 'denied';
    }
  }

  /// Open OS-level location settings (GPS toggle).
  static Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }

  /// Open app-specific settings in OS settings.
  static Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
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
