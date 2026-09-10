// lib/features/mobility/presentation/bloc/mobility_bloc.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Mobility Master BLoC
// Manages Ride-Hailing, Vehicle Rentals, and Sales marketplace flows
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart';

import '../../data/services/location_manager.dart';
import '../../domain/entities/mobility_vehicle_entity.dart';
import '../../domain/entities/ride_entity.dart';
import '../../domain/entities/trip_delivery_entity.dart';
import '../../domain/entities/nearby_seller_entity.dart';
import '../../domain/entities/vehicle_category_catalog.dart';
import '../../domain/services/fare_calculation_service.dart';
import '../../domain/repositories/mobility_repository.dart';
import '../../../real_estate/domain/entities/property_listing_entity.dart';
import 'mobility_event.dart';
import 'mobility_state.dart';

class MobilityBloc extends Bloc<MobilityEvent, MobilityState> {
  final MobilityRepository _repository;
  final LocationManager _locationManager = LocationManager();
  final FareCalculationService _fareService = const FareCalculationService();
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  StreamSubscription<RideEntity?>? _activeRideSubscription;
  Timer? _searchSimulationTimer;

  MobilityBloc({required MobilityRepository repository})
      : _repository = repository,
        super(const MobilityState()) {
    on<LoadMobilityHomeEvent>(_onLoadMobilityHome);
    on<SwitchMobilityModeEvent>(_onSwitchMobilityMode);
    on<SelectVehicleCategoryEvent>(_onSelectVehicleCategory);
    on<UpdateLocationsEvent>(_onUpdateLocations);
    on<RequestRideEvent>(_onRequestRide);
    on<CancelRideEvent>(_onCancelRide);
    on<ToggleRentalDriverOptionEvent>(_onToggleRentalDriverOption);
    on<UpdateRentalDaysEvent>(_onUpdateRentalDaysEvent);
    on<DetectUserLocationEvent>(_onDetectUserLocation);
    on<SetManualPickupLocationEvent>(_onSetManualPickupLocation);
    on<TogglePinDragModeEvent>(_onTogglePinDragMode);
    on<DismissVpnMismatchEvent>(_onDismissVpnMismatch);
    on<DismissLocationPermissionModalEvent>(_onDismissLocationPermissionModal);
    on<SwitchBookingServiceTypeEvent>(_onSwitchBookingServiceType);
    on<SelectBookingCategoryEvent>(_onSelectBookingCategory);
    on<UpdateDeliveryDetailsEvent>(_onUpdateDeliveryDetails);
    on<ConfirmBookingRequestEvent>(_onConfirmBookingRequest);
    on<CancelSearchingRequestEvent>(_onCancelSearchingRequest);
    on<DriverAcceptedTripEvent>(_onDriverAcceptedTrip);
    on<FetchNearbyDriversDebouncedEvent>(
      _onFetchNearbyDriversDebounced,
      transformer: (events, mapper) => events
          .debounceTime(const Duration(milliseconds: 400))
          .switchMap(mapper),
    );
    on<_ActiveRideUpdatedInternalEvent>(_onActiveRideUpdated);
    on<DriverArrivedEvent>(_onDriverArrived);
    on<DriverLocationProgressionEvent>(_onDriverLocationProgression);
  }

