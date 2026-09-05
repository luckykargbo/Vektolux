// lib/core/theme/components/vx_button.dart
// ═══════════════════════════════════════════════════════════════════════
// Elevated Action Button with Dynamic Loading Spinner
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../app_colors.dart';

/// Vektolux primary action button with built-in loading state.
///
/// ```dart
/// VxButton(
///   label: 'Confirm Booking',
///   onPressed: () => handleBooking(),
///   isLoading: state.isSubmitting,
///   icon: Icons.check_circle_outline,
/// )
/// ```
class VxButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final VxButtonVariant variant;
  final double? width;
  final double height;

  const VxButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.variant = VxButtonVariant.primary,
    this.width,
    this.height = 56,
  });

  /// Primary convenience constructor.
  const VxButton.primary({
    super.key,
    required String text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 56,
  })  : label = text,
        variant = VxButtonVariant.primary;

  /// Destructive variant (red).
  const VxButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 56,
  }) : variant = VxButtonVariant.destructive;

  /// Outlined / secondary variant.
  const VxButton.outlined({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width,
    this.height = 56,
  }) : variant = VxButtonVariant.outlined;

  /// Small compact variant.
  const VxButton.small({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.variant = VxButtonVariant.primary,
    this.width,
  }) : height = 40;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null || isLoading;

    final (bgColor, fgColor, borderSide) = switch (variant) {
      VxButtonVariant.primary => (
          AppColors.emerald,
          AppColors.white,
          BorderSide.none,
        ),
      VxButtonVariant.secondary => (
          AppColors.obsidian,
          AppColors.white,
          BorderSide.none,
        ),
      VxButtonVariant.outlined => (
          Colors.transparent,
          AppColors.obsidian,
          const BorderSide(color: AppColors.border, width: 1.5),
        ),
      VxButtonVariant.destructive => (
          AppColors.error,
          AppColors.white,
          BorderSide.none,
        ),
      VxButtonVariant.ghost => (
          Colors.transparent,
          AppColors.emerald,
          BorderSide.none,
        ),
    };

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton(
          onPressed: isDisabled ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: bgColor,
            foregroundColor: fgColor,
            disabledBackgroundColor: bgColor.withValues(alpha: 0.5),
            disabledForegroundColor: fgColor.withValues(alpha: 0.5),
            elevation: variant == VxButtonVariant.primary ? 2 : 0,
            shadowColor: AppColors.emerald.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: borderSide,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: (width != null && width! < 130) ? 8 : (height < 48 ? 14 : 24),
              vertical: 0,
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: isLoading
                ? SizedBox(
                    key: const ValueKey('loading'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(fgColor),
                    ),
                  )
                : FittedBox(
                    key: const ValueKey('content'),
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: height < 48 ? 16 : 20),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

enum VxButtonVariant {
  primary,
  secondary,
  outlined,
  destructive,
  ghost,
}
