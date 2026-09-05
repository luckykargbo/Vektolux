// lib/features/real_estate/domain/entities/booking_slot_entity.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Booking Slot & Reservation Entity
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

/// Available time slots for inspections and site visits.
class InspectionTimeSlot extends Equatable {
  final String slotId;
  final String label; // e.g. "09:00 AM - 10:00 AM"
  final int startHour;
  final int endHour;
  final bool isBooked;

  const InspectionTimeSlot({
    required this.slotId,
    required this.label,
    required this.startHour,
    required this.endHour,
    this.isBooked = false,
  });

  InspectionTimeSlot copyWith({bool? isBooked}) {
    return InspectionTimeSlot(
      slotId: slotId,
      label: label,
      startHour: startHour,
      endHour: endHour,
      isBooked: isBooked ?? this.isBooked,
    );
  }

  @override
  List<Object?> get props => [slotId, label, startHour, endHour, isBooked];
}

/// A scheduled booking entity (either inspection or instant guest house stay).
class PropertyBookingEntity extends Equatable {
  final String id;
  final String listingId;
  final String buyerId;
  final String ownerId;
  final String bookingType; // "inspection" or "instant_stay"
  final DateTime startTime;
  final DateTime endTime;
  final double totalAmount;
  final double platformFee;
  final String currency;
  final String paymentStatus;
  final String? paymentReference;
  final String? notes;

  const PropertyBookingEntity({
    required this.id,
    required this.listingId,
    required this.buyerId,
    required this.ownerId,
    required this.bookingType,
    required this.startTime,
    required this.endTime,
    required this.totalAmount,
    required this.platformFee,
    this.currency = 'SLE',
    required this.paymentStatus,
    this.paymentReference,
    this.notes,
  });

  @override
  List<Object?> get props => [
        id,
        listingId,
        buyerId,
        ownerId,
        bookingType,
        startTime,
        endTime,
        totalAmount,
        platformFee,
        currency,
        paymentStatus,
        paymentReference,
        notes,
      ];
}
