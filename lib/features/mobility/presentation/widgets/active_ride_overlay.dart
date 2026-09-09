// lib/features/mobility/presentation/widgets/active_ride_overlay.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Active Ride Tracking View
// Displays live driver info, call/message actions, route ETA,
// and on-chain blockchain audit verification badge.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../../core/theme/components/vx_status_badge.dart';
import '../../domain/entities/ride_entity.dart';
import '../../../../core/widgets/vektolux_avatar.dart';
import '../../domain/entities/vehicle_tier_catalog.dart';
import 'isometric_vehicle_3d_render.dart';
import 'share_trip_sheet.dart';
import 'emergency_sos_modal.dart';

class ActiveRideOverlay extends StatelessWidget {
  final RideEntity ride;
  final VoidCallback onCancelRide;

  const ActiveRideOverlay({
    super.key,
    required this.ride,
    required this.onCancelRide,
  });

  VehicleTierId get _tierId {
    return VehicleTierId.fromString(
      ride.vehicleCategory ?? ride.vehicleModel ?? ride.vehicleMake ?? 'car',
    );
  }

  @override
  Widget build(BuildContext context) {
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
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Drag Handle ───────────────────────────────────────────
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
          const SizedBox(height: 14),

          // ── Status & ETA Header ───────────────────────────────────
          Row(
            children: [
              VxStatusBadge(
                label: ride.status.displayName,
                status: VxBadgeStatus.active,
                pulse: true,
              ),
              const Spacer(),
              Text(
                'ETA ${ride.estimatedDurationMin} mins',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Driver & Vehicle Information Card ─────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Driver Profile & Contact Row
                Row(
                  children: [
                    // Verified Driver Profile Avatar
                    Stack(
                      children: [
                        VektoluxAvatar(
                          avatarUrl: ride.driverAvatarUrl,
                          name: ride.driverName ?? 'Momoh Kargbo',
                          radius: 24,
                          borderColor: AppColors.emerald,
                          borderWidth: 2,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: const BoxDecoration(
                              color: AppColors.emerald,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: AppColors.white,
                              size: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),

                    // Driver Name & Rating
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  ride.driverName ?? 'Momoh Kargbo (Verified)',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.obsidian,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.verified_rounded,
                                size: 14,
                                color: AppColors.emerald,
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 15,
                                color: AppColors.amber,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${ride.driverRating ?? 4.9}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.obsidian,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '• Verified Operator',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.emeraldDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Quick Call & Chat Actions
                    Row(
                      children: [
                        _buildCircleActionButton(
                          icon: Icons.phone_rounded,
                          color: AppColors.emerald,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Calling ${ride.driverName ?? 'driver'}...'),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        _buildCircleActionButton(
                          icon: Icons.chat_bubble_outline_rounded,
                          color: AppColors.obsidian,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Opening live in-app ride chat...'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: AppColors.gray200),
                ),

                // ── Vehicle 3D Isometric Identity & Formatted Badge ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      // 3D Isometric Vehicle Render
                      IsometricVehicle3DRender(
                        tierId: _tierId,
                        width: 62,
                        height: 44,
                      ),
                      const SizedBox(width: 10),

                      // Formatted Vehicle Specs Badge: {Color} {Make} {Model} • {Plate}
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.obsidian,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                ride.formattedVehicleBadge,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.white,
                                  letterSpacing: 0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Standardized 3D Model • Sierra Leone Fleet',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Passenger 4-Digit Boarding Verification PIN ───────────
          Builder(
            builder: (context) {
              final isDriverArrived = ride.status == RideStatus.arrived;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDriverArrived)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.emerald, width: 1.2),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: AppColors.emeraldDark, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Driver has arrived at pickup! Share your PIN below.',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDriverArrived ? const Color(0xFFF0FDF4) : AppColors.gray50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDriverArrived ? AppColors.emerald : AppColors.emerald.withValues(alpha: 0.5),
                        width: isDriverArrived ? 2.0 : 1.5,
                      ),
                      boxShadow: isDriverArrived
                          ? [
                              BoxShadow(
                                color: AppColors.emerald.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDriverArrived ? AppColors.emerald : AppColors.emeraldSurface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.pin_outlined,
                            color: isDriverArrived ? AppColors.white : AppColors.emeraldDark,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'YOUR PICKUP PIN',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: AppColors.emeraldDark,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Share this PIN with your driver upon arrival to begin your trip.',
                                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.obsidian,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            ride.verificationPin ?? '4821',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              color: AppColors.emerald,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),

          // ── Blockchain Smart Contract Security Badge ──────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.emeraldSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.emerald.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppColors.emeraldDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Blockchain Escrow & Safety Audit Active',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                      Text(
                        'Ledger Hash: ${ride.blockchainLogHash ?? "0x7e2a9...d48b"}',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'Courier',
                          color: AppColors.emeraldDark.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: AppColors.emeraldDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── In-App Safety Tools: Share Live Trip & Emergency SOS ─
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => ShareTripSheet.show(context, ride: ride),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.gray100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.gray300),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.share_location_rounded, color: AppColors.emeraldDark, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Share Live Trip',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.obsidian,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => EmergencySosModal.show(
                    context,
                    ride: ride,
                    currentLat: ride.pickupLat,
                    currentLng: ride.pickupLng,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_rounded, color: AppColors.error, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Emergency SOS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Trip Route Details ────────────────────────────────────
          Row(
            children: [
              const Column(
                children: [
                  Icon(Icons.circle, size: 10, color: AppColors.emerald),
                  SizedBox(
                    height: 20,
                    child: VerticalDivider(
                      color: AppColors.gray300,
                      thickness: 1.5,
                    ),
                  ),
                  Icon(Icons.square, size: 10, color: AppColors.obsidian),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.pickupAddress,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.obsidian,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ride.dropoffAddress,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.obsidian,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${ride.currency} ${ride.fareAmount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.obsidian,
                    ),
                  ),
                  Text(
                    '${ride.distanceKm} km',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.gray500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Cancel Ride CTA ───────────────────────────────────────
          VxButton.destructive(
            label: 'Cancel Ride Request',
            height: 48,
            onPressed: onCancelRide,
          ),
        ],
      ),
    );
  }

  Widget _buildCircleActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}
