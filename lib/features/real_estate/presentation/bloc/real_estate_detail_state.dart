// lib/features/real_estate/presentation/bloc/real_estate_detail_state.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Listing Detail State
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import '../../domain/entities/property_listing_entity.dart';

enum RealEstateDetailStatus {
  initial,
  loading,
  loaded,
  submitting,
  bookingSuccess,
  paymentRequired,
  failure,
}

class RealEstateDetailState extends Equatable {
  final RealEstateDetailStatus status;
  final PropertyListingEntity? listing;
  final String? errorMessage;
  final String? successMessage;

  // Site visit inspection state
  final DateTime? selectedVisitDate;
  final String? selectedTimeSlot;
  final List<String> bookedSlotsForDate;
  final bool isLoadingBookedSlots;

  // Hourly guest house state
  final int hourlyDuration;
  final bool isOvernight;
  final double calculatedTotal;
  final double hourlyPlatformFee;
  final double hostPayout;

  // Payment checkout flow state
  final String? paymentCheckoutUrl;
  final String? paymentReference;
  final String? bookingId;

  const RealEstateDetailState({
    this.status = RealEstateDetailStatus.initial,
    this.listing,
    this.errorMessage,
    this.successMessage,
    this.selectedVisitDate,
    this.selectedTimeSlot,
    this.bookedSlotsForDate = const [],
    this.isLoadingBookedSlots = false,
    this.hourlyDuration = 2,
    this.isOvernight = false,
    this.calculatedTotal = 0.0,
    this.hourlyPlatformFee = 0.0,
    this.hostPayout = 0.0,
    this.paymentCheckoutUrl,
    this.paymentReference,
    this.bookingId,
  });

  RealEstateDetailState copyWith({
    RealEstateDetailStatus? status,
    PropertyListingEntity? listing,
    String? errorMessage,
    String? successMessage,
    DateTime? selectedVisitDate,
    String? selectedTimeSlot,
    List<String>? bookedSlotsForDate,
    bool? isLoadingBookedSlots,
    int? hourlyDuration,
    bool? isOvernight,
    double? calculatedTotal,
    double? hourlyPlatformFee,
    double? hostPayout,
    String? paymentCheckoutUrl,
    String? paymentReference,
    String? bookingId,
  }) {
    return RealEstateDetailState(
      status: status ?? this.status,
      listing: listing ?? this.listing,
      errorMessage: errorMessage,
      successMessage: successMessage,
      selectedVisitDate: selectedVisitDate ?? this.selectedVisitDate,
      selectedTimeSlot: selectedTimeSlot ?? this.selectedTimeSlot,
      bookedSlotsForDate: bookedSlotsForDate ?? this.bookedSlotsForDate,
      isLoadingBookedSlots: isLoadingBookedSlots ?? this.isLoadingBookedSlots,
      hourlyDuration: hourlyDuration ?? this.hourlyDuration,
      isOvernight: isOvernight ?? this.isOvernight,
      calculatedTotal: calculatedTotal ?? this.calculatedTotal,
      hourlyPlatformFee: hourlyPlatformFee ?? this.hourlyPlatformFee,
      hostPayout: hostPayout ?? this.hostPayout,
      paymentCheckoutUrl: paymentCheckoutUrl ?? this.paymentCheckoutUrl,
      paymentReference: paymentReference ?? this.paymentReference,
      bookingId: bookingId ?? this.bookingId,
    );
  }

  bool get isSlotBooked =>
      selectedTimeSlot != null && bookedSlotsForDate.contains(selectedTimeSlot);

  bool get canConfirmSiteVisit =>
      selectedVisitDate != null &&
      selectedTimeSlot != null &&
      !isSlotBooked &&
      status != RealEstateDetailStatus.submitting;

  @override
  List<Object?> get props => [
        status,
        listing,
        errorMessage,
        successMessage,
        selectedVisitDate,
        selectedTimeSlot,
        bookedSlotsForDate,
        isLoadingBookedSlots,
        hourlyDuration,
        isOvernight,
        calculatedTotal,
        hourlyPlatformFee,
        hostPayout,
        paymentCheckoutUrl,
        paymentReference,
        bookingId,
      ];
}
