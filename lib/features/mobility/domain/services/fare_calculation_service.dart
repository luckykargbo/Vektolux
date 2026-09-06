// lib/features/mobility/domain/services/fare_calculation_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Fare & ETA Calculation Engine
// Computes upfront transparent fares:
//   Fare = Base Fare + (Distance * Per-Km) + (Duration * Per-Min)
// with live ETAs determined from the closest spatial driver nodes.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:math';
import 'package:equatable/equatable.dart';
import '../entities/nearby_driver_entity.dart';
import '../entities/vehicle_category_catalog.dart';

/// Resolved fare and ETA estimate for a specific vehicle tier.
class CalculatedTierEstimate extends Equatable {
  final BookingVehicleCategory category;
  final double fareAmount;
  final String currency;
  final int arrivalEtaMinutes;
  final int tripDurationMinutes;
  final double distanceKm;
  final bool hasNearbyDriver;
  final String? closestDriverName;
  final double? closestDriverDistanceKm;

  const CalculatedTierEstimate({
    required this.category,
    required this.fareAmount,
    this.currency = 'SLE',
    required this.arrivalEtaMinutes,
    required this.tripDurationMinutes,
    required this.distanceKm,
    required this.hasNearbyDriver,
    this.closestDriverName,
    this.closestDriverDistanceKm,
  });

  @override
  List<Object?> get props => [
        category,
        fareAmount,
        currency,
        arrivalEtaMinutes,
        tripDurationMinutes,
        distanceKm,
        hasNearbyDriver,
        closestDriverName,
        closestDriverDistanceKm,
      ];
}

class FareCalculationService {
  const FareCalculationService();

  /// Calculate upfront fare and ETA estimates for all categories given distance, duration, and nearby drivers.
  Map<BookingVehicleCategory, CalculatedTierEstimate> calculateAllTiers({
    required double distanceKm,
    int? durationMins,
    required List<NearbyDriverEntity> nearbyDrivers,
    required String serviceType, // 'ride' | 'delivery'
  }) {
    final availableCategories = VehicleCategoryCatalog.categoriesForService(serviceType);
    final Map<BookingVehicleCategory, CalculatedTierEstimate> results = {};

    for (final category in availableCategories) {
      // 1. Calculate trip duration in minutes if not provided
      final avgSpeedKmh = switch (category) {
        BookingVehicleCategory.courierBike => 30.0,
        BookingVehicleCategory.kekehTricycle => 25.0,
        BookingVehicleCategory.standardRide => 22.0,
        BookingVehicleCategory.comfortRide => 24.0,
        BookingVehicleCategory.truckHaulage => 18.0,
      };

      final calculatedDuration = durationMins ??
          max(3, ((distanceKm / avgSpeedKmh) * 60).round());

      // 2. Upfront Fare Formula:
      // Fare = Base Fare + (Distance * Per-Km) + (Duration * Per-Min)
      final rawFare = category.baseFare +
          (distanceKm * category.perKmRate) +
          (calculatedDuration * category.perMinRate);

      // Round to clean SLE currency representation (multiples of 5 or whole Leones)
      final fare = (rawFare * 2).round() / 2.0;

      // 3. Find closest driver matching this category
      NearbyDriverEntity? closestDriver;
      double minDriverDist = double.infinity;

      for (final driver in nearbyDrivers) {
        if (_driverMatchesCategory(driver, category)) {
          if (driver.distanceKm < minDriverDist) {
            minDriverDist = driver.distanceKm;
            closestDriver = driver;
          }
        }
      }

      // Arrival ETA: closest driver's ETA or urban fallback
      final int arrivalEta;
      if (closestDriver != null) {
        arrivalEta = max(2, closestDriver.etaMinutes);
      } else {
        arrivalEta = (category == BookingVehicleCategory.courierBike ||
                category == BookingVehicleCategory.kekehTricycle)
            ? 3
            : 6;
      }

      results[category] = CalculatedTierEstimate(
        category: category,
        fareAmount: fare,
        currency: 'SLE',
        arrivalEtaMinutes: arrivalEta,
        tripDurationMinutes: calculatedDuration,
        distanceKm: distanceKm,
        hasNearbyDriver: closestDriver != null,
        closestDriverName: closestDriver?.driverName,
        closestDriverDistanceKm: closestDriver != null ? minDriverDist : null,
      );
    }

    return results;
  }

  bool _driverMatchesCategory(
    NearbyDriverEntity driver,
    BookingVehicleCategory category,
  ) {
    final vehicleCategory = driver.vehicle?.category;
    if (vehicleCategory == null) return false;

    return switch (category) {
      BookingVehicleCategory.standardRide =>
        vehicleCategory == DriverVehicleCategory.standard,
      BookingVehicleCategory.comfortRide =>
        vehicleCategory == DriverVehicleCategory.comfort,
      BookingVehicleCategory.kekehTricycle =>
        vehicleCategory == DriverVehicleCategory.kekehTricycle,
      BookingVehicleCategory.courierBike =>
        vehicleCategory == DriverVehicleCategory.deliveryBike,
      BookingVehicleCategory.truckHaulage =>
        vehicleCategory == DriverVehicleCategory.standard,
    };
  }
}
