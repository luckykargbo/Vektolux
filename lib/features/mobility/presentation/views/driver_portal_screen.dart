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
      child: const _DriverPortalScreenView(),
    );
  }
}

class _DriverPortalScreenView extends StatelessWidget {
  const _DriverPortalScreenView();

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
                child: DriverOnlineToggleBar(
                  isOnline: state.isOnline,
                  todaysEarnings: state.todaysEarnings,
                  completedTripsCount: state.completedTripsCount,
                  rating: state.rating,
                  onToggleOnline: (val) {
                    context.read<DriverPortalBloc>().add(ToggleDriverOnlineStatusEvent(val));
                  },
                  onBackToPassengerMode: () => Navigator.of(context).pop(),
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
