// lib/core/theme/components/verified_badge.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Verified Trust Badge Component
// Renders an Electric Emerald shield with tick and interactive tooltip.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../app_colors.dart';

enum VerifiedBadgeSize { small, medium, large }

class VerifiedBadge extends StatelessWidget {
  final VerifiedBadgeSize size;
  final bool showLabel;
  final String? customTooltip;
  final VoidCallback? onTap;

  const VerifiedBadge({
    super.key,
    this.size = VerifiedBadgeSize.small,
    this.showLabel = false,
    this.customTooltip,
    this.onTap,
  });

  double get _iconSize => switch (size) {
        VerifiedBadgeSize.small => 15.0,
        VerifiedBadgeSize.medium => 18.0,
        VerifiedBadgeSize.large => 24.0,
      };

  double get _fontSize => switch (size) {
        VerifiedBadgeSize.small => 11.0,
        VerifiedBadgeSize.medium => 12.5,
        VerifiedBadgeSize.large => 14.0,
      };

  @override
  Widget build(BuildContext context) {
    final tooltipMessage = customTooltip ??
        'Vektolux Verified Seller\n'
        '• Sierra Leone National ID / Passport Validated\n'
        '• 3D Biometric Liveness Confirmed (Zero Fraud Record)';

    final badgeIcon = Container(
      padding: EdgeInsets.all(size == VerifiedBadgeSize.large ? 4 : 2),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.emerald.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: Icon(
        Icons.verified_rounded,
        color: AppColors.emerald,
        size: _iconSize,
      ),
    );

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        badgeIcon,
        if (showLabel) ...[
          const SizedBox(width: 5),
          Text(
            'Verified',
            style: TextStyle(
              color: AppColors.emerald,
              fontWeight: FontWeight.w700,
              fontSize: _fontSize,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: content,
      );
    }

    return Tooltip(
      message: tooltipMessage,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
      child: content,
    );
  }
}
