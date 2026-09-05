// lib/features/mobility/presentation/widgets/booking_service_mode_toggle.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Ride vs. Delivery Mode Switcher
// Elegant segmented toggle between "Book a Ride" and "Send Package / Delivery"
// with emerald highlights and obsidian micro-animations.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class BookingServiceModeToggle extends StatelessWidget {
  final String activeServiceType; // 'ride' | 'delivery'
  final ValueChanged<String> onServiceTypeChanged;

  const BookingServiceModeToggle({
    super.key,
    required this.activeServiceType,
    required this.onServiceTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isRide = activeServiceType == 'ride';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // ── Option 1: Book a Ride ──────────────────────────────────
          Expanded(
            child: _buildToggleOption(
              label: 'Book a Ride',
              icon: Icons.directions_car_rounded,
              badgeText: 'Instant',
              isSelected: isRide,
              onTap: () => onServiceTypeChanged('ride'),
            ),
          ),
          const SizedBox(width: 4),

          // ── Option 2: Send Package / Delivery ──────────────────────
          Expanded(
            child: _buildToggleOption(
              label: 'Send Delivery',
              icon: Icons.inventory_2_rounded,
              badgeText: 'Courier',
              isSelected: !isRide,
              onTap: () => onServiceTypeChanged('delivery'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleOption({
    required String label,
    required IconData icon,
    required String badgeText,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.obsidian.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.emeraldDark : AppColors.gray500,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? AppColors.obsidian : AppColors.gray600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.emeraldDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
