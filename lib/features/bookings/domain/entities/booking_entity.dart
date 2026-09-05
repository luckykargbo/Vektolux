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
  pendingPayment,
  confirmed,
  inProgress,
  completed,
  cancelled,
}

extension BookingStatusX on BookingStatus {
  String get convexValue => switch (this) {
        BookingStatus.pendingPayment => 'pending_payment',
        BookingStatus.confirmed => 'confirmed',
        BookingStatus.inProgress => 'in_progress',
        BookingStatus.completed => 'completed',
        BookingStatus.cancelled => 'cancelled',
      };

  String get displayName => switch (this) {
        BookingStatus.pendingPayment => 'Pending Payment',
        BookingStatus.confirmed => 'Confirmed',
        BookingStatus.inProgress => 'In Progress',
        BookingStatus.completed => 'Completed',
        BookingStatus.cancelled => 'Cancelled',
      };

  static BookingStatus fromString(String value) {
    return switch (value) {
      'pending_payment' => BookingStatus.pendingPayment,
      'confirmed' => BookingStatus.confirmed,
      'in_progress' => BookingStatus.inProgress,
      'completed' => BookingStatus.completed,
      'cancelled' => BookingStatus.cancelled,
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
  });

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
      ];
}
