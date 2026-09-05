// lib/features/mobility/presentation/widgets/finding_driver_radar_overlay.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — "Finding Your Driver" Pulsing Radar Animation Overlay
// Displays concentric emerald wave pulses, real-time broadcast status,
// and trip summary cards while nearby driver nodes receive the dispatch.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';

class FindingDriverRadarOverlay extends StatefulWidget {
  final String serviceType; // 'ride' | 'delivery'
  final String categoryTitle;
  final String pickupAddress;
  final String dropoffAddress;
  final double estimatedFare;
  final String currency;
  final VoidCallback onCancelRequest;

  const FindingDriverRadarOverlay({
    super.key,
    required this.serviceType,
    required this.categoryTitle,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.estimatedFare,
    this.currency = 'SLE',
    required this.onCancelRequest,
  });

  @override
  State<FindingDriverRadarOverlay> createState() => _FindingDriverRadarOverlayState();
}

class _FindingDriverRadarOverlayState extends State<FindingDriverRadarOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDelivery = widget.serviceType == 'delivery';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidian.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, -8),
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
        children: [
          // Drag handle
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

          // ── 1. Pulsing Concentric Radar Scanner ───────────────────
          SizedBox(
            width: 140,
            height: 140,
            child: AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _RadarPulsePainter(animationValue: _radarController.value),
                  child: Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.obsidian,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.emerald.withValues(alpha: 0.4),
                            blurRadius: 14,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          isDelivery
                              ? Icons.local_shipping_rounded
                              : Icons.directions_car_filled_rounded,
                          color: AppColors.emerald,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // ── 2. Status Typography ──────────────────────────────────
          Text(
            isDelivery ? 'Locating Nearby Courier...' : 'Finding your driver...',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isDelivery
                ? 'Broadcasting parcel pickup request to verified couriers...'
                : 'Connecting with closest ${widget.categoryTitle} in Freetown...',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.gray600,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // ── 3. Trip Summary Pill Card ─────────────────────────────
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Route endpoints
                Row(
                  children: [
                    const Icon(Icons.my_location_rounded, size: 15, color: AppColors.emerald),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.pickupAddress,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.obsidian,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 7, top: 4, bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 1,
                      height: 12,
                      color: AppColors.gray300,
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 15, color: AppColors.obsidian),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.dropoffAddress,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.obsidian,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 18),

                // Vehicle Category & Estimated Upfront Fare
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.emeraldSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.categoryTitle,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.emeraldDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Upfront Fare:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.gray600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${widget.currency} ${widget.estimatedFare.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 4. Cancel Request Action ──────────────────────────────
          VxButton(
            label: 'Cancel Request',
            variant: VxButtonVariant.outlined,
            icon: Icons.close_rounded,
            height: 48,
            onPressed: widget.onCancelRequest,
          ),
        ],
      ),
    );
  }
}

/// Custom painter rendering animated concentric ripple circles.
class _RadarPulsePainter extends CustomPainter {
  final double animationValue;

  const _RadarPulsePainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final waveProgress = (animationValue + (i * 0.33)) % 1.0;
      final radius = maxRadius * waveProgress;
      final opacity = (1.0 - waveProgress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = AppColors.emerald.withValues(alpha: opacity * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(center, radius, paint);

      final fillPaint = Paint()
        ..color = AppColors.emerald.withValues(alpha: opacity * 0.08)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center, radius, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPulsePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
