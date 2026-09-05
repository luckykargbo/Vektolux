// lib/features/mobility/presentation/widgets/vehicle_selection_bottom_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vehicle & Courier Category Selection Bottom Sheet
// Standalone modal bottom sheet for selecting a vehicle tier with
// real-time fare previews, ETA badges, and driver availability dots.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/vehicle_category_catalog.dart';
import '../../domain/services/fare_calculation_service.dart';

class VehicleSelectionBottomSheet extends StatefulWidget {
  /// 'ride' | 'delivery'
  final String serviceType;

  /// Currently selected category.
  final BookingVehicleCategory selectedCategory;

  /// Pre-computed fare & ETA estimates per tier.
  final Map<BookingVehicleCategory, CalculatedTierEstimate>
      calculatedTierEstimates;

  /// Pickup and dropoff labels (displayed in the route summary).
  final String pickupAddress;
  final String dropoffAddress;

  /// Estimated route distance and duration (top-level).
  final double estimatedDistanceKm;
  final int estimatedDurationMin;

  /// Called when the user taps a different category tile.
  final ValueChanged<BookingVehicleCategory> onSelectCategory;

  /// Called when the user taps "Confirm & Book".
  final VoidCallback onConfirm;

  const VehicleSelectionBottomSheet({
    super.key,
    required this.serviceType,
    required this.selectedCategory,
    required this.calculatedTierEstimates,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.estimatedDistanceKm,
    required this.estimatedDurationMin,
    required this.onSelectCategory,
    required this.onConfirm,
  });

  /// Convenience static method to present the sheet via `showModalBottomSheet`.
  static Future<void> show(
    BuildContext context, {
    required String serviceType,
    required BookingVehicleCategory selectedCategory,
    required Map<BookingVehicleCategory, CalculatedTierEstimate>
        calculatedTierEstimates,
    required String pickupAddress,
    required String dropoffAddress,
    required double estimatedDistanceKm,
    required int estimatedDurationMin,
    required ValueChanged<BookingVehicleCategory> onSelectCategory,
    required VoidCallback onConfirm,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VehicleSelectionBottomSheet(
        serviceType: serviceType,
        selectedCategory: selectedCategory,
        calculatedTierEstimates: calculatedTierEstimates,
        pickupAddress: pickupAddress,
        dropoffAddress: dropoffAddress,
        estimatedDistanceKm: estimatedDistanceKm,
        estimatedDurationMin: estimatedDurationMin,
        onSelectCategory: onSelectCategory,
        onConfirm: () {
          Navigator.of(context).pop();
          onConfirm();
        },
      ),
    );
  }

  @override
  State<VehicleSelectionBottomSheet> createState() =>
      _VehicleSelectionBottomSheetState();
}

class _VehicleSelectionBottomSheetState
    extends State<VehicleSelectionBottomSheet> {
  late BookingVehicleCategory _localSelected;

  @override
  void initState() {
    super.initState();
    _localSelected = widget.selectedCategory;
  }

  @override
  void didUpdateWidget(covariant VehicleSelectionBottomSheet old) {
    super.didUpdateWidget(old);
    if (old.selectedCategory != widget.selectedCategory) {
      _localSelected = widget.selectedCategory;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDelivery = widget.serviceType == 'delivery';
    final categories =
        VehicleCategoryCatalog.categoriesForService(widget.serviceType);
    final selectedEstimate = widget.calculatedTierEstimates[_localSelected];
    final fare =
        selectedEstimate?.fareAmount ?? _localSelected.baseFare + 25.0;
    final currency = selectedEstimate?.currency ?? 'SLE';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        0,
        10,
        0,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ─────────────────────────────────────────
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

          // ── Header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isDelivery
                      ? 'Choose Courier Tier'
                      : 'Choose Your Ride',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.obsidian,
                    letterSpacing: -0.3,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.estimatedDistanceKm.toStringAsFixed(1)} km · ${widget.estimatedDurationMin} min',
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

          // ── Route summary ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.my_location_rounded,
                    size: 13, color: AppColors.emerald),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.pickupAddress,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.gray600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 13, color: AppColors.gray400),
                ),
                const Icon(Icons.location_on_rounded,
                    size: 13, color: AppColors.obsidian),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    widget.dropoffAddress,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.gray600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Category tiles ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isDelivery
                      ? 'Select Delivery Courier Tier'
                      : 'Select Vehicle Tier',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                  ),
                ),
                const Text(
                  'Upfront Guaranteed Fare',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.emeraldDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Vertical scrollable category list ────────────────────
          ...categories.map((category) {
            final isSelected = category == _localSelected;
            final estimate = widget.calculatedTierEstimates[category];
            final tierFare =
                estimate?.fareAmount ?? category.baseFare + 20.0;
            final arrivalEta = estimate?.arrivalEtaMinutes ?? 5;
            final hasDriver = estimate?.hasNearbyDriver ?? false;

            return Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: _buildCategoryTile(
                category: category,
                isSelected: isSelected,
                fare: tierFare,
                arrivalEta: arrivalEta,
                currency: currency,
                hasDriver: hasDriver,
                onTap: () {
                  setState(() => _localSelected = category);
                  widget.onSelectCategory(category);
                },
              ),
            );
          }),

          const SizedBox(height: 16),

          // ── Confirm CTA ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: VxButton(
              label: isDelivery
                  ? 'Confirm ${_localSelected.title} ($currency ${fare.toStringAsFixed(0)})'
                  : 'Confirm ${_localSelected.title} ($currency ${fare.toStringAsFixed(0)})',
              icon: isDelivery
                  ? Icons.local_shipping_rounded
                  : Icons.directions_car_filled_rounded,
              onPressed: widget.onConfirm,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile({
    required BookingVehicleCategory category,
    required bool isSelected,
    required double fare,
    required int arrivalEta,
    required String currency,
    required bool hasDriver,
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.emerald.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Category icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.emerald : AppColors.gray100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                category.iconData,
                size: 22,
                color: isSelected ? AppColors.white : AppColors.obsidian,
              ),
            ),
            const SizedBox(width: 14),

            // Title, subtitle, capacity
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? AppColors.emeraldDark
                          : AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${category.subtitle} · ${category.capacity}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.gray500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // ETA + fare column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ETA pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.emerald.withValues(alpha: 0.5)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasDriver) ...[
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: const BoxDecoration(
                            color: AppColors.emerald,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      Text(
                        '$arrivalEta min',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? AppColors.emeraldDark
                              : AppColors.gray600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // Fare
                Text(
                  '$currency ${fare.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isSelected
                        ? AppColors.emeraldDark
                        : AppColors.obsidian,
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
