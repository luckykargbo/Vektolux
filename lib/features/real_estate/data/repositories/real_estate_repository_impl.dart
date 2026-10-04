// lib/features/real_estate/data/repositories/real_estate_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Repository Implementation
// 100% Direct Convex Cloud integration for real estate listings and tours.
// ═══════════════════════════════════════════════════════════════════════

import 'package:logger/logger.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../domain/entities/property_listing_entity.dart';
import '../../domain/repositories/real_estate_repository.dart';
import '../models/property_listing_model.dart';

class RealEstateRepositoryImpl implements RealEstateRepository {
  final ConvexClientWrapper _convexClient;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  // In-memory cache for locally booked slots during session to prevent double-booking
  final Map<String, Set<String>> _localBookedSlotsMap = {};

  RealEstateRepositoryImpl({
    required ConvexClientWrapper convexClient,
  }) : _convexClient = convexClient;

  @override
  Stream<PropertyListingEntity?> watchListing(String id) {
    return _convexClient
        .subscribe('realEstate:getPropertyById', args: {'propertyId': id})
        .map((val) {
      if (val != null && val is Map<String, dynamic>) {
        return PropertyListingModel.fromJson(val);
      }
      return null;
    });
  }

  @override
  Future<PropertyListingEntity?> getListing(String id) async {
    try {
      final result = await _convexClient.query(
        'realEstate:getPropertyById',
        args: {'propertyId': id},
      );
      if (result.success && result.value is Map<String, dynamic>) {
        return PropertyListingModel.fromJson(result.value);
      }
    } catch (e) {
      _log.e('Cloud fetch error for listing $id: $e');
    }
    return null;
  }

  @override
  Future<List<String>> getBookedSlotsForDate(String listingId, DateTime date) async {
    final dateKey = '${listingId}_${date.year}_${date.month}_${date.day}';
    final Set<String> bookedSlots = Set.from(_localBookedSlotsMap[dateKey] ?? {});

    try {
      final startOfDay = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch;

      final result = await _convexClient.query(
        'bookings:getUserBookings',
        args: {
          'listingId': listingId,
          'startTime': startOfDay,
          'endTime': endOfDay,
        },
      );

      if (result.success && result.value is List) {
        for (final item in result.value) {
          if (item is Map && item['notes'] != null) {
            final slotLabel = item['notes'].toString();
            if (slotLabel.isNotEmpty) {
              bookedSlots.add(slotLabel);
            }
          }
        }
      }
    } catch (e) {
      _log.w('Could not fetch cloud booked slots: $e');
    }

    return bookedSlots.toList();
  }

  @override
  Future<String> scheduleSiteVisit({
    required String listingId,
    required String buyerId,
    required String ownerId,
    required DateTime date,
    required String timeSlotLabel,
    String? notes,
  }) async {
    final dateKey = '${listingId}_${date.year}_${date.month}_${date.day}';
    final startOfDay = DateTime(date.year, date.month, date.day, 9).millisecondsSinceEpoch;
    final endOfDay = DateTime(date.year, date.month, date.day, 17).millisecondsSinceEpoch;

    // The server decides the vendor (the listing owner), the price and the status.
    final result = await _convexClient.mutation(
      'bookings:createBooking',
      args: {
        'listingId': listingId,
        'listingType': 'property',
        'listingTitle': 'Property Inspection Tour',
        'buyerId': buyerId,
        'bookingType': 'property_inspection',
        'startTime': startOfDay,
        'endTime': endOfDay,
        'notes': notes != null ? '$timeSlotLabel - $notes' : timeSlotLabel,
      },
    );
    final value = result.value;
    if (!result.success || value is! Map || value['bookingId'] == null) {
      throw Exception(result.errorMessage ?? 'The viewing request could not be sent.');
    }
    _localBookedSlotsMap.putIfAbsent(dateKey, () => {}).add(timeSlotLabel);
    return value['bookingId'].toString();
  }

  @override
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
  }) async {
    final endTime = startTime.add(Duration(hours: durationHours));

    // Creates a REAL booking. The server prices it from the listing (the client total is not
    // sent) and returns it awaiting payment; it is paid from the wallet or by Mobile Money,
    // and the vendor/platform split is decided by the server.
    final result = await _convexClient.mutation(
      'bookings:createBooking',
      args: {
        'listingId': listingId,
        'listingType': 'property',
        'listingTitle': 'Hourly Stay Reservation',
        'buyerId': buyerId,
        'bookingType': 'hourly_guesthouse',
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime.millisecondsSinceEpoch,
        'hours': durationHours,
      },
    );
    final value = result.value;
    if (!result.success || value is! Map || value['bookingId'] == null) {
      throw Exception(result.errorMessage ?? 'The booking could not be created.');
    }
    return {
      'bookingId': value['bookingId'].toString(),
      'reference': value['txRef']?.toString() ?? '',
      'status': value['status']?.toString() ?? '',
      'paymentStatus': value['paymentStatus']?.toString() ?? '',
      'totalAmount': value['totalAmount'],
      'currency': currency,
    };
  }
}
