// lib/features/mobility/domain/entities/commercial_vehicle_catalog.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Commercial Vehicle & Fleet Catalog
// Centralized taxonomy for commercial vehicle sales, rentals, and heavy haulage.
// Strictly dedicated to:
// 1. Car for Sale (Dealership / Private Auto Seller)
// 2. Car Rental (Daily / Weekly Hire)
// 3. Cargo & Delivery Van (Light / Medium Freight Logistics)
// 4. Sand / Dump Tipper Truck (Quarry Aggregate & Construction Haulage)
// 5. Container / Flatbed Cargo Truck (Port Containers & Heavy Industrial Freight)
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

enum CommercialVehicleCategory {
  carSale,
  carRental,
  deliveryVan,
  sandDumpTruck,
  containerFreightTruck;

  String get id => switch (this) {
        CommercialVehicleCategory.carSale => 'car_sale',
        CommercialVehicleCategory.carRental => 'car_rental',
        CommercialVehicleCategory.deliveryVan => 'delivery_van',
        CommercialVehicleCategory.sandDumpTruck => 'sand_dump_truck',
        CommercialVehicleCategory.containerFreightTruck => 'container_freight_truck',
      };

  String get title => switch (this) {
        CommercialVehicleCategory.carSale => 'Car for Sale',
        CommercialVehicleCategory.carRental => 'Car Rental',
        CommercialVehicleCategory.deliveryVan => 'Cargo & Delivery Van',
        CommercialVehicleCategory.sandDumpTruck => 'Sand / Dump Tipper Truck',
        CommercialVehicleCategory.containerFreightTruck => 'Container / Flatbed Truck',
      };

  String get shortLabel => switch (this) {
        CommercialVehicleCategory.carSale => 'Car Sale',
        CommercialVehicleCategory.carRental => 'Rental',
        CommercialVehicleCategory.deliveryVan => 'Delivery Van',
        CommercialVehicleCategory.sandDumpTruck => 'Sand Tipper',
        CommercialVehicleCategory.containerFreightTruck => 'Container Truck',
      };

  String get subtitle => switch (this) {
        CommercialVehicleCategory.carSale => 'Sedans, SUVs & pickups for direct dealership purchase',
        CommercialVehicleCategory.carRental => 'Vehicles for business hire, airport transfers & daily rent',
        CommercialVehicleCategory.deliveryVan => 'Light to medium freight, courier moving & package dispatch',
        CommercialVehicleCategory.sandDumpTruck => 'Heavy tippers for quarry sand, aggregate & building materials',
        CommercialVehicleCategory.containerFreightTruck => 'Articulated flatbeds for 20ft/40ft shipping containers & steel',
      };

  IconData get icon => switch (this) {
        CommercialVehicleCategory.carSale => Icons.car_rental_rounded,
        CommercialVehicleCategory.carRental => Icons.directions_car_rounded,
        CommercialVehicleCategory.deliveryVan => Icons.local_shipping_rounded,
        CommercialVehicleCategory.sandDumpTruck => Icons.fire_truck_rounded,
        CommercialVehicleCategory.containerFreightTruck => Icons.departure_board_rounded,
      };

  String get defaultPricingType => switch (this) {
        CommercialVehicleCategory.carSale => 'total_sale',
        CommercialVehicleCategory.carRental => 'per_day',
        CommercialVehicleCategory.deliveryVan => 'per_day',
        CommercialVehicleCategory.sandDumpTruck => 'per_trip',
        CommercialVehicleCategory.containerFreightTruck => 'per_trip',
      };

  String get pricingSuffix => switch (this) {
        CommercialVehicleCategory.carSale => 'Total',
        CommercialVehicleCategory.carRental => '/ day',
        CommercialVehicleCategory.deliveryVan => '/ day',
        CommercialVehicleCategory.sandDumpTruck => '/ trip',
        CommercialVehicleCategory.containerFreightTruck => '/ trip',
      };

  List<String> get makeSuggestions => switch (this) {
        CommercialVehicleCategory.carSale => [
            'Toyota', 'Mercedes-Benz', 'Hyundai', 'Nissan', 'Honda', 'Kia', 'Ford', 'Mitsubishi'
          ],
        CommercialVehicleCategory.carRental => [
            'Toyota', 'Hyundai', 'Nissan', 'Ford', 'Kia', 'Mercedes-Benz'
          ],
        CommercialVehicleCategory.deliveryVan => [
            'Toyota HiAce', 'Hyundai H-1', 'Ford Transit', 'Nissan Urvan', 'Mercedes Sprinter', 'Isuzu Elf'
          ],
        CommercialVehicleCategory.sandDumpTruck => [
            'Howo SinoTruck', 'MAN TGS', 'Mercedes-Benz Actros', 'Iveco Trakker', 'Shacman', 'DAF'
          ],
        CommercialVehicleCategory.containerFreightTruck => [
            'Mack Trucks', 'Freightliner', 'Mercedes-Benz Actros', 'Volvo FH', 'Scania', 'Howo A7'
          ],
      };

  List<String> get capacityPresets => switch (this) {
        CommercialVehicleCategory.carSale => ['5 Seats', '7 Seats', 'Double Cabin Pickup'],
        CommercialVehicleCategory.carRental => ['5 Seats Sedan', '7 Seats SUV', 'Double Cabin 4x4'],
        CommercialVehicleCategory.deliveryVan => ['1.0 Ton Payload', '1.5 Tons (Short Wheelbase)', '2.5 Tons (High Roof)', '3.0 Tons Long Chassis'],
        CommercialVehicleCategory.sandDumpTruck => ['10 Tons (6-Wheeler)', '15 Tons (8-Wheeler)', '20 Tons (10-Wheeler)', '25 Tons (12 Cubic Meters)', '30 Tons Tipper'],
        CommercialVehicleCategory.containerFreightTruck => ['20ft Container (25 Tons)', '40ft Standard Container (30 Tons)', '40ft High Cube (35 Tons)', 'Flatbed Steel Haulage (40 Tons)'],
      };

  static CommercialVehicleCategory fromString(String? val) {
    if (val == null) return CommercialVehicleCategory.carSale;
    final v = val.toLowerCase().trim();
    if (v == 'car_rental' || v.contains('rental')) return CommercialVehicleCategory.carRental;
    if (v == 'delivery_van' || v.contains('van')) return CommercialVehicleCategory.deliveryVan;
    if (v == 'sand_dump_truck' || v.contains('dump') || v.contains('tipper') || v.contains('sand')) return CommercialVehicleCategory.sandDumpTruck;
    if (v == 'container_freight_truck' || v.contains('container') || v.contains('flatbed') || v.contains('freight')) return CommercialVehicleCategory.containerFreightTruck;
    return CommercialVehicleCategory.carSale;
  }
}
