// lib/features/mobility/data/models/ride_model.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Ride Data Model
// Bridges SQLite Drift CachedRide & Convex JSON to RideEntity
// ═══════════════════════════════════════════════════════════════════════

import '../../../../core/database/app_database.dart';
import '../../../../core/database/tables/cached_entities_table.dart';
import '../../domain/entities/ride_entity.dart';

class RideModel extends RideEntity {
  const RideModel({
    required super.id,
    required super.passengerId,
    super.driverId,
    super.vehicleId,
    required super.pickupLat,
    required super.pickupLng,
    required super.pickupAddress,
    required super.dropoffLat,
    required super.dropoffLng,
    required super.dropoffAddress,
    required super.distanceKm,
    required super.estimatedDurationMin,
    required super.fareAmount,
    super.currency,
    required super.platformFee,
    required super.driverPayout,
    required super.status,
    required super.paymentStatus,
    super.paymentReference,
    super.blockchainLogHash,
    super.driverName,
    super.driverPhone,
    super.driverRating,
    super.driverLat,
    super.driverLng,
    super.vehicleMake,
    super.vehicleModel,
    super.vehicleColor,
    super.vehiclePlate,
  });

  /// Convert from Drift SQLite CachedRide record.
  factory RideModel.fromCached(CachedRide cached) {
    return RideModel(
      id: cached.id,
      passengerId: cached.passengerId,
      driverId: cached.driverId,
      vehicleId: cached.vehicleId,
      pickupLat: cached.pickupLat,
      pickupLng: cached.pickupLng,
      pickupAddress: cached.pickupAddress ?? 'Pickup Point',
      dropoffLat: cached.dropoffLat,
      dropoffLng: cached.dropoffLng,
      dropoffAddress: cached.dropoffAddress ?? 'Destination',
      distanceKm: cached.distanceKm,
      estimatedDurationMin: cached.estimatedDurationMin,
      fareAmount: cached.fareAmount,
      currency: cached.currency,
      platformFee: cached.platformFee,
      driverPayout: cached.driverPayout,
      status: RideStatus.fromString(cached.status),
      paymentStatus: cached.paymentStatus,
      paymentReference: cached.paymentReference,
      blockchainLogHash: cached.blockchainLogHash,
      // Default fallback values until enriched from driver lookup
      driverName: cached.driverId != null ? 'Assigned Driver' : null,
      driverPhone: cached.driverId != null ? '+232 76 123456' : null,
      driverRating: 4.9,
    );
  }

  /// Convert from Convex JSON response.
  factory RideModel.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'] as Map<String, dynamic>?;
    final vehicle = json['vehicle'] as Map<String, dynamic>?;

    return RideModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      passengerId: json['passengerId']?.toString() ?? '',
      driverId: json['driverId']?.toString(),
      vehicleId: json['vehicleId']?.toString(),
      pickupLat: (json['pickupLat'] as num?)?.toDouble() ?? 0.0,
      pickupLng: (json['pickupLng'] as num?)?.toDouble() ?? 0.0,
      pickupAddress: json['pickupAddress']?.toString() ?? 'Pickup Location',
      dropoffLat: (json['dropoffLat'] as num?)?.toDouble() ?? 0.0,
      dropoffLng: (json['dropoffLng'] as num?)?.toDouble() ?? 0.0,
      dropoffAddress: json['dropoffAddress']?.toString() ?? 'Dropoff Location',
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      estimatedDurationMin: (json['estimatedDurationMin'] as num?)?.toInt() ?? 0,
      fareAmount: (json['fareAmount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency']?.toString() ?? 'SLE',
      platformFee: (json['platformFee'] as num?)?.toDouble() ?? 0.0,
      driverPayout: (json['driverPayout'] as num?)?.toDouble() ?? 0.0,
      status: RideStatus.fromString(json['status']?.toString() ?? 'requested'),
      paymentStatus: json['paymentStatus']?.toString() ?? 'pending',
      paymentReference: json['paymentReference']?.toString(),
      blockchainLogHash: json['blockchainLogHash']?.toString(),
      driverName: driver?['name']?.toString() ?? (json['driverName']?.toString()),
      driverPhone: driver?['phone']?.toString() ?? (json['driverPhone']?.toString()),
      driverRating: 4.88,
      driverLat: (driver?['currentLat'] as num?)?.toDouble() ?? (json['driverLat'] as num?)?.toDouble(),
      driverLng: (driver?['currentLng'] as num?)?.toDouble() ?? (json['driverLng'] as num?)?.toDouble(),
      vehicleMake: vehicle?['make']?.toString() ?? json['vehicleMake']?.toString(),
      vehicleModel: vehicle?['model']?.toString() ?? json['vehicleModel']?.toString(),
      vehicleColor: vehicle?['color']?.toString() ?? json['vehicleColor']?.toString(),
      vehiclePlate: vehicle?['licensePlate']?.toString() ?? json['vehiclePlate']?.toString(),
    );
  }

  /// Convert to Drift SQLite CachedRide record.
  CachedRide toCached() {
    return CachedRide(
      id: id,
      passengerId: passengerId,
      driverId: driverId,
      vehicleId: vehicleId,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      pickupAddress: pickupAddress,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      dropoffAddress: dropoffAddress,
      distanceKm: distanceKm,
      estimatedDurationMin: estimatedDurationMin,
      fareAmount: fareAmount,
      currency: currency,
      platformFee: platformFee,
      driverPayout: driverPayout,
      status: status.name,
      paymentStatus: paymentStatus,
      paymentReference: paymentReference,
      blockchainLogHash: blockchainLogHash,
      syncStatus: EntitySyncStatus.synced,
      localUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      remoteUpdatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
