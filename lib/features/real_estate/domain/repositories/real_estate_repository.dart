// lib/features/real_estate/domain/repositories/real_estate_repository.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Repository Interface
// ═══════════════════════════════════════════════════════════════════════

import '../entities/property_listing_entity.dart';

abstract class RealEstateRepository {
  /// Stream single listing from local SQLite database (reactive & instant).
  Stream<PropertyListingEntity?> watchListing(String id);

  /// Fetch single listing from local cache or cloud fallback.
  Future<PropertyListingEntity?> getListing(String id);

  /// Fetch booked slot labels for a specific listing and calendar date
  /// to prevent double-booking.
  Future<List<String>> getBookedSlotsForDate(String listingId, DateTime date);

  /// Schedule an on-site property inspection (offline-first write).
  Future<String> scheduleSiteVisit({
    required String listingId,
    required String buyerId,
    required String ownerId,
    required DateTime date,
    required String timeSlotLabel,
    String? notes,
  });

  /// Instant book an hourly stay and initialize payment gateway flow.
  Future<Map<String, dynamic>> initiateInstantHourlyBooking({
    required String listingId,
    required String buyerId,
    required String ownerId,
    required DateTime startTime,
    required int durationHours,
    required double totalAmount,
    required String currency,
    required String paymentMethod,
    required String gatewayProvider,
    required String customerEmail,
    String? customerPhone,
    String? customerName,
  });
}
