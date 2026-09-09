// lib/features/mobility/data/services/platform_location_web.dart
// ═══════════════════════════════════════════════════════════════════════
// Web-specific implementation querying navigator.permissions and geolocation.
// ═══════════════════════════════════════════════════════════════════════

// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

class PlatformLocationDelegate {
  /// Query navigator.permissions.query({ name: 'geolocation' })
  static Future<String> queryPermissionState() async {
    try {
      final permissions = html.window.navigator.permissions;
      if (permissions != null) {
        final status = await permissions.query({'name': 'geolocation'});
        return status.state ?? 'prompt';
      }
    } catch (_) {
      // Some browsers don't support permissions.query
    }
    return 'prompt';
  }

  static Future<bool> isLocationServiceEnabled() async => true;

  static Future<String> requestPermission() async {
    final pos = await getCurrentPosition(timeoutMs: 5000);
    return pos != null ? 'granted' : 'denied';
  }

  static Future<bool> openLocationSettings() async => false;

  static Future<bool> openAppSettings() async => false;

  /// Trigger navigator.geolocation.getCurrentPosition with enableHighAccuracy: true, timeout: 10000
  static Future<Map<String, double>?> getCurrentPosition({int timeoutMs = 10000}) async {
    try {
      final geo = html.window.navigator.geolocation;
      final pos = await geo.getCurrentPosition(
        enableHighAccuracy: true,
        timeout: Duration(milliseconds: timeoutMs),
      );
      final coords = pos.coords;
      if (coords != null) {
        final lat = coords.latitude?.toDouble();
        final lng = coords.longitude?.toDouble();
        final acc = coords.accuracy?.toDouble();
        if (lat != null && lng != null) {
          return {
            'latitude': lat,
            'longitude': lng,
            'accuracy': acc ?? 10.0,
          };
        }
      }
    } catch (_) {
      // User denied permission or timeout occurred
    }
    return null;
  }
}
