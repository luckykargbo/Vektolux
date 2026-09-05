// lib/features/real_estate/domain/entities/property_listing_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Listing Domain Entity
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

/// Real estate category enum.
enum RealEstateCategory {
  sale,
  longTermRent,
  hourlyGuestHouse;

  static RealEstateCategory fromString(String val) {
    return switch (val.toLowerCase()) {
      'sale' => RealEstateCategory.sale,
      'long_term_rent' || 'longtermrent' || 'rent' =>
        RealEstateCategory.longTermRent,
      'hourly_guesthouse' || 'hourlyguesthouse' || 'guesthouse' =>
        RealEstateCategory.hourlyGuestHouse,
      _ => RealEstateCategory.sale,
    };
  }

  String get displayName => switch (this) {
        RealEstateCategory.sale => 'For Sale',
        RealEstateCategory.longTermRent => 'Long-Term Rent',
        RealEstateCategory.hourlyGuestHouse => 'Hourly Guest House',
      };
}

/// Core domain entity representing a real estate property.
class PropertyListingEntity extends Equatable {
  final String id;
  final String ownerId;
  final String title;
  final String description;
  final RealEstateCategory category;
  final double price;
  final double? hourlyRate;
  final String currency;
  final String address;
  final String city;
  final String country;
  final double latitude;
  final double longitude;
  final String geohash;
  final String availabilityStatus;
  final List<String> imageUrls;
  final bool isFeatured;
  final bool isVerified;
  final int viewCount;
  final int? bedrooms;
  final int? bathrooms;
  final double? areaSqM;
  final List<String> amenities;
  final String? ownerName;
  final String? ownerPhone;
  final String? ownerAvatarUrl;

  const PropertyListingEntity({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    required this.category,
    required this.price,
    this.hourlyRate,
    this.currency = 'SLE',
    required this.address,
    required this.city,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.availabilityStatus,
    this.imageUrls = const [],
    this.isFeatured = false,
    this.isVerified = true,
    this.viewCount = 0,
    this.bedrooms,
    this.bathrooms,
    this.areaSqM,
    this.amenities = const [],
    this.ownerName,
    this.ownerPhone,
    this.ownerAvatarUrl,
  });

  /// Check if the property offers hourly stays.
  bool get isHourlyStay => category == RealEstateCategory.hourlyGuestHouse;

  /// Check if property requires site visits before purchase/lease.
  bool get isSiteVisitApplicable =>
      category == RealEstateCategory.sale ||
      category == RealEstateCategory.longTermRent;

  /// Effective hourly rate (falls back to price / 24 if not specified).
  double get effectiveHourlyRate => hourlyRate ?? (price > 0 ? price / 24 : 50.0);

  @override
  List<Object?> get props => [
        id,
        ownerId,
        title,
        description,
        category,
        price,
        hourlyRate,
        currency,
        address,
        city,
        country,
        latitude,
        longitude,
        geohash,
        availabilityStatus,
        imageUrls,
        isFeatured,
        isVerified,
        viewCount,
        bedrooms,
        bathrooms,
        areaSqM,
        amenities,
        ownerName,
        ownerPhone,
        ownerAvatarUrl,
      ];
}
