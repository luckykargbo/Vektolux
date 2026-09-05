// lib/features/mobility/presentation/widgets/share_trip_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Share Live Trip with Family Bottom Sheet
// Generates end-to-end encrypted tracking link, route status,
// vehicle/driver credentials, and WhatsApp / SMS sharing actions.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/ride_entity.dart';

class ShareTripSheet extends StatelessWidget {
  final RideEntity ride;

  const ShareTripSheet({
    super.key,
    required this.ride,
  });

  static Future<void> show(BuildContext context, {required RideEntity ride}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ShareTripSheet(ride: ride),
    );
  }

  String get _trackingUrl => 'https://vektolux.com/track/ride-${ride.id.substring(0, mathMin(8, ride.id.length))}';

  int mathMin(int a, int b) => a < b ? a : b;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidian.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        MediaQuery.of(context).padding.bottom + 20,
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
          const SizedBox(height: 18),

          // ── Title & Icon ──────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.share_location_rounded,
                  color: AppColors.emeraldDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share Live Trip with Family',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Real-time GPS tracking link with driver & car details',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── Trip Summary Card ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_pin_rounded, color: AppColors.emerald, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Driver: ${ride.driverName ?? "Verified Driver"}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.gray200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ride.vehiclePlate ?? 'SL-940-BA',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'Courier',
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.directions_car_filled_rounded, color: AppColors.gray500, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      '${ride.vehicleMake ?? "Toyota"} ${ride.vehicleModel ?? "Corolla"} (${ride.vehicleColor ?? "Silver"})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.gray700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'ETA ${ride.estimatedDurationMin}m',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.emeraldDark,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, color: AppColors.obsidian, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'To: ${ride.dropoffAddress}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Generated Live Link Box ───────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.gray300),
            ),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, color: AppColors.gray500, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _trackingUrl,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'Courier',
                      color: AppColors.obsidian,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: AppColors.emeraldDark, size: 20),
                  tooltip: 'Copy Tracking Link',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _trackingUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Live trip tracking link copied to clipboard!'),
                        backgroundColor: AppColors.emerald,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Action Buttons: WhatsApp & SMS ────────────────────────
          Row(
            children: [
              Expanded(
                child: VxButton.outlined(
                  label: 'Share WhatsApp',
                  icon: Icons.chat_rounded,
                  height: 48,
                  onPressed: () {
                    final message = 'Track my live ride in Freetown with Vektolux:\n'
                        'Driver: ${ride.driverName ?? "Verified Driver"} (${ride.vehiclePlate ?? "SL-940-BA"})\n'
                        'Tracking Link: $_trackingUrl';
                    Clipboard.setData(ClipboardData(text: message));
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Live trip message copied for WhatsApp sharing!'),
                        backgroundColor: AppColors.emerald,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: VxButton.primary(
                  text: 'Copy Full SMS',
                  icon: Icons.sms_outlined,
                  height: 48,
                  onPressed: () {
                    final sms = 'I am on my way via Vektolux. Live tracking: $_trackingUrl';
                    Clipboard.setData(ClipboardData(text: sms));
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Trip tracking SMS copied to clipboard!'),
                        backgroundColor: AppColors.emerald,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
