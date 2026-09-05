// lib/features/mobility/presentation/bloc/driver_portal_state.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Portal State Definition
// State machine for online status, location broadcasting, incoming dispatches,
// and 4-step active trip lifecycle execution.
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import '../../domain/entities/trip_delivery_entity.dart';

enum DriverTripLifecycleStep {
  idle,
  navigatingToPickup, // Step 1: Heading to passenger / courier pickup
  arrivedAtPickup,    // Step 2: Waiting at pickup point
  inProgress,         // Step 3: Passenger aboard / package in transit (PIN verified)
  tripCompleted,      // Step 4: Arrived at dropoff, payment settled, rating sheet open
}

class DriverPortalState extends Equatable {
  final bool isOnline;
  final bool isAvailable;
  final bool isPollingDispatches;
  final double currentLat;
  final double currentLng;
  final String? driverProfileId;
  final String? vehicleId;
  final String? driverUserId;
  final double todaysEarnings;
  final int completedTripsCount;
  final double rating;

  // Incoming Dispatch Modal
  final TripDeliveryEntity? incomingDispatch;
  final int countdownSeconds; // 15s circular countdown

  // Active Trip Execution
  final TripDeliveryEntity? activeTrip;
  final DriverTripLifecycleStep lifecycleStep;
  final bool isProcessingAction;
  final String? pinErrorMessage;

  // Feedback notifications
  final String? errorMessage;
  final String? successMessage;

  const DriverPortalState({
    this.isOnline = false,
    this.isAvailable = false,
    this.isPollingDispatches = false,
    this.currentLat = 8.484,
    this.currentLng = -13.229,
    this.driverProfileId,
    this.vehicleId,
    this.driverUserId,
    this.todaysEarnings = 385.0,
    this.completedTripsCount = 3,
    this.rating = 4.95,
    this.incomingDispatch,
    this.countdownSeconds = 15,
    this.activeTrip,
    this.lifecycleStep = DriverTripLifecycleStep.idle,
    this.isProcessingAction = false,
    this.pinErrorMessage,
    this.errorMessage,
    this.successMessage,
  });

  bool get hasIncomingDispatch => incomingDispatch != null;
  bool get hasActiveTrip => activeTrip != null && lifecycleStep != DriverTripLifecycleStep.idle;

  DriverPortalState copyWith({
    bool? isOnline,
    bool? isAvailable,
    bool? isPollingDispatches,
    double? currentLat,
    double? currentLng,
    String? driverProfileId,
    String? vehicleId,
    String? driverUserId,
    double? todaysEarnings,
    int? completedTripsCount,
    double? rating,
    TripDeliveryEntity? incomingDispatch,
    bool clearIncomingDispatch = false,
    int? countdownSeconds,
    TripDeliveryEntity? activeTrip,
    bool clearActiveTrip = false,
    DriverTripLifecycleStep? lifecycleStep,
    bool? isProcessingAction,
    String? pinErrorMessage,
    bool clearPinError = false,
    String? errorMessage,
    String? successMessage,
  }) {
    return DriverPortalState(
      isOnline: isOnline ?? this.isOnline,
      isAvailable: isAvailable ?? this.isAvailable,
      isPollingDispatches: isPollingDispatches ?? this.isPollingDispatches,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      driverProfileId: driverProfileId ?? this.driverProfileId,
      vehicleId: vehicleId ?? this.vehicleId,
      driverUserId: driverUserId ?? this.driverUserId,
      todaysEarnings: todaysEarnings ?? this.todaysEarnings,
      completedTripsCount: completedTripsCount ?? this.completedTripsCount,
      rating: rating ?? this.rating,
      incomingDispatch: clearIncomingDispatch ? null : (incomingDispatch ?? this.incomingDispatch),
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      activeTrip: clearActiveTrip ? null : (activeTrip ?? this.activeTrip),
      lifecycleStep: lifecycleStep ?? this.lifecycleStep,
      isProcessingAction: isProcessingAction ?? this.isProcessingAction,
      pinErrorMessage: clearPinError ? null : (pinErrorMessage ?? this.pinErrorMessage),
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }

  @override
  List<Object?> get props => [
        isOnline,
        isAvailable,
        isPollingDispatches,
        currentLat,
        currentLng,
        driverProfileId,
        vehicleId,
        driverUserId,
        todaysEarnings,
        completedTripsCount,
        rating,
        incomingDispatch,
        countdownSeconds,
        activeTrip,
        lifecycleStep,
        isProcessingAction,
        pinErrorMessage,
        errorMessage,
        successMessage,
      ];
}