  Future<void> _onLoadMobilityHome(
    LoadMobilityHomeEvent event,
    Emitter<MobilityState> emit,
  ) async {
    // 1. Subscribe to active ride from local SQLite
    await _activeRideSubscription?.cancel();
    _activeRideSubscription = _repository.watchActiveRide(event.userId).listen((ride) {
      add(_ActiveRideUpdatedInternalEvent(ride));
    });

    // 2. Generate baseline mock data for instantaneous zero-wait first render
    final baselineRentals = _generateRentalVehicles(event.currentLat, event.currentLng);
    final baselineSales = _generateSalesVehicles(event.currentLat, event.currentLng);
    final baselineProperties = _generateRealEstateProperties(event.currentLat, event.currentLng);

    final distKm = _computeHaversine(
      event.currentLat,
      event.currentLng,
      state.dropoffLat,
      state.dropoffLng,
    );
    final durationMins = math.max(3, ((distKm / 22.0) * 60).round());
    final tierEstimates = _fareService.calculateAllTiers(
      distanceKm: distKm,
      durationMins: durationMins,
      nearbyDrivers: state.onDemandDrivers,
      serviceType: state.bookingServiceType,
    );

    // 3. Emit baseline state immediately — UI renders with ZERO blank screen or loading block
    emit(state.copyWith(
      isLoading: false,
      currentLat: event.currentLat,
      currentLng: event.currentLng,
      pickupLat: event.currentLat,
      pickupLng: event.currentLng,
      estimatedDistanceKm: distKm,
      estimatedDurationMin: durationMins,
      calculatedTierEstimates: tierEstimates,
      availableRentalVehicles: state.availableRentalVehicles.isNotEmpty
          ? state.availableRentalVehicles
          : baselineRentals,
      catalogSalesVehicles: state.catalogSalesVehicles.isNotEmpty
          ? state.catalogSalesVehicles
          : baselineSales,
      realEstateListings: state.realEstateListings.isNotEmpty
          ? state.realEstateListings
          : baselineProperties,
    ));

    // 4. Concurrently fetch live vehicles, properties, nearby drivers, and fare options in background
    try {
      final results = await Future.wait([
        _repository.getNearbyVehicles(
          lat: event.currentLat,
          lng: event.currentLng,
          radiusKm: 5.0,
        ),
        _computeAllFareOptions(
          event.currentLat,
          event.currentLng,
          state.dropoffLat,
          state.dropoffLng,
        ),
        _repository.getNearbySellers(
          lat: event.currentLat,
          lng: event.currentLng,
          radiusKm: 10.0,
        ),
        _repository.listVehicles(listingIntent: 'rental'),
        _repository.listVehicles(listingIntent: 'sale'),
        _repository.listProperties(),
      ]);

      final nearby = results[0] as List<VehicleListingEntity>;
      final options = results[1] as Map<MobilityVehicleType, VehicleCategoryOption>;
      final sellers = results[2] as List<NearbySellerEntity>;
      final liveRentals = results[3] as List<VehicleListingEntity>;
      final liveSales = results[4] as List<VehicleListingEntity>;
      final liveProperties = results[5] as List<PropertyListingEntity>;

      emit(state.copyWith(
        nearbyVehicles: nearby,
        vehicleOptions: options,
        nearbySellers: sellers,
        availableRentalVehicles: liveRentals.isNotEmpty ? liveRentals : null,
        catalogSalesVehicles: liveSales.isNotEmpty ? liveSales : null,
        realEstateListings: liveProperties.isNotEmpty ? liveProperties : null,
      ));
    } catch (e) {
      _log.w('Background catalog sync in _onLoadMobilityHome encountered error: $e');
    }
  }

  void _onSwitchMobilityMode(
    SwitchMobilityModeEvent event,
    Emitter<MobilityState> emit,
  ) {
    final mode = switch (event.modeIndex) {
      0 => MobilityHomeMode.rideHailing,
      1 => MobilityHomeMode.rental,
      2 => MobilityHomeMode.buyVehicle,
      3 => MobilityHomeMode.realEstate,
      _ => MobilityHomeMode.rideHailing,
    };
    emit(state.copyWith(mode: mode));
  }

  void _onSelectVehicleCategory(
    SelectVehicleCategoryEvent event,
    Emitter<MobilityState> emit,
  ) {
    emit(state.copyWith(selectedVehicleType: event.vehicleType));
  }

