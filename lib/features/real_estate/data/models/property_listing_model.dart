// lib/features/real_estate/data/models/property_listing_model.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Listing Data Model
// Direct Convex Cloud JSON parser for PropertyListingEntity
// ═══════════════════════════════════════════════════════════════════════

import '../../../../core/utils/safe_parser.dart';
import '../../domain/entities/property_listing_entity.dart';

class PropertyListingModel extends PropertyListingEntity {
  const PropertyListingModel({
    required super.id,
    required super.ownerId,
    required super.title,
    required super.description,
    required super.category,
    required super.price,
    super.hourlyRate,
    super.currency,
    required super.address,
    required super.city,
    required super.country,
    required super.latitude,
    required super.longitude,
    required super.geohash,
    required super.availabilityStatus,
    super.imageUrls,
    super.isFeatured,
    super.isVerified,
    super.viewCount,
    super.bedrooms,
    super.bathrooms,
    super.areaSqM,
    super.amenities,
    super.ownerName,
    super.ownerPhone,
    super.ownerAvatarUrl,
  });

  /// Convert from Convex Document JSON Map.
  factory PropertyListingModel.fromJson(Map<String, dynamic> rawJson) {
    final json = asStringKeyedMap(rawJson);
    final images = asStringList(json['imageUrls']);
    final amenities = asStringList(json['amenities']);

    return PropertyListingModel(
      id: asString(json['_id'] ?? json['id']),
      ownerId: asString(json['ownerId']),
      title: asString(json['title'], 'Untitled Property'),
      description: asString(json['description']),
      category: RealEstateCategory.fromString(
        asString(json['category'], 'sale'),
      ),
      price: asDouble(json['price'], 0.0),
      hourlyRate: json['hourlyRate'] != null ? asDouble(json['hourlyRate']) : null,
      currency: asString(json['currency'], 'SLE'),
      address: asString(json['address'], 'Location Unavailable'),
      city: asString(json['city'], 'Freetown'),
      country: asString(json['country'], 'Sierra Leone'),
      latitude: asDouble(json['latitude'], 0.0),
      longitude: asDouble(json['longitude'], 0.0),
      geohash: asString(json['geohash']),
      availabilityStatus: asString(json['availabilityStatus'], 'available'),
      imageUrls: images,
      isFeatured: asBool(json['isFeatured']),
      isVerified: json['isVerified'] != false,
      viewCount: asInt(json['viewCount'], 0),
      bedrooms: json['bedrooms'] != null ? asInt(json['bedrooms']) : null,
      bathrooms: json['bathrooms'] != null ? asInt(json['bathrooms']) : null,
      areaSqM: json['areaSqM'] != null ? asDouble(json['areaSqM']) : null,
      amenities: amenities,
      ownerName: asString(json['ownerName'], 'Vektolux Verified Partner'),
      ownerPhone: json['ownerPhone']?.toString(),
      ownerAvatarUrl: json['ownerAvatarUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerId': ownerId,
      'title': title,
      'description': description,
      'category': category.name,
      'price': price,
      if (hourlyRate != null) 'hourlyRate': hourlyRate,
      'currency': currency,
      'address': address,
      'city': city,
      'country': country,
      'latitude': latitude,
      'longitude': longitude,
      'geohash': geohash,
      'availabilityStatus': availabilityStatus,
      'imageUrls': imageUrls,
      'isFeatured': isFeatured,
      'isVerified': isVerified,
      'viewCount': viewCount,
      if (bedrooms != null) 'bedrooms': bedrooms,
      if (bathrooms != null) 'bathrooms': bathrooms,
      if (areaSqM != null) 'areaSqM': areaSqM,
      'amenities': amenities,
      'ownerName': ownerName,
      'ownerPhone': ownerPhone,
      'ownerAvatarUrl': ownerAvatarUrl,
    };
  }
}
