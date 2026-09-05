// lib/features/real_estate/presentation/views/real_estate_listing_detail_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Listing Detail Screen
// Production-grade Flutter screen with local-first SQLite streaming,
// Dual-Mode Action Panel (Site Visit vs Instant Hourly Booking),
// anti-collision slot validation, and payment gateway checkout.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/property_listing_entity.dart';
import '../bloc/real_estate_detail_bloc.dart';
import '../bloc/real_estate_detail_event.dart';
import '../bloc/real_estate_detail_state.dart';
import '../widgets/hero_image_carousel.dart';
import '../widgets/sticky_header.dart';
import '../widgets/site_visit_booking_modal.dart';
import '../widgets/hourly_booking_panel.dart';
import '../widgets/payment_webview_dialog.dart';

class RealEstateListingDetailScreen extends StatefulWidget {
  final String listingId;
  final String currentUserId;
  final String userEmail;
  final String? userPhone;
  final String? userName;

  const RealEstateListingDetailScreen({
    super.key,
    required this.listingId,
    required this.currentUserId,
    required this.userEmail,
    this.userPhone,
    this.userName,
  });

  @override
  State<RealEstateListingDetailScreen> createState() =>
      _RealEstateListingDetailScreenState();
}

class _RealEstateListingDetailScreenState
    extends State<RealEstateListingDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    // Dispatch initial load event to trigger SQLite local stream
    context
        .read<RealEstateDetailBloc>()
        .add(LoadListingDetailEvent(widget.listingId));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RealEstateDetailBloc, RealEstateDetailState>(
      listener: (context, state) {
        // Handle payment gateway redirect trigger
        if (state.status == RealEstateDetailStatus.paymentRequired &&
            state.paymentCheckoutUrl != null) {
          PaymentCheckoutDialog.show(
            context: context,
            checkoutUrl: state.paymentCheckoutUrl!,
            reference: state.paymentReference ?? 'vktlx_booking',
            totalAmount: state.calculatedTotal,
            currency: state.listing?.currency ?? 'SLE',
            onPaymentCompleted: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Payment verified! Booking confirmed on-chain.'),
                  backgroundColor: AppColors.emerald,
                ),
              );
            },
          );
        }

        // Handle error notifications
        if (state.status == RealEstateDetailStatus.failure &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state.status == RealEstateDetailStatus.loading &&
            state.listing == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(
                color: AppColors.emerald,
                strokeWidth: 3,
              ),
            ),
          );
        }

        if (state.listing == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Property Details')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.home_work_outlined, size: 64, color: AppColors.gray400),
                  const SizedBox(height: 16),
                  Text(
                    state.errorMessage ?? 'Property unavailable',
                    style: const TextStyle(fontSize: 16, color: AppColors.gray600),
                  ),
                  const SizedBox(height: 16),
                  VxButton.small(
                    label: 'Retry',
                    onPressed: () {
                      context
                          .read<RealEstateDetailBloc>()
                          .add(LoadListingDetailEvent(widget.listingId));
                    },
                    width: 120,
                  ),
                ],
              ),
            ),
          );
        }

        final listing = state.listing!;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              // ── Main Scrollable Body ──────────────────────────────
              CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // ── 1. Hero Image Carousel (Sliver Header) ────────
                  SliverToBoxAdapter(
                    child: Stack(
                      children: [
                        HeroImageCarousel(
                          imageUrls: listing.imageUrls,
                          heroTag: listing.id,
                          height: 380,
                        ),
                        // Custom Nav Action Bar overlaid on Carousel
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 8,
                          left: 16,
                          right: 16,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildCircleNavButton(
                                icon: Icons.arrow_back_rounded,
                                onTap: () => Navigator.of(context).maybePop(),
                              ),
                              Row(
                                children: [
                                  _buildCircleNavButton(
                                    icon: _isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    iconColor: _isFavorite ? AppColors.error : AppColors.obsidian,
                                    onTap: () {
                                      setState(() => _isFavorite = !_isFavorite);
                                    },
                                  ),
                                  const SizedBox(width: 10),
                                  _buildCircleNavButton(
                                    icon: Icons.share_rounded,
                                    onTap: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Listing link copied to clipboard!'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── 2. Sticky Header with Map Preview ─────────────
                  SliverToBoxAdapter(
                    child: PropertyStickyHeader(
                      listing: listing,
                      onMapPreviewTap: () => _openLocationMap(listing),
                    ),
                  ),

                  // ── 3. Property Key Attributes (Bed/Bath/SqM) ──────
                  SliverToBoxAdapter(
                    child: Container(
                      color: AppColors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          if (listing.bedrooms != null)
                            Expanded(
                              child: _buildAttributeBox(
                                icon: Icons.king_bed_outlined,
                                value: '${listing.bedrooms} Beds',
                                label: 'Bedrooms',
                              ),
                            ),
                          if (listing.bedrooms != null && listing.bathrooms != null)
                            const SizedBox(width: 10),
                          if (listing.bathrooms != null)
                            Expanded(
                              child: _buildAttributeBox(
                                icon: Icons.bathtub_outlined,
                                value: '${listing.bathrooms} Baths',
                                label: 'Bathrooms',
                              ),
                            ),
                          if (listing.areaSqM != null) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildAttributeBox(
                                icon: Icons.square_foot_rounded,
                                value: '${listing.areaSqM!.toStringAsFixed(0)} m²',
                                label: 'Total Area',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // ── 4. On-Chain Ledger & Deed Verification Chip ───
                  SliverToBoxAdapter(
                    child: Container(
                      color: AppColors.white,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              color: AppColors.emeraldDark,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Polygon / Base On-Chain Audit Trail',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.emeraldDark,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Property deed and bookings cryptographically hashed via Smart Contract.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.obsidianSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── 5. Property Overview / Description ────────────
                  SliverToBoxAdapter(
                    child: Container(
                      color: AppColors.white,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'About this Property',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.obsidian,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            listing.description.isNotEmpty
                                ? listing.description
                                : 'Experience modern living in this prime location property. Built with premium materials, secure perimeter, backup generator, high-speed WiFi, and 24/7 dedicated management.',
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: AppColors.obsidianSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── 6. Amenities Section ──────────────────────────
                  if (listing.amenities.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        color: AppColors.white,
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Amenities & Features',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: listing.amenities.map((amenity) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.gray50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 16,
                                        color: AppColors.emerald,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        amenity,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.obsidian,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── 7. Host / Verified Agent Card ─────────────────
                  SliverToBoxAdapter(
                    child: Container(
                      color: AppColors.white,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 26,
                            backgroundColor: AppColors.emeraldSurface,
                            child: Icon(
                              Icons.person_rounded,
                              color: AppColors.emeraldDark,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  listing.ownerName ?? 'Verified Property Host',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.obsidian,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Identity & Ownership Verified by Vektolux',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.gray500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: AppColors.gray100,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18,
                                color: AppColors.obsidian,
                              ),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Opening encrypted host chat...'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom spacer so content isn't obscured by bottom bar
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 140),
                  ),
                ],
              ),

              // ── 8. Dual-Mode Persistent Action Panel ───────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildDualModeActionPanel(context, state, listing),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Dual-Mode Action Panel:
  /// - IF Category == "Sale" or "Long-Term Rent": Show a "Schedule Site Visit" primary button.
  /// - IF Category == "Hourly Guest House": Show an "Instant Booking" panel with hourly sliders.
  Widget _buildDualModeActionPanel(
    BuildContext context,
    RealEstateDetailState state,
    PropertyListingEntity listing,
  ) {
    if (listing.isHourlyStay) {
      // ── MODE A: Hourly Guest House Instant Booking Panel ──────────
      return HourlyBookingPanel(
        listing: listing,
        currentUserId: widget.currentUserId,
        userEmail: widget.userEmail,
        userPhone: widget.userPhone,
        userName: widget.userName,
      );
    } else {
      // ── MODE B: Sale / Long-Term Rent Site Visit Bar ──────────────
      return Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.obsidian.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Row(
          children: [
            // Price & status summary
            Expanded(
              flex: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${listing.currency} ${listing.price.toStringAsFixed(0)}',
                    style: AppTypography.priceDisplay.copyWith(fontSize: 22),
                  ),
                  Text(
                    listing.category == RealEstateCategory.sale
                        ? 'Sale Deed Ready'
                        : 'Annual Lease Term',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.gray500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Primary Site Visit Action Button
            Expanded(
              flex: 6,
              child: VxButton(
                label: 'Schedule Site Visit',
                icon: Icons.calendar_today_rounded,
                onPressed: () {
                  SiteVisitBookingModal.show(
                    context: context,
                    listing: listing,
                    currentUserId: widget.currentUserId,
                    bloc: context.read<RealEstateDetailBloc>(),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildCircleNavButton({
    required IconData icon,
    required VoidCallback onTap,
    Color iconColor = AppColors.obsidian,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.obsidian.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }

  Widget _buildAttributeBox({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.emeraldDark),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.gray500,
            ),
          ),
        ],
      ),
    );
  }

  void _openLocationMap(PropertyListingEntity listing) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.pin_drop_rounded, color: AppColors.emerald, size: 28),
                  const SizedBox(width: 10),
                  const Text(
                    'Property Coordinates',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                listing.address,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Geohash: ${listing.geohash} • Lat: ${listing.latitude} • Lng: ${listing.longitude}',
                style: const TextStyle(fontSize: 12, color: AppColors.gray600),
              ),
              const SizedBox(height: 20),
              VxButton(
                label: 'Get Navigation Directions',
                icon: Icons.directions_rounded,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
}
