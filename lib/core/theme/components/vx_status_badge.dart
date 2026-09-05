// lib/core/theme/components/vx_status_badge.dart
// ═══════════════════════════════════════════════════════════════════════
// Status Badge — Compact colored chip for ride/booking/payment status
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_typography.dart';

/// Semantic status types that map to specific color schemes.
enum VxBadgeStatus {
  active,     // Emerald — ride in progress, available listing
  pending,    // Amber — waiting for confirmation
  completed,  // Obsidian with emerald accent — finished successfully
  cancelled,  // Error red — cancelled or failed
  info,       // Blue — informational
  offline,    // Gray — offline queued, syncing
  verified,   // Emerald with icon — verified badge
}

/// A compact status badge with semantic coloring and optional icon.
///
/// ```dart
/// VxStatusBadge(
///   label: 'In Transit',
///   status: VxBadgeStatus.active,
/// )
///
/// VxStatusBadge(
///   label: 'Payment Failed',
///   status: VxBadgeStatus.cancelled,
///   icon: Icons.error_outline,
/// )
/// ```
class VxStatusBadge extends StatelessWidget {
  final String label;
  final VxBadgeStatus status;
  final IconData? icon;
  final VxBadgeSize size;
  final bool pulse;

  const VxStatusBadge({
    super.key,
    required this.label,
    required this.status,
    this.icon,
    this.size = VxBadgeSize.medium,
    this.pulse = false,
  });

  @override
  Widget build(BuildContext context) {
    final (bgColor, fgColor, defaultIcon) = _statusColors();
    final displayIcon = icon ?? defaultIcon;

    final (fontSize, paddingH, paddingV, iconSize) = switch (size) {
      VxBadgeSize.small => (10.0, 8.0, 3.0, 12.0),
      VxBadgeSize.medium => (11.0, 12.0, 5.0, 14.0),
      VxBadgeSize.large => (13.0, 16.0, 7.0, 16.0),
    };

    Widget badge = Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100), // Pill shape
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (displayIcon != null) ...[
            Icon(displayIcon, size: iconSize, color: fgColor),
            SizedBox(width: size == VxBadgeSize.small ? 3 : 5),
          ],
          Text(
            label.toUpperCase(),
            style: AppTypography.badge.copyWith(
              fontSize: fontSize,
              color: fgColor,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );

    // Pulse animation for active states
    if (pulse) {
      badge = _PulsingBadge(color: fgColor, child: badge);
    }

    return badge;
  }

  (Color bg, Color fg, IconData? icon) _statusColors() {
    return switch (status) {
      VxBadgeStatus.active => (
          AppColors.emeraldSurface,
          AppColors.emeraldDark,
          Icons.directions_car_rounded,
        ),
      VxBadgeStatus.pending => (
          AppColors.amberSurface,
          AppColors.amberDark,
          Icons.schedule_rounded,
        ),
      VxBadgeStatus.completed => (
          AppColors.gray100,
          AppColors.obsidianMedium,
          Icons.check_circle_outline_rounded,
        ),
      VxBadgeStatus.cancelled => (
          AppColors.errorLight,
          AppColors.errorDark,
          Icons.cancel_outlined,
        ),
      VxBadgeStatus.info => (
          AppColors.infoLight,
          AppColors.info,
          Icons.info_outline_rounded,
        ),
      VxBadgeStatus.offline => (
          AppColors.gray200,
          AppColors.gray600,
          Icons.cloud_off_rounded,
        ),
      VxBadgeStatus.verified => (
          AppColors.emeraldSurface,
          AppColors.emeraldDark,
          Icons.verified_rounded,
        ),
    };
  }
}

enum VxBadgeSize { small, medium, large }

/// Wraps a badge with a subtle pulse animation.
class _PulsingBadge extends StatefulWidget {
  final Widget child;
  final Color color;

  const _PulsingBadge({required this.child, required this.color});

  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.3 * _controller.value),
                blurRadius: 8 * _controller.value,
                spreadRadius: 1 * _controller.value,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
