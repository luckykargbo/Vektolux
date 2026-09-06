// lib/features/mobility/presentation/widgets/seller_marker_preview_card.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Interactive Verified Seller & Vendor Marker Preview Card
// Opens when a user taps a verified merchant/vendor marker on the map.
// Displays store photo, verified badge, live ETA, and direct action CTAs.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/verified_badge.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/nearby_seller_entity.dart';

class SellerMarkerPreviewCard extends StatelessWidget {
  final NearbySellerEntity seller;
  final VoidCallback onClose;
  final ValueChanged<NearbySellerEntity> onOrder;
  final ValueChanged<NearbySellerEntity> onCallOrChat;
  final ValueChanged<NearbySellerEntity> onShareLocation;

  const SellerMarkerPreviewCard({
    super.key,
    required this.seller,
    required this.onClose,
    required this.onOrder,
    required this.onCallOrChat,
    required this.onShareLocation,
  });

  @override
  Widget build(BuildContext context) {
    final initials = seller.businessName
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

          // ── Seller Avatar & Credentials Row ─────────────────────────
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.emeraldSurface,
                      border: Border.all(color: AppColors.emerald, width: 2.5),
                    ),
                    child: Center(
                      child: seller.avatarUrl != null && seller.avatarUrl!.isNotEmpty
                          ? ClipOval(
                              child: Image.network(
                                seller.avatarUrl!,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Text(
                                  initials,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    color: AppColors.emeraldDark,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              initials.isNotEmpty ? initials : 'SL',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                    ),
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
                        Icons.storefront_rounded,
                        size: 13,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // Business Name & Category
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            seller.businessName,
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
                      '${seller.category} • by ${seller.ownerName}',
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
                        Text(
                          '${seller.rating.toStringAsFixed(1)} (${seller.totalSales}+ orders)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.obsidian,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.emeraldSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
                          ),
                          child: const Text(
                            'Verified Merchant',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.emeraldDark,
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
          const SizedBox(height: 14),

          // ── Proximity ETA & Address Banner ──────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 18, color: AppColors.emerald),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        seller.address,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.obsidian,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${seller.distanceKm.toStringAsFixed(1)} km away • ~${seller.etaMinutes} mins courier delivery',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.gray500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Open Now',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.emeraldDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Action Buttons ──────────────────────────────────────────
          Row(
            children: [
              // Contact / Direct Chat
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.obsidian,
                    side: const BorderSide(color: AppColors.border, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                  label: const Text(
                    'Call / Chat',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  onPressed: () => onCallOrChat(seller),
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
                  tooltip: 'Share My Location with Merchant',
                  onPressed: () => onShareLocation(seller),
                ),
              ),
              const SizedBox(width: 10),

              // Primary: Book / Order
              Expanded(
                flex: 3,
                child: VxButton.primary(
                  text: 'Book / Order',
                  icon: Icons.shopping_bag_outlined,
                  height: 48,
                  onPressed: () => onOrder(seller),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
