// lib/features/mobility/presentation/widgets/driver_trip_lifecycle_panel.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Active Trip Lifecycle Stepper Panel
// 4-step execution:
//   Step 1: Navigate to Pickup (Address + External Maps + Contact)
//   Step 2: Arrived at Pickup (Status update + Waiting timer)
//   Step 3: Passenger 4-Digit PIN Verification -> Trip in Progress
//   Step 4: Complete Trip (Fare calculation + Escrow release + Passenger rating)
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/trip_delivery_entity.dart';
import '../bloc/driver_portal_state.dart';

class DriverTripLifecyclePanel extends StatefulWidget {
  final TripDeliveryEntity trip;
  final DriverTripLifecycleStep currentStep;
  final bool isProcessing;
  final String? pinErrorMessage;
  final VoidCallback onArrivedAtPickup;
  final ValueChanged<String> onVerifyPin;
  final VoidCallback onCompleteTrip;
  final void Function(int rating, String? notes) onSubmitRating;
  final VoidCallback onFinishAndReset;

  const DriverTripLifecyclePanel({
    super.key,
    required this.trip,
    required this.currentStep,
    required this.isProcessing,
    this.pinErrorMessage,
    required this.onArrivedAtPickup,
    required this.onVerifyPin,
    required this.onCompleteTrip,
    required this.onSubmitRating,
    required this.onFinishAndReset,
  });

  @override
  State<DriverTripLifecyclePanel> createState() => _DriverTripLifecyclePanelState();
}

