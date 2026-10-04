// lib/features/bookings/domain/entities/booking_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Booking Domain Entity
// Universal entity modeling stays, rentals, and free inspections.
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

enum BookingType {
  hourlyGuesthouse,
  vehicleRental,
  propertyInspection,
  vehicleInspection,
}

extension BookingTypeX on BookingType {
  String get convexValue => switch (this) {
        BookingType.hourlyGuesthouse => 'hourly_guesthouse',
        BookingType.vehicleRental => 'vehicle_rental',
        BookingType.propertyInspection => 'property_inspection',
        BookingType.vehicleInspection => 'vehicle_inspection',
      };

  String get displayName => switch (this) {
        BookingType.hourlyGuesthouse => 'Hourly Stay',
        BookingType.vehicleRental => 'Vehicle Rental',
        BookingType.propertyInspection => 'Property Inspection',
        BookingType.vehicleInspection => 'Vehicle Inspection',
      };

  static BookingType fromString(String value) {
    return switch (value) {
      'hourly_guesthouse' => BookingType.hourlyGuesthouse,
      'vehicle_rental' => BookingType.vehicleRental,
      'property_inspection' => BookingType.propertyInspection,
      'vehicle_inspection' => BookingType.vehicleInspection,
      _ => BookingType.propertyInspection,
    };
  }
}

enum BookingStatus {
  /// A free property viewing the agent has not answered yet.
  requested,

  /// A viewing request the agent declined (the reason is on the booking).
  declined,
  pendingPayment,
  confirmed,
  inProgress,
  completed,
  cancelled,
  disputed,
}

extension BookingStatusX on BookingStatus {
  String get convexValue => switch (this) {
        BookingStatus.requested => 'requested',
        BookingStatus.declined => 'declined',
        BookingStatus.pendingPayment => 'pending_payment',
        BookingStatus.confirmed => 'confirmed',
        BookingStatus.inProgress => 'in_progress',
        BookingStatus.completed => 'completed',
        BookingStatus.cancelled => 'cancelled',
        BookingStatus.disputed => 'disputed',
      };

  String get displayName => switch (this) {
        BookingStatus.requested => 'Requested',
        BookingStatus.declined => 'Declined',
        BookingStatus.pendingPayment => 'Pending Payment',
        BookingStatus.confirmed => 'Confirmed',
        BookingStatus.inProgress => 'In Progress',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
        BookingStatus.disputed => 'Under Review',
      };

  static BookingStatus fromString(String value) {
    return switch (value) {
      'requested' => BookingStatus.requested,
      'declined' => BookingStatus.declined,
      'pending_payment' => BookingStatus.pendingPayment,
      'confirmed' => BookingStatus.confirmed,
      'in_progress' => BookingStatus.inProgress,
      'completed' => BookingStatus.completed,
      'cancelled' => BookingStatus.cancelled,
      'disputed' => BookingStatus.disputed,
      _ => BookingStatus.pendingPayment,
    };
  }
}

class BookingEntity extends Equatable {
  final String id;
  final String listingId;
  final String listingTitle;
  final String listingType;
  final String buyerId;
  final String? buyerName;
  final String? buyerPhone;
  final String vendorId;
  final BookingType bookingType;
  final BookingStatus status;
  final int startTime;
  final int endTime;
  final int? hours;
  final int? days;
  final double subtotal;
  final double serviceFee;
  final double totalAmount;
  final String currency;
  final String paymentStatus;
  final String? paymentMethod;
  final String? txRef;
  final String? flwRef;
  final String? notes;
  final int updatedAt;

  /// Why the agent declined the request / why the booking was cancelled (server text).
  final String? declineReason;
  final String? cancelReason;

  /// Server-driven escrow settlement: 'held' | 'disputed' | 'released' | 'refunded' (null if unpaid).
  final String? settlementStatus;

  /// When the escrow is released automatically if nobody disputes (end time + 24h).
  final int? releaseEligibleAt;

  const BookingEntity({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.listingType,
    required this.buyerId,
    this.buyerName,
    this.buyerPhone,
    required this.vendorId,
    required this.bookingType,
    required this.status,
    required this.startTime,
    required this.endTime,
    this.hours,
    this.days,
    required this.subtotal,
    required this.serviceFee,
    required this.totalAmount,
    this.currency = 'SLE',
    required this.paymentStatus,
    this.paymentMethod,
    this.txRef,
    this.flwRef,
    this.notes,
    required this.updatedAt,
    this.declineReason,
    this.cancelReason,
    this.settlementStatus,
    this.releaseEligibleAt,
  });

  /// Paid and held in escrow (also bookings paid before settlement tracking existed).
  bool get isEscrowHeld =>
      settlementStatus == 'held' ||
      (settlementStatus == null &&
          paymentStatus == 'completed' &&
          status != BookingStatus.completed &&
          status != BookingStatus.cancelled &&
          status != BookingStatus.disputed);

  factory BookingEntity.fromJson(Map<String, dynamic> json) {
    return BookingEntity(
      id: (json['_id'] ?? json['id'] ?? '') as String,
      listingId: (json['listingId'] ?? '') as String,
      listingTitle: (json['listingTitle'] ?? '') as String,
      listingType: (json['listingType'] ?? 'property') as String,
      buyerId: (json['buyerId'] ?? '') as String,
      buyerName: json['buyerName'] as String?,
      buyerPhone: json['buyerPhone'] as String?,
      vendorId: (json['vendorId'] ?? '') as String,
      bookingType: BookingTypeX.fromString((json['bookingType'] ?? '') as String),
      status: BookingStatusX.fromString((json['status'] ?? json['bookingStatus'] ?? 'pending_payment') as String),
      startTime: (json['startTime'] as num?)?.toInt() ?? 0,
      endTime: (json['endTime'] as num?)?.toInt() ?? 0,
      hours: (json['hours'] as num?)?.toInt(),
      days: (json['days'] as num?)?.toInt(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      serviceFee: (json['serviceFee'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      currency: (json['currency'] ?? 'SLE') as String,
      paymentStatus: (json['paymentStatus'] ?? 'pending') as String,
      paymentMethod: json['paymentMethod'] as String?,
      txRef: json['txRef'] as String?,
      flwRef: json['flwRef'] as String?,
      notes: json['notes'] as String?,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ??
          (json['_creationTime'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      declineReason: json['declineReason'] as String?,
      cancelReason: json['cancelReason'] as String?,
      settlementStatus: json['settlementStatus'] as String?,
      releaseEligibleAt: (json['releaseEligibleAt'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        listingId,
        listingTitle,
        listingType,
        buyerId,
        buyerName,
        buyerPhone,
        vendorId,
        bookingType,
        status,
        startTime,
        endTime,
        hours,
        days,
        subtotal,
        serviceFee,
        totalAmount,
        currency,
        paymentStatus,
        paymentMethod,
        txRef,
        flwRef,
        notes,
        updatedAt,
        declineReason,
        cancelReason,
        settlementStatus,
        releaseEligibleAt,
      ];
}
