// lib/features/mobility/presentation/views/mobility_home_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Mobility Master Screen (Ride-Hailing, Rentals, Sales)
// Production map SDK on Ride tab, dedicated showroom on Rent & Buy tabs,
// unblocked gesture responsiveness, real-time routing, and full checkout.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../bookings/presentation/views/checkout_screen.dart';
import '../../../discovery/presentation/views/discovery_feed_screen.dart';
import '../../domain/entities/mobility_vehicle_entity.dart';
import '../bloc/mobility_bloc.dart';
import '../bloc/mobility_event.dart';
import '../bloc/mobility_state.dart';
import '../widgets/interactive_map_view.dart';
import '../widgets/ride_search_panel.dart';
import '../widgets/rental_panel.dart';
import '../widgets/vehicle_sales_catalog.dart';
import '../widgets/active_ride_overlay.dart';
import '../widgets/location_permission_modal.dart';
import '../widgets/landmark_autocomplete_sheet.dart';
import '../widgets/vpn_fallback_banner.dart';
import '../widgets/finding_driver_radar_overlay.dart';
import '../widgets/real_estate_showcase_panel.dart';
import '../widgets/driver_marker_preview_card.dart';
import '../widgets/seller_marker_preview_card.dart';
import '../widgets/group_trip_sheet.dart';
import '../widgets/share_location_sheet.dart';
import '../../data/services/location_manager.dart';
import '../../domain/entities/nearby_driver_entity.dart';
import '../../domain/entities/nearby_seller_entity.dart';
import '../../domain/entities/vehicle_category_catalog.dart';
import 'driver_portal_screen.dart';
import '../../../profile/presentation/views/profile_screen.dart';
import '../../../listings/presentation/views/property_detail_screen.dart';

class MobilityHomeScreen extends StatefulWidget {
  final String currentUserId;
  final double initialLat;
  final double initialLng;

  const MobilityHomeScreen({
    super.key,
    required this.currentUserId,
    this.initialLat = 8.484,
    this.initialLng = -13.229,
  });

  @override
  State<MobilityHomeScreen> createState() => _MobilityHomeScreenState();
}

class _MobilityHomeScreenState extends State<MobilityHomeScreen> {
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  bool _isPermissionModalShowing = false;
  NearbyDriverEntity? _selectedDriverPreview;
  NearbySellerEntity? _selectedSellerPreview;

