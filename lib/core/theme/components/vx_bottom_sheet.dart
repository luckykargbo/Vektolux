// lib/core/theme/components/vx_bottom_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// Bottom Sheet Dialogs — Standardized modal and persistent sheets
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../app_colors.dart';
import 'vx_button.dart';

/// Show a standardized Vektolux modal bottom sheet.
///
/// Includes drag handle, optional title, content area,
/// and action buttons at the bottom.
///
/// ```dart
/// await VxBottomSheet.show(
///   context: context,
///   title: 'Confirm Ride',
///   child: RideConfirmationContent(),
///   primaryAction: VxBottomSheetAction(
///     label: 'Confirm & Pay',
///     onPressed: () => confirmRide(),
///   ),
/// );
/// ```
class VxBottomSheet {
  /// Show a modal bottom sheet with Vektolux styling.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    String? subtitle,
    VxBottomSheetAction? primaryAction,
    VxBottomSheetAction? secondaryAction,
    bool isDismissible = true,
    bool enableDrag = true,
    bool isScrollControlled = true,
    double? maxHeight,
    bool useSafeArea = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      backgroundColor: Colors.transparent,
      builder: (context) => _VxBottomSheetContent(
        title: title,
        subtitle: subtitle,
        primaryAction: primaryAction,
        secondaryAction: secondaryAction,
        maxHeight: maxHeight,
        child: child,
      ),
    );
  }

  /// Show a confirmation dialog as a bottom sheet.
  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    VxButtonVariant confirmVariant = VxButtonVariant.primary,
    IconData? confirmIcon,
  }) {
    return show<bool>(
      context: context,
      title: title,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ),
      primaryAction: VxBottomSheetAction(
        label: confirmLabel,
        icon: confirmIcon,
        variant: confirmVariant,
        onPressed: () => Navigator.of(context).pop(true),
      ),
      secondaryAction: VxBottomSheetAction(
        label: cancelLabel,
        variant: VxButtonVariant.outlined,
        onPressed: () => Navigator.of(context).pop(false),
      ),
    );
  }

  /// Show a destructive confirmation (e.g., cancel ride, delete listing).
  static Future<bool?> confirmDestructive({
    required BuildContext context,
    required String title,
    required String message,
    String confirmLabel = 'Delete',
  }) {
    return confirm(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      confirmVariant: VxButtonVariant.destructive,
      confirmIcon: Icons.delete_outline_rounded,
    );
  }
}

/// Action button configuration for bottom sheets.
class VxBottomSheetAction {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final VxButtonVariant variant;
  final bool isLoading;

  const VxBottomSheetAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = VxButtonVariant.primary,
    this.isLoading = false,
  });
}

/// Internal bottom sheet content widget.
class _VxBottomSheetContent extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final VxBottomSheetAction? primaryAction;
  final VxBottomSheetAction? secondaryAction;
  final double? maxHeight;

  const _VxBottomSheetContent({
    this.title,
    this.subtitle,
    required this.child,
    this.primaryAction,
    this.secondaryAction,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = maxHeight ??
        MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag Handle ─────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.gray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ── Title ───────────────────────────────────────────────
          if (title != null || subtitle != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                ],
              ),
            ),

          // ── Content ─────────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: child,
            ),
          ),

          // ── Actions ─────────────────────────────────────────────
          if (primaryAction != null || secondaryAction != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (primaryAction != null)
                      VxButton(
                        label: primaryAction!.label,
                        onPressed: primaryAction!.onPressed,
                        icon: primaryAction!.icon,
                        isLoading: primaryAction!.isLoading,
                        variant: primaryAction!.variant,
                      ),
                    if (secondaryAction != null) ...[
                      const SizedBox(height: 8),
                      VxButton(
                        label: secondaryAction!.label,
                        onPressed: secondaryAction!.onPressed,
                        icon: secondaryAction!.icon,
                        variant: secondaryAction!.variant,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
