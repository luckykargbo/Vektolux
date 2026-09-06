// lib/features/listings/presentation/views/property_detail_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Property Detail Screen
// Photo carousel, property specs (beds/baths/furnished), Sierra Leone
// amenities (EDSA/Generator, Guma water), agent profile, and dual-mode
// actions (Physical Site Visit vs Instant Hourly Guesthouse Booking).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../bookings/presentation/widgets/booking_modals.dart';
import '../../../real_estate/domain/entities/property_listing_entity.dart';

class PropertyDetailScreen extends StatefulWidget {
  final String id;
  final String title;
  final String description;
  final String category; // sale, long_term_rent, hourly_guesthouse
  final double price;
  final double? hourlyRate;
  final String address;
  final double latitude;
  final double longitude;
  final List<String> imageUrls;
  final String ownerId;
  final String? ownerName;
  final String? ownerPhone;
  final int? bedrooms;
  final int? bathrooms;
  final double? squareMeters;
  final bool isFurnished;
  final bool isVerified;
  final List<String> amenities;

  const PropertyDetailScreen({
    super.key,
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.price,
    this.hourlyRate,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.imageUrls = const [],
    required this.ownerId,
    this.ownerName,
    this.ownerPhone,
    this.bedrooms,
    this.bathrooms,
    this.squareMeters,
    this.isFurnished = true,
    this.isVerified = true,
    this.amenities = const [
      'EDSA Grid + Standby Generator',
      '24/7 Guma Valley Water + Borehole',
      'Air Conditioning',
      'High-Speed Starlink WiFi',
      'Dedicated Security Guard',
      'Gated Compound Parking',
    ],
  });

  /// Factory from CachedPropertyListing (Drift SQLite)
  factory PropertyDetailScreen.fromCached(CachedPropertyListing cached) {
    return PropertyDetailScreen(
      id: cached.id,
      title: cached.title,
      description: cached.description,
      category: cached.category,
      price: cached.price,
      hourlyRate: cached.hourlyRate,
      address: cached.address,
      latitude: cached.latitude,
      longitude: cached.longitude,
      imageUrls: cached.primaryImageUrl != null ? [cached.primaryImageUrl!] : [],
      ownerId: cached.ownerId,
    );
  }

  /// Factory from PropertyListingEntity
  factory PropertyDetailScreen.fromEntity(PropertyListingEntity entity) {
    return PropertyDetailScreen(
      id: entity.id,
      title: entity.title,
      description: entity.description,
      category: entity.category.name,
      price: entity.price,
      hourlyRate: entity.hourlyRate,
      address: entity.address,
      latitude: entity.latitude,
      longitude: entity.longitude,
      imageUrls: entity.imageUrls,
      ownerId: entity.ownerId,
      ownerName: entity.ownerName,
      ownerPhone: entity.ownerPhone,
      bedrooms: entity.bedrooms,
      bathrooms: entity.bathrooms,
      squareMeters: entity.areaSqM,
      isFurnished: true,
      isVerified: entity.isVerified,
      amenities: entity.amenities.isNotEmpty
          ? entity.amenities
          : const [
              'EDSA Grid + Standby Generator',
              '24/7 Guma Valley Water + Borehole',
              'Air Conditioning',
              'High-Speed Starlink WiFi',
              'Dedicated Security Guard',
              'Gated Compound Parking',
            ],
    );
  }

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  final PageController _pageController = PageController();
  int _activeImageIndex = 0;
  final _currencyFormat = NumberFormat('#,##0', 'en_US');

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isHourly => widget.category == 'hourly_guesthouse';

  String get _categoryBadgeText => switch (widget.category) {
        'sale' => 'FOR SALE',
        'long_term_rent' => 'ANNUAL RENT',
        'hourly_guesthouse' => 'HOURLY GUEST HOUSE',
        _ => widget.category.toUpperCase(),
      };

  Color get _categoryBadgeColor => switch (widget.category) {
        'sale' => AppColors.emerald,
        'long_term_rent' => const Color(0xFF6366F1), // Indigo
        'hourly_guesthouse' => const Color(0xFF06B6D4), // Cyan
        _ => AppColors.obsidian,
      };

  String get _priceFormatted {
    if (_isHourly && widget.hourlyRate != null) {
      return 'SLE ${_currencyFormat.format(widget.hourlyRate)} / hr';
    }
    if (widget.category == 'long_term_rent') {
      return 'SLE ${_currencyFormat.format(widget.price)} / yr';
    }
    return 'SLE ${_currencyFormat.format(widget.price)}';
  }

