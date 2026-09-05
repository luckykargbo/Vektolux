// lib/features/mobility/domain/entities/vehicle_category_catalog.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vehicle & Courier Category Catalog (Static Asset Mapping)
// Maps vehicle categories to clean, lightweight vector illustrations,
// seat/luggage capacities, and rate parameters for Sierra Leone (SLE).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// Vehicle tiers available for Passenger Rides & Parcel Deliveries.
enum BookingVehicleCategory {
  standardRide, // 4-seater economy sedan
  comfortRide,  // SUV / premium vehicle
  kekehTricycle,// 3-wheeler urban ride
  courierBike;  // Motorcycle / parcel delivery courier

  static BookingVehicleCategory fromString(String val) {
    return switch (val.toLowerCase()) {
      'comfort_ride' || 'comfort' => BookingVehicleCategory.comfortRide,
      'kekeh_tricycle' || 'kekeh' => BookingVehicleCategory.kekehTricycle,
      'courier_bike' || 'courier' || 'delivery_bike' => BookingVehicleCategory.courierBike,
      _ => BookingVehicleCategory.standardRide,
    };
  }

  String get id => switch (this) {
        BookingVehicleCategory.standardRide => 'standard_ride',
        BookingVehicleCategory.comfortRide => 'comfort_ride',
        BookingVehicleCategory.kekehTricycle => 'kekeh_tricycle',
        BookingVehicleCategory.courierBike => 'courier_bike',
      };

  String get title => switch (this) {
        BookingVehicleCategory.standardRide => 'Standard Ride',
        BookingVehicleCategory.comfortRide => 'Comfort Plus',
        BookingVehicleCategory.kekehTricycle => 'Kekeh Tricycle',
        BookingVehicleCategory.courierBike => 'Courier Express',
      };

  String get subtitle => switch (this) {
        BookingVehicleCategory.standardRide => '4-seater economy sedan',
        BookingVehicleCategory.comfortRide => 'Spacious SUV / premium vehicle',
        BookingVehicleCategory.kekehTricycle => '3-wheeler swift urban ride',
        BookingVehicleCategory.courierBike => 'Fast motorcycle parcel courier',
      };

  String get capacity => switch (this) {
        BookingVehicleCategory.standardRide => '4 Seats',
        BookingVehicleCategory.comfortRide => '6 Seats / SUV',
        BookingVehicleCategory.kekehTricycle => '3 Seats',
        BookingVehicleCategory.courierBike => 'Up to 25kg Parcel',
      };

  bool get supportsRide => switch (this) {
        BookingVehicleCategory.standardRide => true,
        BookingVehicleCategory.comfortRide => true,
        BookingVehicleCategory.kekehTricycle => true,
        BookingVehicleCategory.courierBike => false,
      };

  bool get supportsDelivery => switch (this) {
        BookingVehicleCategory.standardRide => true,
        BookingVehicleCategory.comfortRide => false,
        BookingVehicleCategory.kekehTricycle => true,
        BookingVehicleCategory.courierBike => true,
      };

  /// Sierra Leone Base Fare in SLE (Leones)
  double get baseFare => switch (this) {
        BookingVehicleCategory.standardRide => 15.0,
        BookingVehicleCategory.comfortRide => 25.0,
        BookingVehicleCategory.kekehTricycle => 8.0,
        BookingVehicleCategory.courierBike => 10.0,
      };

  /// Rate per kilometer in SLE
  double get perKmRate => switch (this) {
        BookingVehicleCategory.standardRide => 7.0,
        BookingVehicleCategory.comfortRide => 11.0,
        BookingVehicleCategory.kekehTricycle => 4.5,
        BookingVehicleCategory.courierBike => 5.0,
      };

  /// Rate per minute in SLE
  double get perMinRate => switch (this) {
        BookingVehicleCategory.standardRide => 1.5,
        BookingVehicleCategory.comfortRide => 2.5,
        BookingVehicleCategory.kekehTricycle => 1.0,
        BookingVehicleCategory.courierBike => 1.2,
      };

  IconData get iconData => switch (this) {
        BookingVehicleCategory.standardRide => Icons.directions_car_filled_rounded,
        BookingVehicleCategory.comfortRide => Icons.airport_shuttle_rounded,
        BookingVehicleCategory.kekehTricycle => Icons.electric_rickshaw_rounded,
        BookingVehicleCategory.courierBike => Icons.delivery_dining_rounded,
      };
}

/// Static catalog configuration class.
class VehicleCategoryCatalog {
  const VehicleCategoryCatalog._();

  static const List<BookingVehicleCategory> allCategories = [
    BookingVehicleCategory.standardRide,
    BookingVehicleCategory.comfortRide,
    BookingVehicleCategory.kekehTricycle,
    BookingVehicleCategory.courierBike,
  ];

  static List<BookingVehicleCategory> categoriesForService(String serviceType) {
    if (serviceType == 'delivery') {
      return allCategories.where((c) => c.supportsDelivery).toList();
    }
    return allCategories.where((c) => c.supportsRide).toList();
  }
}
