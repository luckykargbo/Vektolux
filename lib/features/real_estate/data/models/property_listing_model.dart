// lib/features/real_estate/data/models/property_listing_model.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Listing Data Model
// Bridges SQLite Drift CachedProperty & Convex JSON with Domain Entity
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/cached_entities_table.dart';
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

  /// Convert from Drift SQLite CachedProperty record.
  factory PropertyListingModel.fromCached(CachedProperty cached) {
    List<String> images = [];
    try {
      final decoded = jsonDecode(cached.imageUrlsJson);
      if (decoded is List) {
        images = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    return PropertyListingModel(
      id: cached.id,
      ownerId: cached.ownerId,
      title: cached.title,
      description: cached.description,
      category: RealEstateCategory.fromString(cached.category),
      price: cached.price,
      hourlyRate: cached.hourlyRate,
      currency: cached.currency,
      address: cached.address,
      city: cached.city,
      country: cached.country,
      latitude: cached.latitude,
      longitude: cached.longitude,
      geohash: cached.geohash,
      availabilityStatus: cached.availabilityStatus,
      imageUrls: images,
      isFeatured: cached.isFeatured,
      isVerified: true, // Synced items from backend are vetted
      viewCount: cached.viewCount,
    );
  }

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

  /// Convert to Drift SQLite Companion for caching.
  CachedProperty toCached() {
    return CachedProperty(
      id: id,
      ownerId: ownerId,
      title: title,
      description: description,
      category: category.name,
      price: price,
      hourlyRate: hourlyRate,
      currency: currency,
      address: address,
      city: city,
      country: country,
      latitude: latitude,
      longitude: longitude,
      geohash: geohash,
      availabilityStatus: availabilityStatus,
      imageUrlsJson: jsonEncode(imageUrls),
      isFeatured: isFeatured,
      viewCount: viewCount,
      syncStatus: EntitySyncStatus.synced,
      localUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      remoteUpdatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
