// lib/features/real_estate/data/repositories/real_estate_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Repository Implementation
// 100% Direct Convex Cloud integration for real estate listings and tours.
// ═══════════════════════════════════════════════════════════════════════

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../domain/entities/property_listing_entity.dart';
import '../../domain/repositories/real_estate_repository.dart';
import '../models/property_listing_model.dart';

class RealEstateRepositoryImpl implements RealEstateRepository {
  final ConvexClientWrapper _convexClient;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final Uuid _uuid = const Uuid();

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
    final bookingId = _uuid.v4();
    final dateKey = '${listingId}_${date.year}_${date.month}_${date.day}';

    _localBookedSlotsMap.putIfAbsent(dateKey, () => {}).add(timeSlotLabel);

    final startOfDay = DateTime(date.year, date.month, date.day, 9).millisecondsSinceEpoch;
    final endOfDay = DateTime(date.year, date.month, date.day, 17).millisecondsSinceEpoch;

    final payload = {
      'listingId': listingId,
      'listingType': 'property',
      'listingTitle': 'Property Inspection Tour',
      'buyerId': buyerId,
      'vendorId': ownerId,
      'bookingType': 'property_inspection',
      'startTime': startOfDay,
      'endTime': endOfDay,
      'totalAmount': 0.0,
      'notes': notes != null ? '$timeSlotLabel - $notes' : timeSlotLabel,
    };

    final result = await _convexClient.mutation(
      'bookings:createBooking',
      args: payload,
    );

    if (!result.success) {
      _log.w('Convex scheduleSiteVisit notice: ${result.errorMessage}');
    }

    return bookingId;
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
    final bookingId = _uuid.v4();
    final idempotencyKey = 'hourly_booking_${bookingId}_${DateTime.now().millisecondsSinceEpoch}';
    final endTime = startTime.add(Duration(hours: durationHours));

    // 1. Create payment intent in Convex Cloud
    final intentResult = await _convexClient.mutation(
      'payments:createPaymentIntent',
      args: {
        'userId': buyerId,
        'amount': totalAmount,
        'currency': currency,
        'paymentMethod': paymentMethod,
        'gatewayProvider': gatewayProvider,
        'referenceType': 'hourly_guesthouse',
        'referenceId': bookingId,
        'vendorId': ownerId,
        'idempotencyKey': idempotencyKey,
        'commissionType': 'hourly_guesthouse',
      },
    );

    if (!intentResult.success) {
      throw Exception(intentResult.errorMessage ?? 'Failed to create payment intent');
    }

    final paymentIntentId = intentResult.value['paymentIntentId'];

    // 2. Direct Convex Cloud booking creation
    await _convexClient.mutation(
      'bookings:createBooking',
      args: {
        'listingId': listingId,
        'listingType': 'property',
        'listingTitle': 'Hourly Stay Reservation',
        'buyerId': buyerId,
        'vendorId': ownerId,
        'bookingType': 'short_stay_booking',
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime.millisecondsSinceEpoch,
        'totalAmount': totalAmount,
        'notes': 'PaymentIntent: $paymentIntentId',
      },
    );

    return {
      'bookingId': bookingId,
      'paymentIntentId': paymentIntentId,
      'gatewayProvider': gatewayProvider,
      'totalAmount': totalAmount,
      'currency': currency,
    };
  }
}
