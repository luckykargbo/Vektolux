// lib/features/mobility/domain/entities/nearby_driver_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Nearby Driver Proximity Domain Entity
// Returned by Convex getNearbyDrivers query with ETAs and category icons.
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

enum DriverVehicleCategory {
  standard,
  comfort,
  kekehTricycle,
  deliveryBike;

  static DriverVehicleCategory fromString(String val) {
    return switch (val.toLowerCase()) {
      'comfort' => DriverVehicleCategory.comfort,
      'kekeh_tricycle' || 'kekehtricycle' => DriverVehicleCategory.kekehTricycle,
      'delivery_bike' || 'deliverybike' => DriverVehicleCategory.deliveryBike,
      _ => DriverVehicleCategory.standard,
    };
  }

  String get displayName => switch (this) {
        DriverVehicleCategory.standard => 'Standard Taxi',
        DriverVehicleCategory.comfort => 'Comfort Sedan',
        DriverVehicleCategory.kekehTricycle => 'Kekeh Tricycle',
        DriverVehicleCategory.deliveryBike => 'Express Bike Delivery',
      };

  String get iconKey => switch (this) {
        DriverVehicleCategory.standard => 'standard_taxi',
        DriverVehicleCategory.comfort => 'sedan_premium',
        DriverVehicleCategory.kekehTricycle => 'kekeh_tricycle',
        DriverVehicleCategory.deliveryBike => 'two_wheeler_delivery',
      };
}

class DriverVehicleInfo extends Equatable {
  final String id;
  final String make;
  final String model;
  final int year;
  final String color;
  final String licensePlate;
  final DriverVehicleCategory category;
  final String categoryIconKey;
  final bool isVerified;

  const DriverVehicleInfo({
    required this.id,
    required this.make,
    required this.model,
    required this.year,
    required this.color,
    required this.licensePlate,
    required this.category,
    required this.categoryIconKey,
    required this.isVerified,
  });

  factory DriverVehicleInfo.fromJson(Map<String, dynamic> json) {
    return DriverVehicleInfo(
      id: json['id'] as String? ?? '',
      make: json['make'] as String? ?? '',
      model: json['model'] as String? ?? '',
      year: (json['year'] as num?)?.toInt() ?? 2020,
      color: json['color'] as String? ?? '',
      licensePlate: json['licensePlate'] as String? ?? '',
      category: DriverVehicleCategory.fromString(json['category'] as String? ?? 'standard'),
      categoryIconKey: json['categoryIconKey'] as String? ?? 'standard_taxi',
      isVerified: json['isVerified'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, make, model, year, color, licensePlate, category, isVerified];
}

class NearbyDriverEntity extends Equatable {
  final String driverId;
  final String userId;
  final String driverName;
  final String driverPhone;
  final String? avatarUrl;
  final String serviceType;
  final double currentLat;
  final double currentLng;
  final int distanceMeters;
  final double distanceKm;
  final int etaMinutes;
  final DriverVehicleInfo? vehicle;
  final double? bearing;

  const NearbyDriverEntity({
    required this.driverId,
    required this.userId,
    required this.driverName,
    required this.driverPhone,
    this.avatarUrl,
    required this.serviceType,
    required this.currentLat,
    required this.currentLng,
    required this.distanceMeters,
    required this.distanceKm,
    required this.etaMinutes,
    this.vehicle,
    this.bearing,
  });

  factory NearbyDriverEntity.fromJson(Map<String, dynamic> json) {
    return NearbyDriverEntity(
      driverId: json['driverId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      driverName: json['driverName'] as String? ?? 'Driver',
      driverPhone: json['driverPhone'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      serviceType: json['serviceType'] as String? ?? 'ride',
      currentLat: (json['currentLat'] as num).toDouble(),
      currentLng: (json['currentLng'] as num).toDouble(),
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      etaMinutes: (json['etaMinutes'] as num?)?.toInt() ?? 5,
      vehicle: json['vehicle'] != null
          ? DriverVehicleInfo.fromJson(json['vehicle'] as Map<String, dynamic>)
          : null,
      bearing: (json['bearing'] as num?)?.toDouble(),
    );
  }

  @override
  List<Object?> get props => [
        driverId,
        userId,
        driverName,
        serviceType,
        currentLat,
        currentLng,
        distanceMeters,
        distanceKm,
        etaMinutes,
        vehicle,
        bearing,
      ];
}
