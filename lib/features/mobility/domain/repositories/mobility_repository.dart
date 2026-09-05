// lib/features/mobility/domain/repositories/mobility_repository.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Mobility Repository Contract
// ═══════════════════════════════════════════════════════════════════════

import '../entities/ride_entity.dart';
import '../entities/mobility_vehicle_entity.dart';
import '../entities/nearby_driver_entity.dart';
import '../entities/trip_delivery_entity.dart';

abstract class MobilityRepository {
  /// Reactive stream watching active ride from local SQLite & Convex sync.
  Stream<RideEntity?> watchActiveRide(String passengerId);

  /// Fetch list of nearby vehicles/drivers for the interactive map markers.
  Future<List<VehicleListingEntity>> getNearbyVehicles({
    required double lat,
    required double lng,
    double radiusKm = 5.0,
    MobilityVehicleType? vehicleType,
  });

  /// Calculate ride fare using Convex haversine calculator.
  Future<Map<String, dynamic>> estimateFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required MobilityVehicleType vehicleType,
    double? surgeMultiplier,
  });

  /// Request a ride offline-first via SQLite outbox sync.
  Future<String> requestRide({
    required String passengerId,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double dropoffLat,
    required double dropoffLng,
    required String dropoffAddress,
    required MobilityVehicleType vehicleType,
    required double fareAmount,
    required double distanceKm,
    required int estimatedDurationMin,
  });

  /// Cancel an ongoing ride request.
  Future<void> cancelRide({
    required String rideId,
    required String reason,
  });

  /// Book a vehicle rental (daily/weekly, with/without driver).
  Future<String> requestVehicleRental({
    required String userId,
    required String vehicleId,
    required DateTime startDate,
    required DateTime endDate,
    required bool isWithDriver,
    required double totalAmount,
  });

  /// Fetch nearby on-demand drivers (rides, kekehs, delivery bikes) via Convex Geohash queries.
  Future<List<NearbyDriverEntity>> getNearbyDrivers({
    required double lat,
    required double lng,
    double radiusKm = 5.0,
    String? serviceFilter,
  });

  /// Dispatch an on-demand ride or package delivery request.
  Future<String> createTripDeliveryRequest({
    required String passengerId,
    required String serviceType,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddressText,
    required double dropoffLat,
    required double dropoffLng,
    required String dropoffAddressText,
    required double fareAmount,
    required double distanceKm,
    required int durationMins,
    String paymentMethod = 'wallet',
    Map<String, dynamic>? packageDetails,
  });

  /// Get trip or delivery details by ID.
  Future<TripDeliveryEntity?> getTripDelivery(String tripId);
}
