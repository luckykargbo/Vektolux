// lib/features/mobility/presentation/widgets/active_searching_overlay.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Active Searching Overlay (Composing Wrapper)
// Wraps FindingDriverRadarOverlay with enhanced nearby driver count,
// elapsed search timer, and expandable matching driver proximity feed.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/nearby_driver_entity.dart';
import 'finding_driver_radar_overlay.dart';

class ActiveSearchingOverlay extends StatefulWidget {
  /// 'ride' | 'delivery'
  final String serviceType;

  /// Title of the selected vehicle/courier category.
  final String categoryTitle;

  /// Route endpoint labels.
  final String pickupAddress;
  final String dropoffAddress;

  /// Upfront guaranteed fare.
  final double estimatedFare;
  final String currency;

  /// Live list of nearby drivers being queried.
  final List<NearbyDriverEntity> nearbyDrivers;

  /// Cancel the active search request.
  final VoidCallback onCancelRequest;

  const ActiveSearchingOverlay({
    super.key,
    required this.serviceType,
    required this.categoryTitle,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.estimatedFare,
    this.currency = 'SLE',
    this.nearbyDrivers = const [],
    required this.onCancelRequest,
  });

  @override
  State<ActiveSearchingOverlay> createState() => _ActiveSearchingOverlayState();
}

class _ActiveSearchingOverlayState extends State<ActiveSearchingOverlay> {
  late Timer _elapsedTimer;
  int _elapsedSeconds = 0;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  @override
  void dispose() {
    _elapsedTimer.cancel();
    super.dispose();
  }

  String get _formattedElapsed {
    final mins = _elapsedSeconds ~/ 60;
    final secs = _elapsedSeconds % 60;
    return mins > 0
        ? '${mins}m ${secs.toString().padLeft(2, '0')}s'
        : '${secs}s';
  }

  @override
  Widget build(BuildContext context) {
    final driverCount = widget.nearbyDrivers.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Enhanced status bar above the radar overlay ────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.obsidian,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(
            children: [
              // Live driver count badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: driverCount > 0
                      ? AppColors.emerald.withValues(alpha: 0.25)
                      : AppColors.gray600.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: driverCount > 0
                            ? AppColors.emerald
                            : AppColors.gray400,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$driverCount ${widget.serviceType == 'delivery' ? 'courier' : 'driver'}${driverCount == 1 ? '' : 's'} nearby',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Elapsed search timer
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: AppColors.white.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formattedElapsed,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white.withValues(alpha: 0.85),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 10),

              // Expand/collapse driver list
              if (driverCount > 0)
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  child: Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: AppColors.white,
                    size: 22,
                  ),
                ),
            ],
          ),
        ),

        // ── Expandable nearby driver proximity feed ─────────────────
        if (_isExpanded && widget.nearbyDrivers.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              border: Border.all(color: AppColors.border),
            ),
            constraints: const BoxConstraints(maxHeight: 120),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: widget.nearbyDrivers.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 12, color: AppColors.border),
              itemBuilder: (context, index) {
                final driver = widget.nearbyDrivers[index];
                return Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.directions_car_filled_rounded,
                        size: 14,
                        color: AppColors.emeraldDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driver.driverName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.obsidian,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${driver.distanceKm.toStringAsFixed(1)} km away · ${driver.etaMinutes} min',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.gray500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      driver.vehicle?.category.displayName ?? 'Standard',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.emeraldDark,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

        // ── Core radar overlay ──────────────────────────────────────
        FindingDriverRadarOverlay(
          serviceType: widget.serviceType,
          categoryTitle: widget.categoryTitle,
          pickupAddress: widget.pickupAddress,
          dropoffAddress: widget.dropoffAddress,
          estimatedFare: widget.estimatedFare,
          currency: widget.currency,
          onCancelRequest: widget.onCancelRequest,
        ),
      ],
    );
  }
}
