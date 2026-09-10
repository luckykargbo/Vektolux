// lib/core/widgets/vx_network_image.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Production Network Image Loader & Media Showcase
// Supports explicit aspect ratios (16:9, 4:3), smooth shimmer skeleton
// loading animations, and elegant branded fallback UI (no blank grey boxes).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class VxNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final double? aspectRatio;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;
  final String? fallbackLabel;
  final String? heroTag;

  const VxNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.aspectRatio,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallbackIcon = Icons.home_work_outlined,
    this.fallbackLabel,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final hasValidUrl = imageUrl != null &&
        imageUrl!.trim().isNotEmpty &&
        (imageUrl!.startsWith('http://') || imageUrl!.startsWith('https://'));

    Widget content;

    if (!hasValidUrl) {
      content = _buildFallbackUi();
    } else {
      content = Image.network(
        imageUrl!.trim(),
        width: width ?? double.infinity,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          final expected = loadingProgress.expectedTotalBytes;
          final loaded = loadingProgress.cumulativeBytesLoaded;
          final progress = expected != null && expected > 0
              ? (loaded / expected)
              : null;

          return _buildLoadingSkeleton(progress);
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackUi();
        },
      );
    }

    if (heroTag != null && heroTag!.isNotEmpty) {
      content = Hero(tag: heroTag!, child: content);
    }

    if (aspectRatio != null && aspectRatio! > 0) {
      content = AspectRatio(
        aspectRatio: aspectRatio!,
        child: content,
      );
    }

    if (borderRadius != null) {
      content = ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return content;
  }

  /// Ultra-light loading skeleton without ticker leaks
  Widget _buildLoadingSkeleton(double? progress) {
    return Container(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFE2E8F0),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            fallbackIcon,
            color: AppColors.gray400.withValues(alpha: 0.5),
            size: 28,
          ),
          if (progress != null)
            Positioned(
              bottom: 8,
              left: 16,
              right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.black12,
                  color: AppColors.emerald,
                  minHeight: 3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Styled branded fallback UI in place of unstyled blank grey boxes
  Widget _buildFallbackUi() {
    return Container(
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle background diagonal pattern / glow
          Positioned(
            right: -20,
            bottom: -20,
            child: Icon(
              fallbackIcon,
              size: 90,
              color: Colors.white.withValues(alpha: 0.04),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.emerald.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  fallbackIcon,
                  color: AppColors.emerald,
                  size: 24,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                fallbackLabel ?? 'VEKTOLUX VERIFIED',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}