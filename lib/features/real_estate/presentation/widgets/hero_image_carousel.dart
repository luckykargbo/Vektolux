// lib/features/real_estate/presentation/widgets/hero_image_carousel.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Hero Property Image Carousel
// Full-width hero gallery with page indicators, photo index pill, & tap-to-expand.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class HeroImageCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final String heroTag;
  final double height;
  final VoidCallback? onFavoriteTap;
  final bool isFavorite;

  const HeroImageCarousel({
    super.key,
    required this.imageUrls,
    required this.heroTag,
    this.height = 360,
    this.onFavoriteTap,
    this.isFavorite = false,
  });

  @override
  State<HeroImageCarousel> createState() => _HeroImageCarouselState();
}

class _HeroImageCarouselState extends State<HeroImageCarousel> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // Fallback high-res real estate architectural photos if listing images are empty
  static const List<String> _fallbackPhotos = [
    'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?auto=format&fit=crop&w=1200&q=80',
    'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=1200&q=80',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.imageUrls.isNotEmpty ? widget.imageUrls : _fallbackPhotos;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. PageView Image Carousel ────────────────────────────
          PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return Hero(
                tag: '${widget.heroTag}_image_$index',
                child: Image.network(
                  images[index],
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.obsidianLight,
                      child: const Center(
                        child: Icon(
                          Icons.apartment_rounded,
                          size: 64,
                          color: AppColors.gray400,
                        ),
                      ),
                    );
                  },
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: AppColors.gray100,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.emerald,
                          strokeWidth: 2.5,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),

          // ── 2. Atmospheric Ambient Gradients ──────────────────────
          // Top gradient for status bar and back button legibility
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 100,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.obsidian.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Bottom gradient for clean indicator contrast
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 80,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.obsidian.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── 3. Photo Counter Pill (Bottom Right) ──────────────────
          Positioned(
            bottom: 16,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.obsidian.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    color: AppColors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_currentIndex + 1} / ${images.length}',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 4. Clean Page Indicators (Bottom Center) ──────────────
          if (images.length > 1)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (index) {
                  final isActive = index == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 5,
                    width: isActive ? 24 : 6,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.emerald
                          : AppColors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
