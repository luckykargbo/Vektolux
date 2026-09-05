// lib/features/mobility/presentation/widgets/driver_online_toggle_bar.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Online/Offline Floating Status Bar
// Top floating header with Online/Offline toggle, live GPS beacon,
// and daily earnings / completed trips overview.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class DriverOnlineToggleBar extends StatelessWidget {
  final bool isOnline;
  final double todaysEarnings;
  final int completedTripsCount;
  final double rating;
  final ValueChanged<bool> onToggleOnline;
  final VoidCallback onBackToPassengerMode;

  const DriverOnlineToggleBar({
    super.key,
    required this.isOnline,
    required this.todaysEarnings,
    required this.completedTripsCount,
    required this.rating,
    required this.onToggleOnline,
    required this.onBackToPassengerMode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Main Header Row ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.obsidian,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.obsidian.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Back / Exit Driver Mode
              InkWell(
                onTap: onBackToPassengerMode,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: AppColors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Status indicator & label
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isOnline ? AppColors.emerald : AppColors.gray400,
                            shape: BoxShape.circle,
                            boxShadow: isOnline
                                ? [
                                    BoxShadow(
                                      color: AppColors.emerald.withValues(alpha: 0.6),
                                      blurRadius: 6,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isOnline ? 'ONLINE & READY' : 'OFFLINE',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: isOnline ? AppColors.emerald : AppColors.gray400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOnline
                          ? 'Streaming live GPS • Radar Active'
                          : 'Go online to accept ride & delivery requests',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.white.withValues(alpha: 0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Online / Offline Switch Toggle
              GestureDetector(
                onTap: () => onToggleOnline(!isOnline),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isOnline ? AppColors.emerald : AppColors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isOnline ? AppColors.emerald : AppColors.white.withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOnline ? Icons.power_settings_new_rounded : Icons.play_arrow_rounded,
                        color: isOnline ? AppColors.obsidian : AppColors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOnline ? 'OFFLINE' : 'GO ONLINE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: isOnline ? AppColors.obsidian : AppColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Today's Metrics Chip Bar ─────────────────────────────────
        if (isOnline) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.obsidian.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Earnings
                Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppColors.emeraldDark),
                    const SizedBox(width: 6),
                    Text(
                      'SLE ${todaysEarnings.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'today',
                      style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                Container(width: 1, height: 16, color: AppColors.gray200),
                // Completed Trips
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.obsidian),
                    const SizedBox(width: 6),
                    Text(
                      '$completedTripsCount trips',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                  ],
                ),
                Container(width: 1, height: 16, color: AppColors.gray200),
                // Driver Rating
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 17, color: AppColors.amber),
                    const SizedBox(width: 4),
                    Text(
                      rating.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
