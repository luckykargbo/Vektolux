// lib/features/mobility/data/services/routing_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Dynamic Routing & Live Directions Service
// Connects pickup and drop-off coordinates using OSRM to generate
// dynamic polyline coordinates, doorstep distances, and real-time ETAs.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';

/// Structured route result containing polyline geometry, distance, and ETA.
class RouteDetails {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;
  final String formattedDistance;
  final String formattedEta;

  const RouteDetails({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
    required this.formattedDistance,
    required this.formattedEta,
  });

  /// Factory for an empty or uninitialized route.
  factory RouteDetails.empty() {
    return const RouteDetails(
      points: [],
      distanceKm: 0.0,
      durationMinutes: 0,
      formattedDistance: '0.0 km',
      formattedEta: '0 min',
    );
  }
}

class RoutingService {
  final http.Client _client;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  RoutingService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches real-world driving directions between [start] and [end].
  /// Uses OSRM public directions routing with graceful geodesic fallback.
  Future<RouteDetails> getDirections(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await _client.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;

        if (routes != null && routes.isNotEmpty) {
          final firstRoute = routes[0] as Map<String, dynamic>;
          final geometry = firstRoute['geometry'] as Map<String, dynamic>?;
          final coordinates = geometry?['coordinates'] as List<dynamic>?;

          final rawDistanceMeters = (firstRoute['distance'] as num?)?.toDouble() ?? 0.0;
          final rawDurationSeconds = (firstRoute['duration'] as num?)?.toDouble() ?? 0.0;

          final distanceKm = rawDistanceMeters / 1000.0;
          final durationMin = math.max(1, (rawDurationSeconds / 60.0).ceil());

          final polylinePoints = <LatLng>[];
          if (coordinates != null) {
            for (final coord in coordinates) {
              if (coord is List && coord.length >= 2) {
                final lng = (coord[0] as num).toDouble();
                final lat = (coord[1] as num).toDouble();
                polylinePoints.add(LatLng(lat, lng));
              }
            }
          }

          if (polylinePoints.isEmpty) {
            polylinePoints.addAll([start, end]);
          }

          return RouteDetails(
            points: polylinePoints,
            distanceKm: distanceKm,
            durationMinutes: durationMin,
            formattedDistance: '${distanceKm.toStringAsFixed(1)} km',
            formattedEta: '$durationMin mins',
          );
        }
      }
    } catch (e) {
      _log.w('OSRM directions fetch failed (using fallback): $e');
    }

    // Graceful fallback: Haversine distance + realistic urban duration calculation
    return _computeFallbackRoute(start, end);
  }

  /// Calculates geodesic distance and realistic road approximation.
  RouteDetails _computeFallbackRoute(LatLng start, LatLng end) {
    const earthRadiusKm = 6371.0;

    final dLat = _degreesToRadians(end.latitude - start.latitude);
    final dLon = _degreesToRadians(end.longitude - start.longitude);

    final lat1 = _degreesToRadians(start.latitude);
    final lat2 = _degreesToRadians(end.latitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) * math.sin(dLon / 2) * math.cos(lat1) * math.cos(lat2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final directDistanceKm = earthRadiusKm * c;

    // Urban road factor (~1.3x direct distance due to streets/turns)
    final roadDistanceKm = directDistanceKm * 1.3;
    // Average urban speed ~32 km/h
    final durationMinutes = math.max(3, (roadDistanceKm / 32.0 * 60.0).round());

    // Generate interpolated points with slight curve for natural polyline rendering
    final points = <LatLng>[start];
    const steps = 8;
    for (int i = 1; i < steps; i++) {
      final fraction = i / steps;
      final lat = start.latitude + (end.latitude - start.latitude) * fraction;
      final lng = start.longitude + (end.longitude - start.longitude) * fraction;
      // Slight sinusoidal curve to emulate roads
      final offset = math.sin(fraction * math.pi) * 0.0015;
      points.add(LatLng(lat + offset, lng - offset));
    }
    points.add(end);

    return RouteDetails(
      points: points,
      distanceKm: roadDistanceKm,
      durationMinutes: durationMinutes,
      formattedDistance: '${roadDistanceKm.toStringAsFixed(1)} km',
      formattedEta: '$durationMinutes mins',
    );
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }
}
