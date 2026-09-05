// lib/features/mobility/presentation/widgets/vehicle_type_carousel.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vehicle Type Selection Carousel
// Displays Bike, Standard Taxi, Delivery Van, and Heavy Truck
// with dynamic fares, ETA minutes, and capacity specifications.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/mobility_vehicle_entity.dart';

class VehicleTypeCarousel extends StatelessWidget {
  final MobilityVehicleType selectedType;
  final Map<MobilityVehicleType, VehicleCategoryOption> vehicleOptions;
  final ValueChanged<MobilityVehicleType> onSelectType;

  const VehicleTypeCarousel({
    super.key,
    required this.selectedType,
    required this.vehicleOptions,
    required this.onSelectType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Choose Vehicle Category',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 142,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: MobilityVehicleType.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final type = MobilityVehicleType.values[index];
              final isSelected = type == selectedType;
              final option = vehicleOptions[type];

              final fare = option?.estimatedFare ?? 2000.0;
              final eta = option?.etaMinutes ?? 5;
              final currency = option?.currency ?? 'SLE';

              return _buildVehicleCard(
                type: type,
                isSelected: isSelected,
                fare: fare,
                eta: eta,
                currency: currency,
                onTap: () => onSelectType(type),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleCard({
    required MobilityVehicleType type,
    required bool isSelected,
    required double fare,
    required int eta,
    required String currency,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 154,
        padding: const EdgeInsets.all(12),
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
                    color: AppColors.emerald.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top icon & ETA pill
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.emerald
                        : AppColors.gray100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    type.iconData,
                    size: 20,
                    color: isSelected ? AppColors.white : AppColors.obsidian,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '$eta min',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? AppColors.emeraldDark : AppColors.gray600,
                    ),
                  ),
                ),
              ],
            ),

            // Vehicle Category Name
            Text(
              type.displayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            // Capacity indicator (passengers + luggage)
            Row(
              children: [
                const Icon(
                  Icons.person_outline_rounded,
                  size: 13,
                  color: AppColors.gray500,
                ),
                const SizedBox(width: 2),
                Text(
                  '${type.passengerCapacity}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.gray500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.luggage_outlined,
                  size: 13,
                  color: AppColors.gray500,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    type.luggageCapacity,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.gray500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // Price estimate
            Text(
              '$currency ${fare.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
