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

  String get _vehicleDisplayName {
    final v = driver.vehicle;
    if (v != null) {
      final categoryLabel = switch (v.category) {
        DriverVehicleCategory.kekehTricycle => 'Kekeh Tricycle',
        DriverVehicleCategory.deliveryBike => 'Okada Bike',
        DriverVehicleCategory.comfort => 'Comfort Sedan',
        DriverVehicleCategory.standard => 'Standard Taxi',
      };
      return '${v.make} ${v.model} • $categoryLabel';
    }
    return 'Bajaj RE • Kekeh Tricycle';
  }

  String get _plateNumber => driver.vehicle?.licensePlate ?? 'SL-492-KE';

  IconData get _vehicleIcon {
    final cat = driver.vehicle?.category ?? DriverVehicleCategory.kekehTricycle;
    return switch (cat) {
      DriverVehicleCategory.kekehTricycle => Icons.moped_rounded,
      DriverVehicleCategory.deliveryBike => Icons.two_wheeler_rounded,
      DriverVehicleCategory.comfort => Icons.directions_car_filled_rounded,
      DriverVehicleCategory.standard => Icons.local_taxi_rounded,
    };
  }

  Color get _categoryColor {
    final cat = driver.vehicle?.category ?? DriverVehicleCategory.kekehTricycle;
    return switch (cat) {
      DriverVehicleCategory.kekehTricycle => AppColors.amber,
      DriverVehicleCategory.deliveryBike => const Color(0xFFF97316), // Orange
      DriverVehicleCategory.comfort => const Color(0xFF6366F1), // Indigo
      DriverVehicleCategory.standard => AppColors.emerald,
    };
  }

  @override
  Widget build(BuildContext context) {
    final initials = driver.driverName
        .trim()
        .split(' ')
        .take(2)
        .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
        .join();

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
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _categoryColor.withValues(alpha: 0.15),
                      border: Border.all(color: _categoryColor, width: 2),
                    ),
                    child: Center(
                      child: driver.avatarUrl != null && driver.avatarUrl!.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                driver.avatarUrl!,
                                width: 58,
                                height: 58,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Text(
                                  initials,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    color: _categoryColor,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              initials.isNotEmpty ? initials : 'DR',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: _categoryColor,
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_vehicleIcon, size: 16, color: _categoryColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // Name & Status
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
                    Text(
                      _vehicleDisplayName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: AppColors.amber, size: 16),
                        const SizedBox(width: 3),
                        const Text(
                          '4.9 (180+ trips)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.obsidian,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.gray100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            _plateNumber,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'Courier',
                              fontWeight: FontWeight.w700,
                              color: AppColors.obsidian,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

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
