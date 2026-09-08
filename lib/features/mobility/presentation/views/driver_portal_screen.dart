// lib/features/mobility/presentation/views/driver_portal_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Portal Master Screen
// Interactive map background with live driver GPS tracking, top online/offline toggle bar,
// incoming 15-second countdown dispatch card, and 4-step active trip lifecycle stepper panel.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/database/app_database.dart';
import '../../data/services/driver_heartbeat_service.dart';
import '../bloc/driver_portal_bloc.dart';
import '../bloc/driver_portal_event.dart';
import '../bloc/driver_portal_state.dart';
import '../widgets/interactive_map_view.dart';
import '../widgets/driver_online_toggle_bar.dart';
import '../widgets/incoming_dispatch_card.dart';
import '../widgets/driver_trip_lifecycle_panel.dart';
import '../../domain/entities/trip_delivery_entity.dart';

import '../../domain/entities/driver_vehicle_entity.dart';
import '../widgets/isometric_vehicle_3d_render.dart';
import 'driver_vehicle_registration_screen.dart';

class DriverPortalScreen extends StatelessWidget {
  final String currentUserId;
  final double initialLat;
  final double initialLng;

  const DriverPortalScreen({
    super.key,
    required this.currentUserId,
    this.initialLat = 8.484,
    this.initialLng = -13.229,
  });

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final convexClient = context.read<ConvexClientWrapper>();

    final heartbeatService = DriverHeartbeatService(
      convexClient: convexClient,
      driverDao: db.cachedDriverProfilesDao,
    );

    return BlocProvider<DriverPortalBloc>(
      create: (_) => DriverPortalBloc(
        convexClient: convexClient,
        heartbeatService: heartbeatService,
        tripsDao: db.cachedTripsDeliveriesDao,
        driverDao: db.cachedDriverProfilesDao,
      )..add(
          InitDriverPortalEvent(
            userId: currentUserId,
            initialLat: initialLat,
            initialLng: initialLng,
          ),
        ),
      child: _DriverPortalScreenView(currentUserId: currentUserId),
    );
  }
}

class _DriverPortalScreenView extends StatefulWidget {
  final String currentUserId;

  const _DriverPortalScreenView({required this.currentUserId});

  @override
  State<_DriverPortalScreenView> createState() => _DriverPortalScreenViewState();
}

class _DriverPortalScreenViewState extends State<_DriverPortalScreenView> {
  DriverVehicleEntity? _driverVehicle;
  bool _isLoadingVehicle = true;

  @override
  void initState() {
    super.initState();
    _loadDriverVehicle();
  }

  Future<void> _loadDriverVehicle() async {
    try {
      final convexClient = context.read<ConvexClientWrapper>();
      final result = await convexClient.query(
        'driverVehicles:getDriverVehicle',
        args: {'driverId': widget.currentUserId},
      );
      if (!mounted) return;
      if (result.success && result.value != null) {
        final data = Map<String, dynamic>.from(result.value as Map);
        setState(() {
          _driverVehicle = DriverVehicleEntity.fromJson(data);
          _isLoadingVehicle = false;
        });
      } else {
        setState(() {
          _driverVehicle = null;
          _isLoadingVehicle = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingVehicle = false;
        });
      }
    }
  }

  Future<void> _openVehicleRegistration() async {
    final registered = await DriverVehicleRegistrationScreen.open(
      context,
      driverId: widget.currentUserId,
    );
    if (registered == true) {
      await _loadDriverVehicle();
    }
  }

