// lib/features/mobility/domain/entities/mobility_vehicle_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Mobility Vehicle & Category Entities
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Supported vehicle categories in Vektolux.
enum MobilityVehicleType {
  bike,
  taxi,
  deliveryVan,
  truck;

  static MobilityVehicleType fromString(String val) {
    return switch (val.toLowerCase()) {
      'bike' || 'motorcycle' => MobilityVehicleType.bike,
      'taxi' || 'standard_taxi' || 'car' => MobilityVehicleType.taxi,
      'delivery_van' || 'deliveryvan' || 'van' => MobilityVehicleType.deliveryVan,
      'truck' || 'heavy_truck' => MobilityVehicleType.truck,
      _ => MobilityVehicleType.taxi,
    };
  }

  String get backendKey => switch (this) {
        MobilityVehicleType.bike => 'bike',
        MobilityVehicleType.taxi => 'taxi',
        MobilityVehicleType.deliveryVan => 'delivery_van',
        MobilityVehicleType.truck => 'truck',
      };

  String get displayName => switch (this) {
        MobilityVehicleType.bike => 'Express Bike',
        MobilityVehicleType.taxi => 'Standard Taxi',
        MobilityVehicleType.deliveryVan => 'Delivery Van',
        MobilityVehicleType.truck => 'Heavy Truck',
      };

  String get subtitle => switch (this) {
        MobilityVehicleType.bike => 'Fast single passenger / courier',
        MobilityVehicleType.taxi => 'Comfortable 4-seater sedan',
        MobilityVehicleType.deliveryVan => 'Medium cargo & package moves',
        MobilityVehicleType.truck => 'Heavy haulage & bulk freight',
      };

  IconData get iconData => switch (this) {
        MobilityVehicleType.bike => Icons.two_wheeler_rounded,
        MobilityVehicleType.taxi => Icons.local_taxi_rounded,
        MobilityVehicleType.deliveryVan => Icons.local_shipping_outlined,
        MobilityVehicleType.truck => Icons.fire_truck_outlined,
      };

  int get passengerCapacity => switch (this) {
        MobilityVehicleType.bike => 1,
        MobilityVehicleType.taxi => 4,
        MobilityVehicleType.deliveryVan => 2,
        MobilityVehicleType.truck => 2,
      };

  String get luggageCapacity => switch (this) {
        MobilityVehicleType.bike => 'Small backpack',
        MobilityVehicleType.taxi => '2-3 Large bags',
        MobilityVehicleType.deliveryVan => 'Up to 500 kg',
        MobilityVehicleType.truck => 'Up to 5 tonnes',
      };
}

/// Helper model for the Vehicle Type Selection Carousel.
class VehicleCategoryOption extends Equatable {
  final MobilityVehicleType type;
  final double estimatedFare;
  final int etaMinutes;
  final String currency;

  const VehicleCategoryOption({
    required this.type,
    required this.estimatedFare,
    required this.etaMinutes,
    this.currency = 'SLE',
  });

  @override
  List<Object?> get props => [type, estimatedFare, etaMinutes, currency];
}

/// Domain entity for vehicles listed for rental or sale.
class VehicleListingEntity extends Equatable {
  final String id;
  final String ownerId;
  final MobilityVehicleType vehicleType;
  final String listingIntent; // "rental", "sale", "ride_hailing"
  final String make;
  final String model;
  final int year;
  final String? color;
  final String? licensePlate;
  final List<String> imageUrls;
  final double? pricePerKm;
  final double? pricePerDay;
  final double? salePrice;
  final String currency;
  final double latitude;
  final double longitude;
  final String availabilityStatus;
  final String? ownerName;
  final String? ownerPhone;

  const VehicleListingEntity({
    required this.id,
    required this.ownerId,
    required this.vehicleType,
    required this.listingIntent,
    required this.make,
    required this.model,
    required this.year,
    this.color,
    this.licensePlate,
    this.imageUrls = const [],
    this.pricePerKm,
    this.pricePerDay,
    this.salePrice,
    this.currency = 'SLE',
    required this.latitude,
    required this.longitude,
    required this.availabilityStatus,
    this.ownerName,
    this.ownerPhone,
  });

  String get fullTitle => '$year $make $model';

  bool get isForRent => listingIntent == 'rental';
  bool get isForSale => listingIntent == 'sale';

  @override
  List<Object?> get props => [
        id,
        ownerId,
        vehicleType,
        listingIntent,
        make,
        model,
        year,
        color,
        licensePlate,
        imageUrls,
        pricePerKm,
        pricePerDay,
        salePrice,
        currency,
        latitude,
        longitude,
        availabilityStatus,
        ownerName,
        ownerPhone,
      ];
}
