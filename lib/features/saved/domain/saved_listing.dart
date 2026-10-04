// lib/features/saved/domain/saved_listing.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — A listing the signed-in user saved (savedListings:getMySavedListings).
// Parsed from the server only. A listing that is no longer public is returned WITHOUT details
// (`available == false`) so it can be removed; nothing private is ever part of a saved card.
// ═══════════════════════════════════════════════════════════════════════

import 'package:intl/intl.dart';

final NumberFormat _money = NumberFormat('#,##0', 'en_US');

String _s(dynamic v, [String f = '']) => v == null ? f : v.toString();
String? _os(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

class SavedListing {
  /// property | vehicle
  final String listingType;
  final String listingId;
  final int savedAt;

  /// False when the listing is no longer public (removed, unpublished, under review …).
  final bool available;
  final String title;
  final String? category;
  final num price;
  final num? hourlyRate;
  final String currency;
  final String location;
  final String? imageUrl;
  final int? bedrooms;
  final int? bathrooms;
  final num? areaSqM;
  final String ownerId;

  const SavedListing({
    required this.listingType,
    required this.listingId,
    this.savedAt = 0,
    this.available = true,
    this.title = 'Listing',
    this.category,
    this.price = 0,
    this.hourlyRate,
    this.currency = 'SLE',
    this.location = 'Sierra Leone',
    this.imageUrl,
    this.bedrooms,
    this.bathrooms,
    this.areaSqM,
    this.ownerId = '',
  });

  factory SavedListing.fromMap(Map<String, dynamic> m) => SavedListing(
        listingType: _s(m['listingType'], 'property'),
        listingId: _s(m['listingId']),
        savedAt: m['savedAt'] is num ? (m['savedAt'] as num).toInt() : 0,
        available: m['available'] == true,
        title: _s(m['title'], 'Listing'),
        category: _os(m['category']),
        price: m['price'] is num ? m['price'] as num : 0,
        hourlyRate: m['hourlyRate'] is num ? m['hourlyRate'] as num : null,
        currency: _s(m['currency'], 'SLE'),
        location: _s(m['location'], 'Sierra Leone'),
        imageUrl: _os(m['imageUrl']),
        bedrooms: m['bedrooms'] is num ? (m['bedrooms'] as num).toInt() : null,
        bathrooms: m['bathrooms'] is num ? (m['bathrooms'] as num).toInt() : null,
        areaSqM: m['areaSqM'] is num ? m['areaSqM'] as num : null,
        ownerId: _s(m['ownerId']),
      );

  bool get isProperty => listingType == 'property';

  String get tag => switch (category) {
        'sale' => 'For Sale',
        'long_term_rent' => 'For Rent',
        'hourly_guesthouse' => 'Short Stay',
        _ => '',
      };

  String get priceLabel {
    final rate = hourlyRate;
    if (category == 'hourly_guesthouse' && rate != null && rate > 0) return '$currency ${_money.format(rate)} / hr';
    if (price <= 0) return 'Price on request';
    if (category == 'long_term_rent') return '$currency ${_money.format(price)} / year';
    return '$currency ${_money.format(price)}';
  }
}
