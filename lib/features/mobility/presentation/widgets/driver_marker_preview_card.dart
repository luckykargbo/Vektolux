// lib/features/mobility/presentation/widgets/driver_marker_preview_card.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Interactive Driver & Vehicle Marker Preview Card
// Opens when a user taps a tricycle/keke, bike, or taxi marker on the map.
// Displays driver photo, vehicle specs, live ETA, and direct action CTAs.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/verified_badge.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/nearby_driver_entity.dart';

import '../../../../core/widgets/vektolux_avatar.dart';
import '../../domain/entities/vehicle_tier_catalog.dart';
import 'isometric_vehicle_3d_render.dart';

class DriverMarkerPreviewCard extends StatelessWidget {
  final NearbyDriverEntity driver;
  final VoidCallback onClose;
  final ValueChanged<NearbyDriverEntity> onBook;
  final ValueChanged<NearbyDriverEntity> onCall;
  final ValueChanged<NearbyDriverEntity> onShareLocation;

  const DriverMarkerPreviewCard({
    super.key,
    required this.driver,
    required this.onClose,
    required this.onBook,
    required this.onCall,
    required this.onShareLocation,
  });

  String get _categoryLabel {
    final v = driver.vehicle;
    if (v != null) {
      return switch (v.category) {
        DriverVehicleCategory.kekehTricycle => 'Kekeh Tricycle',
        DriverVehicleCategory.deliveryBike => 'Okada Bike',
        DriverVehicleCategory.comfort => 'Comfort Sedan',
        DriverVehicleCategory.standard => 'Standard Taxi',
        DriverVehicleCategory.deliveryVan => 'Cargo Van',
      };
    }
    return 'Kekeh Tricycle';
  }

  String get _formattedVehicleBadge {
    final v = driver.vehicle;
    final color = (v != null && v.color.trim().isNotEmpty) ? v.color : 'Yellow';
    final make = (v != null && v.make.trim().isNotEmpty) ? v.make : 'Bajaj';
    final model = (v != null && v.model.trim().isNotEmpty) ? v.model : 'RE 4S';
    final plate = (v != null && v.licensePlate.trim().isNotEmpty) ? v.licensePlate : _plateNumber;
    return '$color $make $model • $plate';
  }

  String get _plateNumber => driver.vehicle?.licensePlate ?? 'SL-492-KE';

  VehicleTierId get _tierId {
    final cat = driver.vehicle?.category;
    if (cat != null) {
      return switch (cat) {
        DriverVehicleCategory.kekehTricycle => VehicleTierId.kekeBajaj,
        DriverVehicleCategory.deliveryBike => VehicleTierId.okadaBike,
        DriverVehicleCategory.deliveryVan => VehicleTierId.deliveryVan,
        _ => VehicleTierId.carStandard,
      };
    }
    return VehicleTierId.fromString(driver.serviceType);
  }

  Color get _categoryColor {
    final cat = driver.vehicle?.category ?? DriverVehicleCategory.kekehTricycle;
    return switch (cat) {
      DriverVehicleCategory.kekehTricycle => AppColors.amber,
      DriverVehicleCategory.deliveryBike => const Color(0xFFF97316), // Orange
      DriverVehicleCategory.comfort => const Color(0xFF6366F1), // Indigo
      DriverVehicleCategory.standard => AppColors.emerald,
      DriverVehicleCategory.deliveryVan => const Color(0xFF3B82F6), // Blue
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: AppColors.obsidian.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Drag Handle & Close ─────────────────────────────────────
          Row(
            children: [
              const Spacer(),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.gray500),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onClose,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Driver Avatar & Credentials Row ─────────────────────────
          Row(
            children: [
              Stack(
                children: [
                  VektoluxAvatar(
                    avatarUrl: driver.avatarUrl,
                    name: driver.driverName,
                    radius: 26,
                    borderColor: _categoryColor,
                    borderWidth: 2,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
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
              const SizedBox(width: 14),

              // Name & Verified Operator Status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            driver.driverName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.obsidian,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const VerifiedBadge(size: VerifiedBadgeSize.small, showLabel: false),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: AppColors.amber, size: 16),
                        const SizedBox(width: 3),
                        const Text(
                          '4.9 (180+ trips)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.obsidian,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• $_categoryLabel',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _categoryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 3D Isometric Vehicle Identity & Formatted Badge Card ────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                // 3D Isometric Vector Render
                IsometricVehicle3DRender(
                  tierId: _tierId,
                  width: 68,
                  height: 48,
                  customAccentColor: _categoryColor,
                ),
                const SizedBox(width: 12),

                // Formatted Specs Badge: {Color} {Make} {Model} • {Plate}
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: AppColors.obsidian,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _formattedVehicleBadge,
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
                      const SizedBox(height: 4),
                      const Text(
                        'Verified Commercial Transport • Clean 3D Twin',
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
          const SizedBox(height: 12),

          // ── Proximity ETA & Live Distance Banner ─────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.emeraldSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18, color: AppColors.emeraldDark),
                const SizedBox(width: 8),
                Text(
                  '${driver.etaMinutes} mins away',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.emeraldDark,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('•', style: TextStyle(color: AppColors.emeraldDark)),
                const SizedBox(width: 6),
                Text(
                  '${driver.distanceKm.toStringAsFixed(1)} km from Current Location',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.emeraldDark,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.emeraldDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Action Buttons ──────────────────────────────────────────
          Row(
            children: [
              // Contact / Call Driver
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.obsidian,
                    side: const BorderSide(color: AppColors.border, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.phone_outlined, size: 18),
                  label: const Text(
                    'Call Driver',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  onPressed: () => onCall(driver),
                ),
              ),
              const SizedBox(width: 10),

              // Share Location
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.share_location_rounded, color: AppColors.emerald, size: 20),
                  tooltip: 'Share My Location with Driver',
                  onPressed: () => onShareLocation(driver),
                ),
              ),
              const SizedBox(width: 10),

              // Primary: Book Ride / Keke
              Expanded(
                flex: 3,
                child: VxButton.primary(
                  text: 'Book Ride / Keke',
                  icon: Icons.flash_on_rounded,
                  height: 48,
                  onPressed: () => onBook(driver),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
