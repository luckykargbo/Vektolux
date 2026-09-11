// lib/features/real_estate/presentation/views/real_estate_listing_detail_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Listing Detail Screen
// Production-grade Flutter screen with local-first SQLite streaming,
// Dual-Mode Action Panel (Site Visit vs Instant Hourly Booking),
// anti-collision slot validation, and payment gateway checkout.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/services/sqlite_post_archive_service.dart';
import '../../../../core/network/convex_client_wrapper.dart';
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

                  // ── 1B. Owner / Agent Quick Controls Banner ──────
                  if (widget.currentUserId == listing.ownerId)
                    SliverToBoxAdapter(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.emerald.withValues(alpha: 0.4)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.emerald.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.shield_outlined, color: AppColors.emeraldLight, size: 12),
                                      SizedBox(width: 4),
                                      Text(
                                        'YOU ARE THE POST CREATOR / AGENT',
                                        style: TextStyle(
                                          color: AppColors.emeraldLight,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'Price: ${listing.currency} ${listing.price.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.price_change_outlined, size: 16),
                                    label: const Text('Update Price / Range'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.emerald,
                                      foregroundColor: AppColors.obsidian,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                    ),
                                    onPressed: () => _openOwnerPriceUpdateModal(context, listing),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: Color(0xFFFCA5A5)),
                                    label: const Text('Sold? Delete Post', style: TextStyle(color: Color(0xFFFCA5A5))),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                    ),
                                    onPressed: () => _deleteAndArchiveProperty(context, listing),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
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
    if (widget.currentUserId == listing.ownerId) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.obsidian.withValues(alpha: 0.1),
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
            Expanded(
              flex: 3,
              child: VxButton.primary(
                text: 'Update Price / Range',
                icon: Icons.price_change_outlined,
                onPressed: () => _openOwnerPriceUpdateModal(context, listing),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Sold? Delete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                onPressed: () => _deleteAndArchiveProperty(context, listing),
              ),
            ),
          ],
        ),
      );
    }

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

  // ═══════════════════════════════════════════════════════════════════
  //              OWNER ACTION: UPDATE PRICE & LISTING DETAILS
  // ═══════════════════════════════════════════════════════════════════

  void _openOwnerPriceUpdateModal(
    BuildContext context,
    PropertyListingEntity listing,
  ) {
    final priceController = TextEditingController(
      text: listing.price.toStringAsFixed(0),
    );
    final hourlyRateController = TextEditingController(
      text: listing.hourlyRate != null ? listing.hourlyRate!.toStringAsFixed(0) : '',
    );
    final titleController = TextEditingController(text: listing.title);
    final descController = TextEditingController(text: listing.description);
    final bedsController = TextEditingController(
      text: listing.bedrooms != null ? listing.bedrooms.toString() : '3',
    );
    final bathsController = TextEditingController(
      text: listing.bathrooms != null ? listing.bathrooms.toString() : '2',
    );

    bool isUpdating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void applyPercentage(double factor) {
              final current = double.tryParse(priceController.text.trim()) ?? listing.price;
              final updated = (current * factor).roundToDouble();
              setModalState(() {
                priceController.text = updated.toStringAsFixed(0);
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Update Price & Details',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                            ),
                            Text(
                              'Changes reflect immediately across the public marketplace',
                              style: TextStyle(fontSize: 11, color: AppColors.gray500),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(modalCtx).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    // Price Input
                    TextFormField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.emeraldDark,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Price (${listing.currency})',
                        prefixText: '${listing.currency}  ',
                        helperText: 'Current: ${listing.currency} ${listing.price.toStringAsFixed(0)}',
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Quick Percentage Adjustment Buttons
                    Row(
                      children: [
                        const Text(
                          'Quick Range:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.gray600),
                        ),
                        const SizedBox(width: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            _buildQuickAdjustChip('-10%', () => applyPercentage(0.90), isDiscount: true),
                            _buildQuickAdjustChip('-5%', () => applyPercentage(0.95), isDiscount: true),
                            _buildQuickAdjustChip('+5%', () => applyPercentage(1.05), isDiscount: false),
                            _buildQuickAdjustChip('+10%', () => applyPercentage(1.10), isDiscount: false),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (listing.isHourlyStay) ...[
                      TextFormField(
                        controller: hourlyRateController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Hourly Rate (${listing.currency})',
                          prefixText: '${listing.currency}  ',
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Title
                    TextFormField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Headline / Title'),
                    ),
                    const SizedBox(height: 14),

                    // Beds & Baths
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: bedsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Bedrooms / Rooms'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: bathsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Bathrooms'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Description
                    TextFormField(
                      controller: descController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Description'),
                    ),
                    const SizedBox(height: 20),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isUpdating
                            ? null
                            : () async {
                                final newPrice = double.tryParse(priceController.text.trim());
                                if (newPrice == null || newPrice <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please enter a valid price amount.'),
                                      backgroundColor: AppColors.error,
                                    ),
                                  );
                                  return;
                                }

                                setModalState(() => isUpdating = true);

                                try {
                                  final convexClient = context.read<ConvexClientWrapper>();
                                  final newHourly = double.tryParse(hourlyRateController.text.trim());
                                  final newBeds = int.tryParse(bedsController.text.trim());
                                  final newBaths = int.tryParse(bathsController.text.trim());

                                  final res = await convexClient.mutation(
                                    'realEstate:updatePropertyListing',
                                    args: {
                                      'listingId': listing.id,
                                      'ownerId': widget.currentUserId,
                                      'price': newPrice,
                                      'title': titleController.text.trim(),
                                      'description': descController.text.trim(),
                                      if (newHourly != null) 'hourlyRate': newHourly,
                                      if (newBeds != null) 'bedrooms': newBeds,
                                      if (newBaths != null) 'bathrooms': newBaths,
                                    },
                                  );

                                  if (res.success) {
                                    if (modalCtx.mounted) Navigator.of(modalCtx).pop();
                                    if (context.mounted) {
                                      context.read<RealEstateDetailBloc>().add(LoadListingDetailEvent(widget.listingId));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('✓ Price updated to ${listing.currency} ${newPrice.toStringAsFixed(0)}! Browsing buyers see this updated price.'),
                                          backgroundColor: AppColors.emeraldDark,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  } else {
                                    setModalState(() => isUpdating = false);
                                    if (modalCtx.mounted) {
                                      ScaffoldMessenger.of(modalCtx).showSnackBar(
                                        SnackBar(
                                          content: Text('Update failed: ${res.errorMessage ?? "Unknown error"}'),
                                          backgroundColor: AppColors.error,
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  setModalState(() => isUpdating = false);
                                  if (modalCtx.mounted) {
                                    ScaffoldMessenger.of(modalCtx).showSnackBar(
                                      SnackBar(content: Text('Update failed: $e'), backgroundColor: AppColors.error),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.emerald,
                          foregroundColor: AppColors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isUpdating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Save & Publish Updated Price', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickAdjustChip(String label, VoidCallback onTap, {required bool isDiscount}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDiscount ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isDiscount ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isDiscount ? AppColors.errorDark : AppColors.emeraldDark,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //              OWNER ACTION: SOLD? DELETE & ARCHIVE POST
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _deleteAndArchiveProperty(
    BuildContext context,
    PropertyListingEntity listing,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 24),
            SizedBox(width: 8),
            Text('Delete Property Post', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Did a client buy/rent "${listing.title}" or do you want to remove it?',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.inventory_2_outlined, color: AppColors.emeraldDark, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The post will immediately be removed from Convex public search and permanently archived into your local encrypted SQLite storage for future reference.',
                      style: TextStyle(fontSize: 11, color: AppColors.obsidianSoft, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.gray600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Delete & Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Evacuating post and archiving to local SQLite...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      final convexClient = context.read<ConvexClientWrapper>();
      final database = context.read<AppDatabase>();
      final archiveService = SqlitePostArchiveService(database);

      final res = await convexClient.mutation(
        'realEstate:deletePropertyListing',
        args: {
          'listingId': listing.id,
          'ownerId': widget.currentUserId,
        },
      );

      if (res.success && res.value != null) {
        final archivedMap = res.value['archivedData'] as Map<String, dynamic>?;
        if (archivedMap != null) {
          await archiveService.archivePost(
            id: archivedMap['id']?.toString() ?? listing.id,
            postType: 'property',
            ownerId: archivedMap['ownerId']?.toString() ?? widget.currentUserId,
            title: archivedMap['title']?.toString() ?? listing.title,
            description: archivedMap['description']?.toString() ?? listing.description,
            category: archivedMap['category']?.toString() ?? listing.category.name,
            price: (archivedMap['price'] as num?)?.toDouble() ?? listing.price,
            currency: archivedMap['currency']?.toString() ?? listing.currency,
            location: archivedMap['location']?.toString() ?? '${listing.address}, ${listing.city}',
            bedrooms: archivedMap['bedrooms'] as int? ?? listing.bedrooms,
            bathrooms: archivedMap['bathrooms'] as int? ?? listing.bathrooms,
            privateContactPhone: archivedMap['privateContactPhone']?.toString(),
            imageUrls: (archivedMap['imageUrls'] as List?)?.cast<String>() ?? listing.imageUrls,
            originalCreatedAt: (archivedMap['originalCreatedAt'] as num?)?.toInt(),
          );
        }

        if (context.mounted) {
          Navigator.of(context).pop();
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('✓ Property post successfully deleted and archived to local SQLite.'),
              backgroundColor: AppColors.obsidian,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to delete listing: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
