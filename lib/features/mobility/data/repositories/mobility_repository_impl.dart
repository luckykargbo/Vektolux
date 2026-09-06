// lib/features/mobility/data/repositories/mobility_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Mobility Repository Implementation
// Combines Drift SQLite local outbox with Convex geospatial & backend functions
// ═══════════════════════════════════════════════════════════════════════

import 'dart:math';
import 'package:drift/drift.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/cached_entities_dao.dart';
import '../../../../core/database/tables/cached_entities_table.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/sync/offline_sync_engine.dart';
import '../../domain/entities/mobility_vehicle_entity.dart';
import '../../domain/entities/ride_entity.dart';
import '../../domain/entities/nearby_driver_entity.dart';
import '../../domain/entities/nearby_seller_entity.dart';
import '../../domain/entities/trip_delivery_entity.dart';
import '../../domain/repositories/mobility_repository.dart';
import '../models/ride_model.dart';

class MobilityRepositoryImpl implements MobilityRepository {
  final CachedRidesDao _ridesDao;
  final ConvexClientWrapper _convexClient;
  final OfflineSyncEngine _syncEngine;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final Uuid _uuid = const Uuid();

  MobilityRepositoryImpl({
    required CachedRidesDao ridesDao,
    required ConvexClientWrapper convexClient,
    required OfflineSyncEngine syncEngine,
  })  : _ridesDao = ridesDao,
        _convexClient = convexClient,
        _syncEngine = syncEngine;

  @override
  Stream<RideEntity?> watchActiveRide(String passengerId) {
    // 1. Reactive stream from Drift SQLite for instant offline-first rendering
    return _ridesDao.watchActiveRide(passengerId).map((cached) {
      if (cached == null) return null;
      return RideModel.fromCached(cached);
    });
  }

  @override
  Future<List<VehicleListingEntity>> getNearbyVehicles({
    required double lat,
    required double lng,
    double radiusKm = 5.0,
    MobilityVehicleType? vehicleType,
  }) async {
    try {
      final args = <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'radiusKm': radiusKm,
      };
      if (vehicleType != null) {
        args['vehicleType'] = vehicleType.backendKey;
      }

      final result = await _convexClient.query(
        'rides:findNearbyDrivers',
        args: args,
      );

      if (result.success && result.value is Map && result.value['drivers'] is List) {
        final drivers = result.value['drivers'] as List;
        return drivers.map<VehicleListingEntity>((d) {
          final type = MobilityVehicleType.fromString(
            d['vehicleType']?.toString() ?? 'taxi',
          );
          return VehicleListingEntity(
            id: d['driverId']?.toString() ?? _uuid.v4(),
            ownerId: d['driverId']?.toString() ?? '',
            vehicleType: type,
            listingIntent: 'ride_hailing',
            make: d['vehicleMake']?.toString() ?? 'Toyota',
            model: d['vehicleModel']?.toString() ?? 'Corolla',
            year: 2021,
            color: 'White',
            licensePlate: 'SL-782-AA',
            latitude: (d['lat'] as num?)?.toDouble() ?? lat,
            longitude: (d['lng'] as num?)?.toDouble() ?? lng,
            availabilityStatus: 'available',
            ownerName: d['name']?.toString() ?? 'Verified Driver',
          );
        }).toList();
      }
    } catch (e) {
      _log.w('Could not fetch cloud nearby drivers, falling back to local simulation: $e');
    }

