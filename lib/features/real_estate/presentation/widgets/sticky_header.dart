// lib/features/real_estate/presentation/widgets/sticky_header.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Property Sticky Header & Location Map Preview
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/components/vx_status_badge.dart';
import '../../domain/entities/property_listing_entity.dart';

class PropertyStickyHeader extends StatelessWidget {
  final PropertyListingEntity listing;

  const PropertyStickyHeader({
    super.key,
    required this.listing,
    VoidCallback? onMapPreviewTap,
  });

  @override
  Widget build(BuildContext context) {
    final broadCity = listing.city.isNotEmpty ? listing.city : 'Sierra Leone';
    final broadLocation = broadCity.toLowerCase().contains('sierra leone')
        ? broadCity
        : '$broadCity, Sierra Leone';

    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Category & Verified Status Row ────────────────────────
          Row(
            children: [
              VxStatusBadge(
                label: listing.category.displayName,
                status: listing.isHourlyStay
                    ? VxBadgeStatus.active
                    : VxBadgeStatus.info,
                size: VxBadgeSize.small,
              ),
              const SizedBox(width: 8),
              if (listing.isVerified)
                const VxStatusBadge(
                  label: 'Verified Property',
                  status: VxBadgeStatus.verified,
                  size: VxBadgeSize.small,
                ),
              const Spacer(),
              // View count pill
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.visibility_outlined,
                    size: 14,
                    color: AppColors.gray400,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${listing.viewCount} views',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.gray500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Title & Price Header ──────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  listing.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                        height: 1.2,
                      ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${listing.currency} ${listing.price.toStringAsFixed(0)}',
                    style: AppTypography.priceDisplay.copyWith(
                      fontSize: 26,
                    ),
                  ),
                  Text(
                    listing.isHourlyStay ? 'per day / flat' : 'guide price',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.gray500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── General Location Privacy Card (Zero Map / Zero Coordinates) ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.location_city_rounded,
                    color: AppColors.emeraldDark,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        broadLocation,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Broad Area Only • Location Protected',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.gray500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: AppColors.emeraldDark,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Verified Area',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.obsidian,
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
    );
  }
}
