// lib/features/mobility/presentation/widgets/incoming_dispatch_card.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Incoming Dispatch Alert Card
// Displays real-time job offer with 15-second circular countdown timer,
// route distance, estimated driver payout, passenger trust rating, and Accept/Decline actions.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/trip_delivery_entity.dart';

class IncomingDispatchCard extends StatelessWidget {
  final TripDeliveryEntity dispatch;
  final int countdownSeconds;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool isAccepting;

  const IncomingDispatchCard({
    super.key,
    required this.dispatch,
    required this.countdownSeconds,
    required this.onAccept,
    required this.onDecline,
    this.isAccepting = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDelivery = dispatch.serviceType == 'delivery';
    final payout = dispatch.driverPayout ?? (dispatch.fareAmount * 0.85);
    final progress = (countdownSeconds / 15.0).clamp(0.0, 1.0);

    // Dynamic timer color based on urgency
    Color timerColor = AppColors.emerald;
    if (countdownSeconds <= 4) {
      timerColor = AppColors.error;
    } else if (countdownSeconds <= 8) {
      timerColor = AppColors.amber;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidian.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: timerColor.withValues(alpha: 0.5), width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Header Banner with 15s Circular Countdown ────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              color: AppColors.obsidian,
              child: Row(
                children: [
                  // Service Type Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDelivery
                          ? AppColors.amber.withValues(alpha: 0.2)
                          : AppColors.emerald.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDelivery ? AppColors.amber : AppColors.emerald,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDelivery ? Icons.local_shipping_rounded : Icons.directions_car_rounded,
                          color: isDelivery ? AppColors.amber : AppColors.emerald,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isDelivery ? 'PACKAGE DELIVERY' : 'RIDE HAIL',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: isDelivery ? AppColors.amber : AppColors.emerald,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),

                  // ── 15-Second Circular Radial Timer ───────────────────
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 4,
                          backgroundColor: AppColors.white.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                        ),
                        Text(
                          '$countdownSeconds',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: timerColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Body: Estimated Driver Payout & Locations ─────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Payout Banner
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ESTIMATED EARNINGS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${dispatch.currency} ',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.emeraldDark,
                                ),
                              ),
                              Text(
                                payout.toStringAsFixed(2),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.obsidian,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Passenger Trust Rating Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.gray100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, size: 16, color: AppColors.amber),
                            const SizedBox(width: 4),
                            Text(
                              dispatch.passengerRating?.toStringAsFixed(1) ?? '4.9',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              dispatch.passengerName ?? 'Verified Rider',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Route Card (Pickup -> Dropoff)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.gray50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        // Pickup row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: const BoxDecoration(
                                color: AppColors.emerald,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'PICKUP',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.emeraldDark,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (dispatch.distanceToPickupKm != null)
                                        Text(
                                          '${dispatch.distanceToPickupKm} km away (~${dispatch.etaToPickupMinutes ?? 3} mins)',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.emeraldDark,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dispatch.pickupAddressText,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.obsidian,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 4, top: 4, bottom: 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              height: 12,
                              child: VerticalDivider(color: AppColors.gray300, thickness: 1.5),
                            ),
                          ),
                        ),
                        // Dropoff row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: const BoxDecoration(
                                color: AppColors.obsidian,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'DROP-OFF ZONE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textSecondary,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${dispatch.distanceKm.toStringAsFixed(1)} km • ${dispatch.durationMins} mins',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dispatch.dropoffAddressText,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.obsidian,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Package Details Note if Delivery
                  if (isDelivery && dispatch.packageDetails != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.amberSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Recipient: ${dispatch.packageDetails!.recipientName} • ${dispatch.packageDetails!.isFragile ? "⚠️ Fragile" : "Standard"}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.obsidian,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // ── Actions: Accept & Decline ────────────────────────
                  Row(
                    children: [
                      // Decline button
                      Expanded(
                        flex: 2,
                        child: VxButton.outlined(
                          label: 'Decline',
                          onPressed: isAccepting ? null : onDecline,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Accept button with countdown
                      Expanded(
                        flex: 3,
                        child: VxButton(
                          label: 'Accept Job (${countdownSeconds}s)',
                          icon: Icons.check_circle_rounded,
                          isLoading: isAccepting,
                          onPressed: isAccepting ? null : onAccept,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