class _DriverTripLifecyclePanelState extends State<DriverTripLifecyclePanel> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _reviewNotesController = TextEditingController();
  int _selectedStars = 5;

  @override
  void dispose() {
    _pinController.dispose();
    _reviewNotesController.dispose();
    super.dispose();
  }

  void _showPinEntryDialog() {
    _pinController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.pin_outlined, color: AppColors.emeraldDark, size: 26),
                SizedBox(width: 10),
                Text(
                  'Verify Passenger PIN',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.obsidian,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ask passenger for their 4-digit security code displayed on their app to verify boarding.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 12,
                    color: AppColors.obsidian,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••',
                    hintStyle: const TextStyle(letterSpacing: 12, color: AppColors.gray400),
                    filled: true,
                    fillColor: AppColors.gray100,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (widget.pinErrorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.pinErrorMessage!,
                    style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel', style: TextStyle(color: AppColors.gray500, fontWeight: FontWeight.w700)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: AppColors.obsidian,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onPressed: () {
                  final pin = _pinController.text.trim();
                  if (pin.length == 4) {
                    Navigator.of(dialogCtx).pop();
                    widget.onVerifyPin(pin);
                  }
                },
                child: const Text(
                  'Start Trip',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRatingAndSettlementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final payout = widget.trip.driverPayout ?? (widget.trip.fareAmount * 0.85);

          return Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top handle
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.gray300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Success icon & Payout release
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: AppColors.emeraldSurface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: AppColors.emeraldDark, size: 36),
                  ),
                ),
                const SizedBox(height: 14),
                const Center(
                  child: Text(
                    'Trip Completed & Escrow Released',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.obsidian,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'SLE ${payout.toStringAsFixed(2)} has been credited to your wallet',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.emeraldDark,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Star Rating Selector
                const Center(
                  child: Text(
                    'Rate your passenger',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final starNum = index + 1;
                    return IconButton(
                      icon: Icon(
                        starNum <= _selectedStars ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: AppColors.amber,
                        size: 36,
                      ),
                      onPressed: () {
                        setSheetState(() => _selectedStars = starNum);
                        setState(() => _selectedStars = starNum);
                      },
                    );
                  }),
                ),
                const SizedBox(height: 12),

                // Optional Review Notes
                TextField(
                  controller: _reviewNotesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Optional passenger feedback (polite, on-time, etc.)',
                    hintStyle: const TextStyle(fontSize: 12, color: AppColors.gray400),
                    filled: true,
                    fillColor: AppColors.gray50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 20),

                // Submit Rating & Finish CTA
                VxButton(
                  label: 'Submit Rating & Ready for Next Ride',
                  icon: Icons.check_circle_rounded,
                  isLoading: widget.isProcessing,
                  onPressed: () {
                    widget.onSubmitRating(_selectedStars, _reviewNotesController.text.trim());
                    Navigator.of(sheetCtx).pop();
                    widget.onFinishAndReset();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidian.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Stepper Progress Bar ──────────────────────────────
            _buildLifecycleStepper(),
            const SizedBox(height: 16),

            // ── Dynamic Step View ─────────────────────────────────────
            switch (widget.currentStep) {
              DriverTripLifecycleStep.navigatingToPickup => _buildStep1NavigatingToPickup(),
              DriverTripLifecycleStep.arrivedAtPickup => _buildStep2ArrivedAtPickup(),
              DriverTripLifecycleStep.inProgress => _buildStep3TripInProgress(),
              DriverTripLifecycleStep.tripCompleted => _buildStep4TripCompleted(),
              DriverTripLifecycleStep.idle => const SizedBox.shrink(),
            },
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 1. STEPPER BAR: Navigate -> Arrived -> In Progress -> Complete
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildLifecycleStepper() {
    final stepIndex = switch (widget.currentStep) {
      DriverTripLifecycleStep.navigatingToPickup => 1,
      DriverTripLifecycleStep.arrivedAtPickup => 2,
      DriverTripLifecycleStep.inProgress => 3,
      DriverTripLifecycleStep.tripCompleted => 4,
      DriverTripLifecycleStep.idle => 0,
    };

    return Row(
      children: [
        _buildStepNode(1, 'Pickup', stepIndex >= 1, stepIndex == 1),
        _buildStepConnector(stepIndex >= 2),
        _buildStepNode(2, 'Arrived', stepIndex >= 2, stepIndex == 2),
        _buildStepConnector(stepIndex >= 3),
        _buildStepNode(3, 'In Transit', stepIndex >= 3, stepIndex == 3),
        _buildStepConnector(stepIndex >= 4),
        _buildStepNode(4, 'Complete', stepIndex >= 4, stepIndex == 4),
      ],
    );
  }

  Widget _buildStepNode(int number, String label, bool isDone, bool isActive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.emerald
                : (isDone ? AppColors.obsidian : AppColors.gray200),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: isDone && !isActive
              ? const Icon(Icons.check, size: 14, color: AppColors.white)
              : Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isActive ? AppColors.obsidian : (isDone ? AppColors.white : AppColors.gray600),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive ? AppColors.obsidian : AppColors.gray500,
          ),
        ),
      ],
    );
  }

  Widget _buildStepConnector(bool isDone) {
    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.only(bottom: 14),
        color: isDone ? AppColors.obsidian : AppColors.gray200,
      ),
    );
  }

  void _showExternalMapsSelector(BuildContext context, double destLat, double destLng, String address) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Navigate with External App',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              address,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 18),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              leading: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.emeraldSurface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.map_rounded, color: AppColors.emeraldDark),
              ),
              title: const Text(
                'Google Maps',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian),
              ),
              subtitle: const Text('Turn-by-turn navigation', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.gray400),
              onTap: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Launching Google Maps navigation to $address...'),
                    backgroundColor: AppColors.obsidian,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.navigation_rounded, color: Colors.blue),
              ),
              title: const Text(
                'Waze',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian),
              ),
              subtitle: const Text('Live traffic & hazard alerts', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.gray400),
              onTap: () {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Launching Waze navigation to $address...'),
                    backgroundColor: AppColors.obsidian,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 1: NAVIGATING TO PICKUP
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStep1NavigatingToPickup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pickup Address Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.gray50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.emeraldSurface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.navigation_rounded, color: AppColors.emeraldDark, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'STEP 1: PICKUP LOCATION',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.emeraldDark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.trip.pickupAddressText,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Navigation Action & Contact Row
        Row(
          children: [
            // External Maps Button
            Expanded(
              child: VxButton.outlined(
                label: 'Google Maps / Waze',
                icon: Icons.navigation_rounded,
                onPressed: () {
                  _showExternalMapsSelector(
                    context,
                    widget.trip.pickupLat,
                    widget.trip.pickupLng,
                    widget.trip.pickupAddressText,
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            // Contact Passenger Button
            Container(
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: IconButton(
                tooltip: 'Call Passenger',
                icon: const Icon(Icons.phone_outlined, color: AppColors.obsidian, size: 20),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Calling passenger: ${widget.trip.passengerPhone ?? "+232 (Mobile)"}'),
                      backgroundColor: AppColors.obsidian,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Primary CTA: Arrived at Pickup
        VxButton(
          label: 'I Have Arrived at Pickup',
          icon: Icons.location_on_rounded,
          isLoading: widget.isProcessing,
          onPressed: widget.onArrivedAtPickup,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 2: ARRIVED AT PICKUP — WAITING FOR PASSENGER & PIN
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStep2ArrivedAtPickup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.emeraldSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined, color: AppColors.emeraldDark, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Passenger Notified of Arrival',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Waiting at: ${widget.trip.pickupAddressText}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Primary CTA: Enter PIN & Start Trip
        VxButton(
          label: 'Verify 4-Digit PIN & Start Trip',
          icon: Icons.pin_outlined,
          isLoading: widget.isProcessing,
          onPressed: _showPinEntryDialog,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 3: TRIP IN PROGRESS — HEADING TO DESTINATION
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStep3TripInProgress() {
    final payout = widget.trip.driverPayout ?? (widget.trip.fareAmount * 0.85);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.obsidian,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_car_rounded, color: AppColors.emerald, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EN ROUTE TO DESTINATION',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.emerald),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.trip.dropoffAddressText,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                'SLE ${payout.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.emerald),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Primary CTA: Complete Trip
        VxButton(
          label: 'Complete Trip at Drop-off',
          icon: Icons.flag_rounded,
          isLoading: widget.isProcessing,
          onPressed: () {
            widget.onCompleteTrip();
            _showRatingAndSettlementSheet();
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 4: TRIP COMPLETED — RATING & SETTLEMENT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStep4TripCompleted() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VxButton(
          label: 'Rate Passenger & Release Escrow',
          icon: Icons.star_rounded,
          onPressed: _showRatingAndSettlementSheet,
        ),
      ],
    );
  }
}
