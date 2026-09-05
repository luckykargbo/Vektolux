// lib/features/real_estate/presentation/bloc/real_estate_detail_bloc.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Listing Detail BLoC
// Handles local SQLite streaming, dynamic pricing, anti-collision slot validation,
// and payment gateway orchestration.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../domain/entities/property_listing_entity.dart';
import '../../domain/repositories/real_estate_repository.dart';
import 'real_estate_detail_event.dart';
import 'real_estate_detail_state.dart';

class RealEstateDetailBloc
    extends Bloc<RealEstateDetailEvent, RealEstateDetailState> {
  final RealEstateRepository _repository;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  StreamSubscription<PropertyListingEntity?>? _listingSubscription;

  RealEstateDetailBloc({required RealEstateRepository repository})
      : _repository = repository,
        super(const RealEstateDetailState()) {
    on<LoadListingDetailEvent>(_onLoadListingDetail);
    on<SelectVisitDateEvent>(_onSelectVisitDate);
    on<SelectVisitTimeSlotEvent>(_onSelectVisitTimeSlot);
    on<UpdateHourlyDurationEvent>(_onUpdateHourlyDuration);
    on<SubmitSiteVisitEvent>(_onSubmitSiteVisit);
    on<SubmitInstantHourlyBookingEvent>(_onSubmitInstantHourlyBooking);
    on<ClearBookingStatusEvent>(_onClearBookingStatus);
  }

  Future<void> _onLoadListingDetail(
    LoadListingDetailEvent event,
    Emitter<RealEstateDetailState> emit,
  ) async {
    emit(state.copyWith(status: RealEstateDetailStatus.loading));

    await _listingSubscription?.cancel();

    // 1. Initial date setup: default to tomorrow for inspections
    final tomorrow = DateTime.now().add(const Duration(days: 1));

    // 2. Reactively stream from local SQLite cache
    await emit.forEach<PropertyListingEntity?>(
      _repository.watchListing(event.listingId),
      onData: (listing) {
        if (listing == null) {
          return state.copyWith(
            status: RealEstateDetailStatus.failure,
            errorMessage: 'Property listing not found.',
          );
        }

        // Calculate initial hourly pricing if this is a guest house
        final rate = listing.effectiveHourlyRate;
        final initialDuration = state.hourlyDuration;
        final total = rate * initialDuration;
        final fee = total * 0.10; // 10% platform fee

        return state.copyWith(
          status: RealEstateDetailStatus.loaded,
          listing: listing,
          selectedVisitDate: state.selectedVisitDate ?? tomorrow,
          calculatedTotal: total,
          hourlyPlatformFee: fee,
          hostPayout: total - fee,
        );
      },
      onError: (error, stack) {
        _log.e('Listing stream error: $error');
        return state.copyWith(
          status: RealEstateDetailStatus.failure,
          errorMessage: error.toString(),
        );
      },
    );
  }

  Future<void> _onSelectVisitDate(
    SelectVisitDateEvent event,
    Emitter<RealEstateDetailState> emit,
  ) async {
    if (state.listing == null) return;

    emit(state.copyWith(
      selectedVisitDate: event.date,
      isLoadingBookedSlots: true,
    ));

    try {
      final booked = await _repository.getBookedSlotsForDate(
        state.listing!.id,
        event.date,
      );

      // Check if previously selected slot is now booked on this new date
      final slotStillValid =
          state.selectedTimeSlot != null && !booked.contains(state.selectedTimeSlot);

      emit(state.copyWith(
        bookedSlotsForDate: booked,
        isLoadingBookedSlots: false,
        selectedTimeSlot: slotStillValid ? state.selectedTimeSlot : null,
      ));
    } catch (e) {
      _log.e('Error fetching booked slots for date: $e');
      emit(state.copyWith(
        isLoadingBookedSlots: false,
        bookedSlotsForDate: const [],
      ));
    }
  }

  void _onSelectVisitTimeSlot(
    SelectVisitTimeSlotEvent event,
    Emitter<RealEstateDetailState> emit,
  ) {
    // Validate anti-collision
    if (state.bookedSlotsForDate.contains(event.timeSlotLabel)) {
      emit(state.copyWith(
        errorMessage: 'This time slot is already reserved. Please choose another.',
      ));
      return;
    }

    emit(state.copyWith(
      selectedTimeSlot: event.timeSlotLabel,
      errorMessage: null,
    ));
  }

  void _onUpdateHourlyDuration(
    UpdateHourlyDurationEvent event,
    Emitter<RealEstateDetailState> emit,
  ) {
    if (state.listing == null) return;

    final rate = state.listing!.effectiveHourlyRate;
    double total = 0.0;

    if (event.isOvernight) {
      // Overnight stay: 12-hour bundle with 15% discount or listing daily price
      total = (rate * 12) * 0.85;
    } else {
      total = rate * event.durationHours;
    }

    final fee = total * 0.10; // 10% platform commission

    emit(state.copyWith(
      hourlyDuration: event.durationHours,
      isOvernight: event.isOvernight,
      calculatedTotal: total,
      hourlyPlatformFee: fee,
      hostPayout: total - fee,
    ));
  }

  Future<void> _onSubmitSiteVisit(
    SubmitSiteVisitEvent event,
    Emitter<RealEstateDetailState> emit,
  ) async {
    final listing = state.listing;
    final date = state.selectedVisitDate;
    final slot = state.selectedTimeSlot;

    if (listing == null || date == null || slot == null) {
      emit(state.copyWith(
        errorMessage: 'Please select a date and an available time slot.',
      ));
      return;
    }

    // Double-booking check
    if (state.bookedSlotsForDate.contains(slot)) {
      emit(state.copyWith(
        errorMessage: 'Time slot collision: Slot was just taken. Please pick another.',
      ));
      return;
    }

    emit(state.copyWith(status: RealEstateDetailStatus.submitting));

    try {
      final bookingId = await _repository.scheduleSiteVisit(
        listingId: listing.id,
        buyerId: event.buyerId,
        ownerId: listing.ownerId,
        date: date,
        timeSlotLabel: slot,
        notes: event.notes,
      );

      // Add slot to locally booked list
      final updatedBooked = List<String>.from(state.bookedSlotsForDate)..add(slot);

      emit(state.copyWith(
        status: RealEstateDetailStatus.bookingSuccess,
        bookingId: bookingId,
        bookedSlotsForDate: updatedBooked,
        successMessage: 'Site visit confirmed for ${date.day}/${date.month}/${date.year} at $slot!',
      ));
    } catch (e) {
      _log.e('Failed to schedule site visit: $e');
      emit(state.copyWith(
        status: RealEstateDetailStatus.failure,
        errorMessage: 'Failed to schedule visit: ${e.toString()}',
      ));
    }
  }

  Future<void> _onSubmitInstantHourlyBooking(
    SubmitInstantHourlyBookingEvent event,
    Emitter<RealEstateDetailState> emit,
  ) async {
    final listing = state.listing;
    if (listing == null) return;

    emit(state.copyWith(status: RealEstateDetailStatus.submitting));

    try {
      final startTime = DateTime.now();

      final result = await _repository.initiateInstantHourlyBooking(
        listingId: listing.id,
        buyerId: event.buyerId,
        ownerId: listing.ownerId,
        startTime: startTime,
        durationHours: state.hourlyDuration,
        totalAmount: state.calculatedTotal,
        currency: listing.currency,
        paymentMethod: event.paymentMethod,
        gatewayProvider: event.gatewayProvider,
        customerEmail: event.customerEmail,
        customerPhone: event.customerPhone,
        customerName: event.customerName,
      );

      final paymentLink = result['paymentLink']?.toString() ?? '';
      final reference = result['reference']?.toString() ?? '';
      final bookingId = result['bookingId']?.toString() ?? '';

      if (paymentLink.isNotEmpty) {
        emit(state.copyWith(
          status: RealEstateDetailStatus.paymentRequired,
          paymentCheckoutUrl: paymentLink,
          paymentReference: reference,
          bookingId: bookingId,
          successMessage: 'Payment session created. Complete payment to secure booking.',
        ));
      } else {
        emit(state.copyWith(
          status: RealEstateDetailStatus.bookingSuccess,
          bookingId: bookingId,
          paymentReference: reference,
          successMessage: 'Instant booking confirmed! Enjoy your stay.',
        ));
      }
    } catch (e) {
      _log.e('Instant booking failure: $e');
      emit(state.copyWith(
        status: RealEstateDetailStatus.failure,
        errorMessage: 'Booking initialization failed: ${e.toString()}',
      ));
    }
  }

  void _onClearBookingStatus(
    ClearBookingStatusEvent event,
    Emitter<RealEstateDetailState> emit,
  ) {
    emit(state.copyWith(
      status: RealEstateDetailStatus.loaded,
      errorMessage: null,
      successMessage: null,
    ));
  }

  @override
  Future<void> close() {
    _listingSubscription?.cancel();
    return super.close();
  }
}
