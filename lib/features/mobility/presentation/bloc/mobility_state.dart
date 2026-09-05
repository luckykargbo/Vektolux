// lib/features/mobility/presentation/bloc/mobility_state.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Mobility BLoC State
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import '../../domain/entities/mobility_vehicle_entity.dart';
import '../../domain/entities/ride_entity.dart';
import '../../domain/entities/nearby_driver_entity.dart';
import '../../domain/entities/trip_delivery_entity.dart';
import '../../domain/entities/vehicle_category_catalog.dart';
import '../../domain/services/fare_calculation_service.dart';
import '../../../real_estate/domain/entities/property_listing_entity.dart';

enum MobilityHomeMode {
  rideHailing, // Mode 1: Request Immediate Ride
  rental,      // Mode 2: Rent a Car / Truck
  buyVehicle,  // Mode 3: Buy a Vehicle
  realEstate,  // Mode 4: Real Estate Properties & Hourly Stays
}

class MobilityState extends Equatable {
  final MobilityHomeMode mode;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  // Active Ride & Delivery tracking
  final RideEntity? activeRide;
  final TripDeliveryEntity? activeTripDelivery;
  final bool isSearchingDriver;

  // Map markers
  final List<VehicleListingEntity> nearbyVehicles;
  final double currentLat;
  final double currentLng;

  // Locations
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String dropoffAddress;
  final double dropoffLat;
  final double dropoffLng;

  // Selected Category & Fare
  final MobilityVehicleType selectedVehicleType;
  final Map<MobilityVehicleType, VehicleCategoryOption> vehicleOptions;
  final double estimatedDistanceKm;
  final int estimatedDurationMin;
  final bool isSubmittingRide;

  // Ride vs. Delivery Booking Mode & Categorized Tier Estimates
  final String bookingServiceType; // 'ride' | 'delivery'
  final BookingVehicleCategory selectedBookingCategory;
  final Map<BookingVehicleCategory, CalculatedTierEstimate> calculatedTierEstimates;
  final DeliveryPackageDetails? deliveryPackageDetails;

  // Rental Mode state
  final bool isRentalWithDriver;
  final int rentalDays;
  final List<VehicleListingEntity> availableRentalVehicles;

  // Sales Mode state
  final List<VehicleListingEntity> catalogSalesVehicles;

  // Real Estate Mode state
  final List<PropertyListingEntity> realEstateListings;

  // Location, Geofencing & On-Demand Drivers
  final bool isPinDragMode;
  final bool isVpnMismatch;
  final bool showLocationPermissionModal;
  final List<NearbyDriverEntity> onDemandDrivers;

  const MobilityState({
    this.mode = MobilityHomeMode.rideHailing,
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
    this.activeRide,
    this.activeTripDelivery,
    this.isSearchingDriver = false,
    this.nearbyVehicles = const [],
    this.currentLat = 8.484,
    this.currentLng = -13.229,
    this.pickupAddress = 'Current Location (Freetown Central)',
    this.pickupLat = 8.484,
    this.pickupLng = -13.229,
    this.dropoffAddress = 'Lumley Beach Rd, Aberdeen',
    this.dropoffLat = 8.490,
    this.dropoffLng = -13.285,
    this.selectedVehicleType = MobilityVehicleType.taxi,
    this.vehicleOptions = const {},
    this.estimatedDistanceKm = 5.2,
    this.estimatedDurationMin = 18,
    this.isSubmittingRide = false,
    this.bookingServiceType = 'ride',
    this.selectedBookingCategory = BookingVehicleCategory.standardRide,
    this.calculatedTierEstimates = const {},
    this.deliveryPackageDetails,
    this.isRentalWithDriver = true,
    this.rentalDays = 3,
    this.availableRentalVehicles = const [],
    this.catalogSalesVehicles = const [],
    this.realEstateListings = const [],
    this.isPinDragMode = false,
    this.isVpnMismatch = false,
    this.showLocationPermissionModal = false,
    this.onDemandDrivers = const [],
  });