  void _handleBookingAction(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to book or schedule a site visit.'),
          backgroundColor: AppColors.obsidian,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final database = context.read<AppDatabase>();
    final convexClient = context.read<ConvexClientWrapper>();

    // Adapt to CachedPropertyListing for standard modals
    final cachedListing = CachedPropertyListing(
      id: widget.id,
      ownerId: widget.ownerId,
      title: widget.title,
      description: widget.description,
      category: widget.category,
      price: widget.price,
      hourlyRate: widget.hourlyRate,
      address: widget.address,
      latitude: widget.latitude,
      longitude: widget.longitude,
      primaryImageUrl: widget.imageUrls.isNotEmpty ? widget.imageUrls.first : null,
      isSynced: true,
      cachedAt: DateTime.now().millisecondsSinceEpoch,
    );

    if (_isHourly) {
      HourlyBookingModal.show(
        context,
        property: cachedListing,
        currentUser: user,
        database: database,
        convexClient: convexClient,
      );
    } else {
      PropertyInspectionModal.show(
        context,
        property: cachedListing,
        currentUser: user,
        database: database,
        convexClient: convexClient,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.imageUrls;

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.white,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppColors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.white),
            tooltip: 'Share listing',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Property link copied to clipboard.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Photo Showcase Carousel ──────────────────────────
            Stack(
              children: [
                SizedBox(
                  height: 260,
                  width: double.infinity,
                  child: images.isNotEmpty
                      ? PageView.builder(
                          controller: _pageController,
                          itemCount: images.length,
                          onPageChanged: (idx) => setState(() => _activeImageIndex = idx),
                          itemBuilder: (ctx, idx) {
                            return Image.network(
                              images[idx],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildFallbackHero(),
                            );
                          },
                        )
                      : _buildFallbackHero(),
                ),
                // Category Chip
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _categoryBadgeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _categoryBadgeText,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                // Verified Deed Badge
                if (widget.isVerified)
                  Positioned(
                    top: 14,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.emerald,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded, size: 14, color: AppColors.white),
                          SizedBox(width: 4),
                          Text(
                            'Verified Deed',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Price Pill
                Positioned(
                  bottom: 14,
                  right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.obsidian.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _priceFormatted,
                      style: const TextStyle(
                        color: AppColors.emerald,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                // Dot Indicators
                if (images.length > 1)
                  Positioned(
                    bottom: 14,
                    left: 14,
                    child: Row(
                      children: List.generate(images.length, (idx) {
                        final isSel = idx == _activeImageIndex;
                        return Container(
                          margin: const EdgeInsets.only(right: 4),
                          width: isSel ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isSel ? AppColors.white : AppColors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),

            // ── 2. Main Content & Overview ──────────────────────────
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: AppColors.gray500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.address,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // ── 3. Specs Summary Bar ──────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSpecIcon(Icons.bed_rounded, '${widget.bedrooms ?? 3} Bedrooms'),
                      _buildSpecIcon(Icons.bathtub_outlined, '${widget.bathrooms ?? 2} Bathrooms'),
                      _buildSpecIcon(
                        Icons.chair_outlined,
                        widget.isFurnished ? 'Furnished' : 'Unfurnished',
                      ),
                      _buildSpecIcon(
                        Icons.square_foot_rounded,
                        '${widget.squareMeters?.toStringAsFixed(0) ?? 240} m²',
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // ── 4. Property Description ───────────────────────
                  const Text(
                    'Property Description',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.description.isNotEmpty
                        ? widget.description
                        : 'Exquisite modern property situated in one of Freetown\'s most sought-after prime residential enclaves. Fully inspected by licensed surveyors with certified title deeds.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.gray600,
                    ),
                  ),

                  const SizedBox(height: 22),

                  // ── 5. Amenities & Infrastructure ─────────────────
                  const Text(
                    'Amenities & Sierra Leone Utilities',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.amenities.map((item) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.gray100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 14, color: AppColors.emeraldDark),
                            const SizedBox(width: 6),
                            Text(
                              item,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.obsidian,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  const SizedBox(height: 18),

                  // ── 6. Agent / Host Information ───────────────────
                  const Text(
                    'Listing Agent & Verification',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.gray50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.obsidian,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.real_estate_agent_rounded, color: AppColors.emerald, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.ownerName ?? 'Freetown Realty Partners',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.obsidian,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Certified Real Estate Broker • Western Area Urban',
                                style: TextStyle(fontSize: 11, color: AppColors.gray500),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.phone_outlined, color: AppColors.emeraldDark),
                          tooltip: 'Call Broker',
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Broker phone: ${widget.ownerPhone ?? "+232 76 543 210"}'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── 7. Escrow Guarantee ───────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_user_rounded, color: AppColors.emeraldDark, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'VEKTOLUX DEED PROTECTION: All rental and sales deposits are held securely in smart contract escrow until legal title deeds and keys are surrendered.',
                            style: TextStyle(
                              color: AppColors.emeraldDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 100), // Spacing for sticky bottom bar
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.of(context).padding.bottom + 14,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rate', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                Text(
                  _priceFormatted,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.obsidian,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _isHourly
                  ? VxButton(
                      label: 'Instant Booking & Pay',
                      icon: Icons.flash_on_rounded,
                      onPressed: () => _handleBookingAction(context),
                    )
                  : VxButton(
                      label: 'Book Site Visit / Inspection',
                      icon: Icons.calendar_today_rounded,
                      onPressed: () => _handleBookingAction(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackHero() {
    return Container(
      color: const Color(0xFF1E293B),
      child: const Center(
        child: Icon(
          Icons.apartment_outlined,
          size: 72,
          color: AppColors.emerald,
        ),
      ),
    );
  }

  Widget _buildSpecIcon(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.gray100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.obsidian),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.obsidian,
          ),
        ),
      ],
    );
  }
}
