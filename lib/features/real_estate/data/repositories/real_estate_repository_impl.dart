// lib/features/real_estate/data/repositories/real_estate_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Repository Implementation
// Combines local SQLite persistence (Drift) with Convex serverless backend
// ═══════════════════════════════════════════════════════════════════════

import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/daos/cached_entities_dao.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/sync/offline_sync_engine.dart';
import '../../domain/entities/property_listing_entity.dart';
import '../../domain/repositories/real_estate_repository.dart';
import '../models/property_listing_model.dart';

class RealEstateRepositoryImpl implements RealEstateRepository {
  final CachedPropertiesDao _propertiesDao;
  final ConvexClientWrapper _convexClient;
  final OfflineSyncEngine _syncEngine;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final Uuid _uuid = const Uuid();

  // In-memory cache for locally booked slots during session to prevent double-booking
  final Map<String, Set<String>> _localBookedSlotsMap = {};

  RealEstateRepositoryImpl({
    required CachedPropertiesDao propertiesDao,
    required ConvexClientWrapper convexClient,
    required OfflineSyncEngine syncEngine,
  })  : _propertiesDao = propertiesDao,
        _convexClient = convexClient,
        _syncEngine = syncEngine;

  @override
  Stream<PropertyListingEntity?> watchListing(String id) {
    // 1. Instantly stream local SQLite cache
    return _propertiesDao.watchById(id).asyncMap((cached) async {
      if (cached != null) {
        return PropertyListingModel.fromCached(cached);
      }

      // If not present in local SQLite yet, trigger a background fetch
      try {
        final result = await _convexClient.query(
          'realEstateListings:getListing',
          args: {'listingId': id},
        );
        if (result.success && result.value is Map<String, dynamic>) {
          final model = PropertyListingModel.fromJson(result.value);
          await _propertiesDao.upsert(model.toCached());
          return model;
        }
      } catch (e) {
        _log.e('Background fetch failed for listing $id: $e');
      }
      return null;
    });
  }

  @override
  Future<PropertyListingEntity?> getListing(String id) async {
    // Check local SQLite first
    final cached = await _propertiesDao.getById(id);
    if (cached != null) {
      return PropertyListingModel.fromCached(cached);
    }

    // Fetch from Convex cloud if absent locally
    try {
      final result = await _convexClient.query(
        'realEstateListings:getListing',
        args: {'listingId': id},
      );
      if (result.success && result.value is Map<String, dynamic>) {
        final model = PropertyListingModel.fromJson(result.value);
        await _propertiesDao.upsert(model.toCached());
        return model;
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
      // Query Convex for cloud bookings on this date
      final startOfDay = DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59).millisecondsSinceEpoch;

      final result = await _convexClient.query(
        'realEstateBookings:getBookingsByListingAndTime',
        args: {
          'listingId': listingId,
          'startTime': startOfDay,
          'endTime': endOfDay,
        },
      );

      if (result.success && result.value is List) {
        for (final item in result.value) {
          if (item is Map && item['notes'] != null) {
            // Check slot label stored in notes or metadata
            final slotLabel = item['notes'].toString();
            if (slotLabel.isNotEmpty) {
              bookedSlots.add(slotLabel);
            }
          }
        }
      }
    } catch (e) {
      _log.w('Could not fetch cloud booked slots (offline mode): $e');
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

    // 1. Immediately mark slot locally to prevent double booking
    _localBookedSlotsMap.putIfAbsent(dateKey, () => {}).add(timeSlotLabel);

    // Calculate approximate start and end timestamps
    final startOfDay = DateTime(date.year, date.month, date.day, 9).millisecondsSinceEpoch;
    final endOfDay = DateTime(date.year, date.month, date.day, 17).millisecondsSinceEpoch;

    final payload = {
      'bookingId': bookingId,
      'listingId': listingId,
      'buyerId': buyerId,
      'ownerId': ownerId,
      'bookingType': 'inspection',
      'startTime': startOfDay,
      'endTime': endOfDay,
      'totalAmount': 0.0, // Inspections are complimentary or low-fee
      'platformFee': 0.0,
      'currency': 'SLE',
      'paymentStatus': 'completed',
      'notes': timeSlotLabel,
    };

    // 2. Write to local outbox queue for transactional offline-first push
    await _syncEngine.writeAndQueue(
      entityType: 'realEstateBookings',
      entityId: bookingId,
      mutationPath: 'realEstateBookings:createBooking',
      payload: payload,
      localWrite: () async {
        _log.i('Locally reserved site visit slot: $timeSlotLabel on $date');
      },
      priority: 2,
    );

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

    // 1. Create payment intent in Convex
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

    // 2. Call HTTP action /payments/initialize for Flutterwave/Paystack checkout URL
    final initPayload = {
      'paymentIntentId': paymentIntentId,
      'customerEmail': customerEmail,
      'customerPhone': customerPhone ?? '',
      'customerName': customerName ?? 'Vektolux Guest',
      'redirectUrl': 'https://app.vektolux.com/payment/callback',
      'mobileMoneyProvider': paymentMethod == 'mobile_money' ? 'orange_money' : null,
    };

    final httpResponse = await _convexClient.action(
      'http:initializePayment',
      args: initPayload,
    );

    // Also queue local booking reservation
    await _syncEngine.writeAndQueue(
      entityType: 'realEstateBookings',
      entityId: bookingId,
      mutationPath: 'realEstateBookings:createBooking',
      payload: {
        'bookingId': bookingId,
        'listingId': listingId,
        'buyerId': buyerId,
        'ownerId': ownerId,
        'bookingType': 'instant_stay',
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime.millisecondsSinceEpoch,
        'totalAmount': totalAmount,
        'platformFee': totalAmount * 0.10, // 10% commission
        'currency': currency,
        'paymentStatus': 'pending',
        'paymentReference': paymentIntentId,
      },
      localWrite: () async {
        _log.i('Locally saved pending hourly guest house booking $bookingId');
      },
      priority: 1,
    );

    return {
      'bookingId': bookingId,
      'paymentIntentId': paymentIntentId,
      'paymentLink': httpResponse.value?['paymentLink'] ?? '',
      'reference': httpResponse.value?['reference'] ?? bookingId,
      'gatewayProvider': gatewayProvider,
      'totalAmount': totalAmount,
      'currency': currency,
    };
  }
}
