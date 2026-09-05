// lib/features/mobility/presentation/bloc/mobility_event.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Mobility BLoC Events
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import '../../domain/entities/mobility_vehicle_entity.dart';
import '../../domain/entities/trip_delivery_entity.dart';
import '../../domain/entities/vehicle_category_catalog.dart';

abstract class MobilityEvent extends Equatable {
  const MobilityEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load & stream subscription for user's active ride and nearby drivers.
class LoadMobilityHomeEvent extends MobilityEvent {
  final String userId;
  final double currentLat;
  final double currentLng;

  const LoadMobilityHomeEvent({
    required this.userId,
    required this.currentLat,
    required this.currentLng,
  });

  @override
  List<Object?> get props => [userId, currentLat, currentLng];
}

/// Switch between the 3 bottom panel modes:
/// 1 = Immediate Ride, 2 = Rent Vehicle, 3 = Buy Vehicle
class SwitchMobilityModeEvent extends MobilityEvent {
  final int modeIndex; // 0: Ride, 1: Rent, 2: Buy

  const SwitchMobilityModeEvent(this.modeIndex);

  @override
  List<Object?> get props => [modeIndex];
}

/// Select a vehicle category (Bike, Taxi, Delivery Van, Truck).
class SelectVehicleCategoryEvent extends MobilityEvent {
  final MobilityVehicleType vehicleType;

  const SelectVehicleCategoryEvent(this.vehicleType);

  @override
  List<Object?> get props => [vehicleType];
}

/// Update pickup or destination locations and recalculate fare estimates.
class UpdateLocationsEvent extends MobilityEvent {
  final String? pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final String? dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;

  const UpdateLocationsEvent({
    this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    this.dropoffAddress,
    this.dropoffLat,
    this.dropoffLng,
  });

  @override
  List<Object?> get props => [
        pickupAddress,
        pickupLat,
        pickupLng,
        dropoffAddress,
        dropoffLat,
        dropoffLng,
      ];
}

/// Dispatch immediate ride request.
class RequestRideEvent extends MobilityEvent {
  final String passengerId;

  const RequestRideEvent(this.passengerId);

  @override
  List<Object?> get props => [passengerId];
}

/// Cancel active ride.
class CancelRideEvent extends MobilityEvent {
  final String reason;

  const CancelRideEvent({this.reason = 'Cancelled by passenger'});

  @override
  List<Object?> get props => [reason];
}

/// Toggle rental driver option (self-drive vs with dedicated driver).
class ToggleRentalDriverOptionEvent extends MobilityEvent {
  final bool isWithDriver;

  const ToggleRentalDriverOptionEvent(this.isWithDriver);

  @override
  List<Object?> get props => [isWithDriver];
}

/// Change rental days duration.
class UpdateRentalDaysEvent extends MobilityEvent {
  final int days;

  const UpdateRentalDaysEvent(this.days);

  @override
  List<Object?> get props => [days];
}

/// Detect GPS location with automated permission handling & VPN fallback.
class DetectUserLocationEvent extends MobilityEvent {
  const DetectUserLocationEvent();
}

/// Manually set pickup location (from landmark autocomplete or reverse geocoding).
class SetManualPickupLocationEvent extends MobilityEvent {
  final double lat;
  final double lng;
  final String address;

  const SetManualPickupLocationEvent({
    required this.lat,
    required this.lng,
    required this.address,
  });

  @override
  List<Object?> get props => [lat, lng, address];
}

/// Toggle interactive pin-drag mode on the map.
class TogglePinDragModeEvent extends MobilityEvent {
  final bool isEnabled;

  const TogglePinDragModeEvent(this.isEnabled);

  @override
  List<Object?> get props => [isEnabled];
}

/// Dismiss the VPN / IP mismatch notification banner.
class DismissVpnMismatchEvent extends MobilityEvent {
  const DismissVpnMismatchEvent();
}

/// Dismiss location permission modal.
class DismissLocationPermissionModalEvent extends MobilityEvent {
  const DismissLocationPermissionModalEvent();
}

/// Lightweight debounced query for passenger screen fetching nearby drivers within 3-5km.
class FetchNearbyDriversDebouncedEvent extends MobilityEvent {
  final double lat;
  final double lng;
  final double radiusKm;

  const FetchNearbyDriversDebouncedEvent({
    required this.lat,
    required this.lng,
    this.radiusKm = 4.0,
  });

  @override
  List<Object?> get props => [lat, lng, radiusKm];
}

/// Switch booking mode between 'ride' and 'delivery'.
class SwitchBookingServiceTypeEvent extends MobilityEvent {
  final String serviceType; // 'ride' | 'delivery'
  const SwitchBookingServiceTypeEvent(this.serviceType);

  @override
  List<Object?> get props => [serviceType];
}

/// Select a booking vehicle tier (standard_ride, comfort_ride, kekeh_tricycle, courier_bike).
class SelectBookingCategoryEvent extends MobilityEvent {
  final BookingVehicleCategory category;
  const SelectBookingCategoryEvent(this.category);

  @override
  List<Object?> get props => [category];
}

/// Update recipient and parcel details for package delivery.
class UpdateDeliveryDetailsEvent extends MobilityEvent {
  final DeliveryPackageDetails details;
  const UpdateDeliveryDetailsEvent(this.details);

  @override
  List<Object?> get props => [details];
}

/// Confirm trip/delivery request — broadcasts to nearby drivers and shows pulsing radar.
class ConfirmBookingRequestEvent extends MobilityEvent {
  final String passengerId;
  final String paymentMethod;

  const ConfirmBookingRequestEvent({
    required this.passengerId,
    this.paymentMethod = 'wallet',
  });

  @override
  List<Object?> get props => [passengerId, paymentMethod];
}

/// Cancel the active finding driver search radar.
class CancelSearchingRequestEvent extends MobilityEvent {
  const CancelSearchingRequestEvent();
}

/// Driver accepted the broadcasted trip/delivery.
class DriverAcceptedTripEvent extends MobilityEvent {
  final TripDeliveryEntity trip;
  const DriverAcceptedTripEvent(this.trip);

  @override
  List<Object?> get props => [trip];
}

