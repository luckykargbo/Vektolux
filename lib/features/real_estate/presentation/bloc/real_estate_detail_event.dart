// lib/features/real_estate/presentation/bloc/real_estate_detail_event.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Listing Detail Events
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

abstract class RealEstateDetailEvent extends Equatable {
  const RealEstateDetailEvent();

  @override
  List<Object?> get props => [];
}

/// Load or subscribe to listing details by ID.
class LoadListingDetailEvent extends RealEstateDetailEvent {
  final String listingId;
  const LoadListingDetailEvent(this.listingId);

  @override
  List<Object?> get props => [listingId];
}

/// User selected a calendar date for site visit inspection.
class SelectVisitDateEvent extends RealEstateDetailEvent {
  final DateTime date;
  const SelectVisitDateEvent(this.date);

  @override
  List<Object?> get props => [date];
}

/// User selected a time slot for site visit inspection.
class SelectVisitTimeSlotEvent extends RealEstateDetailEvent {
  final String timeSlotLabel;
  const SelectVisitTimeSlotEvent(this.timeSlotLabel);

  @override
  List<Object?> get props => [timeSlotLabel];
}

/// User adjusted hourly duration slider or tapped duration chip.
class UpdateHourlyDurationEvent extends RealEstateDetailEvent {
  final int durationHours;
  final bool isOvernight;

  const UpdateHourlyDurationEvent({
    required this.durationHours,
    this.isOvernight = false,
  });

  @override
  List<Object?> get props => [durationHours, isOvernight];
}

/// Submit site visit inspection booking.
class SubmitSiteVisitEvent extends RealEstateDetailEvent {
  final String buyerId;
  final String? notes;

  const SubmitSiteVisitEvent({
    required this.buyerId,
    this.notes,
  });

  @override
  List<Object?> get props => [buyerId, notes];
}

/// Submit instant booking for hourly guesthouse and trigger payment gateway.
class SubmitInstantHourlyBookingEvent extends RealEstateDetailEvent {
  final String buyerId;
  final String customerEmail;
  final String? customerPhone;
  final String? customerName;
  final String paymentMethod; // "mobile_money" or "card"
  final String gatewayProvider; // "flutterwave" or "paystack"

  const SubmitInstantHourlyBookingEvent({
    required this.buyerId,
    required this.customerEmail,
    this.customerPhone,
    this.customerName,
    this.paymentMethod = 'mobile_money',
    this.gatewayProvider = 'flutterwave',
  });

  @override
  List<Object?> get props => [
        buyerId,
        customerEmail,
        customerPhone,
        customerName,
        paymentMethod,
        gatewayProvider,
      ];
}

/// Dismiss any booking notifications or reset error states.
class ClearBookingStatusEvent extends RealEstateDetailEvent {
  const ClearBookingStatusEvent();
}
