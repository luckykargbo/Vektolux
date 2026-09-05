// lib/features/mobility/presentation/bloc/driver_portal_event.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Portal Events
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import '../../domain/entities/trip_delivery_entity.dart';

abstract class DriverPortalEvent extends Equatable {
  const DriverPortalEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize driver portal, fetch/create driver profile, set initial GPS.
class InitDriverPortalEvent extends DriverPortalEvent {
  final String userId;
  final double initialLat;
  final double initialLng;

  const InitDriverPortalEvent({
    required this.userId,
    this.initialLat = 8.484,
    this.initialLng = -13.229,
  });

  @override
  List<Object?> get props => [userId, initialLat, initialLng];
}

/// Driver switches top Online/Offline toggle.
class ToggleDriverOnlineStatusEvent extends DriverPortalEvent {
  final bool isOnline;

  const ToggleDriverOnlineStatusEvent(this.isOnline);

  @override
  List<Object?> get props => [isOnline];
}

/// Periodic or GPS movement coordinate update.
class UpdateDriverCoordinatesEvent extends DriverPortalEvent {
  final double lat;
  final double lng;

  const UpdateDriverCoordinatesEvent({required this.lat, required this.lng});

  @override
  List<Object?> get props => [lat, lng];
}

/// Reactive query / poll detected a new incoming trip/delivery dispatch.
class IncomingDispatchPolledEvent extends DriverPortalEvent {
  final TripDeliveryEntity dispatch;

  const IncomingDispatchPolledEvent(this.dispatch);

  @override
  List<Object?> get props => [dispatch];
}

/// Driver accepted the incoming dispatch card.
class AcceptDispatchEvent extends DriverPortalEvent {
  const AcceptDispatchEvent();
}

/// Driver declined the incoming dispatch card (or dismissed).
class DeclineDispatchEvent extends DriverPortalEvent {
  final String reason;

  const DeclineDispatchEvent({this.reason = 'Declined by driver'});

  @override
  List<Object?> get props => [reason];
}

/// 15-second circular countdown timer tick.
class DispatchCountdownTickEvent extends DriverPortalEvent {
  final int remainingSeconds;

  const DispatchCountdownTickEvent(this.remainingSeconds);

  @override
  List<Object?> get props => [remainingSeconds];
}

/// 15-second timer reached 0 without response -> auto-decline to dispatch next driver.
class DispatchTimeoutEvent extends DriverPortalEvent {
  const DispatchTimeoutEvent();
}

/// Step 2: Driver arrived at passenger pickup location.
class DriverArrivedAtPickupEvent extends DriverPortalEvent {
  const DriverArrivedAtPickupEvent();
}

/// Step 3: Driver enters 4-digit passenger PIN to start the trip.
class VerifyPinAndStartTripEvent extends DriverPortalEvent {
  final String pin;

  const VerifyPinAndStartTripEvent(this.pin);

  @override
  List<Object?> get props => [pin];
}

/// Step 4: Driver completes the trip at dropoff location.
class CompleteTripEvent extends DriverPortalEvent {
  const CompleteTripEvent();
}

/// Step 4 finish: Driver submits star rating (1-5) and feedback for the passenger.
class SubmitPassengerRatingEvent extends DriverPortalEvent {
  final int rating;
  final String? notes;

  const SubmitPassengerRatingEvent({required this.rating, this.notes});

  @override
  List<Object?> get props => [rating, notes];
}

/// Dismiss trip completed summary and return to online idle state.
class ResetAfterTripEvent extends DriverPortalEvent {
  const ResetAfterTripEvent();
}

/// Clear transient feedback messages (snackbars).
class ClearDriverPortalFeedbackEvent extends DriverPortalEvent {
  const ClearDriverPortalFeedbackEvent();
}
