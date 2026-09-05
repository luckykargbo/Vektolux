// lib/features/mobility/presentation/bloc/driver_portal_bloc.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Portal Master BLoC
// Manages driver online/offline state machine, real-time GPS location streaming,
// incoming dispatch alert modal with 15s countdown, and 4-step trip lifecycle.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/database/daos/cached_trips_deliveries_dao.dart';
import '../../../../core/database/daos/cached_driver_profiles_dao.dart';
import '../../data/services/driver_heartbeat_service.dart';
import '../../domain/entities/trip_delivery_entity.dart';
import 'driver_portal_event.dart';
import 'driver_portal_state.dart';

class DriverPortalBloc extends Bloc<DriverPortalEvent, DriverPortalState> {
  final ConvexClientWrapper _convexClient;
  final DriverHeartbeatService _heartbeatService;
  final CachedTripsDeliveriesDao _tripsDao;
  final CachedDriverProfilesDao _driverDao;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  Timer? _dispatchPollingTimer;
  Timer? _countdownTimer;

  DriverPortalBloc({
    required ConvexClientWrapper convexClient,
    required DriverHeartbeatService heartbeatService,
    required CachedTripsDeliveriesDao tripsDao,
    required CachedDriverProfilesDao driverDao,
  })  : _convexClient = convexClient,
        _heartbeatService = heartbeatService,
        _tripsDao = tripsDao,
        _driverDao = driverDao,
        super(const DriverPortalState()) {
    on<InitDriverPortalEvent>(_onInit);
    on<ToggleDriverOnlineStatusEvent>(_onToggleOnline);
    on<UpdateDriverCoordinatesEvent>(_onUpdateCoordinates);
    on<IncomingDispatchPolledEvent>(_onIncomingDispatchPolled);
    on<AcceptDispatchEvent>(_onAcceptDispatch);
    on<DeclineDispatchEvent>(_onDeclineDispatch);
    on<DispatchCountdownTickEvent>(_onCountdownTick);
    on<DispatchTimeoutEvent>(_onDispatchTimeout);
    on<DriverArrivedAtPickupEvent>(_onDriverArrived);
    on<VerifyPinAndStartTripEvent>(_onVerifyPin);
    on<CompleteTripEvent>(_onCompleteTrip);
    on<SubmitPassengerRatingEvent>(_onSubmitRating);
    on<ResetAfterTripEvent>(_onResetAfterTrip);
    on<ClearDriverPortalFeedbackEvent>(_onClearFeedback);
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onInit(
    InitDriverPortalEvent event,
    Emitter<DriverPortalState> emit,
  ) async {
    emit(state.copyWith(
      driverUserId: event.userId,
      currentLat: event.initialLat,
      currentLng: event.initialLng,
      isProcessingAction: true,
    ));

    try {
      // 1. Ensure driver profile exists in Convex
      final profileResult = await _convexClient.mutation(
        'mobility:registerOrUpdateDriverProfile',
        args: {
          'userId': event.userId,
          'serviceType': 'both',
          'currentLat': event.initialLat,
          'currentLng': event.initialLng,
          'isOnline': false,
          'isAvailable': false,
        },
      );

      String? profileId;
      if (profileResult.success && profileResult.value is String) {
        profileId = profileResult.value as String;
      }

      emit(state.copyWith(
        driverProfileId: profileId,
        isProcessingAction: false,
      ));

      _log.i('Driver portal initialized for profile: $profileId');
    } catch (e) {
      _log.w('Failed to init driver profile in Convex: $e');
      emit(state.copyWith(isProcessingAction: false));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //              ONLINE / OFFLINE STATE MACHINE
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onToggleOnline(
    ToggleDriverOnlineStatusEvent event,
    Emitter<DriverPortalState> emit,
  ) async {
    final willBeOnline = event.isOnline;
    final profileId = state.driverProfileId;

    if (willBeOnline) {
      // 1. Start heartbeat location streaming
      if (profileId != null) {
        _heartbeatService.startHeartbeat(
          driverProfileId: profileId,
          initialLat: state.currentLat,
          initialLng: state.currentLng,
        );

        // Update Convex online status
        _convexClient.mutation(
          'mobility:setDriverOnlineStatus',
          args: {
            'driverProfileId': profileId,
            'isOnline': true,
            'isAvailable': true,
          },
        ).ignore();

        // Update local Drift SQLite status
        _driverDao.updateDriverStatus(
          driverId: profileId,
          isOnline: true,
          isAvailable: true,
        ).ignore();
      }

      emit(state.copyWith(
        isOnline: true,
        isAvailable: true,
        successMessage: 'You are now ONLINE. Searching for nearby rides & packages...',
      ));

      // 2. Start dispatch listener / polling loop (every 3 seconds)
      _startDispatchPolling();
    } else {
      // 1. Stop heartbeat
      _heartbeatService.stopHeartbeat();

      // 2. Stop polling
      _stopDispatchPolling();
      _stopCountdown();

      // Update Convex & SQLite online status
      if (profileId != null) {
        _convexClient.mutation(
          'mobility:setDriverOnlineStatus',
          args: {
            'driverProfileId': profileId,
            'isOnline': false,
            'isAvailable': false,
          },
        ).ignore();

        _driverDao.updateDriverStatus(
          driverId: profileId,
          isOnline: false,
          isAvailable: false,
        ).ignore();
      }

      emit(state.copyWith(
        isOnline: false,
        isAvailable: false,
        clearIncomingDispatch: true,
        successMessage: 'You are now OFFLINE.',
      ));
    }
  }

  void _onUpdateCoordinates(
    UpdateDriverCoordinatesEvent event,
    Emitter<DriverPortalState> emit,
  ) {
    _heartbeatService.updateCoordinates(event.lat, event.lng);
    emit(state.copyWith(currentLat: event.lat, currentLng: event.lng));
  }

  // ═══════════════════════════════════════════════════════════════════
  //             REAL-TIME DISPATCH LISTENER & COUNTDOWN
  // ═══════════════════════════════════════════════════════════════════

  void _startDispatchPolling() {
    _stopDispatchPolling();
    _dispatchPollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!state.isOnline || !state.isAvailable || state.hasActiveTrip || state.hasIncomingDispatch) {
        return;
      }

      final profileId = state.driverProfileId;
      if (profileId == null) return;

      try {
        final result = await _convexClient.query(
          'mobility:getAvailableDispatches',
          args: {
            'driverProfileId': profileId,
            'driverLat': state.currentLat,
            'driverLng': state.currentLng,
            'serviceType': 'both',
            'radiusKm': 6.0,
          },
        );

        if (result.success && result.value != null && result.value is Map<String, dynamic>) {
          final tripMap = result.value as Map<String, dynamic>;
          final dispatch = TripDeliveryEntity.fromJson(tripMap);
          add(IncomingDispatchPolledEvent(dispatch));
        }
      } catch (e) {
        _log.d('Polling dispatches: $e');
      }
    });
  }

