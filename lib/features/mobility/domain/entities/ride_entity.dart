// lib/features/mobility/domain/entities/ride_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Ride Domain Entity
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

/// Ride lifecycle status enum.
enum RideStatus {
  requested,
  accepted,
  driverArriving,
  arrived,
  inTransit,
  completed,
  cancelled;

  static RideStatus fromString(String val) {
    return switch (val.toLowerCase()) {
      'requested' => RideStatus.requested,
      'accepted' => RideStatus.accepted,
      'driver_arriving' || 'driverarriving' => RideStatus.driverArriving,
      'arrived' => RideStatus.arrived,
      'in_transit' || 'intransit' => RideStatus.inTransit,
      'completed' => RideStatus.completed,
      'cancelled' => RideStatus.cancelled,
      _ => RideStatus.requested,
    };
  }

  String get displayName => switch (this) {
        RideStatus.requested => 'Finding Driver...',
        RideStatus.accepted => 'Driver Accepted',
        RideStatus.driverArriving => 'Driver Arriving',
        RideStatus.arrived => 'Driver Arrived at Pickup',
        RideStatus.inTransit => 'Ride In Transit',
        RideStatus.completed => 'Completed',
        RideStatus.cancelled => 'Cancelled',
      };

  bool get isActive =>
      this == RideStatus.requested ||
      this == RideStatus.accepted ||
      this == RideStatus.driverArriving ||
      this == RideStatus.arrived ||
      this == RideStatus.inTransit;
}

/// Core domain entity for a ride request.
class RideEntity extends Equatable {
  final String id;
  final String passengerId;
  final String? driverId;
  final String? vehicleId;

  // Locations
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double dropoffLat;
  final double dropoffLng;
  final String dropoffAddress;

  // Fare & distance
  final double distanceKm;
  final int estimatedDurationMin;
  final double fareAmount;
  final String currency;
  final double platformFee;
  final double driverPayout;

  // Status & payment
  final RideStatus status;
  final String paymentStatus;
  final String? paymentReference;
  final String? blockchainLogHash;

  // Driver details (joined/denormalized)
  final String? driverName;
  final String? driverPhone;
  final double? driverRating;
  final String? driverAvatarUrl;
  final double? driverLat;
  final double? driverLng;

  // Vehicle details
  final String? vehicleCategory;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? vehiclePlate;

  // Passenger Verification PIN
  final String? verificationPin;

  const RideEntity({
    required this.id,
    required this.passengerId,
    this.driverId,
    this.vehicleId,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.estimatedDurationMin,
    required this.fareAmount,
    this.currency = 'SLE',
    required this.platformFee,
    required this.driverPayout,
    required this.status,
    required this.paymentStatus,
    this.paymentReference,
    this.blockchainLogHash,
    this.driverName,
    this.driverPhone,
    this.driverRating,
    this.driverAvatarUrl,
    this.driverLat,
    this.driverLng,
    this.vehicleCategory,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleColor,
    this.vehiclePlate,
    this.verificationPin = '4821',
  });

  /// Clean formatted text badge: `{Color} {Make} {Model} • {Plate Number}`
  /// Example: "Silver Toyota Corolla • SL-940-BA"
  String get formattedVehicleBadge {
    final c = (vehicleColor != null && vehicleColor!.trim().isNotEmpty) ? vehicleColor! : 'Silver';
    final mk = (vehicleMake != null && vehicleMake!.trim().isNotEmpty) ? vehicleMake! : 'Toyota';
    final md = (vehicleModel != null && vehicleModel!.trim().isNotEmpty) ? vehicleModel! : 'Corolla';
    final pl = (vehiclePlate != null && vehiclePlate!.trim().isNotEmpty) ? vehiclePlate! : 'SL-940-BA';
    return '$c $mk $md • $pl';
  }

  @override
  List<Object?> get props => [
        id,
        passengerId,
        driverId,
        vehicleId,
        pickupLat,
        pickupLng,
        pickupAddress,
        dropoffLat,
        dropoffLng,
        dropoffAddress,
        distanceKm,
        estimatedDurationMin,
        fareAmount,
        currency,
        platformFee,
        driverPayout,
        status,
        paymentStatus,
        paymentReference,
        blockchainLogHash,
        driverName,
        driverPhone,
        driverRating,
        driverAvatarUrl,
        driverLat,
        driverLng,
        vehicleCategory,
        vehicleMake,
        vehicleModel,
        vehicleColor,
        vehiclePlate,
        verificationPin,
      ];

  RideEntity copyWith({
    String? id,
    String? passengerId,
    String? driverId,
    String? vehicleId,
    double? pickupLat,
    double? pickupLng,
    String? pickupAddress,
    double? dropoffLat,
    double? dropoffLng,
    String? dropoffAddress,
    double? distanceKm,
    int? estimatedDurationMin,
    double? fareAmount,
    String? currency,
    double? platformFee,
    double? driverPayout,
    RideStatus? status,
    String? paymentStatus,
    String? paymentReference,
    String? blockchainLogHash,
    String? driverName,
    String? driverPhone,
    double? driverRating,
    String? driverAvatarUrl,
    double? driverLat,
    double? driverLng,
    String? vehicleCategory,
    String? vehicleMake,
    String? vehicleModel,
    String? vehicleColor,
    String? vehiclePlate,
    String? verificationPin,
  }) {
    return RideEntity(
      id: id ?? this.id,
      passengerId: passengerId ?? this.passengerId,
      driverId: driverId ?? this.driverId,
      vehicleId: vehicleId ?? this.vehicleId,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      dropoffLat: dropoffLat ?? this.dropoffLat,
      dropoffLng: dropoffLng ?? this.dropoffLng,
      dropoffAddress: dropoffAddress ?? this.dropoffAddress,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedDurationMin: estimatedDurationMin ?? this.estimatedDurationMin,
      fareAmount: fareAmount ?? this.fareAmount,
      currency: currency ?? this.currency,
      platformFee: platformFee ?? this.platformFee,
      driverPayout: driverPayout ?? this.driverPayout,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentReference: paymentReference ?? this.paymentReference,
      blockchainLogHash: blockchainLogHash ?? this.blockchainLogHash,
      driverName: driverName ?? this.driverName,
      driverPhone: driverPhone ?? this.driverPhone,
      driverRating: driverRating ?? this.driverRating,
      driverAvatarUrl: driverAvatarUrl ?? this.driverAvatarUrl,
      driverLat: driverLat ?? this.driverLat,
      driverLng: driverLng ?? this.driverLng,
      vehicleCategory: vehicleCategory ?? this.vehicleCategory,
      vehicleMake: vehicleMake ?? this.vehicleMake,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleColor: vehicleColor ?? this.vehicleColor,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      verificationPin: verificationPin ?? this.verificationPin,
    );
  }
}
