// lib/features/mobility/presentation/widgets/dynamic_ride_selection_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Dynamic 3D Isometric Ride Selection Sheet
// Presents Sierra Leone vehicle tiers with 3D isometric renders,
// dynamic upfront SLE fare calculations, capacity badges, and reactive CTA.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/vehicle_tier_catalog.dart';
import 'isometric_vehicle_3d_render.dart';

class DynamicRideSelectionSheet extends StatefulWidget {
  final String serviceType; // 'ride' | 'delivery'
  final VehicleTierConfig selectedTier;
  final double distanceKm;
  final int durationMins;
  final String pickupAddress;
  final String dropoffAddress;
  final ValueChanged<VehicleTierConfig> onSelectTier;
  final VoidCallback onConfirmBooking;
  final bool isSubmitting;

  const DynamicRideSelectionSheet({
    super.key,
    required this.serviceType,
    required this.selectedTier,
    required this.distanceKm,
    required this.durationMins,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.onSelectTier,
    required this.onConfirmBooking,
    this.isSubmitting = false,
  });

  /// Static helper to display as a modal bottom sheet
  static Future<void> show(
    BuildContext context, {
    required String serviceType,
    required VehicleTierConfig selectedTier,
    required double distanceKm,
    required int durationMins,
    required String pickupAddress,
    required String dropoffAddress,
    required ValueChanged<VehicleTierConfig> onSelectTier,
    required VoidCallback onConfirmBooking,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DynamicRideSelectionSheet(
        serviceType: serviceType,
        selectedTier: selectedTier,
        distanceKm: distanceKm,
        durationMins: durationMins,
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
        onSelectTier: onSelectTier,
        onConfirmBooking: () {
          Navigator.of(context).pop();
          onConfirmBooking();
        },
      ),
    );
  }

  @override
  State<DynamicRideSelectionSheet> createState() => _DynamicRideSelectionSheetState();
}

class _DynamicRideSelectionSheetState extends State<DynamicRideSelectionSheet> {
  late VehicleTierConfig _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedTier;
  }

  @override
  void didUpdateWidget(covariant DynamicRideSelectionSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTier != widget.selectedTier) {
      _selected = widget.selectedTier;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDelivery = widget.serviceType == 'delivery';
    final tiers = VehicleTierConfig.tiersForService(widget.serviceType);
    final currentFare = _selected.calculateFare(widget.distanceKm);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        0,
        12,
        0,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. Drag Handle ──
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

          // ── 2. Header with Distance & Estimated Duration ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isDelivery ? 'Select Delivery Courier' : 'Select Vehicle Tier',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.obsidian,
                    letterSpacing: -0.3,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.distanceKm.toStringAsFixed(1)} km · ${widget.durationMins} min',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.emeraldDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // ── 3. Subtitle / Upfront Guarantee ──
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Guaranteed upfront SLE pricing · No surge surprises',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.gray500,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 4. Vertical List of 3D Isometric Vehicle Tier Cards ──
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tiers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final tier = tiers[index];
              final isSelected = tier.id == _selected.id;
              final fare = tier.calculateFare(widget.distanceKm);

              return _buildTierCard(
                tier: tier,
                isSelected: isSelected,
                fare: fare,
                onTap: () {
                  setState(() => _selected = tier);
                  widget.onSelectTier(tier);
                },
              );
            },
          ),
          const SizedBox(height: 18),

          // ── 5. Reactive CTA Button ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: VxButton(
              label: '${_selected.buttonLabel} · SLE ${currentFare.toStringAsFixed(0)}',
              icon: isDelivery ? Icons.local_shipping_rounded : Icons.directions_car_filled_rounded,
              isLoading: widget.isSubmitting,
              onPressed: widget.isSubmitting ? null : widget.onConfirmBooking,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCard({
    required VehicleTierConfig tier,
    required bool isSelected,
    required double fare,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emeraldSurface : AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.emerald.withValues(alpha: 0.20),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // ── Left: 3D Isometric Transparent Vehicle Render ──
            IsometricVehicle3DRender(
              tierId: tier.tierId,
              render3DUrl: tier.render3DUrl,
              width: 72,
              height: 52,
              isSelected: isSelected,
            ),
            const SizedBox(width: 14),

            // ── Center: Tier Name, Capacity Badge, and Live ETA ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tier.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Capacity Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.white : AppColors.gray100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.emerald.withValues(alpha: 0.4)
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          tier.capacityLabel,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? AppColors.emeraldDark : AppColors.gray600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tier.description,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.gray500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // ETA Badge
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.emerald,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'ETA ${tier.etaMinutesDefault} min away',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppColors.emeraldDark : AppColors.gray600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // ── Right: Upfront Dynamic Calculated Fare ──
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'SLE ${fare.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SLE ${tier.pricePerKmSLE.toStringAsFixed(0)}/km',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.gray500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