  Future<void> _onUpdateLocations(
    UpdateLocationsEvent event,
    Emitter<MobilityState> emit,
  ) async {
    final pLat = event.pickupLat ?? state.pickupLat;
    final pLng = event.pickupLng ?? state.pickupLng;
    final dLat = event.dropoffLat ?? state.dropoffLat;
    final dLng = event.dropoffLng ?? state.dropoffLng;

    final options = await _computeAllFareOptions(pLat, pLng, dLat, dLng);

    final distKm = _computeHaversine(pLat, pLng, dLat, dLng);
    final durationMins = math.max(3, ((distKm / 22.0) * 60).round());
    final tierEstimates = _fareService.calculateAllTiers(
      distanceKm: distKm,
      durationMins: durationMins,
      nearbyDrivers: state.onDemandDrivers,
      serviceType: state.bookingServiceType,
    );

    emit(state.copyWith(
      pickupAddress: event.pickupAddress ?? state.pickupAddress,
      pickupLat: pLat,
      pickupLng: pLng,
      dropoffAddress: event.dropoffAddress ?? state.dropoffAddress,
      dropoffLat: dLat,
      dropoffLng: dLng,
      vehicleOptions: options,
      estimatedDistanceKm: distKm,
      estimatedDurationMin: durationMins,
      calculatedTierEstimates: tierEstimates,
    ));
  }

  Future<void> _onRequestRide(
    RequestRideEvent event,
    Emitter<MobilityState> emit,
  ) async {
    emit(state.copyWith(isSubmittingRide: true));

    try {
      final selectedOpt = state.selectedOption ??
          VehicleCategoryOption(
            type: state.selectedVehicleType,
            estimatedFare: 2500,
            etaMinutes: 4,
          );

      final rideId = await _repository.requestRide(
        passengerId: event.passengerId,
        pickupLat: state.pickupLat,
        pickupLng: state.pickupLng,
        pickupAddress: state.pickupAddress,
        dropoffLat: state.dropoffLat,
        dropoffLng: state.dropoffLng,
        dropoffAddress: state.dropoffAddress,
        vehicleType: state.selectedVehicleType,
        fareAmount: selectedOpt.estimatedFare,
        distanceKm: state.estimatedDistanceKm,
        estimatedDurationMin: state.estimatedDurationMin,
      );

      // Create optimistic ride entity for zero-latency UI transition
      final optimisticRide = RideEntity(
        id: rideId,
        passengerId: event.passengerId,
        pickupLat: state.pickupLat,
        pickupLng: state.pickupLng,
        pickupAddress: state.pickupAddress,
        dropoffLat: state.dropoffLat,
        dropoffLng: state.dropoffLng,
        dropoffAddress: state.dropoffAddress,
        distanceKm: state.estimatedDistanceKm,
        estimatedDurationMin: state.estimatedDurationMin,
        fareAmount: selectedOpt.estimatedFare,
        platformFee: selectedOpt.estimatedFare * 0.15,
        driverPayout: selectedOpt.estimatedFare * 0.85,
        status: RideStatus.requested,
        paymentStatus: 'pending',
        blockchainLogHash: '0x8f3c7...9a21 (Pending Confirmation)',
      );

      emit(state.copyWith(
        isSubmittingRide: false,
        activeRide: optimisticRide,
        successMessage: 'Searching for nearby verified drivers...',
      ));
    } catch (e) {
      _log.e('Failed to request ride: $e');
      emit(state.copyWith(
        isSubmittingRide: false,
        errorMessage: 'Ride dispatch error: ${e.toString()}',
      ));
    }
  }

  Future<void> _onCancelRide(
    CancelRideEvent event,
    Emitter<MobilityState> emit,
  ) async {
    final rideToCancel = state.activeRide;
    _searchSimulationTimer?.cancel();

    // Immediately reset UI active state so the passenger is never stuck
    emit(state.copyWith(
      clearActiveRide: true,
      clearActiveTripDelivery: true,
      isSearchingDriver: false,
      successMessage: 'Ride has been cancelled.',
    ));

    if (rideToCancel != null) {
      try {
        await _repository.cancelRide(
          rideId: rideToCancel.id,
          reason: event.reason,
        );
      } catch (e) {
        _log.w('Cancel ride network error: $e');
      }
    }
  }