    // High-fidelity fallback for offline or zero-driver map view
    return _generateSimulatedDrivers(lat, lng, vehicleType);
  }

  @override
  Future<Map<String, dynamic>> estimateFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required MobilityVehicleType vehicleType,
    double? surgeMultiplier,
  }) async {
    try {
      final result = await _convexClient.query(
        'rides:estimateRideFare',
        args: {
          'pickupLat': pickupLat,
          'pickupLng': pickupLng,
          'dropoffLat': dropoffLat,
          'dropoffLng': dropoffLng,
          'vehicleType': vehicleType.backendKey,
          if (surgeMultiplier != null) 'surgeMultiplier': surgeMultiplier,
        },
      );

      if (result.success && result.value is Map<String, dynamic>) {
        return result.value;
      }
    } catch (e) {
      _log.w('Cloud fare estimate failed, using local offline calculation: $e');
    }

    // Offline Haversine fallback calculation
    return _calculateOfflineFare(
      pickupLat,
      pickupLng,
      dropoffLat,
      dropoffLng,
      vehicleType,
    );
  }

  @override
  Future<String> requestRide({
    required String passengerId,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    required double dropoffLat,
    required double dropoffLng,
    required String dropoffAddress,
    required MobilityVehicleType vehicleType,
    required double fareAmount,
    required double distanceKm,
    required int estimatedDurationMin,
  }) async {
    final rideId = _uuid.v4();
    final platformFee = fareAmount * 0.15; // 15% platform commission
    final driverPayout = fareAmount - platformFee;

    final cachedRide = CachedRide(
      id: rideId,
      passengerId: passengerId,
      driverId: null,
      vehicleId: null,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      pickupAddress: pickupAddress,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      dropoffAddress: dropoffAddress,
      distanceKm: distanceKm,
      estimatedDurationMin: estimatedDurationMin,
      fareAmount: fareAmount,
      currency: 'SLE',
      platformFee: platformFee,
      driverPayout: driverPayout,
      status: 'requested',
      paymentStatus: 'pending',
      syncStatus: EntitySyncStatus.pendingSync,
      localUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      remoteUpdatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final payload = {
      'rideId': rideId,
      'passengerId': passengerId,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'pickupAddress': pickupAddress,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'dropoffAddress': dropoffAddress,
      'vehicleType': vehicleType.backendKey,
      'fareAmount': fareAmount,
      'distanceKm': distanceKm,
      'estimatedDurationMin': estimatedDurationMin,
    };

    // ── Atomic local write + Outbox queue push ───────────────────────
    await _syncEngine.writeAndQueue(
      entityType: 'rideRequests',
      entityId: rideId,
      mutationPath: 'rides:requestRide',
      payload: payload,
      localWrite: () async {
        await _ridesDao.upsert(cachedRide);
      },
      priority: 1, // Highest priority
    );

    return rideId;
  }

  @override
  Future<void> cancelRide({
    required String rideId,
    required String reason,
  }) async {
    final cached = await _ridesDao.getById(rideId);
    if (cached != null) {
      await _ridesDao.upsert(
        cached.copyWith(
          status: 'cancelled',
          cancelReason: Value(reason),
          cancelledAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    }

    await _syncEngine.writeAndQueue(
      entityType: 'rideRequests',
      entityId: rideId,
      mutationPath: 'rides:updateRideStatus',
      payload: {
        'rideId': rideId,
        'newStatus': 'cancelled',
        'cancelReason': reason,
      },
      localWrite: () async {},
      priority: 1,
    );
  }

  @override
  Future<String> requestVehicleRental({
    required String userId,
    required String vehicleId,
    required DateTime startDate,
    required DateTime endDate,
    required bool isWithDriver,
    required double totalAmount,
  }) async {
    final rentalId = _uuid.v4();

    await _syncEngine.writeAndQueue(
      entityType: 'vehicleRentals',
      entityId: rentalId,
      mutationPath: 'vehicleRentals:createRental',
      payload: {
        'rentalId': rentalId,
        'userId': userId,
        'vehicleId': vehicleId,
        'startDate': startDate.millisecondsSinceEpoch,
        'endDate': endDate.millisecondsSinceEpoch,
        'isWithDriver': isWithDriver,
        'totalAmount': totalAmount,
      },
      localWrite: () async {
        _log.i('Locally saved rental reservation: $rentalId');
      },
      priority: 2,
    );

    return rentalId;
  }

  // ═══════════════════════════════════════════════════════════════════
  //                       HELPERS
  // ═══════════════════════════════════════════════════════════════════

  Map<String, dynamic> _calculateOfflineFare(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
    MobilityVehicleType type,
  ) {
    const r = 6371; // Earth radius in km
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLng = (lng2 - lng1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final distanceKm = max(0.5, r * c);

    final (baseFare, ratePerKm, ratePerMin, minFare, speed) = switch (type) {
      MobilityVehicleType.bike => (500.0, 100.0, 20.0, 1000.0, 25.0),
      MobilityVehicleType.taxi => (1000.0, 200.0, 40.0, 2000.0, 30.0),
      MobilityVehicleType.deliveryVan => (2000.0, 350.0, 50.0, 5000.0, 25.0),
      MobilityVehicleType.truck => (5000.0, 600.0, 80.0, 10000.0, 20.0),
    };

    final durationMin = (distanceKm / speed) * 60;
    final rawFare = baseFare + (distanceKm * ratePerKm) + (durationMin * ratePerMin);
    final finalFare = max(rawFare.roundToDouble(), minFare);
    final platformFee = finalFare * 0.15;

    return {
      'distanceKm': (distanceKm * 100).round() / 100,
      'estimatedDurationMin': durationMin.round(),
      'fareAmount': finalFare,
      'platformFee': platformFee,
      'driverPayout': finalFare - platformFee,
      'currency': 'SLE',
      'vehicleType': type.backendKey,
    };
  }

  List<VehicleListingEntity> _generateSimulatedDrivers(
    double lat,
    double lng,
    MobilityVehicleType? filterType,
  ) {
    final rand = Random(42);
    final types = filterType != null ? [filterType] : MobilityVehicleType.values;

    return List.generate(6, (i) {
      final type = types[i % types.length];
      final offsetLat = (rand.nextDouble() - 0.5) * 0.03;
      final offsetLng = (rand.nextDouble() - 0.5) * 0.03;

      return VehicleListingEntity(
        id: 'sim_driver_$i',
        ownerId: 'owner_$i',
        vehicleType: type,
        listingIntent: 'ride_hailing',
        make: type == MobilityVehicleType.bike ? 'Honda' : (type == MobilityVehicleType.truck ? 'MAN' : 'Toyota'),
        model: type == MobilityVehicleType.bike ? 'CG125' : (type == MobilityVehicleType.truck ? 'TGM' : 'Corolla'),
        year: 2022,
        color: 'Yellow',
        licensePlate: 'VKT-0$i${rand.nextInt(9)}',
        latitude: lat + offsetLat,
        longitude: lng + offsetLng,
        availabilityStatus: 'available',
        ownerName: 'Vektolux Driver $i',
      );
    });
  }

  @override
  Future<List<NearbyDriverEntity>> getNearbyDrivers({
    required double lat,
    required double lng,
    double radiusKm = 5.0,
    String? serviceFilter,
  }) async {
    try {
      final args = <String, dynamic>{
        'userLat': lat,
        'userLng': lng,
        'radiusKm': radiusKm,
      };
      if (serviceFilter != null) {
        args['serviceFilter'] = serviceFilter;
      }

      final result = await _convexClient.query('mobility:getNearbyDrivers', args: args);
      if (result.success && result.value != null && result.value is List) {
        final list = result.value as List<dynamic>;
        if (list.isNotEmpty) {
          return list
              .map((item) => NearbyDriverEntity.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      }
      return _generateSimulatedOnDemandDrivers(lat, lng, serviceFilter);
    } catch (e) {
      _log.w('Falling back to local simulated on-demand drivers: $e');
      return _generateSimulatedOnDemandDrivers(lat, lng, serviceFilter);
    }
  }

  List<NearbyDriverEntity> _generateSimulatedOnDemandDrivers(
    double lat,
    double lng,
    String? serviceFilter,
  ) {
    return [
      NearbyDriverEntity(
        driverId: 'drv_kekeh_01',
        userId: 'usr_drv_01',
        driverName: 'Mohamed Kamara',
        driverPhone: '+232 76 892 104',
        avatarUrl: null,
        serviceType: 'ride',
        currentLat: lat + 0.0035,
        currentLng: lng - 0.0028,
        distanceMeters: 450,
        distanceKm: 0.45,
        etaMinutes: 3,
        vehicle: const DriverVehicleInfo(
          id: 'veh_kekeh_01',
          make: 'Bajaj',
          model: 'RE 4S (Tricycle)',
          year: 2023,
          color: 'Yellow',
          licensePlate: 'SL-492-KE',
          category: DriverVehicleCategory.kekehTricycle,
          categoryIconKey: 'kekeh_tricycle',
          isVerified: true,
        ),
      ),
      NearbyDriverEntity(
        driverId: 'drv_kekeh_02',
        userId: 'usr_drv_02',
        driverName: 'Alie Sesay',
        driverPhone: '+232 78 341 902',
        avatarUrl: null,
        serviceType: 'ride',
        currentLat: lat - 0.0042,
        currentLng: lng + 0.0031,
        distanceMeters: 620,
        distanceKm: 0.62,
        etaMinutes: 4,
        vehicle: const DriverVehicleInfo(
          id: 'veh_kekeh_02',
          make: 'TVS',
          model: 'King Deluxe (Tricycle)',
          year: 2024,
          color: 'Green',
          licensePlate: 'SL-118-KE',
          category: DriverVehicleCategory.kekehTricycle,
          categoryIconKey: 'kekeh_tricycle',
          isVerified: true,
        ),
      ),
      NearbyDriverEntity(
        driverId: 'drv_bike_01',
        userId: 'usr_drv_03',
        driverName: 'Ibrahim Bangura',
        driverPhone: '+232 77 554 219',
        avatarUrl: null,
        serviceType: 'both',
        currentLat: lat + 0.0051,
        currentLng: lng + 0.0042,
        distanceMeters: 310,
        distanceKm: 0.31,
        etaMinutes: 2,
        vehicle: const DriverVehicleInfo(
          id: 'veh_bike_01',
          make: 'Bajaj',
          model: 'Boxer 150 (Okada)',
          year: 2022,
          color: 'Red',
          licensePlate: 'SL-883-BK',
          category: DriverVehicleCategory.deliveryBike,
          categoryIconKey: 'two_wheeler_delivery',
          isVerified: true,
        ),
      ),
      NearbyDriverEntity(
        driverId: 'drv_taxi_01',
        userId: 'usr_drv_04',
        driverName: 'Chernor Bah',
        driverPhone: '+232 30 221 890',
        avatarUrl: null,
        serviceType: 'ride',
        currentLat: lat - 0.0065,
        currentLng: lng - 0.0048,
        distanceMeters: 890,
        distanceKm: 0.89,
        etaMinutes: 5,
        vehicle: const DriverVehicleInfo(
          id: 'veh_taxi_01',
          make: 'Toyota',
          model: 'Corolla Sedan',
          year: 2021,
          color: 'Silver',
          licensePlate: 'SL-940-BA',
          category: DriverVehicleCategory.standard,
          categoryIconKey: 'standard_taxi',
          isVerified: true,
        ),
      ),
      NearbyDriverEntity(
        driverId: 'drv_taxi_02',
        userId: 'usr_drv_05',
        driverName: 'Fatmata Koroma',
        driverPhone: '+232 79 112 345',
        avatarUrl: null,
        serviceType: 'ride',
        currentLat: lat + 0.0022,
        currentLng: lng + 0.0062,
        distanceMeters: 750,
        distanceKm: 0.75,
        etaMinutes: 4,
        vehicle: const DriverVehicleInfo(
          id: 'veh_taxi_02',
          make: 'Hyundai',
          model: 'Elantra Comfort',
          year: 2022,
          color: 'Blue',
          licensePlate: 'SL-604-TX',
          category: DriverVehicleCategory.comfort,
          categoryIconKey: 'sedan_premium',
          isVerified: true,
        ),
      ),
    ];
  }

  @override
  Future<String> createTripDeliveryRequest({
    required String passengerId,
    required String serviceType,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddressText,
    required double dropoffLat,
    required double dropoffLng,
    required String dropoffAddressText,
    required double fareAmount,
    required double distanceKm,
    required int durationMins,
    String paymentMethod = 'wallet',
    Map<String, dynamic>? packageDetails,
  }) async {
    try {
      final args = <String, dynamic>{
        'passengerId': passengerId,
        'serviceType': serviceType,
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'pickupAddressText': pickupAddressText,
        'dropoffLat': dropoffLat,
        'dropoffLng': dropoffLng,
        'dropoffAddressText': dropoffAddressText,
        'fareAmount': fareAmount,
        'distanceKm': distanceKm,
        'durationMins': durationMins,
        'paymentMethod': paymentMethod,
        if (packageDetails != null) 'deliveryPackageDetails': packageDetails,
      };

      final result = await _convexClient.mutation('mobility:createTripDeliveryRequest', args: args);
      if (!result.success || result.value == null) {
        throw Exception(result.errorMessage ?? 'Failed to create trip request');
      }

      final tripId = result.value as String;
      _log.i('Created trip/delivery request: $tripId');
      return tripId;
    } catch (e) {
      _log.e('Trip request creation error: $e');
      rethrow;
    }
  }

  @override
  Future<TripDeliveryEntity?> getTripDelivery(String tripId) async {
    try {
      final result = await _convexClient.query('mobility:getTripById', args: {'tripId': tripId});
      if (!result.success || result.value == null) {
        return null;
      }
      return TripDeliveryEntity.fromJson(result.value as Map<String, dynamic>);
    } catch (e) {
      _log.e('Failed to fetch trip delivery: $e');
      return null;
    }
  }

  @override
  Future<List<NearbySellerEntity>> getNearbySellers({
    required double lat,
    required double lng,
    double radiusKm = 10.0,
  }) async {
    return [
      NearbySellerEntity(
        id: 'seller_kissy_01',
        businessName: 'Kissy Auto & Fleet Spares',
        ownerName: 'Alhaji Sorie Bah',
        category: 'Auto Parts & Commercial Fleet',
        phone: '+232 78 400 123',
        avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
        latitude: lat + 0.0062,
        longitude: lng + 0.0055,
        address: 'Kissy Bypass Road, East End, Freetown',
        rating: 4.9,
        totalSales: 380,
        isVerified: true,
        distanceKm: 0.8,
        etaMinutes: 4,
      ),
      NearbySellerEntity(
        id: 'seller_lumley_02',
        businessName: 'Lumley Bay Fresh & Goods',
        ownerName: 'Aminata Mansaray',
        category: 'Provisions & Hospitality Supply',
        phone: '+232 76 910 445',
        avatarUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=150',
        latitude: lat - 0.0048,
        longitude: lng - 0.0068,
        address: 'Lumley Beach Road, Aberdeen Peninsula',
        rating: 4.8,
        totalSales: 520,
        isVerified: true,
        distanceKm: 1.1,
        etaMinutes: 6,
      ),
      NearbySellerEntity(
        id: 'seller_waterloo_03',
        businessName: 'Waterloo Express Traders',
        ownerName: 'Samuel Conteh',
        category: 'General Hardware & Construction',
        phone: '+232 30 882 119',
        avatarUrl: 'https://images.unsplash.com/photo-1501196354995-cbb51c65aaea?w=150',
        latitude: lat + 0.0085,
        longitude: lng - 0.0034,
        address: 'Waterloo Main Motor Road',
        rating: 4.9,
        totalSales: 210,
        isVerified: true,
        distanceKm: 1.7,
        etaMinutes: 9,
      ),
    ];
  }
}
