// lib/core/widgets/vx_network_image.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Production Network Image Loader & Media Showcase
// Supports explicit aspect ratios (16:9, 4:3), smooth shimmer skeleton
// loading animations, and elegant branded fallback UI (no blank grey boxes).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class VxNetworkImage extends StatefulWidget {
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
  State<VxNetworkImage> createState() => _VxNetworkImageState();
}

class _VxNetworkImageState extends State<VxNetworkImage>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasValidUrl = widget.imageUrl != null &&
        widget.imageUrl!.trim().isNotEmpty &&
        (widget.imageUrl!.startsWith('http://') ||
            widget.imageUrl!.startsWith('https://'));

    Widget content;

    if (!hasValidUrl) {
      content = _buildFallbackUi();
    } else {
      content = Image.network(
        widget.imageUrl!.trim(),
        width: widget.width ?? double.infinity,
        height: widget.height,
        fit: widget.fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          final expected = loadingProgress.expectedTotalBytes;
          final loaded = loadingProgress.cumulativeBytesLoaded;
          final progress = expected != null && expected > 0
              ? (loaded / expected)
              : null;

          return _buildShimmerSkeleton(progress);
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackUi();
        },
      );
    }

    if (widget.heroTag != null && widget.heroTag!.isNotEmpty) {
      content = Hero(tag: widget.heroTag!, child: content);
    }

    if (widget.aspectRatio != null && widget.aspectRatio! > 0) {
      content = AspectRatio(
        aspectRatio: widget.aspectRatio!,
        child: content,
      );
    }

    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    return content;
  }

  /// Shimmer loading skeleton with an animated diagonal gradient sweep
  Widget _buildShimmerSkeleton(double? progress) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          width: widget.width ?? double.infinity,
          height: widget.height ?? double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.5 + (_shimmerController.value * 3.0), -0.5),
              end: Alignment(0.5 + (_shimmerController.value * 3.0), 1.5),
              colors: const [
                Color(0xFFE2E8F0),
                Color(0xFFF8FAFC),
                Color(0xFFE2E8F0),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                widget.fallbackIcon,
                color: AppColors.gray300.withValues(alpha: 0.6),
                size: 28,
              ),
              if (progress != null)
                Positioned(
                  bottom: 10,
                  left: 20,
                  right: 20,
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
      },
    );
  }

  /// Styled branded fallback UI in place of unstyled blank grey boxes
  Widget _buildFallbackUi() {
    return Container(
      width: widget.width ?? double.infinity,
      height: widget.height ?? double.infinity,
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
              widget.fallbackIcon,
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
                  widget.fallbackIcon,
                  color: AppColors.emerald,
                  size: 24,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.fallbackLabel ?? 'VEKTOLUX VERIFIED',
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