  @override
  void initState() {
    super.initState();
    // Dispatch initial load for user's active ride & nearby drivers
    context.read<MobilityBloc>().add(
          LoadMobilityHomeEvent(
            userId: widget.currentUserId,
            currentLat: widget.initialLat,
            currentLng: widget.initialLng,
          ),
        );
    // Trigger location & geofencing detection (with automated permission prompt)
    context.read<MobilityBloc>().add(const DetectUserLocationEvent());
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _handleRentalCheckout(VehicleListingEntity vehicle, MobilityState state) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to proceed with vehicle rental checkout.'),
          backgroundColor: AppColors.obsidian,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final dailyRate = vehicle.pricePerDay ?? 350.0;
    final driverSurcharge = state.isRentalWithDriver ? 120.0 * state.rentalDays : 0.0;
    final subtotal = (dailyRate * state.rentalDays) + driverSurcharge;
    final serviceFee = (subtotal * 0.05).roundToDouble();
    final total = subtotal + serviceFee;

    final now = DateTime.now();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          database: context.read<AppDatabase>(),
          convexClient: context.read<ConvexClientWrapper>(),
          currentUser: user,
          listingId: vehicle.id,
          listingType: 'vehicle',
          listingTitle: vehicle.fullTitle,
          listingSubtitle:
              '${state.rentalDays} Days Rental${state.isRentalWithDriver ? " with Chauffeur" : " (Self-Drive)"}',
          primaryImageUrl: vehicle.imageUrls.isNotEmpty ? vehicle.imageUrls.first : null,
          vendorId: vehicle.ownerId,
          bookingType: 'vehicle_rental',
          startTime: now.millisecondsSinceEpoch,
          endTime: now.add(Duration(days: state.rentalDays)).millisecondsSinceEpoch,
          days: state.rentalDays,
          subtotal: subtotal,
          serviceFee: serviceFee,
          totalAmount: total,
        ),
      ),
    );
  }

  Future<void> _handleScheduleInspection(VehicleListingEntity vehicle) async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to book a complimentary vehicle inspection.'),
          backgroundColor: AppColors.obsidian,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final startTime = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10, 0).millisecondsSinceEpoch;
    final endTime = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 11, 0).millisecondsSinceEpoch;

    try {
      final result = await context.read<ConvexClientWrapper>().mutation(
        'bookings:createBooking',
        args: {
          'buyerId': user.id,
          'vendorId': vehicle.ownerId,
          'listingId': vehicle.id,
          'listingType': 'vehicle',
          'listingTitle': vehicle.fullTitle,
          'bookingType': 'vehicle_inspection',
          'startTime': startTime,
          'endTime': endTime,
          'subtotal': 0,
          'notes': 'Complimentary 120-point mechanical check scheduled for ${vehicle.fullTitle}',
        },
      );

      if (result.success && mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 28),
                SizedBox(width: 10),
                Text('Inspection Booked', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              ],
            ),
            content: Text(
              'Your complimentary 120-point mechanical inspection for ${vehicle.fullTitle} has been confirmed for tomorrow at 10:00 AM in Freetown.\n\nEscrow protection is active.',
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Great, Got it', style: TextStyle(color: AppColors.emeraldDark, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to book inspection: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _openLandmarkSheet(BuildContext context, {bool isPickup = true}) {
    LandmarkAutocompleteSheet.show(
      context,
      initialQuery: '',
      onSelectLandmark: (landmark) {
        if (isPickup) {
          context.read<MobilityBloc>().add(
                SetManualPickupLocationEvent(
                  lat: landmark.latitude,
                  lng: landmark.longitude,
                  address: landmark.name,
                ),
              );
        } else {
          context.read<MobilityBloc>().add(
                UpdateLocationsEvent(
                  dropoffLat: landmark.latitude,
                  dropoffLng: landmark.longitude,
                  dropoffAddress: landmark.name,
                ),
              );
        }
      },
      onEnablePinDrag: () {
        context.read<MobilityBloc>().add(const TogglePinDragModeEvent(true));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MobilityBloc, MobilityState>(
      listener: (context, state) {
        if (state.showLocationPermissionModal && !_isPermissionModalShowing) {
          _isPermissionModalShowing = true;
          LocationPermissionModal.show(
            context,
            onEnableLocation: () {
              _isPermissionModalShowing = false;
              context.read<MobilityBloc>().add(const DetectUserLocationEvent());
            },
            onManualInput: () {
              _isPermissionModalShowing = false;
              context.read<MobilityBloc>().add(const DismissLocationPermissionModalEvent());
              _openLandmarkSheet(context, isPickup: true);
            },
          ).then((_) {
            _isPermissionModalShowing = false;
          });
        }
        if (state.successMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.successMessage!),
              backgroundColor: AppColors.emerald,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final isRideMode = state.mode == MobilityHomeMode.rideHailing;

        return Scaffold(
          backgroundColor: AppColors.gray50,
          body: isRideMode
              ? _buildRideModeWithMap(context, state)
              : _buildDedicatedCatalogMode(context, state),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //       1. RIDE-HAILING MODE — DOMINANT MAP + BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildRideModeWithMap(BuildContext context, MobilityState state) {
    return Stack(
      children: [
        // ── Full-Screen Interactive OpenStreetMap Layer ─────────────
        Positioned.fill(
          child: InteractiveMapView(
            pickupLat: state.pickupLat,
            pickupLng: state.pickupLng,
            dropoffLat: state.dropoffLat,
            dropoffLng: state.dropoffLng,
            nearbyVehicles: state.nearbyVehicles,
            onDemandDrivers: state.onDemandDrivers,
            nearbySellers: state.nearbySellers,
            currentUserAvatarUrl: context.read<AuthBloc>().state.user?.avatarUrl,
            isPinDragMode: state.isPinDragMode,
            showRoute: state.hasActiveRide || state.mode == MobilityHomeMode.rideHailing,
            assignedDriverLat: state.activeRide?.driverLat ??
                (state.hasActiveRide ? state.pickupLat + 0.003 : null),
            assignedDriverLng: state.activeRide?.driverLng ??
                (state.hasActiveRide ? state.pickupLng + 0.002 : null),
            assignedDriverCategory: state.selectedBookingCategory.id,
            assignedDriverName: state.activeRide?.driverName,
            assignedDriverPlate: state.activeRide?.vehiclePlate,
            selectedCategory: state.selectedBookingCategory.id,
            onPickupPositionChanged: (newPoint) {
              final readable = LocationManager().reverseGeocode(newPoint.latitude, newPoint.longitude);
              context.read<MobilityBloc>().add(
                    UpdateLocationsEvent(
                      pickupLat: newPoint.latitude,
                      pickupLng: newPoint.longitude,
                      pickupAddress: readable,
                    ),
                  );
            },
            onDriverTap: (driver) {
              setState(() {
                _selectedDriverPreview = driver;
                _selectedSellerPreview = null;
              });
            },
            onSellerTap: (seller) {
              setState(() {
                _selectedSellerPreview = seller;
                _selectedDriverPreview = null;
              });
            },
            onConfirmPinSpot: () {
              context.read<MobilityBloc>().add(const TogglePinDragModeEvent(false));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Pickup location set from map pin.'),
                  backgroundColor: AppColors.emerald,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ),

        // ── Floating Top Header & Mode Bar & VPN Banner ─────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTopFloatingBar(context, state),
              if (state.isVpnMismatch) ...[
                const SizedBox(height: 6),
                VpnFallbackBanner(
                  onTapSelectLandmark: () => _openLandmarkSheet(context, isPickup: true),
                  onDismiss: () {
                    context.read<MobilityBloc>().add(const DismissVpnMismatchEvent());
                  },
                ),
              ],
            ],
          ),
        ),

        // ── Floating Quick Action Pill Row (Group Trip & Share Location) ────
        if (_selectedDriverPreview == null &&
            _selectedSellerPreview == null &&
            !state.isSearchingDriver &&
            !(state.activeRide != null && state.activeRide!.status.isActive))
          Positioned(
            top: MediaQuery.of(context).padding.top + 64 + (state.isVpnMismatch ? 44 : 0),
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQuickActionChip(
                  icon: Icons.groups_rounded,
                  label: 'Group Trip',
                  backgroundColor: AppColors.obsidian,
                  textColor: AppColors.white,
                  iconColor: AppColors.amber,
                  onTap: () {
                    GroupTripSheet.show(
                      context,
                      pickupAddress: state.pickupAddress,
                      dropoffAddress: state.dropoffAddress,
                      totalFare: state.currentCalculatedEstimate?.fareAmount ?? 35.0,
                      vehicleType: state.selectedBookingCategory.title,
                    );
                  },
                ),
                const SizedBox(width: 8),
                _buildQuickActionChip(
                  icon: Icons.share_location_rounded,
                  label: 'Share Pin',
                  backgroundColor: AppColors.white,
                  textColor: AppColors.obsidian,
                  iconColor: AppColors.emerald,
                  onTap: () {
                    ShareLocationSheet.show(
                      context,
                      latitude: state.pickupLat,
                      longitude: state.pickupLng,
                      label: 'Pickup: ${state.pickupAddress}',
                    );
                  },
                ),
              ],
            ),
          ),

        // ── Bottom Panel (Seller Card OR Driver Card OR Finding Driver Radar OR Active Ride Overlay OR Draggable Sheet) ───
        if (_selectedSellerPreview != null) ...[
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SellerMarkerPreviewCard(
              seller: _selectedSellerPreview!,
              onClose: () => setState(() => _selectedSellerPreview = null),
              onOrder: (seller) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Viewing merchant catalog for ${seller.businessName}...'),
                    backgroundColor: AppColors.emerald,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              onCallOrChat: (seller) {
                final phone = seller.phone.isNotEmpty ? seller.phone : '+232 76 999 888';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Calling ${seller.businessName} at $phone...'),
                    backgroundColor: AppColors.obsidian,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              onShareLocation: (seller) {
                ShareLocationSheet.show(
                  context,
                  latitude: seller.latitude,
                  longitude: seller.longitude,
                  label: 'Store: ${seller.businessName} (${seller.address})',
                  recipientName: seller.businessName,
                );
              },
            ),
          ),
        ] else if (_selectedDriverPreview != null) ...[
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: DriverMarkerPreviewCard(
              driver: _selectedDriverPreview!,
              onClose: () => setState(() => _selectedDriverPreview = null),
              onBook: (driver) {
                final cat = driver.vehicle?.category ?? DriverVehicleCategory.kekehTricycle;
                final bookingCat = switch (cat) {
                  DriverVehicleCategory.kekehTricycle => BookingVehicleCategory.kekehTricycle,
                  DriverVehicleCategory.deliveryBike => BookingVehicleCategory.courierBike,
                  DriverVehicleCategory.comfort => BookingVehicleCategory.comfortRide,
                  DriverVehicleCategory.standard => BookingVehicleCategory.standardRide,
                };
                context.read<MobilityBloc>().add(SelectBookingCategoryEvent(bookingCat));
                setState(() => _selectedDriverPreview = null);
                context.read<MobilityBloc>().add(
                      ConfirmBookingRequestEvent(passengerId: widget.currentUserId),
                    );
              },
              onCall: (driver) {
                final phone = driver.driverPhone.isNotEmpty ? driver.driverPhone : '+232 76 555 432';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Calling ${driver.driverName} at $phone...'),
                    backgroundColor: AppColors.obsidian,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              onShareLocation: (driver) {
                ShareLocationSheet.show(
                  context,
                  latitude: state.pickupLat,
                  longitude: state.pickupLng,
                  label: 'Pickup: ${state.pickupAddress}',
                  recipientName: driver.driverName,
                );
              },
            ),
          ),
        ] else if (state.isSearchingDriver) ...[
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FindingDriverRadarOverlay(
              serviceType: state.bookingServiceType,
              categoryTitle: state.selectedBookingCategory.title,
              pickupAddress: state.pickupAddress,
              dropoffAddress: state.dropoffAddress,
              estimatedFare: state.currentCalculatedEstimate?.fareAmount ?? 35.0,
              currency: state.currentCalculatedEstimate?.currency ?? 'SLE',
              onCancelRequest: () {
                context.read<MobilityBloc>().add(const CancelSearchingRequestEvent());
              },
            ),
          ),
        ] else if (state.activeRide != null && state.activeRide!.status.isActive) ...[
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ActiveRideOverlay(
              ride: state.activeRide!,
              onCancelRide: () {
                context.read<MobilityBloc>().add(const CancelRideEvent());
              },
            ),
          ),
        ] else ...[
          // Sliding DraggableScrollableSheet for Ride Mode
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.48,
            minChildSize: 0.24,
            maxChildSize: 0.90,
            snap: true,
            snapSizes: const [0.24, 0.48, 0.90],
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.obsidian.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    // Sheet drag handle & mode bar
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.gray300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildModeSegmentedTabBar(context, state),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ),
                    // Ride Search Panel
                    SliverToBoxAdapter(
                      child: RideSearchPanel(
                        pickupAddress: state.pickupAddress,
                        dropoffAddress: state.dropoffAddress,
                        activeServiceType: state.bookingServiceType,
                        selectedCategory: state.selectedBookingCategory,
                        calculatedTierEstimates: state.calculatedTierEstimates,
                        isSubmitting: state.isSubmittingRide,
                        onTapPickup: () => _openLandmarkSheet(context, isPickup: true),
                        onTapDropoff: () => _openLandmarkSheet(context, isPickup: false),
                        onServiceTypeChanged: (serviceType) {
                          context.read<MobilityBloc>().add(SwitchBookingServiceTypeEvent(serviceType));
                        },
                        onSelectCategory: (category) {
                          context.read<MobilityBloc>().add(SelectBookingCategoryEvent(category));
                        },
                        onConfirmBooking: (deliveryDetails) {
                          if (deliveryDetails != null) {
                            context.read<MobilityBloc>().add(UpdateDeliveryDetailsEvent(deliveryDetails));
                          }
                          context.read<MobilityBloc>().add(
                                ConfirmBookingRequestEvent(passengerId: widget.currentUserId),
                              );
                        },
                        onSelectQuickDestination: (destination) {
                          context.read<MobilityBloc>().add(UpdateLocationsEvent(dropoffAddress: destination));
                        },
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //       2. DEDICATED CATALOG MODE (RENT & BUY VERTICALS)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDedicatedCatalogMode(BuildContext context, MobilityState state) {
    return SafeArea(
      child: Column(
        children: [
          // ── Persistent Top Header with Mode Tabs ───────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _buildTopFloatingBar(context, state),
          ),
          _buildModeSegmentedTabBar(context, state),
          const SizedBox(height: 10),

          // ── Scrollable Catalog Area (Full Screen Unobstructed) ─────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: state.mode == MobilityHomeMode.rental
                  ? RentalPanel(
                      rentalVehicles: state.availableRentalVehicles,
                      isWithDriver: state.isRentalWithDriver,
                      rentalDays: state.rentalDays,
                      onToggleDriver: (val) {
                        context.read<MobilityBloc>().add(ToggleRentalDriverOptionEvent(val));
                      },
                      onUpdateDays: (days) {
                        context.read<MobilityBloc>().add(UpdateRentalDaysEvent(days));
                      },
                      onBookVehicle: (vehicle) => _handleRentalCheckout(vehicle, state),
                    )
                  : state.mode == MobilityHomeMode.buyVehicle
                      ? VehicleSalesCatalog(
                          salesVehicles: state.catalogSalesVehicles,
                          onScheduleInspection: (vehicle) => _handleScheduleInspection(vehicle),
                        )
                      : RealEstateShowcasePanel(
                          properties: state.realEstateListings,
                          onBookSiteVisit: (prop) => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PropertyDetailScreen.fromEntity(prop),
                            ),
                          ),
                          onBookHourlyStay: (prop) => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PropertyDetailScreen.fromEntity(prop),
                            ),
                          ),
                        ),
            ),
          ),

          // ── Persistent Active Ride Mini-Banner (Preserves ride across verticals) ──
          if (state.hasActiveRide)
            _buildActiveRideMiniBanner(context, state),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     SHARED HEADER & TABS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildTopFloatingBar(BuildContext context, MobilityState state) {
    return Row(
      children: [
        // App / Back button
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.obsidian.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.obsidian, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        const SizedBox(width: 10),

        // Live status pill
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.obsidian.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Vektolux',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${state.nearbyVehicles.length} nearby',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.emeraldDark,
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),

        // Marketplace / Discovery Feed FAB
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.obsidian,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.obsidian.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            tooltip: 'Marketplace Feed',
            icon: const Icon(Icons.storefront_rounded, color: AppColors.emerald, size: 20),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DiscoveryFeedScreen(
                    database: context.read<AppDatabase>(),
                    convexClient: context.read<ConvexClientWrapper>(),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),

        // Driver Portal FAB
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.obsidian,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.obsidian.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            tooltip: 'Driver Portal',
            icon: const Icon(Icons.drive_eta_rounded, color: AppColors.emerald, size: 20),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DriverPortalScreen(
                    currentUserId: widget.currentUserId,
                    initialLat: widget.initialLat,
                    initialLng: widget.initialLng,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),

        // Circular Profile Avatar Button
        Builder(
          builder: (avatarContext) {
            final user = avatarContext.watch<AuthBloc>().state.user;
            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      currentUserId: widget.currentUserId,
                    ),
                  ),
                );
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.emerald, width: 2),
                  color: AppColors.obsidian,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.obsidian.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
                      ? Image.network(
                          user.avatarUrl!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_outline_rounded,
                            color: AppColors.white,
                            size: 20,
                          ),
                        )
                      : const Icon(
                          Icons.person_outline_rounded,
                          color: AppColors.white,
                          size: 20,
                        ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color textColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.obsidian.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSegmentedTabBar(BuildContext context, MobilityState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.gray100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            _buildModeTabItem(
              label: 'Ride',
              icon: Icons.directions_car_rounded,
              isSelected: state.mode == MobilityHomeMode.rideHailing,
              onTap: () {
                context.read<MobilityBloc>().add(const SwitchMobilityModeEvent(0));
              },
            ),
            _buildModeTabItem(
              label: 'Rent',
              icon: Icons.key_rounded,
              isSelected: state.mode == MobilityHomeMode.rental,
              onTap: () {
                context.read<MobilityBloc>().add(const SwitchMobilityModeEvent(1));
              },
            ),
            _buildModeTabItem(
              label: 'Buy',
              icon: Icons.sell_outlined,
              isSelected: state.mode == MobilityHomeMode.buyVehicle,
              onTap: () {
                context.read<MobilityBloc>().add(const SwitchMobilityModeEvent(2));
              },
            ),
            _buildModeTabItem(
              label: 'Real Estate',
              icon: Icons.home_work_rounded,
              isSelected: state.mode == MobilityHomeMode.realEstate,
              onTap: () {
                context.read<MobilityBloc>().add(const SwitchMobilityModeEvent(3));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTabItem({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.obsidian.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? AppColors.emeraldDark : AppColors.gray500,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? AppColors.obsidian : AppColors.gray500,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveRideMiniBanner(BuildContext context, MobilityState state) {
    final ride = state.activeRide;
    final driverName = ride?.driverName ?? 'Momoh K. (Verified Driver)';
    final plate = ride?.vehiclePlate ?? 'SL-940-BA';
    final etaMins = ride?.estimatedDurationMin ?? 12;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.emerald, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_taxi_rounded, color: AppColors.emerald, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.emerald,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Active Trip • $plate',
                      style: const TextStyle(
                        color: AppColors.emerald,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$driverName • ETA $etaMins mins',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              context.read<MobilityBloc>().add(const SwitchMobilityModeEvent(0));
            },
            icon: const Icon(Icons.map_rounded, size: 14),
            label: const Text(
              'Live Map',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: AppColors.obsidian,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
