// lib/features/real_estate/data/models/property_listing_model.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Listing Data Model
// Bridges SQLite Drift CachedProperty & Convex JSON with Domain Entity
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/cached_entities_table.dart';
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
  factory PropertyListingModel.fromJson(Map<String, dynamic> json) {
    List<String> images = [];
    if (json['imageUrls'] is List) {
      images = (json['imageUrls'] as List).map((e) => e.toString()).toList();
    }

    List<String> amenities = [];
    if (json['amenities'] is List) {
      amenities = (json['amenities'] as List).map((e) => e.toString()).toList();
    }

    return PropertyListingModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled Property',
      description: json['description']?.toString() ?? '',
      category: RealEstateCategory.fromString(json['category']?.toString() ?? 'sale'),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      hourlyRate: (json['hourlyRate'] as num?)?.toDouble(),
      currency: json['currency']?.toString() ?? 'SLE',
      address: json['address']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      geohash: json['geohash']?.toString() ?? '',
      availabilityStatus: json['availabilityStatus']?.toString() ?? 'available',
      imageUrls: images,
      isFeatured: json['isFeatured'] == true,
      isVerified: json['isVerified'] != false,
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      bedrooms: (json['bedrooms'] as num?)?.toInt(),
      bathrooms: (json['bathrooms'] as num?)?.toInt(),
      areaSqM: (json['areaSqM'] as num?)?.toDouble(),
      amenities: amenities,
      ownerName: json['ownerName']?.toString() ?? 'Vektolux Verified Partner',
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
