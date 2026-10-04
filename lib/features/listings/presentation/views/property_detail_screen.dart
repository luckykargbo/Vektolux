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

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../../core/widgets/vx_video_player.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../messaging/data/messaging_api.dart';
import '../../../messaging/presentation/buyer_messaging.dart';
import '../../../saved/presentation/saved_hearts.dart';
import '../../../social/presentation/views/public_profile_screen.dart';
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

  /// Public property videos (real uploaded files).
  final List<String> videoUrls;
  final String ownerId;
  final String? ownerName;
  final String? ownerPhone;
  final int? bedrooms;
  final int? bathrooms;
  final double? squareMeters;
  /// Null when the listing does not say (nothing is assumed).
  final bool? isFurnished;
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
    this.videoUrls = const [],
    required this.ownerId,
    this.ownerName,
    this.ownerPhone,
    this.bedrooms,
    this.bathrooms,
    this.squareMeters,
    this.isFurnished,
    this.isVerified = false,
    this.amenities = const [],
  });

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
      isVerified: entity.isVerified,
      amenities: entity.amenities,
    );
  }

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  final PageController _pageController = PageController();
  int _activeImageIndex = 0;
  final _currencyFormat = NumberFormat('#,##0', 'en_US');

  /// The heart: saved on the server against the signed-in account.
  late final SavedHearts _hearts = SavedHearts.of(context);

  @override
  void initState() {
    super.initState();
    _hearts.addListener(_onHeartsChanged);
    _hearts.load();
    _recordView();
  }

  @override
  void dispose() {
    _hearts.removeListener(_onHeartsChanged);
    _hearts.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onHeartsChanged() {
    if (mounted) setState(() {});
  }

  /// Tells the server this signed-in user opened the listing (counted once per day, never for the
  /// owner or the listing's agent; guests are not counted). Fire and forget: it must never get in
  /// the way of reading the listing.
  Future<void> _recordView() async {
    try {
      final user = context.read<AuthBloc>().state.user;
      if (user == null || widget.id.isEmpty || _isOwnListing) return;
      await context.read<ConvexClientWrapper>().mutation('listingStats:recordPropertyView', args: {'listingId': widget.id});
    } catch (_) {
      // not counted; nothing to tell the user
    }
  }

  Future<void> _toggleHeart() async {
    final error = await _hearts.toggle(widget.id);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), behavior: SnackBarBehavior.floating));
    }
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

  /// PRIVACY GUARANTEE: Never expose physical street or house numbers to users.
  String get _generalLocation {
    final raw = widget.address.trim();
    if (raw.isEmpty) return 'Sierra Leone';
    for (final town in [
      'Freetown', 'Bo', 'Kenema', 'Makeni', 'Koidu', 'Kailahun', 'Port Loko',
      'Pujehun', 'Bombali', 'Kambia', 'Moyamba', 'Kono', 'Bonthe', 'Tonkolili',
      'Falaba', 'Karene', 'Koinadugu', 'Waterloo', 'Goderich', 'Western Area',
    ]) {
      if (raw.toLowerCase().contains(town.toLowerCase())) {
        return '$town, Sierra Leone';
      }
    }
    final parts = raw.split(',');
    if (parts.length > 1) {
      return '${parts.last.trim()}, Sierra Leone';
    }
    return raw.endsWith('Sierra Leone') ? raw : '$raw, Sierra Leone';
  }

  List<Widget> get _specItems => [
        if ((widget.bedrooms ?? 0) > 0) _buildSpecIcon(Icons.bed_rounded, '${widget.bedrooms} Bedrooms'),
        if ((widget.bathrooms ?? 0) > 0) _buildSpecIcon(Icons.bathtub_outlined, '${widget.bathrooms} Bathrooms'),
        if (widget.isFurnished != null) _buildSpecIcon(Icons.chair_outlined, widget.isFurnished! ? 'Furnished' : 'Unfurnished'),
        if ((widget.squareMeters ?? 0) > 0) _buildSpecIcon(Icons.square_foot_rounded, '${widget.squareMeters!.toStringAsFixed(0)} m²'),
      ];

  /// Real in-app messaging with whoever listed the property (no phone numbers are shown).
  /// The owner looking at their own listing gets no "Message" button (the server refuses
  /// self-inquiries anyway).
  bool get _isOwnListing {
    try {
      final me = context.read<AuthBloc>().state.user?.id;
      return me != null && me.isNotEmpty && me == widget.ownerId;
    } catch (_) {
      return false;
    }
  }

  Future<void> _messageSeller() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to message the seller.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    await openListingConversation(
      context,
      api: MessagingApi(client: context.read<ConvexClientWrapper>(), userId: user.id, sessionToken: user.sessionToken),
      listingId: widget.id,
      listingType: 'property',
      listingTitle: widget.title,
    );
  }

  void _handlePrimaryAction() {
    final authState = context.read<AuthBloc>().state;
    final user = authState.user;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to book or schedule visits'),
          backgroundColor: AppColors.obsidian,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final convexClient = context.read<ConvexClientWrapper>();

    final propertyEntity = PropertyListingEntity(
      id: widget.id,
      ownerId: widget.ownerId,
      title: widget.title,
      description: widget.description,
      category: RealEstateCategory.fromString(widget.category),
      price: widget.price,
      hourlyRate: widget.hourlyRate,
      address: widget.address,
      city: 'Freetown',
      country: 'Sierra Leone',
      latitude: widget.latitude,
      longitude: widget.longitude,
      geohash: '',
      availabilityStatus: 'available',
      imageUrls: widget.imageUrls,
      ownerName: widget.ownerName,
      ownerPhone: widget.ownerPhone,
      bedrooms: widget.bedrooms,
      bathrooms: widget.bathrooms,
      areaSqM: widget.squareMeters,
      amenities: widget.amenities,
    );

    if (_isHourly) {
      HourlyBookingModal.show(
        context,
        property: propertyEntity,
        currentUser: user,
        convexClient: convexClient,
      );
    } else {
      PropertyInspectionModal.show(
        context,
        property: propertyEntity,
        currentUser: user,
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
          // Save / un-save (a server record). Your own listing cannot be saved.
          if (!_isOwnListing)
            IconButton(
              key: const Key('property-heart'),
              icon: Icon(
                _hearts.isSaved(widget.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: _hearts.isSaved(widget.id) ? AppColors.error : AppColors.white,
              ),
              tooltip: _hearts.isSaved(widget.id) ? 'Remove from saved' : 'Save property',
              onPressed: _toggleHeart,
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
                          _generalLocation,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // ── 3. Specs Summary Bar (only the details the listing really has) ──
                  if (_specItems.isNotEmpty) ...[
                    Wrap(
                      alignment: WrapAlignment.spaceAround,
                      spacing: 12,
                      runSpacing: 10,
                      children: _specItems,
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                  ],

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

                  // ── 5. Amenities (only what the listing lists) ─────
                  if (widget.amenities.isNotEmpty) ...[
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

                  ],

                  if (widget.videoUrls.isNotEmpty) ...[
                    // ── Video tour (real uploaded videos) ──────────────
                    const Text(
                      'Video Tour',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (var i = 0; i < widget.videoUrls.length; i++)
                          Material(
                            color: AppColors.obsidian,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              key: Key('property-video-$i'),
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => VxVideoPlayerScreen.open(context, widget.videoUrls[i], title: widget.title),
                              child: SizedBox(
                                width: 132,
                                height: 84,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.play_circle_fill_rounded, color: AppColors.emerald, size: 34),
                                    const SizedBox(height: 4),
                                    Text('Video ${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ── 6. Who listed it (no invented names, credentials or phone numbers) ──
                  const Text(
                    'Listed By',
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
                                widget.ownerName ?? 'Property owner',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.obsidian,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (widget.ownerId.isNotEmpty)
                                GestureDetector(
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => PublicProfileScreen(
                                      userId: widget.ownerId,
                                      convexClient: context.read<ConvexClientWrapper>(),
                                    ),
                                  )),
                                  child: const Text(
                                    'View profile',
                                    style: TextStyle(fontSize: 12, color: AppColors.emeraldDark, fontWeight: FontWeight.w700),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!_isOwnListing) ...[
                          const SizedBox(width: 8),
                          TextButton.icon(
                            key: const Key('property-message-seller'),
                            onPressed: _messageSeller,
                            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                            label: const Text('Message'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: AppColors.emeraldDark,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
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
                      onPressed: _handlePrimaryAction,
                    )
                  : VxButton(
                      key: const Key('property-request-viewing'),
                      label: 'Request a Viewing',
                      icon: Icons.calendar_today_rounded,
                      onPressed: _handlePrimaryAction,
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