  void _stopDispatchPolling() {
    _dispatchPollingTimer?.cancel();
    _dispatchPollingTimer = null;
  }

  void _onIncomingDispatchPolled(
    IncomingDispatchPolledEvent event,
    Emitter<DriverPortalState> emit,
  ) {
    if (!state.isOnline || !state.isAvailable || state.hasActiveTrip) return;

    emit(state.copyWith(
      incomingDispatch: event.dispatch,
      countdownSeconds: 15,
    ));

    _startCountdown();
  }

  void _startCountdown() {
    _stopCountdown();
    int current = 15;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      current--;
      if (current <= 0) {
        timer.cancel();
        add(const DispatchTimeoutEvent());
      } else {
        add(DispatchCountdownTickEvent(current));
      }
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  void _onCountdownTick(
    DispatchCountdownTickEvent event,
    Emitter<DriverPortalState> emit,
  ) {
    emit(state.copyWith(countdownSeconds: event.remainingSeconds));
  }

  Future<void> _onDispatchTimeout(
    DispatchTimeoutEvent event,
    Emitter<DriverPortalState> emit,
  ) async {
    _stopCountdown();
    final dispatch = state.incomingDispatch;
    final profileId = state.driverProfileId;

    if (dispatch != null && profileId != null) {
      _convexClient.mutation(
        'mobility:declineTripDispatch',
        args: {
          'tripId': dispatch.id,
          'driverProfileId': profileId,
        },
      ).ignore();
    }

    emit(state.copyWith(
      clearIncomingDispatch: true,
      countdownSeconds: 15,
      errorMessage: 'Dispatch timed out. Auto-routed to next closest driver.',
    ));
  }

  Future<void> _onDeclineDispatch(
    DeclineDispatchEvent event,
    Emitter<DriverPortalState> emit,
  ) async {
    _stopCountdown();
    final dispatch = state.incomingDispatch;
    final profileId = state.driverProfileId;

    if (dispatch != null && profileId != null) {
      await _convexClient.mutation(
        'mobility:declineTripDispatch',
        args: {
          'tripId': dispatch.id,
          'driverProfileId': profileId,
        },
      );
    }

    emit(state.copyWith(
      clearIncomingDispatch: true,
      countdownSeconds: 15,
      errorMessage: 'Job declined. Returning to standby.',
    ));
  }

  // ═══════════════════════════════════════════════════════════════════
  //             ACTIVE TRIP LIFECYCLE (STEPS 1 TO 4)
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onAcceptDispatch(
    AcceptDispatchEvent event,
    Emitter<DriverPortalState> emit,
  ) async {
    _stopCountdown();
    final dispatch = state.incomingDispatch;
    final profileId = state.driverProfileId;

    if (dispatch == null || profileId == null) return;

    emit(state.copyWith(isProcessingAction: true));

    try {
      final result = await _convexClient.mutation(
        'mobility:acceptTripDispatch',
        args: {
          'tripId': dispatch.id,
          'driverProfileId': profileId,
          if (state.vehicleId != null) 'vehicleId': state.vehicleId,
        },
      );

      if (!result.success) {
        emit(state.copyWith(
          isProcessingAction: false,
          clearIncomingDispatch: true,
          errorMessage: result.errorMessage ?? 'Failed to accept dispatch. It may have been taken.',
        ));
        return;
      }

      // Update local SQLite DAO
      await _tripsDao.updateStatus(
        tripId: dispatch.id,
        status: 'accepted',
        driverId: profileId,
      );

      // Create active trip entity with accepted status
      final acceptedTrip = TripDeliveryEntity(
        id: dispatch.id,
        passengerId: dispatch.passengerId,
        driverId: profileId,
        vehicleId: state.vehicleId,
        serviceType: dispatch.serviceType,
        pickupLat: dispatch.pickupLat,
        pickupLng: dispatch.pickupLng,
        pickupAddressText: dispatch.pickupAddressText,
        dropoffLat: dispatch.dropoffLat,
        dropoffLng: dispatch.dropoffLng,
        dropoffAddressText: dispatch.dropoffAddressText,
        status: TripDeliveryStatus.accepted,
        fareAmount: dispatch.fareAmount,
        currency: dispatch.currency,
        paymentMethod: dispatch.paymentMethod,
        distanceKm: dispatch.distanceKm,
        durationMins: dispatch.durationMins,
        packageDetails: dispatch.packageDetails,
        createdAt: dispatch.createdAt,
        verificationPin: dispatch.verificationPin,
        driverPayout: dispatch.driverPayout,
        passengerName: dispatch.passengerName,
        passengerPhone: dispatch.passengerPhone,
        passengerRating: dispatch.passengerRating,
      );

      emit(state.copyWith(
        isProcessingAction: false,
        clearIncomingDispatch: true,
        activeTrip: acceptedTrip,
        lifecycleStep: DriverTripLifecycleStep.navigatingToPickup,
        isAvailable: false,
        successMessage: 'Dispatch Accepted! Navigate to pickup location.',
      ));
    } catch (e) {
      emit(state.copyWith(
        isProcessingAction: false,
        clearIncomingDispatch: true,
        errorMessage: 'Error accepting dispatch: $e',
      ));
    }
  }

  // Step 2: Driver arrived at pickup
  Future<void> _onDriverArrived(
    DriverArrivedAtPickupEvent event,
    Emitter<DriverPortalState> emit,
  ) async {
    final trip = state.activeTrip;
    final profileId = state.driverProfileId;
    if (trip == null || profileId == null) return;

    emit(state.copyWith(isProcessingAction: true));

    try {
      await _convexClient.mutation(
        'mobility:driverArrivedAtPickup',
        args: {
          'tripId': trip.id,
          'driverProfileId': profileId,
        },
      );

      await _tripsDao.updateStatus(
        tripId: trip.id,
        status: 'arrived',
      );

      emit(state.copyWith(
        isProcessingAction: false,
        lifecycleStep: DriverTripLifecycleStep.arrivedAtPickup,
        successMessage: 'Passenger notified: You have arrived at pickup!',
      ));
    } catch (e) {
      emit(state.copyWith(
        isProcessingAction: false,
        errorMessage: 'Failed to update arrival: $e',
      ));
    }
  }

  // Step 3: Verify 4-digit PIN & Start Trip
  Future<void> _onVerifyPin(
    VerifyPinAndStartTripEvent event,
    Emitter<DriverPortalState> emit,
  ) async {
    final trip = state.activeTrip;
    final profileId = state.driverProfileId;
    if (trip == null || profileId == null) return;

    emit(state.copyWith(isProcessingAction: true, clearPinError: true));

    try {
      final result = await _convexClient.mutation(
        'mobility:verifyPinAndStartTrip',
        args: {
          'tripId': trip.id,
          'driverProfileId': profileId,
          'pin': event.pin,
        },
      );

      if (!result.success) {
        emit(state.copyWith(
          isProcessingAction: false,
          pinErrorMessage: result.errorMessage ?? 'Incorrect 4-digit PIN. Ask passenger for code.',
        ));
        return;
      }

      await _tripsDao.updateStatus(
        tripId: trip.id,
        status: 'in_progress',
      );

      emit(state.copyWith(
        isProcessingAction: false,
        clearPinError: true,
        lifecycleStep: DriverTripLifecycleStep.inProgress,
        successMessage: 'PIN Verified! Trip is now in progress.',
      ));
    } catch (e) {
      emit(state.copyWith(
        isProcessingAction: false,
        pinErrorMessage: 'PIN verification failed: $e',
      ));
    }
  }

  // Step 4: Arrived at destination -> open completion dialog
  void _onCompleteTrip(
    CompleteTripEvent event,
    Emitter<DriverPortalState> emit,
  ) {
    emit(state.copyWith(
      lifecycleStep: DriverTripLifecycleStep.tripCompleted,
    ));
  }

  // Step 4 finish: Release payment and submit rating
  Future<void> _onSubmitRating(
    SubmitPassengerRatingEvent event,
    Emitter<DriverPortalState> emit,
  ) async {
    final trip = state.activeTrip;
    final profileId = state.driverProfileId;
    if (trip == null || profileId == null) return;

    emit(state.copyWith(isProcessingAction: true));

    try {
      await _convexClient.mutation(
        'mobility:completeTripAndReleasePayment',
        args: {
          'tripId': trip.id,
          'driverProfileId': profileId,
          'passengerRating': event.rating,
          if (event.notes != null) 'ratingNotes': event.notes,
        },
      );

      final payout = trip.driverPayout ?? (trip.fareAmount * 0.85);

      await _tripsDao.updateStatus(
        tripId: trip.id,
        status: 'completed',
      );

      emit(state.copyWith(
        isProcessingAction: false,
        todaysEarnings: state.todaysEarnings + payout,
        completedTripsCount: state.completedTripsCount + 1,
        successMessage: 'Trip settled! SLE ${payout.toStringAsFixed(2)} deposited into your wallet balance.',
      ));
    } catch (e) {
      emit(state.copyWith(
        isProcessingAction: false,
        errorMessage: 'Failed to complete trip: $e',
      ));
    }
  }

  void _onResetAfterTrip(
    ResetAfterTripEvent event,
    Emitter<DriverPortalState> emit,
  ) {
    emit(state.copyWith(
      clearActiveTrip: true,
      lifecycleStep: DriverTripLifecycleStep.idle,
      isAvailable: true,
    ));
  }

  void _onClearFeedback(
    ClearDriverPortalFeedbackEvent event,
    Emitter<DriverPortalState> emit,
  ) {
    emit(state.copyWith(
      errorMessage: null,
      successMessage: null,
    ));
  }

  @override
  Future<void> close() {
    _stopDispatchPolling();
    _stopCountdown();
    _heartbeatService.stopHeartbeat();
    return super.close();
  }
}
