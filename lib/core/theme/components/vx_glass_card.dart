// lib/core/theme/components/vx_glass_card.dart
// ═══════════════════════════════════════════════════════════════════════
// Glassmorphism Card — Frosted glass effect with subtle border
// ═══════════════════════════════════════════════════════════════════════

import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_colors.dart';

/// A card with frosted glass (glassmorphism) visual effect.
///
/// Uses `BackdropFilter` with a blur for the translucent effect.
/// Best used over images, maps, or gradient backgrounds.
///
/// ```dart
/// VxGlassCard(
///   child: Column(
///     children: [
///       Text('Ride Fare', style: Theme.of(context).textTheme.titleMedium),
///       Text('Le 12,500', style: AppTypography.priceDisplay),
///     ],
///   ),
/// )
/// ```
class VxGlassCard extends StatelessWidget {
  final Widget child;
  final double blurSigma;
  final Color? backgroundColor;
  final double opacity;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const VxGlassCard({
    super.key,
    required this.child,
    this.blurSigma = 12.0,
    this.backgroundColor,
    this.opacity = 0.75,
    this.borderRadius = 20.0,
    this.padding = const EdgeInsets.all(20),
    this.width,
    this.height,
    this.onTap,
  });

  /// Dark variant for use on light backgrounds.
  const VxGlassCard.dark({
    super.key,
    required this.child,
    this.blurSigma = 16.0,
    this.borderRadius = 20.0,
    this.padding = const EdgeInsets.all(20),
    this.width,
    this.height,
    this.onTap,
  })  : backgroundColor = AppColors.obsidian,
        opacity = 0.65;

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? AppColors.white;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: Container(
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.obsidian.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
