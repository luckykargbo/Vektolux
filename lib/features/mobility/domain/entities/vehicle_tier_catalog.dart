// lib/features/mobility/domain/entities/vehicle_tier_catalog.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Sierra Leone Vehicle Tier Domain Model & Dynamic Catalog
// Centralized transport tier definitions with transparent upfront fares,
// 3D isometric asset mappings, capacities, and Sierra Leone Leones (SLE) rates.
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import 'vehicle_category_catalog.dart';

/// Identifier for Sierra Leone urban transport tiers.
enum VehicleTierId {
  kekeBajaj,
  okadaBike,
  carStandard,
  deliveryVan;

  String get stringId => switch (this) {
        VehicleTierId.kekeBajaj => 'keke_bajaj',
        VehicleTierId.okadaBike => 'okada_bike',
        VehicleTierId.carStandard => 'car_standard',
        VehicleTierId.deliveryVan => 'delivery_van',
      };

  static VehicleTierId fromString(String val) {
    final v = val.toLowerCase().trim();
    if (v.contains('keke') || v.contains('tricycle') || v.contains('bajaj')) {
      return VehicleTierId.kekeBajaj;
    }
    if (v.contains('okada') || v.contains('bike') || v.contains('motorcycle') || v.contains('courier')) {
      return VehicleTierId.okadaBike;
    }
    if (v.contains('van') || v.contains('cargo') || v.contains('truck') || v.contains('delivery_van')) {
      return VehicleTierId.deliveryVan;
    }
    return VehicleTierId.carStandard;
  }
}

/// Immutable configuration entity for a vehicle tier.
class VehicleTierConfig extends Equatable {
  final String id;
  final VehicleTierId tierId;
  final String name;
  final String categoryKey; // 'keke' | 'okada' | 'car' | 'van'
  final int capacity;
  final String capacityLabel;
  final String render3DUrl;
  final String mapIconSvg;
  final double basePriceSLE;
  final double pricePerKmSLE;
  final String buttonLabel;
  final String description;
  final int etaMinutesDefault;
  final bool supportsRide;
  final bool supportsDelivery;

  const VehicleTierConfig({
    required this.id,
    required this.tierId,
    required this.name,
    required this.categoryKey,
    required this.capacity,
    required this.capacityLabel,
    required this.render3DUrl,
    required this.mapIconSvg,
    required this.basePriceSLE,
    required this.pricePerKmSLE,
    required this.buttonLabel,
    required this.description,
    required this.etaMinutesDefault,
    required this.supportsRide,
    required this.supportsDelivery,
  });

  /// Calculate upfront guaranteed fare in SLE.
  /// Formula: BasePrice + (DistanceKm * PricePerKm)
  double calculateFare(double distanceKm) {
    final dist = distanceKm > 0 ? distanceKm : 1.0;
    final rawFare = basePriceSLE + (dist * pricePerKmSLE);
    return (rawFare * 2).round() / 2.0;
  }

  /// Bridge to existing legacy BookingVehicleCategory enum.
  BookingVehicleCategory toBookingCategory() {
    return switch (tierId) {
      VehicleTierId.kekeBajaj => BookingVehicleCategory.kekehTricycle,
      VehicleTierId.okadaBike => BookingVehicleCategory.courierBike,
      VehicleTierId.carStandard => BookingVehicleCategory.standardRide,
      VehicleTierId.deliveryVan => BookingVehicleCategory.truckHaulage,
    };
  }

  /// Map from legacy BookingVehicleCategory to modern tier config.
  static VehicleTierConfig fromBookingCategory(BookingVehicleCategory category) {
    return switch (category) {
      BookingVehicleCategory.kekehTricycle => keke,
      BookingVehicleCategory.courierBike => okada,
      BookingVehicleCategory.standardRide => standardCar,
      BookingVehicleCategory.comfortRide => standardCar,
      BookingVehicleCategory.truckHaulage => cargoVan,
    };
  }

  // ── Predefined Sierra Leone Transport Tiers ──────────────────────

  static const VehicleTierConfig keke = VehicleTierConfig(
    id: 'keke_bajaj',
    tierId: VehicleTierId.kekeBajaj,
    name: 'Keke (Tricycle)',
    categoryKey: 'keke',
    capacity: 3,
    capacityLabel: '3 Seats',
    render3DUrl: '',
    mapIconSvg: 'keke',
    basePriceSLE: 15.0,
    pricePerKmSLE: 5.0,
    buttonLabel: 'Request Keke',
    description: 'Swift 3-wheeler tricycle, ideal for Freetown traffic',
    etaMinutesDefault: 3,
    supportsRide: true,
    supportsDelivery: true,
  );

  static const VehicleTierConfig okada = VehicleTierConfig(
    id: 'okada_bike',
    tierId: VehicleTierId.okadaBike,
    name: 'Okada (Motorbike)',
    categoryKey: 'okada',
    capacity: 1,
    capacityLabel: '1 Passenger',
    render3DUrl: '',
    mapIconSvg: 'okada',
    basePriceSLE: 10.0,
    pricePerKmSLE: 4.0,
    buttonLabel: 'Request Okada',
    description: 'Express 2-wheel motorbike for urgent point-to-point transit',
    etaMinutesDefault: 2,
    supportsRide: true,
    supportsDelivery: true,
  );

  static const VehicleTierConfig standardCar = VehicleTierConfig(
    id: 'car_standard',
    tierId: VehicleTierId.carStandard,
    name: 'Standard Ride (Taxi)',
    categoryKey: 'car',
    capacity: 4,
    capacityLabel: '4 Seats',
    render3DUrl: '',
    mapIconSvg: 'car',
    basePriceSLE: 30.0,
    pricePerKmSLE: 8.0,
    buttonLabel: 'Request Standard Ride',
    description: 'Comfortable air-conditioned sedan for urban commuting',
    etaMinutesDefault: 5,
    supportsRide: true,
    supportsDelivery: true,
  );

  static const VehicleTierConfig cargoVan = VehicleTierConfig(
    id: 'delivery_van',
    tierId: VehicleTierId.deliveryVan,
    name: 'Cargo / Van',
    categoryKey: 'van',
    capacity: 2,
    capacityLabel: '2 Seats / 1 Ton Cargo',
    render3DUrl: '',
    mapIconSvg: 'van',
    basePriceSLE: 45.0,
    pricePerKmSLE: 12.0,
    buttonLabel: 'Request Cargo / Van',
    description: 'Commercial van for heavy cargo, freight, and moving',
    etaMinutesDefault: 7,
    supportsRide: false,
    supportsDelivery: true,
  );

  static const List<VehicleTierConfig> allTiers = [
    keke,
    okada,
    standardCar,
    cargoVan,
  ];

  static List<VehicleTierConfig> tiersForService(String serviceType) {
    if (serviceType == 'delivery') {
      return allTiers.where((t) => t.supportsDelivery).toList();
    }
    return allTiers.where((t) => t.supportsRide).toList();
  }

  static VehicleTierConfig byId(String id) {
    final cleanId = id.toLowerCase().trim();
    return allTiers.firstWhere(
      (t) => t.id == cleanId || t.categoryKey == cleanId,
      orElse: () => standardCar,
    );
  }

  @override
  List<Object?> get props => [
        id,
        tierId,
        name,
        categoryKey,
        capacity,
        capacityLabel,
        render3DUrl,
        mapIconSvg,
        basePriceSLE,
        pricePerKmSLE,
        buttonLabel,
        description,
        etaMinutesDefault,
        supportsRide,
        supportsDelivery,
      ];
}