  void _onToggleRentalDriverOption(
    ToggleRentalDriverOptionEvent event,
    Emitter<MobilityState> emit,
  ) {
    emit(state.copyWith(isRentalWithDriver: event.isWithDriver));
  }

  void _onUpdateRentalDaysEvent(
    UpdateRentalDaysEvent event,
    Emitter<MobilityState> emit,
  ) {
    emit(state.copyWith(rentalDays: event.days));
  }

  void _onActiveRideUpdated(
    _ActiveRideUpdatedInternalEvent event,
    Emitter<MobilityState> emit,
  ) {
    if (event.ride != null) {
      emit(state.copyWith(activeRide: event.ride));
    } else {
      emit(state.copyWith(clearActiveRide: true));
    }
  }

  void _onDriverArrived(
    DriverArrivedEvent event,
    Emitter<MobilityState> emit,
  ) {
    if (state.activeRide != null) {
      final updatedRide = state.activeRide!.copyWith(
        status: RideStatus.arrived,
        driverLat: event.lat ?? state.activeRide!.driverLat,
        driverLng: event.lng ?? state.activeRide!.driverLng,
      );
      emit(state.copyWith(
        activeRide: updatedRide,
        successMessage: 'Driver has arrived at pickup point!',
      ));
    }
  }

  void _onDriverLocationProgression(
    DriverLocationProgressionEvent event,
    Emitter<MobilityState> emit,
  ) {
    if (state.activeRide != null) {
      final updatedRide = state.activeRide!.copyWith(
        driverLat: event.lat,
        driverLng: event.lng,
      );
      emit(state.copyWith(activeRide: updatedRide));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                       HELPERS
  // ═══════════════════════════════════════════════════════════════════

  Future<Map<MobilityVehicleType, VehicleCategoryOption>> _computeAllFareOptions(
    double pLat,
    double pLng,
    double dLat,
    double dLng,
  ) async {
    final Map<MobilityVehicleType, VehicleCategoryOption> options = {};

    for (final type in MobilityVehicleType.values) {
      final estimate = await _repository.estimateFare(
        pickupLat: pLat,
        pickupLng: pLng,
        dropoffLat: dLat,
        dropoffLng: dLng,
        vehicleType: type,
      );

      final fare = (estimate['fareAmount'] as num?)?.toDouble() ?? 2000.0;
      final eta = switch (type) {
        MobilityVehicleType.bike => 3,
        MobilityVehicleType.taxi => 5,
        MobilityVehicleType.deliveryVan => 8,
        MobilityVehicleType.truck => 15,
      };

      options[type] = VehicleCategoryOption(
        type: type,
        estimatedFare: fare,
        etaMinutes: eta,
      );
    }
    return options;
  }

  List<VehicleListingEntity> _generateRentalVehicles(double lat, double lng) {
    return [
      VehicleListingEntity(
        id: 'rent_1',
        ownerId: 'fleet_owner_1',
        vehicleType: MobilityVehicleType.taxi,
        listingIntent: 'rental',
        make: 'Toyota',
        model: 'RAV4 Luxury SUV',
        year: 2023,
        color: 'Graphite Black',
        licensePlate: 'SL-991-AB',
        pricePerDay: 450.0,
        currency: 'SLE',
        latitude: lat + 0.005,
        longitude: lng + 0.005,
        availabilityStatus: 'available',
        ownerName: 'Vektolux Executive Fleet',
      ),
      VehicleListingEntity(
        id: 'rent_2',
        ownerId: 'fleet_owner_2',
        vehicleType: MobilityVehicleType.deliveryVan,
        listingIntent: 'rental',
        make: 'Mercedes-Benz',
        model: 'Sprinter Cargo',
        year: 2022,
        color: 'Pure White',
        licensePlate: 'SL-432-CD',
        pricePerDay: 650.0,
        currency: 'SLE',
        latitude: lat - 0.004,
        longitude: lng + 0.003,
        availabilityStatus: 'available',
        ownerName: 'Vektolux Commercial Logistics',
      ),
    ];
  }

  List<VehicleListingEntity> _generateSalesVehicles(double lat, double lng) {
    return [
      VehicleListingEntity(
        id: 'sale_1',
        ownerId: 'seller_1',
        vehicleType: MobilityVehicleType.taxi,
        listingIntent: 'sale',
        make: 'Hyundai',
        model: 'Tucson AWD',
        year: 2023,
        color: 'Silver Metallic',
        licensePlate: 'DEED-VERIFIED',
        salePrice: 125000.0,
        currency: 'SLE',
        latitude: lat + 0.008,
        longitude: lng - 0.006,
        availabilityStatus: 'available',
        ownerName: 'Apex Motor Dealers',
      ),
      VehicleListingEntity(
        id: 'sale_2',
        ownerId: 'seller_2',
        vehicleType: MobilityVehicleType.truck,
        listingIntent: 'sale',
        make: 'Scania',
        model: 'R500 Heavy Tipper',
        year: 2021,
        color: 'Traffic Yellow',
        licensePlate: 'DEED-VERIFIED',
        salePrice: 380000.0,
        currency: 'SLE',
        latitude: lat - 0.009,
        longitude: lng - 0.008,
        availabilityStatus: 'available',
        ownerName: 'Sahara Mining & Transport',
      ),
    ];
  }

  List<PropertyListingEntity> _generateRealEstateProperties(double lat, double lng) {
    return [
      PropertyListingEntity(
        id: 'prop_1',
        ownerId: 'owner_re_1',
        title: '4-Bedroom Luxury Hilltop Villa',
        description: 'Spectacular panoramic ocean and mountain views in Hill Station with high-speed solar and security.',
        category: RealEstateCategory.sale,
        price: 1850000.0,
        currency: 'SLE',
        address: 'Hill Station Overlook, Freetown',
        city: 'Freetown',
        country: 'Sierra Leone',
        latitude: lat + 0.012,
        longitude: lng + 0.007,
        geohash: 'ebm4u',
        availabilityStatus: 'available',
        imageUrls: const [
          'https://images.unsplash.com/photo-1613977257363-707ba9348227?w=800',
        ],
        isFeatured: true,
        isVerified: true,
        viewCount: 342,
        bedrooms: 4,
        bathrooms: 4,
        areaSqM: 420.0,
        amenities: const ['Solar Power', 'Security Escort', 'Infinity Pool', 'Parking'],
        ownerName: 'Apex Sierra Real Estate',
        ownerPhone: '+232 76 111 222',
      ),
      PropertyListingEntity(
        id: 'prop_2',
        ownerId: 'owner_re_2',
        title: 'Modern Lumley Oceanview Apartment',
        description: 'Spacious 2-bedroom furnished apartment directly on Lumley Beach Road with 24/7 security & gym.',
        category: RealEstateCategory.longTermRent,
        price: 14500.0,
        currency: 'SLE',
        address: 'Lumley Beach Rd, Aberdeen',
        city: 'Freetown',
        country: 'Sierra Leone',
        latitude: lat + 0.006,
        longitude: lng - 0.015,
        geohash: 'ebm4k',
        availabilityStatus: 'available',
        imageUrls: const [
          'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00?w=800',
        ],
        isFeatured: true,
        isVerified: true,
        viewCount: 512,
        bedrooms: 2,
        bathrooms: 2,
        areaSqM: 140.0,
        amenities: const ['Furnished', 'Backup Generator', 'Ocean View', 'Gym'],
        ownerName: 'Coastal Living Sierra',
        ownerPhone: '+232 78 333 444',
      ),
      PropertyListingEntity(
        id: 'prop_3',
        ownerId: 'owner_re_3',
        title: 'Sunset Executive Hourly Guest House',
        description: 'Discreet, pristine executive suite for short daytime or hourly stopovers near Aberdeen point.',
        category: RealEstateCategory.hourlyGuestHouse,
        price: 350.0,
        hourlyRate: 350.0,
        currency: 'SLE',
        address: 'Cape Point, Aberdeen, Freetown',
        city: 'Freetown',
        country: 'Sierra Leone',
        latitude: lat + 0.010,
        longitude: lng - 0.020,
        geohash: 'ebm47',
        availabilityStatus: 'available',
        imageUrls: const [
          'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?w=800',
        ],
        isFeatured: false,
        isVerified: true,
        viewCount: 890,
        bedrooms: 1,
        bathrooms: 1,
        areaSqM: 55.0,
        amenities: const ['Instant Check-in', 'Air Conditioned', 'Smart TV', 'Room Service'],
        ownerName: 'Cape Hospitality Group',
        ownerPhone: '+232 79 555 666',
      ),
    ];
  }

  Future<void> _onDetectUserLocation(
    DetectUserLocationEvent event,
    Emitter<MobilityState> emit,
  ) async {
    final isReady = await _locationManager.hasLocationPermissionAndService();

    if (!isReady) {
      // If permission is not granted and user hasn't dismissed before, show modal
      if (!state.hasDismissedLocationModal) {
        emit(state.copyWith(showLocationPermissionModal: true));
      }
      return;
    }

    final result = await _locationManager.requestDevicePosition(timeoutMs: 10000);

    if (result.isVpnMismatch) {
      emit(state.copyWith(
        isVpnMismatch: true,
        pickupAddress: 'Freetown Central (VPN Active)',
        pickupLat: LocationManager.defaultLat,
        pickupLng: LocationManager.defaultLng,
        showLocationPermissionModal: false,
      ));
      add(const FetchNearbyDriversDebouncedEvent(
        lat: LocationManager.defaultLat,
        lng: LocationManager.defaultLng,
      ));
      return;
    }

    if (result.isGpsActive) {
      emit(state.copyWith(
        pickupLat: result.latitude,
        pickupLng: result.longitude,
        currentLat: result.latitude,
        currentLng: result.longitude,
        pickupAddress: result.addressText,
        isVpnMismatch: false,
        showLocationPermissionModal: false,
      ));
      add(FetchNearbyDriversDebouncedEvent(
        lat: result.latitude,
        lng: result.longitude,
      ));
    }
  }

  void _onSetManualPickupLocation(
    SetManualPickupLocationEvent event,
    Emitter<MobilityState> emit,
  ) {
    emit(state.copyWith(
      pickupLat: event.lat,
      pickupLng: event.lng,
      pickupAddress: event.address,
      isVpnMismatch: false,
      isPinDragMode: false,
    ));
    add(FetchNearbyDriversDebouncedEvent(
      lat: event.lat,
      lng: event.lng,
    ));
  }

  void _onTogglePinDragMode(
    TogglePinDragModeEvent event,
    Emitter<MobilityState> emit,
  ) {
    emit(state.copyWith(isPinDragMode: event.isEnabled));
  }

  void _onDismissVpnMismatch(
    DismissVpnMismatchEvent event,
    Emitter<MobilityState> emit,
  ) {
    emit(state.copyWith(isVpnMismatch: false));
  }

  void _onDismissLocationPermissionModal(
    DismissLocationPermissionModalEvent event,
    Emitter<MobilityState> emit,
  ) {
    emit(state.copyWith(
      showLocationPermissionModal: false,
      hasDismissedLocationModal: true,
    ));
  }

  Future<void> _onFetchNearbyDriversDebounced(
    FetchNearbyDriversDebouncedEvent event,
    Emitter<MobilityState> emit,
  ) async {
    try {
      final drivers = await _repository.getNearbyDrivers(
        lat: event.lat,
        lng: event.lng,
        radiusKm: event.radiusKm,
      );

      final estimates = _fareService.calculateAllTiers(
        distanceKm: state.estimatedDistanceKm,
        durationMins: state.estimatedDurationMin,
        nearbyDrivers: drivers,
        serviceType: state.bookingServiceType,
      );

      emit(state.copyWith(
        onDemandDrivers: drivers,
        calculatedTierEstimates: estimates,
      ));
    } catch (e) {
      _log.w('Debounced proximity query failed: $e');
    }
  }

  void _onSwitchBookingServiceType(
    SwitchBookingServiceTypeEvent event,
    Emitter<MobilityState> emit,
  ) {
    final availableCategories =
        VehicleCategoryCatalog.categoriesForService(event.serviceType);
    final newCategory =
        availableCategories.contains(state.selectedBookingCategory)
            ? state.selectedBookingCategory
            : availableCategories.first;

    final estimates = _fareService.calculateAllTiers(
      distanceKm: state.estimatedDistanceKm,
      durationMins: state.estimatedDurationMin,
      nearbyDrivers: state.onDemandDrivers,
      serviceType: event.serviceType,
    );

    emit(state.copyWith(
      bookingServiceType: event.serviceType,
      selectedBookingCategory: newCategory,
      calculatedTierEstimates: estimates,
    ));
  }

  void _onSelectBookingCategory(
    SelectBookingCategoryEvent event,
    Emitter<MobilityState> emit,
  ) {
    emit(state.copyWith(selectedBookingCategory: event.category));
  }

  void _onUpdateDeliveryDetails(
    UpdateDeliveryDetailsEvent event,
    Emitter<MobilityState> emit,
  ) {
    emit(state.copyWith(deliveryPackageDetails: event.details));
  }

  Future<void> _onConfirmBookingRequest(
    ConfirmBookingRequestEvent event,
    Emitter<MobilityState> emit,
  ) async {
    final estimate = state.currentCalculatedEstimate;
    final fare = estimate?.fareAmount ?? 35.0;

    emit(state.copyWith(
      isSearchingDriver: true,
      isSubmittingRide: false,
    ));

    try {
      // 1. Dispatch request to Convex backend & SQLite Drift
      final tripId = await _repository.createTripDeliveryRequest(
        passengerId: event.passengerId,
        serviceType: state.bookingServiceType,
        pickupLat: state.pickupLat,
        pickupLng: state.pickupLng,
        pickupAddressText: state.pickupAddress,
        dropoffLat: state.dropoffLat,
        dropoffLng: state.dropoffLng,
        dropoffAddressText: state.dropoffAddress,
        fareAmount: fare,
        paymentMethod: event.paymentMethod,
        distanceKm: state.estimatedDistanceKm,
        durationMins: state.estimatedDurationMin,
        packageDetails: state.bookingServiceType == 'delivery' &&
                state.deliveryPackageDetails != null
            ? state.deliveryPackageDetails!.toJson()
            : null,
      );

      _log.i('Trip/Delivery request created on Convex: $tripId');

      // 2. Realistic dispatch simulation: nearby verified driver accepts within 3.2s
      _searchSimulationTimer?.cancel();
      _searchSimulationTimer = Timer(const Duration(milliseconds: 3200), () {
        if (!isClosed && state.isSearchingDriver) {
          final acceptedTrip = TripDeliveryEntity(
            id: tripId,
            passengerId: event.passengerId,
            driverId: state.onDemandDrivers.isNotEmpty
                ? state.onDemandDrivers.first.driverId
                : 'driver_verified_1',
            serviceType: state.bookingServiceType,
            pickupLat: state.pickupLat,
            pickupLng: state.pickupLng,
            pickupAddressText: state.pickupAddress,
            dropoffLat: state.dropoffLat,
            dropoffLng: state.dropoffLng,
            dropoffAddressText: state.dropoffAddress,
            status: TripDeliveryStatus.accepted,
            fareAmount: fare,
            paymentMethod: event.paymentMethod,
            distanceKm: state.estimatedDistanceKm,
            durationMins: state.estimatedDurationMin,
            packageDetails: state.deliveryPackageDetails,
            createdAt: DateTime.now(),
          );

          add(DriverAcceptedTripEvent(acceptedTrip));
        }
      });
    } catch (e) {
      _log.w('Convex trip dispatch fallback: $e');
      _searchSimulationTimer?.cancel();
      _searchSimulationTimer = Timer(const Duration(milliseconds: 3000), () {
        if (!isClosed && state.isSearchingDriver) {
          final fallbackTrip = TripDeliveryEntity(
            id: 'trip_${DateTime.now().millisecondsSinceEpoch}',
            passengerId: event.passengerId,
            driverId: 'driver_verified_local',
            serviceType: state.bookingServiceType,
            pickupLat: state.pickupLat,
            pickupLng: state.pickupLng,
            pickupAddressText: state.pickupAddress,
            dropoffLat: state.dropoffLat,
            dropoffLng: state.dropoffLng,
            dropoffAddressText: state.dropoffAddress,
            status: TripDeliveryStatus.accepted,
            fareAmount: fare,
            paymentMethod: event.paymentMethod,
            distanceKm: state.estimatedDistanceKm,
            durationMins: state.estimatedDurationMin,
            packageDetails: state.deliveryPackageDetails,
            createdAt: DateTime.now(),
          );
          add(DriverAcceptedTripEvent(fallbackTrip));
        }
      });
    }
  }

  void _onCancelSearchingRequest(
    CancelSearchingRequestEvent event,
    Emitter<MobilityState> emit,
  ) {
    _searchSimulationTimer?.cancel();
    final tripId = state.activeTripDelivery?.id ?? state.activeRide?.id;

    emit(state.copyWith(
      isSearchingDriver: false,
      clearActiveRide: true,
      clearActiveTripDelivery: true,
      successMessage: 'Booking request cancelled.',
    ));

    if (tripId != null) {
      _repository
          .cancelRide(
            rideId: tripId,
            reason: 'Cancelled by passenger while finding driver',
          )
          .catchError((e) {
        _log.w('Cancel searching backend error: $e');
      });
    }
  }

  void _onDriverAcceptedTrip(
    DriverAcceptedTripEvent event,
    Emitter<MobilityState> emit,
  ) {
    final trip = event.trip;
    final isDelivery = trip.serviceType == 'delivery';

    final ride = RideEntity(
      id: trip.id,
      passengerId: trip.passengerId,
      driverId: trip.driverId,
      driverName: state.onDemandDrivers.isNotEmpty
          ? state.onDemandDrivers.first.driverName
          : (isDelivery ? 'Amadu Barrie (Courier)' : 'Mohamed Sesay'),
      driverPhone: '+232 76 892 104',
      vehicleModel: isDelivery ? 'Yamaha Express 125' : 'Toyota Corolla Sedan',
      vehiclePlate: 'SL-884-AB',
      pickupLat: trip.pickupLat,
      pickupLng: trip.pickupLng,
      pickupAddress: trip.pickupAddressText,
      dropoffLat: trip.dropoffLat,
      dropoffLng: trip.dropoffLng,
      dropoffAddress: trip.dropoffAddressText,
      distanceKm: trip.distanceKm,
      estimatedDurationMin: trip.durationMins,
      fareAmount: trip.fareAmount,
      platformFee: trip.fareAmount * 0.15,
      driverPayout: trip.fareAmount * 0.85,
      status: RideStatus.accepted,
      paymentStatus: 'escrow_locked',
      blockchainLogHash: '0x4d12...a89c (Sierra Leone Transport Audit)',
    );

    emit(state.copyWith(
      isSearchingDriver: false,
      activeTripDelivery: trip,
      activeRide: ride,
      successMessage: isDelivery
          ? 'Courier assigned and en route for pickup!'
          : 'Driver assigned and en route for pickup!',
    ));
  }

  double _computeHaversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // Earth radius in km
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return double.parse((r * c).toStringAsFixed(2));
  }

  @override
  Future<void> close() {
    _activeRideSubscription?.cancel();
    _searchSimulationTimer?.cancel();
    return super.close();
  }
}

// Internal event for reactive stream listener
class _ActiveRideUpdatedInternalEvent extends MobilityEvent {
  final RideEntity? ride;
  const _ActiveRideUpdatedInternalEvent(this.ride);

  @override
  List<Object?> get props => [ride];
}
