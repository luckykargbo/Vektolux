// lib/features/mobility/presentation/widgets/vehicle_sales_catalog.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vehicle Sales Catalog & Escrow Marketplace (Mode 3)
// Showroom UI with photo showcase, verified badges, direct dealer chat,
// complimentary inspection booking, and cryptographic escrow milestones.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../../core/theme/components/vx_status_badge.dart';
import '../../../../core/widgets/branded_media_fallback.dart';
import '../../domain/entities/mobility_vehicle_entity.dart';
import 'escrow_milestone_modal.dart';
import 'in_app_chat_modal.dart';
import '../../../listings/presentation/views/vehicle_detail_screen.dart';

class VehicleSalesCatalog extends StatelessWidget {
  final List<VehicleListingEntity> salesVehicles;
  final ValueChanged<VehicleListingEntity> onScheduleInspection;

  const VehicleSalesCatalog({
    super.key,
    required this.salesVehicles,
    required this.onScheduleInspection,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Guarantee Header with Escrow Details Trigger ──────────
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => EscrowMilestoneModal.show(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.emeraldSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.emeraldDark, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Escrow-Protected Vehicle Sales',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                        Text(
                          'Funds locked in EscrowManager.sol until inspection & deed handoff.',
                          style: TextStyle(fontSize: 10, color: AppColors.obsidianSoft),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: AppColors.emeraldDark),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Catalog Header ────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Cars & Trucks For Sale',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
              ),
              Text(
                '${salesVehicles.length} verified listings',
                style: const TextStyle(fontSize: 12, color: AppColors.gray500),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Vehicle Cards ─────────────────────────────────────────
          ...salesVehicles.map((vehicle) {
            final salePrice = vehicle.salePrice ?? 120000.0;
            final images = vehicle.imageUrls;

            return InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VehicleDetailScreen.fromEntity(vehicle),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(18),
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.obsidian.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Photo Showcase / Thumbnail (Always 160px with branded fallback)
                  Container(
                    height: 160,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E293B),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: images.isNotEmpty && images.first.isNotEmpty
                        ? Image.network(
                            images.first,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildFallbackThumbnail(vehicle),
                          )
                        : _buildFallbackThumbnail(vehicle),
                  ),

                  // Top info strip
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Vehicle Details Column — Explicitly wrapped in Expanded
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      vehicle.fullTitle,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.obsidian,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const VxStatusBadge(
                                    label: 'Deed Verified',
                                    status: VxBadgeStatus.verified,
                                    size: VxBadgeSize.small,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${vehicle.color ?? "Standard"} • ${vehicle.ownerName ?? "Verified Dealer"}',
                                style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${vehicle.currency} ${salePrice.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.emeraldDark,
                                    ),
                                  ),
                                  // Chat with Dealer action button
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.chat_outlined, size: 14),
                                    label: const Text('Chat Dealer', style: TextStyle(fontSize: 11)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.obsidian,
                                      side: const BorderSide(color: AppColors.border),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () {
                                      InAppChatModal.show(
                                        context,
                                        recipientName: vehicle.ownerName ?? 'Sierra Star Auto',
                                        recipientRole: 'Verified Dealer',
                                        vehicleTitle: vehicle.fullTitle,
                                        vehiclePrice: '${vehicle.currency} ${salePrice.toStringAsFixed(0)}',
                                        recipientPhone: vehicle.ownerPhone,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // ── Inspection Action Row — Fixed 34px RenderFlex overflow ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_outlined,
                          size: 16,
                          color: AppColors.emerald,
                        ),
                        const SizedBox(width: 6),
                        // Wrap label in Expanded so it flexes and never clips/overflows
                        const Expanded(
                          child: Text(
                            'Complimentary Inspection',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.gray600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Wrap button in Flexible + FittedBox to prevent horizontal overflow
                        Flexible(
                          child: SizedBox(
                            height: 38,
                            child: VxButton.small(
                              label: 'Book Inspection',
                              icon: Icons.calendar_today_rounded,
                              onPressed: () => onScheduleInspection(vehicle),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ));
          }),
        ],
      ),
    );
  }

  Widget _buildFallbackThumbnail(VehicleListingEntity vehicle) {
    return brandedMediaFallback(
      icon: vehicle.vehicleType.iconData,
      banner: '${vehicle.year} ${vehicle.make}',
      height: 160,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
    );
  }
}