  Future<void> _demoApproveVehicle() async {
    try {
      final convexClient = context.read<ConvexClientWrapper>();
      final result = await convexClient.mutation(
        'driverVehicles:mockApproveDriverVehicle',
        args: {
          'driverId': widget.currentUserId,
          'approve': true,
        },
      );
      if (!mounted) return;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehicle approved for live dispatching! (Demo Mode)'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadDriverVehicle();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${result.errorMessage ?? "Approval error"}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _handleToggleOnline(BuildContext context, bool val) {
    if (!val) {
      context.read<DriverPortalBloc>().add(const ToggleDriverOnlineStatusEvent(false));
      return;
    }

    // Driver attempts to switch to ONLINE & READY: Enforce vehicle verification gating!
    if (_driverVehicle == null) {
      _showVehicleDialog(
        title: 'Vehicle Registration Required',
        icon: Icons.directions_car_filled_outlined,
        iconColor: AppColors.amber,
        message:
            'You must register your commercial vehicle and submit verification documents to accept rides on Vektolux.',
        primaryButtonText: 'Register Vehicle',
        onPrimaryTap: _openVehicleRegistration,
      );
      return;
    }

    if (!_driverVehicle!.isApproved) {
      if (_driverVehicle!.isPending) {
        _showVehicleDialog(
          title: 'Documents Under Review',
          icon: Icons.hourglass_top_rounded,
          iconColor: AppColors.amber,
          message:
              'Your vehicle documents are awaiting administrator verification. For testing and development, you can use instant demo approval.',
          primaryButtonText: 'Instant Approve (Demo)',
          onPrimaryTap: _demoApproveVehicle,
          secondaryButtonText: 'View Registration',
          onSecondaryTap: _openVehicleRegistration,
        );
      } else {
        _showVehicleDialog(
          title: 'Verification Action Required',
          icon: Icons.error_outline_rounded,
          iconColor: AppColors.error,
          message:
              'Vehicle verification was not approved: ${_driverVehicle!.rejectionReason ?? "Please re-upload your driver credentials."}',
          primaryButtonText: 'Update Registration',
          onPrimaryTap: _openVehicleRegistration,
        );
      }
      return;
    }

    context.read<DriverPortalBloc>().add(const ToggleDriverOnlineStatusEvent(true));
  }

  void _showVehicleDialog({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String message,
    required String primaryButtonText,
    required VoidCallback onPrimaryTap,
    String? secondaryButtonText,
    VoidCallback? onSecondaryTap,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.obsidian,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          if (secondaryButtonText != null)
            TextButton(
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                onSecondaryTap?.call();
              },
              child: Text(
                secondaryButtonText,
                style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.obsidian,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              onPrimaryTap();
            },
            child: Text(
              primaryButtonText,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleStatusBanner(bool isOnline) {
    if (_isLoadingVehicle) {
      return const SizedBox.shrink();
    }

    if (_driverVehicle == null) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Vehicle Registration Required',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.obsidian,
                    ),
                  ),
                  Text(
                    'Register vehicle to accept passenger rides',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.obsidian,
                foregroundColor: AppColors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _openVehicleRegistration,
              child: const Text('Register', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    if (_driverVehicle!.isPending) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            IsometricVehicle3DRender(
              tierId: _driverVehicle!.tierId,
              width: 46,
              height: 34,
            ),
            const SizedBox(width: 10),
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
                          color: AppColors.amber,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'Pending Admin Review',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.amberDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _driverVehicle!.formattedBadge,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emeraldSurface,
                foregroundColor: AppColors.emeraldDark,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppColors.emerald, width: 1),
                ),
              ),
              icon: const Icon(Icons.bolt_rounded, size: 14),
              label: const Text(
                'Approve (Demo)',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
              ),
              onPressed: _demoApproveVehicle,
            ),
          ],
        ),
      );
    }

    if (_driverVehicle!.isRejected) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Registration Rejected',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.error),
                  ),
                  Text(
                    _driverVehicle!.rejectionReason ?? 'Update required documents',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _openVehicleRegistration,
              child: const Text('Update', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
            ),
          ],
        ),
      );
    }

    // Approved:
    if (!isOnline) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            IsometricVehicle3DRender(
              tierId: _driverVehicle!.tierId,
              width: 44,
              height: 32,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified_rounded, color: AppColors.emerald, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Verified Active Vehicle',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _driverVehicle!.formattedBadge,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, size: 20, color: AppColors.gray500),
              tooltip: 'Update Vehicle',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _openVehicleRegistration,
            ),
          ],
        ),
      );
    }

    // Online state: Sleek compact chip
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.obsidian.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IsometricVehicle3DRender(
            tierId: _driverVehicle!.tierId,
            width: 28,
            height: 20,
          ),
          const SizedBox(width: 6),
          Text(
            _driverVehicle!.formattedBadge,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DriverPortalBloc, DriverPortalState>(
      listener: (context, state) {
        if (state.successMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.successMessage!),
              backgroundColor: AppColors.emerald,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.read<DriverPortalBloc>().add(const ClearDriverPortalFeedbackEvent());
        }
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.read<DriverPortalBloc>().add(const ClearDriverPortalFeedbackEvent());
        }
      },
      builder: (context, state) {
        final activeTrip = state.activeTrip;

        return Scaffold(
          backgroundColor: AppColors.gray50,
          body: Stack(
            children: [
              // ── Full-Screen Interactive OpenStreetMap ─────────────
              Positioned.fill(
                child: InteractiveMapView(
                  pickupLat: activeTrip?.pickupLat ?? state.currentLat,
                  pickupLng: activeTrip?.pickupLng ?? state.currentLng,
                  dropoffLat: activeTrip?.dropoffLat ?? (state.currentLat + 0.015),
                  dropoffLng: activeTrip?.dropoffLng ?? (state.currentLng + 0.015),
                  showRoute: state.hasActiveTrip,
                  nearbyVehicles: const [],
                  onDemandDrivers: const [],
                ),
              ),

              // ── Top Floating Driver Status & Online Switch Bar ─────
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16,
                right: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DriverOnlineToggleBar(
                      isOnline: state.isOnline,
                      todaysEarnings: state.todaysEarnings,
                      completedTripsCount: state.completedTripsCount,
                      rating: state.rating,
                      onToggleOnline: (val) => _handleToggleOnline(context, val),
                      onBackToPassengerMode: () => Navigator.of(context).pop(),
                    ),
                    _buildVehicleStatusBanner(state.isOnline),
                  ],
                ),
              ),

              // ── Incoming Dispatch Alert Modal (15s Circular Countdown) ───
              if (state.hasIncomingDispatch)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: IncomingDispatchCard(
                    dispatch: state.incomingDispatch!,
                    countdownSeconds: state.countdownSeconds,
                    isAccepting: state.isProcessingAction,
                    onAccept: () {
                      context.read<DriverPortalBloc>().add(const AcceptDispatchEvent());
                    },
                    onDecline: () {
                      context.read<DriverPortalBloc>().add(const DeclineDispatchEvent());
                    },
                  ),
                ),

              // ── Active Trip Lifecycle Panel (Steps 1 to 4) ─────────
              if (state.hasActiveTrip && !state.hasIncomingDispatch)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: DriverTripLifecyclePanel(
                    trip: activeTrip!,
                    currentStep: state.lifecycleStep,
                    isProcessing: state.isProcessingAction,
                    pinErrorMessage: state.pinErrorMessage,
                    onArrivedAtPickup: () {
                      context.read<DriverPortalBloc>().add(const DriverArrivedAtPickupEvent());
                    },
                    onVerifyPin: (pin) {
                      context.read<DriverPortalBloc>().add(VerifyPinAndStartTripEvent(pin));
                    },
                    onCompleteTrip: () {
                      context.read<DriverPortalBloc>().add(const CompleteTripEvent());
                    },
                    onSubmitRating: (rating, notes) {
                      context.read<DriverPortalBloc>().add(
                            SubmitPassengerRatingEvent(rating: rating, notes: notes),
                          );
                    },
                    onFinishAndReset: () {
                      context.read<DriverPortalBloc>().add(const ResetAfterTripEvent());
                    },
                  ),
                ),

              // ── Standby Radar Banner with Demo Dispatch Simulator ──
              if (state.isOnline && !state.hasIncomingDispatch && !state.hasActiveTrip)
                Positioned(
                  bottom: 24,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.obsidian.withValues(alpha: 0.15),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppColors.emerald,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Listening for Dispatches',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.obsidian,
                                ),
                              ),
                              Text(
                                'Within 6 km radius in Freetown',
                                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            backgroundColor: AppColors.emeraldSurface,
                            foregroundColor: AppColors.emeraldDark,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.bolt_rounded, size: 16),
                          label: const Text(
                            'Demo Dispatch',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          onPressed: () {
                            context.read<DriverPortalBloc>().add(
                                  IncomingDispatchPolledEvent(
                                    TripDeliveryEntity(
                                      id: 'demo_dispatch_${DateTime.now().millisecondsSinceEpoch}',
                                      passengerId: 'demo_user_123',
                                      serviceType: 'ride',
                                      pickupLat: state.currentLat + 0.005,
                                      pickupLng: state.currentLng + 0.004,
                                      pickupAddressText: 'Lumley Beach Road (Near Atlantic Lumley Hotel)',
                                      dropoffLat: state.currentLat + 0.025,
                                      dropoffLng: state.currentLng + 0.020,
                                      dropoffAddressText: 'Cotton Tree & Siaka Stevens Street, Freetown',
                                      status: TripDeliveryStatus.searching,
                                      fareAmount: 50.0,
                                      currency: 'SLE',
                                      paymentMethod: 'wallet',
                                      distanceKm: 4.8,
                                      durationMins: 16,
                                      createdAt: DateTime.now(),
                                      verificationPin: '4821',
                                      driverPayout: 42.50,
                                      passengerName: 'Mohamed K. (Verified Rider)',
                                      passengerPhone: '+232 76 892 110',
                                      passengerRating: 4.9,
                                      distanceToPickupKm: 0.8,
                                      etaToPickupMinutes: 3,
                                    ),
                                  ),
                                );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
