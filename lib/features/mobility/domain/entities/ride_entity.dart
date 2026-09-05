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
  inTransit,
  completed,
  cancelled;

  static RideStatus fromString(String val) {
    return switch (val.toLowerCase()) {
      'requested' => RideStatus.requested,
      'accepted' => RideStatus.accepted,
      'driver_arriving' || 'driverarriving' => RideStatus.driverArriving,
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
        RideStatus.inTransit => 'Ride In Transit',
        RideStatus.completed => 'Completed',
        RideStatus.cancelled => 'Cancelled',
      };

  bool get isActive =>
      this == RideStatus.requested ||
      this == RideStatus.accepted ||
      this == RideStatus.driverArriving ||
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
  final double? driverLat;
  final double? driverLng;

  // Vehicle details
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
    this.driverLat,
    this.driverLng,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleColor,
    this.vehiclePlate,
    this.verificationPin = '4821',
  });

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
        driverLat,
        driverLng,
        vehicleMake,
        vehicleModel,
        vehicleColor,
        vehiclePlate,
        verificationPin,
      ];
}
