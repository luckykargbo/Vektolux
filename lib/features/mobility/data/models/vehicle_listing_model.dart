// lib/features/mobility/data/models/vehicle_listing_model.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vehicle Listing Model (Rentals & Sales)
// ═══════════════════════════════════════════════════════════════════════

import '../../../../core/utils/safe_parser.dart';
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

  factory VehicleListingModel.fromJson(Map<String, dynamic> rawJson) {
    final json = asStringKeyedMap(rawJson);
    final images = asStringList(json['imageUrls']);

    return VehicleListingModel(
      id: asString(json['_id'] ?? json['id']),
      ownerId: asString(json['ownerId']),
      vehicleType: MobilityVehicleType.fromString(
        asString(json['vehicleType'], 'taxi'),
      ),
      listingIntent: asString(json['listingIntent'], 'rental'),
      make: asString(json['make'], 'Vehicle'),
      model: asString(json['model'], 'Listing'),
      year: asInt(json['year'], 2022),
      color: json['color']?.toString(),
      licensePlate: json['licensePlate']?.toString(),
      imageUrls: images,
      pricePerKm: json['pricePerKm'] != null ? asDouble(json['pricePerKm']) : null,
      pricePerDay: asDouble(json['pricePerDay'], 250.0),
      salePrice: json['salePrice'] != null ? asDouble(json['salePrice']) : null,
      currency: asString(json['currency'], 'SLE'),
      latitude: asDouble(json['latitude'], 8.484),
      longitude: asDouble(json['longitude'], -13.229),
      availabilityStatus: asString(json['availabilityStatus'], 'available'),
      ownerName: asString(json['ownerName'], 'Vektolux Mobility Fleet'),
      ownerPhone: json['ownerPhone']?.toString(),
    );
  }
}
