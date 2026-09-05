// lib/features/mobility/domain/entities/trip_delivery_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Trip & Delivery Domain Entity
// Handles lifecycle for ride-hailing and package delivery dispatch.
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

enum TripDeliveryStatus {
  searching,
  accepted,
  arrived,
  inProgress,
  completed,
  cancelled;

  static TripDeliveryStatus fromString(String val) {
    return switch (val.toLowerCase()) {
      'searching' => TripDeliveryStatus.searching,
      'accepted' => TripDeliveryStatus.accepted,
      'arrived' => TripDeliveryStatus.arrived,
      'in_progress' || 'inprogress' => TripDeliveryStatus.inProgress,
      'completed' => TripDeliveryStatus.completed,
      'cancelled' => TripDeliveryStatus.cancelled,
      _ => TripDeliveryStatus.searching,
    };
  }

  String get displayName => switch (this) {
        TripDeliveryStatus.searching => 'Searching for Driver...',
        TripDeliveryStatus.accepted => 'Driver Assigned',
        TripDeliveryStatus.arrived => 'Driver Arrived at Pickup',
        TripDeliveryStatus.inProgress => 'Trip in Progress',
        TripDeliveryStatus.completed => 'Completed',
        TripDeliveryStatus.cancelled => 'Cancelled',
      };

  bool get isActive =>
      this == TripDeliveryStatus.searching ||
      this == TripDeliveryStatus.accepted ||
      this == TripDeliveryStatus.arrived ||
      this == TripDeliveryStatus.inProgress;
}

class DeliveryPackageDetails extends Equatable {
  final String recipientName;
  final String recipientPhone;
  final String? packageDescription;
  final String? packageSize;
  final bool isFragile;

  const DeliveryPackageDetails({
    required this.recipientName,
    required this.recipientPhone,
    this.packageDescription,
    this.packageSize,
    this.isFragile = false,
  });

  factory DeliveryPackageDetails.fromJson(Map<String, dynamic> json) {
    return DeliveryPackageDetails(
      recipientName: json['recipientName'] as String? ?? '',
      recipientPhone: json['recipientPhone'] as String? ?? '',
      packageDescription: json['packageDescription'] as String?,
      packageSize: json['packageSize'] as String?,
      isFragile: json['isFragile'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'recipientName': recipientName,
        'recipientPhone': recipientPhone,
        if (packageDescription != null) 'packageDescription': packageDescription,
        if (packageSize != null) 'packageSize': packageSize,
        'isFragile': isFragile,
      };

  @override
  List<Object?> get props => [recipientName, recipientPhone, packageDescription, packageSize, isFragile];
}

class TripDeliveryEntity extends Equatable {
  final String id;
  final String passengerId;
  final String? driverId;
  final String? vehicleId;
  final String serviceType; // 'ride' | 'delivery'
  final double pickupLat;
  final double pickupLng;
  final String pickupAddressText;
  final double dropoffLat;
  final double dropoffLng;
  final String dropoffAddressText;
  final TripDeliveryStatus status;
  final double fareAmount;
  final String currency;
  final String paymentMethod;
  final double distanceKm;
  final int durationMins;
  final DeliveryPackageDetails? packageDetails;
  final DateTime createdAt;
  final String? verificationPin;
  final double? driverPayout;
  final String? passengerName;
  final String? passengerPhone;
  final double? passengerRating;
  final double? distanceToPickupKm;
  final int? etaToPickupMinutes;

  const TripDeliveryEntity({
    required this.id,
    required this.passengerId,
    this.driverId,
    this.vehicleId,
    required this.serviceType,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddressText,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.dropoffAddressText,
    required this.status,
    required this.fareAmount,
    this.currency = 'SLE',
    required this.paymentMethod,
    required this.distanceKm,
    required this.durationMins,
    this.packageDetails,
    required this.createdAt,
    this.verificationPin,
    this.driverPayout,
    this.passengerName,
    this.passengerPhone,
    this.passengerRating,
    this.distanceToPickupKm,
    this.etaToPickupMinutes,
  });

  factory TripDeliveryEntity.fromJson(Map<String, dynamic> json) {
    return TripDeliveryEntity(
      id: json['_id'] as String? ?? json['id'] as String? ?? '',
      passengerId: json['passengerId'] as String? ?? '',
      driverId: json['driverId'] as String?,
      vehicleId: json['vehicleId'] as String?,
      serviceType: json['serviceType'] as String? ?? 'ride',
      pickupLat: (json['pickupLat'] as num).toDouble(),
      pickupLng: (json['pickupLng'] as num).toDouble(),
      pickupAddressText: json['pickupAddressText'] as String? ?? '',
      dropoffLat: (json['dropoffLat'] as num).toDouble(),
      dropoffLng: (json['dropoffLng'] as num).toDouble(),
      dropoffAddressText: json['dropoffAddressText'] as String? ?? '',
      status: TripDeliveryStatus.fromString(json['status'] as String? ?? 'searching'),
      fareAmount: (json['fareAmount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'SLE',
      paymentMethod: json['paymentMethod'] as String? ?? 'wallet',
      distanceKm: (json['distanceKm'] as num).toDouble(),
      durationMins: (json['durationMins'] as num).toInt(),
      packageDetails: json['deliveryPackageDetails'] != null
          ? DeliveryPackageDetails.fromJson(json['deliveryPackageDetails'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      verificationPin: json['verificationPin'] as String?,
      driverPayout: (json['driverPayout'] as num?)?.toDouble() ??
          ((json['fareAmount'] as num?) != null ? (json['fareAmount'] as num).toDouble() * 0.85 : null),
      passengerName: json['passengerName'] as String?,
      passengerPhone: json['passengerPhone'] as String?,
      passengerRating: (json['passengerRating'] as num?)?.toDouble() ?? 4.9,
      distanceToPickupKm: (json['distanceToPickupKm'] as num?)?.toDouble(),
      etaToPickupMinutes: (json['etaToPickupMinutes'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        passengerId,
        driverId,
        vehicleId,
        serviceType,
        pickupLat,
        pickupLng,
        pickupAddressText,
        dropoffLat,
        dropoffLng,
        dropoffAddressText,
        status,
        fareAmount,
        currency,
        paymentMethod,
        distanceKm,
        durationMins,
        packageDetails,
        createdAt,
        verificationPin,
        driverPayout,
        passengerName,
        passengerPhone,
        passengerRating,
        distanceToPickupKm,
        etaToPickupMinutes,
      ];
}
