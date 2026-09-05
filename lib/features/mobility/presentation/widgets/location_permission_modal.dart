// lib/features/mobility/presentation/widgets/location_permission_modal.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Non-Intrusive Location Permission Prompt Modal
// Matches obsidian slate & emerald design, explaining real-time pickup matching.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';

class LocationPermissionModal extends StatelessWidget {
  final VoidCallback onEnableLocation;
  final VoidCallback onManualInput;

  const LocationPermissionModal({
    super.key,
    required this.onEnableLocation,
    required this.onManualInput,
  });

  /// Static helper to display the modal bottom sheet smoothly.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onEnableLocation,
    required VoidCallback onManualInput,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => LocationPermissionModal(
        onEnableLocation: () {
          Navigator.of(ctx).pop();
          onEnableLocation();
        },
        onManualInput: () {
          Navigator.of(ctx).pop();
          onManualInput();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.gray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Glowing Location Badge
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.emeraldSurface,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.emerald.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.emerald.withValues(alpha: 0.2),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.location_on_rounded,
                color: AppColors.emerald,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Title
          const Text(
            'Enable Location Services',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
              letterSpacing: -0.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // Required Exact Prompt Text
          const Text(
            'Enable device location for real-time pickup and driver matching.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Primary CTA: Enable Location
          VxButton(
            label: 'Enable Device Location',
            icon: Icons.gps_fixed_rounded,
            variant: VxButtonVariant.primary,
            onPressed: onEnableLocation,
          ),
          const SizedBox(height: 12),

          // Secondary CTA: Enter Address Manually
          VxButton(
            label: 'Enter Address Manually',
            icon: Icons.search_rounded,
            variant: VxButtonVariant.outlined,
            onPressed: onManualInput,
          ),
          const SizedBox(height: 8),

          // Dismiss
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Not now',
              style: TextStyle(
                color: AppColors.gray500,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