  MobilityState copyWith({
    MobilityHomeMode? mode,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    RideEntity? activeRide,
    bool clearActiveRide = false,
    List<VehicleListingEntity>? nearbyVehicles,
    double? currentLat,
    double? currentLng,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    MobilityVehicleType? selectedVehicleType,
    Map<MobilityVehicleType, VehicleCategoryOption>? vehicleOptions,
    double? estimatedDistanceKm,
    int? estimatedDurationMin,
    bool? isSubmittingRide,
    String? bookingServiceType,
    BookingVehicleCategory? selectedBookingCategory,
    Map<BookingVehicleCategory, CalculatedTierEstimate>? calculatedTierEstimates,
    DeliveryPackageDetails? deliveryPackageDetails,
    bool clearDeliveryPackageDetails = false,
    bool? isRentalWithDriver,
    int? rentalDays,
    List<VehicleListingEntity>? availableRentalVehicles,
    List<VehicleListingEntity>? catalogSalesVehicles,
    List<PropertyListingEntity>? realEstateListings,
    bool? isPinDragMode,
    bool? isVpnMismatch,
    bool? showLocationPermissionModal,
    List<NearbyDriverEntity>? onDemandDrivers,
    TripDeliveryEntity? activeTripDelivery,
    bool clearActiveTripDelivery = false,
    bool? isSearchingDriver,
  }) {
    return MobilityState(
      mode: mode ?? this.mode,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      successMessage: successMessage,
      activeRide: clearActiveRide ? null : (activeRide ?? this.activeRide),
      activeTripDelivery: clearActiveTripDelivery
          ? null
          : (activeTripDelivery ?? this.activeTripDelivery),
      isSearchingDriver: isSearchingDriver ?? this.isSearchingDriver,
      nearbyVehicles: nearbyVehicles ?? this.nearbyVehicles,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      dropoffAddress: dropoffAddress ?? this.dropoffAddress,
      dropoffLat: dropoffLat ?? this.dropoffLat,
      dropoffLng: dropoffLng ?? this.dropoffLng,
      selectedVehicleType: selectedVehicleType ?? this.selectedVehicleType,
      vehicleOptions: vehicleOptions ?? this.vehicleOptions,
      estimatedDistanceKm: estimatedDistanceKm ?? this.estimatedDistanceKm,
      estimatedDurationMin: estimatedDurationMin ?? this.estimatedDurationMin,
      isSubmittingRide: isSubmittingRide ?? this.isSubmittingRide,
      bookingServiceType: bookingServiceType ?? this.bookingServiceType,
      selectedBookingCategory:
          selectedBookingCategory ?? this.selectedBookingCategory,
      calculatedTierEstimates:
          calculatedTierEstimates ?? this.calculatedTierEstimates,
      deliveryPackageDetails: clearDeliveryPackageDetails
          ? null
          : (deliveryPackageDetails ?? this.deliveryPackageDetails),
      isRentalWithDriver: isRentalWithDriver ?? this.isRentalWithDriver,
      rentalDays: rentalDays ?? this.rentalDays,
      availableRentalVehicles:
          availableRentalVehicles ?? this.availableRentalVehicles,
      catalogSalesVehicles: catalogSalesVehicles ?? this.catalogSalesVehicles,
      realEstateListings: realEstateListings ?? this.realEstateListings,
      isPinDragMode: isPinDragMode ?? this.isPinDragMode,
      isVpnMismatch: isVpnMismatch ?? this.isVpnMismatch,
      showLocationPermissionModal:
          showLocationPermissionModal ?? this.showLocationPermissionModal,
      onDemandDrivers: onDemandDrivers ?? this.onDemandDrivers,
    );
  }

  /// Check if user is currently engaged in an active ride, delivery, or finding search.
  bool get hasActiveRide =>
      isSearchingDriver ||
      (activeTripDelivery != null && activeTripDelivery!.status.isActive) ||
      (activeRide != null && activeRide!.status.isActive);

  /// Current upfront calculated estimate for the selected booking tier.
  CalculatedTierEstimate? get currentCalculatedEstimate =>
      calculatedTierEstimates[selectedBookingCategory];

  /// Get current selected vehicle category option.
  VehicleCategoryOption? get selectedOption => vehicleOptions[selectedVehicleType];

  @override
  List<Object?> get props => [
        mode,
        isLoading,
        errorMessage,
        successMessage,
        activeRide,
        activeTripDelivery,
        isSearchingDriver,
        nearbyVehicles,
        currentLat,
        currentLng,
        pickupAddress,
        pickupLat,
        pickupLng,
        dropoffAddress,
        dropoffLat,
        dropoffLng,
        selectedVehicleType,
        vehicleOptions,
        estimatedDistanceKm,
        estimatedDurationMin,
        isSubmittingRide,
        bookingServiceType,
        selectedBookingCategory,
        calculatedTierEstimates,
        deliveryPackageDetails,
        isRentalWithDriver,
        rentalDays,
        availableRentalVehicles,
        catalogSalesVehicles,
        realEstateListings,
        isPinDragMode,
        isVpnMismatch,
        showLocationPermissionModal,
        onDemandDrivers,
      ];
}
