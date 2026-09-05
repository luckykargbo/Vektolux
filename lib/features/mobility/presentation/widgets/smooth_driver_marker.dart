// lib/features/mobility/presentation/widgets/smooth_driver_marker.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Smooth Driver Marker with Spherical Bearing Interpolation
// Calculates forward azimuth bearing, performs linear coordinate lerp,
// and rotates vehicle marker smoothly with directional arrow & beacon.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_colors.dart';

/// Helper utility for spherical trigonometry bearing calculations.
class GeoBearingHelper {
  /// Calculate forward azimuth bearing (in degrees, 0..360) from start to destination.
  static double calculateBearing(LatLng start, LatLng dest) {
    final lat1 = start.latitude * (math.pi / 180.0);
    final lon1 = start.longitude * (math.pi / 180.0);
    final lat2 = dest.latitude * (math.pi / 180.0);
    final lon2 = dest.longitude * (math.pi / 180.0);

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final radians = math.atan2(y, x);
    final degrees = (radians * (180.0 / math.pi) + 360.0) % 360.0;
    return degrees;
  }

  /// Interpolate angle along the shortest circular path (in degrees).
  static double lerpAngle(double from, double to, double t) {
    final diff = ((to - from + 180.0) % 360.0) - 180.0;
    return (from + diff * t + 360.0) % 360.0;
  }

  /// Linear interpolation between two coordinates.
  static LatLng lerpLatLng(LatLng a, LatLng b, double t) {
    final lat = a.latitude + (b.latitude - a.latitude) * t;
    final lng = a.longitude + (b.longitude - a.longitude) * t;
    return LatLng(lat, lng);
  }
}

/// Visual animated vehicle marker widget with compass heading arrow and pulse glow.
class SmoothDriverMarker extends StatefulWidget {
  final double bearingDegrees;
  final String? vehicleCategory;
  final String? driverName;
  final String? licensePlate;
  final bool isLiveTracking;

  const SmoothDriverMarker({
    super.key,
    required this.bearingDegrees,
    this.vehicleCategory,
    this.driverName,
    this.licensePlate,
    this.isLiveTracking = true,
  });

  @override
  State<SmoothDriverMarker> createState() => _SmoothDriverMarkerState();
}

class _SmoothDriverMarkerState extends State<SmoothDriverMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  IconData _getCategoryIcon(String? category) {
    final cat = (category ?? '').toLowerCase();
    if (cat.contains('kekeh') || cat.contains('tricycle')) {
      return Icons.electric_rickshaw_rounded;
    }
    if (cat.contains('bike') || cat.contains('courier') || cat.contains('delivery')) {
      return Icons.two_wheeler_rounded;
    }
    if (cat.contains('comfort') || cat.contains('suv') || cat.contains('premium')) {
      return Icons.directions_car_filled_rounded;
    }
    return Icons.local_taxi_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final bearingRad = widget.bearingDegrees * (math.pi / 180.0);
    final iconData = _getCategoryIcon(widget.vehicleCategory);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Floating Plate / Driver Badge ─────────────────────────
        if (widget.licensePlate != null || widget.driverName != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.emerald, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              widget.licensePlate ?? widget.driverName ?? 'Driver',
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        const SizedBox(height: 3),

        // ── Rotating Vehicle Avatar with Pulsing Beacon ───────────
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer animated ripple ring
            if (widget.isLiveTracking)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 38 + (_pulseController.value * 16),
                    height: 38 + (_pulseController.value * 16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.emerald.withValues(
                        alpha: 0.35 * (1 - _pulseController.value),
                      ),
                    ),
                  );
                },
              ),

            // Vehicle Circle with Directional Indicator
            Transform.rotate(
              angle: bearingRad,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Directional Arrow / Wedge Pointer
                  Positioned(
                    top: 0,
                    child: Container(
                      width: 0,
                      height: 0,
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: Colors.transparent, width: 5),
                          right: BorderSide(color: Colors.transparent, width: 5),
                          bottom: BorderSide(color: AppColors.emerald, width: 7),
                        ),
                      ),
                    ),
                  ),

                  // Core Vehicle Pod
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.obsidian,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.emerald.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        iconData,
                        size: 18,
                        color: AppColors.emerald,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
