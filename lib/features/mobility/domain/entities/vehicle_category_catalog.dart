// lib/features/mobility/domain/entities/vehicle_category_catalog.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vehicle & Courier Category Catalog (Static Asset Mapping)
// Maps vehicle categories to clean, lightweight vector illustrations,
// seat/luggage capacities, and rate parameters for Sierra Leone (SLE).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// Vehicle tiers available for Passenger Rides & Parcel Deliveries.
enum BookingVehicleCategory {
  courierBike,  // Okada (Motorcycle)
  kekehTricycle,// Kekeh (3-wheeler tricycle)
  standardRide, // Sedan / Comfort (4-seater)
  comfortRide,  // SUV / Executive
  truckHaulage; // Truck / Haulage

  static BookingVehicleCategory fromString(String val) {
    return switch (val.toLowerCase()) {
      'okada_bike' || 'okada' || 'bike' || 'courier_bike' || 'courier' || 'delivery_bike' =>
        BookingVehicleCategory.courierBike,
      'kekeh_tricycle' || 'kekeh' => BookingVehicleCategory.kekehTricycle,
      'comfort_ride' || 'comfort' || 'suv' || 'executive' => BookingVehicleCategory.comfortRide,
      'truck_haulage' || 'truck' || 'haulage' => BookingVehicleCategory.truckHaulage,
      _ => BookingVehicleCategory.standardRide,
    };
  }

  String get id => switch (this) {
        BookingVehicleCategory.courierBike => 'okada_bike',
        BookingVehicleCategory.kekehTricycle => 'kekeh_tricycle',
        BookingVehicleCategory.standardRide => 'standard_ride',
        BookingVehicleCategory.comfortRide => 'comfort_ride',
        BookingVehicleCategory.truckHaulage => 'truck_haulage',
      };

  String get title => switch (this) {
        BookingVehicleCategory.courierBike => 'Okada (Bike)',
        BookingVehicleCategory.kekehTricycle => 'Kekeh',
        BookingVehicleCategory.standardRide => 'Sedan / Comfort',
        BookingVehicleCategory.comfortRide => 'SUV / Executive',
        BookingVehicleCategory.truckHaulage => 'Truck / Haulage',
      };

  String get subtitle => switch (this) {
        BookingVehicleCategory.courierBike => 'Swift 2-wheeler motorcycle',
        BookingVehicleCategory.kekehTricycle => '3-wheeler swift urban ride',
        BookingVehicleCategory.standardRide => '4-seater comfortable sedan',
        BookingVehicleCategory.comfortRide => 'Spacious executive SUV',
        BookingVehicleCategory.truckHaulage => 'Heavy goods & cargo moving truck',
      };

  String get capacity => switch (this) {
        BookingVehicleCategory.courierBike => '1 Passenger / 25kg',
        BookingVehicleCategory.kekehTricycle => '3 Seats',
        BookingVehicleCategory.standardRide => '4 Seats',
        BookingVehicleCategory.comfortRide => '6 Seats / SUV',
        BookingVehicleCategory.truckHaulage => 'Up to 2 Tons Cargo',
      };

  bool get supportsRide => switch (this) {
        BookingVehicleCategory.courierBike => true,
        BookingVehicleCategory.kekehTricycle => true,
        BookingVehicleCategory.standardRide => true,
        BookingVehicleCategory.comfortRide => true,
        BookingVehicleCategory.truckHaulage => false,
      };

  bool get supportsDelivery => switch (this) {
        BookingVehicleCategory.courierBike => true,
        BookingVehicleCategory.kekehTricycle => true,
        BookingVehicleCategory.standardRide => true,
        BookingVehicleCategory.comfortRide => false,
        BookingVehicleCategory.truckHaulage => true,
      };

  /// Sierra Leone Base Fare in SLE (Leones)
  double get baseFare => switch (this) {
        BookingVehicleCategory.courierBike => 5.0,
        BookingVehicleCategory.kekehTricycle => 8.0,
        BookingVehicleCategory.standardRide => 15.0,
        BookingVehicleCategory.comfortRide => 25.0,
        BookingVehicleCategory.truckHaulage => 50.0,
      };

  /// Rate per kilometer in SLE
  double get perKmRate => switch (this) {
        BookingVehicleCategory.courierBike => 3.0,
        BookingVehicleCategory.kekehTricycle => 4.5,
        BookingVehicleCategory.standardRide => 8.0,
        BookingVehicleCategory.comfortRide => 12.0,
        BookingVehicleCategory.truckHaulage => 20.0,
      };

  /// Rate per minute in SLE
  double get perMinRate => switch (this) {
        BookingVehicleCategory.courierBike => 0.5,
        BookingVehicleCategory.kekehTricycle => 0.8,
        BookingVehicleCategory.standardRide => 1.0,
        BookingVehicleCategory.comfortRide => 1.5,
        BookingVehicleCategory.truckHaulage => 2.0,
      };

  IconData get iconData => switch (this) {
        BookingVehicleCategory.courierBike => Icons.two_wheeler_rounded,
        BookingVehicleCategory.kekehTricycle => Icons.electric_rickshaw_rounded,
        BookingVehicleCategory.standardRide => Icons.directions_car_filled_rounded,
        BookingVehicleCategory.comfortRide => Icons.airport_shuttle_rounded,
        BookingVehicleCategory.truckHaulage => Icons.local_shipping_rounded,
      };
}

/// Static catalog configuration class.
class VehicleCategoryCatalog {
  const VehicleCategoryCatalog._();

  static const List<BookingVehicleCategory> allCategories = [
    BookingVehicleCategory.courierBike,
    BookingVehicleCategory.kekehTricycle,
    BookingVehicleCategory.standardRide,
    BookingVehicleCategory.comfortRide,
    BookingVehicleCategory.truckHaulage,
  ];

  static List<BookingVehicleCategory> categoriesForService(String serviceType) {
    if (serviceType == 'delivery') {
      return allCategories.where((c) => c.supportsDelivery).toList();
    }
    return allCategories.where((c) => c.supportsRide).toList();
  }
}
