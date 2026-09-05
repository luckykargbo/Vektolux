// lib/features/mobility/data/models/vehicle_listing_model.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vehicle Listing Model (Rentals & Sales)
// ═══════════════════════════════════════════════════════════════════════

import '../../domain/entities/mobility_vehicle_entity.dart';

class VehicleListingModel extends VehicleListingEntity {
  const VehicleListingModel({
    required super.id,
    required super.ownerId,
    required super.vehicleType,
    required super.listingIntent,
    required super.make,
    required super.model,
    required super.year,
    super.color,
    super.licensePlate,
    super.imageUrls,
    super.pricePerKm,
    super.pricePerDay,
    super.salePrice,
    super.currency,
    required super.latitude,
    required super.longitude,
    required super.availabilityStatus,
    super.ownerName,
    super.ownerPhone,
  });

  factory VehicleListingModel.fromJson(Map<String, dynamic> json) {
    List<String> images = [];
    if (json['imageUrls'] is List) {
      images = (json['imageUrls'] as List).map((e) => e.toString()).toList();
    }

    return VehicleListingModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      vehicleType: MobilityVehicleType.fromString(
        json['vehicleType']?.toString() ?? 'taxi',
      ),
      listingIntent: json['listingIntent']?.toString() ?? 'rental',
      make: json['make']?.toString() ?? 'Vehicle',
      model: json['model']?.toString() ?? 'Model',
      year: (json['year'] as num?)?.toInt() ?? 2022,
      color: json['color']?.toString(),
      licensePlate: json['licensePlate']?.toString(),
      imageUrls: images,
      pricePerKm: (json['pricePerKm'] as num?)?.toDouble(),
      pricePerDay: (json['pricePerDay'] as num?)?.toDouble() ?? 250.0,
      salePrice: (json['salePrice'] as num?)?.toDouble(),
      currency: json['currency']?.toString() ?? 'SLE',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 8.484,
      longitude: (json['longitude'] as num?)?.toDouble() ?? -13.229,
      availabilityStatus: json['availabilityStatus']?.toString() ?? 'available',
      ownerName: json['ownerName']?.toString() ?? 'Vektolux Mobility Fleet',
      ownerPhone: json['ownerPhone']?.toString(),
    );
  }
}
