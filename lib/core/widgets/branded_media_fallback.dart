// lib/core/widgets/branded_media_fallback.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Unified Dark Branded Media Fallback
// Provides a consistent high-fidelity placeholder for missing or broken media
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Renders a unified dark branded media fallback banner
/// preventing layout collapses or blank grey screens on empty/failed images.
class BrandedMediaFallback extends StatelessWidget {
  final IconData icon;
  final String banner;
  final double height;
  final double? width;
  final BorderRadius? borderRadius;

  const BrandedMediaFallback({
    super.key,
    required this.icon,
    required this.banner,
    this.height = 160.0,
    this.width,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Obsidian Slate
        borderRadius: borderRadius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle background watermarked branding
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              icon,
              size: 110,
              color: Colors.white.withValues(alpha: 0.03),
            ),
          ),

          // Central Icon and Banner
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.emerald.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: AppColors.emerald,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.emerald.withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  banner.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.emerald,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Helper function returning [BrandedMediaFallback] directly.
Widget brandedMediaFallback({
  required IconData icon,
  required String banner,
  double height = 160.0,
  double? width,
  BorderRadius? borderRadius,
}) {
  return BrandedMediaFallback(
    icon: icon,
    banner: banner,
    height: height,
    width: width,
    borderRadius: borderRadius,
  );
}
