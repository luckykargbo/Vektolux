// lib/features/navigation/presentation/widgets/client_onboarding_tour_modal.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — First-Time Client Guided Onboarding Walkthrough
// 4-Step visual interactive tour explaining core app verticals:
// 1. Showrooms (Real Estate & Auto)
// 2. Ride-Hailing & Fast Parcel Delivery
// 3. Orange & Africell Mobile Money with Agent Code 001
// 4. Account Profile, Wallet & Vendor Upgrades
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ClientOnboardingTourModal extends StatefulWidget {
  final VoidCallback onFinish;

  const ClientOnboardingTourModal({
    super.key,
    required this.onFinish,
  });

  /// Displays the modal sheet and ensures it's dismissed cleanly
  static Future<void> show(BuildContext context, {required VoidCallback onFinish}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => ClientOnboardingTourModal(onFinish: onFinish),
    );
  }

  @override
  State<ClientOnboardingTourModal> createState() => _ClientOnboardingTourModalState();
}

class _ClientOnboardingTourModalState extends State<ClientOnboardingTourModal> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _steps = [
    {
      'step': '1 of 4',
      'title': 'Discover Properties & Motors',
      'highlight': 'Verified Marketplace',
      'description':
          'Explore modern beach villas, family homes, commercial land, and inspected vehicles for sale or rent with verified Sierra Leone ownership deeds.',
      'icon': Icons.apartment_rounded,
      'accentColor': AppColors.emerald,
      'badge': 'REAL ESTATE & AUTO',
    },
    {
      'step': '2 of 4',
      'title': 'Instant Rides & Deliveries',
      'highlight': 'Live GPS Tracking',
      'description':
          'Hail nearby Keke tricycles, Okada motorbikes, and standard taxis, or dispatch parcels door-to-door with real-time route navigation and arrival alerts.',
      'icon': Icons.local_taxi_rounded,
      'accentColor': const Color(0xFFF59E0B),
      'badge': 'KEKE • OKADA • TAXI',
    },
    {
      'step': '3 of 4',
      'title': 'Orange Money & Africell Payments',
      'highlight': 'Official Agent Code 001',
      'description':
          'Pay seamlessly through the app using Orange Money or Africell. For direct cashier or merchant payment, use Agent Code 001 with protected Escrow vault.',
      'icon': Icons.account_balance_wallet_rounded,
      'accentColor': const Color(0xFF0284C7),
      'badge': 'ESCROW SECURED',
    },
    {
      'step': '4 of 4',
      'title': 'Your Profile & Seller Mode',
      'highlight': 'Earn as a Partner',
      'description':
          'Check ride receipts, manage security PINs, and upgrade your account to an Agent, Car Dealer, or Driver anytime by submitting your National ID or Passport.',
      'icon': Icons.verified_user_rounded,
      'accentColor': const Color(0xFF8B5CF6),
      'badge': 'VERIFIED ACCOUNTS',
    },
  ];

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    } else {
      Navigator.of(context).pop();
      widget.onFinish();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Handle Indicator
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Header Bar with Step Tag and Skip Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'GUIDED TOUR • ${_steps[_currentPage]['step']}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.emeraldDark,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onFinish();
                  },
                  child: const Text(
                    'Skip Tour',
                    style: TextStyle(
                      color: AppColors.gray500,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Carousel Content
            SizedBox(
              height: 290,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemCount: _steps.length,
                itemBuilder: (context, idx) {
                  final step = _steps[idx];
                  final Color accentColor = step['accentColor'] as Color;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Illustrated Circle Icon
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.35),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.15),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            step['icon'] as IconData,
                            size: 42,
                            color: accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Category Pill Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          step['badge'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Title
                      Text(
                        step['title'] as String,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.obsidian,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Description
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          step['description'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: AppColors.gray600,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Pagination Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_steps.length, (idx) {
                final isSelected = idx == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isSelected ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.emerald : AppColors.gray300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 24),

            // Action Buttons (Back & Next / Get Started)
            Row(
              children: [
                if (_currentPage > 0) ...[
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _prevPage,
                      child: const Text(
                        'Back',
                        style: TextStyle(
                          color: AppColors.obsidian,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _nextPage,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentPage == _steps.length - 1
                              ? 'Get Started'
                              : 'Next',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          _currentPage == _steps.length - 1
                              ? Icons.check_circle_rounded
                              : Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
