// lib/features/explore/presentation/views/explore_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Production Explore & Discovery Screen
// Connects to live Convex database with elegant, first-class empty
// states for brand new users and responsive real data carousels.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vektolux_avatar.dart';
import '../../../../core/widgets/vx_network_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../navigation/presentation/views/main_navigation_shell.dart';
import '../../../listings/presentation/views/property_detail_screen.dart';
import '../../../listings/presentation/views/vehicle_detail_screen.dart';
import '../../../social/presentation/views/public_profile_screen.dart';

class ExploreScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final bool showBottomNav;

  const ExploreScreen({
    super.key,
    required this.convexClient,
    this.showBottomNav = false,
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  // Layout tokens (one rhythm for the whole screen).
  static const double _gutter = 20; // screen side margin
  static const double _gap = 12; // gap between cards
  static const double _sectionGap = 20; // gap between sections
  // Dense dashboard: cap iOS Dynamic Type so cards and one-line labels keep their structure.
  static const double _maxTextScale = 1.15;

  /// Width available to content (screen minus both gutters); set from the LayoutBuilder in build().
  double _contentWidth = 350;

  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  // Selected category shortcut ('Properties', 'Vehicles', 'Agents', 'Dealers', 'Rentals')
  String _selectedCategory = 'Properties';
  bool _isLoading = true;
  String? _loadError;
  bool _isSearching = false;
  String _searchQuery = '';
  int _unreadNotificationsCount = 0;

  // Live real database collections
  List<Map<String, dynamic>> _recommended = [];
  List<Map<String, dynamic>> _propertiesNearYou = [];
  List<Map<String, dynamic>> _vehiclesForSaleAndHire = [];
  List<Map<String, dynamic>> _topAgentsAndDealers = [];

  // Live search result lists
  List<Map<String, dynamic>> _searchProperties = [];
  List<Map<String, dynamic>> _searchVehicles = [];
  List<Map<String, dynamic>> _searchAgents = [];

  // Followed agents set for optimistic UI updates
  final Set<String> _followingUserIds = {};
  // Favorited listings set
  final Set<String> _favoritedListingIds = {};

  // 5 standard Category Shortcuts matching visual reference
  static const List<_ExploreCategoryItem> _categoryItems = [
    _ExploreCategoryItem(
      label: 'Properties',
      icon: Icons.home_outlined,
      activeColor: AppColors.emerald,
    ),
    _ExploreCategoryItem(
      label: 'Vehicles',
      icon: Icons.directions_car_outlined,
      activeColor: AppColors.emerald,
      defaultColor: Color(0xFF2563EB), // Blue accent as in reference
    ),
    _ExploreCategoryItem(
      label: 'Agents',
      icon: Icons.person_outline_rounded,
      activeColor: AppColors.emerald,
    ),
    _ExploreCategoryItem(
      label: 'Dealers',
      icon: Icons.storefront_outlined,
      activeColor: AppColors.emerald,
    ),
    _ExploreCategoryItem(
      label: 'Rentals',
      icon: Icons.apartment_outlined,
      activeColor: AppColors.emerald,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadExploreData();
    _fetchUnreadNotifications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Fetch Unread Notification Count ─────────────────────────────────
  Future<void> _fetchUnreadNotifications() async {
    try {
      final authState = context.read<AuthBloc>().state;
      final userId = authState.user?.id;
      final res = await widget.convexClient.query(
        'notifications:getUnreadNotificationCount',
        args: {'userId': userId ?? 'guest'},
      );
      if (res.success && res.value != null && mounted) {
        setState(() {
          _unreadNotificationsCount = (res.value as num).toInt();
        });
      }
    } catch (_) {}
  }

  // ── Load All Real Backend Explore Data ───────────────────────────────
  Future<void> _loadExploreData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final authState = context.read<AuthBloc>().state;
      final userId = authState.user?.id;

      final res = await widget.convexClient.query(
        'explore:getExploreFeed',
        args: {
          if (userId != null && userId.isNotEmpty) 'userId': userId,
          'category': _selectedCategory.toLowerCase(),
          'limit': 15,
        },
      );

      if (res.success && res.value is Map) {
        final data = Map<String, dynamic>.from(res.value as Map);

        final recList = (data['recommended'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final propList = (data['propertiesNearYou'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final vehList = (data['vehiclesForSaleAndHire'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final agentList = (data['topAgentsAndDealers'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        if (mounted) {
          setState(() {
            _recommended = recList;
            _propertiesNearYou = propList;
            _vehiclesForSaleAndHire = vehList;
            _topAgentsAndDealers = agentList;
            _isLoading = false;
            _loadError = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadError = res.errorMessage ?? 'Unable to sync Explore feed';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Connection failed. Please check network.';
        });
      }
    }
  }

  void _onCategorySelected(String category) {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
    });
    if (_searchQuery.isNotEmpty) {
      _performSearch(_searchQuery);
    } else {
      _loadExploreData();
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final trimmed = query.trim();
      if (!mounted) return;
      if (trimmed.isEmpty) {
        setState(() {
          _searchQuery = '';
          _isSearching = false;
          _searchProperties.clear();
          _searchVehicles.clear();
          _searchAgents.clear();
        });
      } else {
        setState(() {
          _searchQuery = trimmed;
          _isSearching = true;
        });
        _performSearch(trimmed);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final res = await widget.convexClient.query(
        'explore:searchExplore',
        args: {
          'searchQuery': query,
          'category': _selectedCategory.toLowerCase(),
          'limit': 20,
        },
      );

      if (res.success && res.value is Map && mounted) {
        final data = Map<String, dynamic>.from(res.value as Map);
        setState(() {
          _searchProperties = (data['properties'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _searchVehicles = (data['vehicles'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _searchAgents = (data['agents'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {}
  }

  // ── Toggle Follow Agent/Dealer ──────────────────────────────────────
  Future<void> _toggleFollow(String targetUserId) async {
    final authState = context.read<AuthBloc>().state;
    final currentUserId = authState.user?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please sign in to follow verified agents and dealers.'),
          backgroundColor: AppColors.obsidian,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final isCurrentlyFollowing = _followingUserIds.contains(targetUserId);
    setState(() {
      if (isCurrentlyFollowing) {
        _followingUserIds.remove(targetUserId);
      } else {
        _followingUserIds.add(targetUserId);
      }
    });

    try {
      final res = await widget.convexClient.mutation(
        'social:toggleFollow',
        args: {
          'currentUserId': currentUserId,
          'targetUserId': targetUserId,
        },
      );

      if (!res.success && mounted) {
        // Rollback on failure
        setState(() {
          if (isCurrentlyFollowing) {
            _followingUserIds.add(targetUserId);
          } else {
            _followingUserIds.remove(targetUserId);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (isCurrentlyFollowing) {
            _followingUserIds.add(targetUserId);
          } else {
            _followingUserIds.remove(targetUserId);
          }
        });
      }
    }
  }

  // ── Toggle Favorite Listing ─────────────────────────────────────────
  void _toggleFavorite(String listingId) {
    setState(() {
      if (_favoritedListingIds.contains(listingId)) {
        _favoritedListingIds.remove(listingId);
      } else {
        _favoritedListingIds.add(listingId);
      }
    });
  }

  // ── Navigation Helpers ──────────────────────────────────────────────
  void _navigateToAgent(String userId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          userId: userId,
          convexClient: widget.convexClient,
        ),
      ),
    );
  }

  void _navigateToProperty(Map<String, dynamic> item) {
    final id = item['id'] as String? ?? item['_id'] as String? ?? '';
    final title = item['title'] as String? ?? 'Property Listing';
    final desc = item['description'] as String? ?? title;
    final category = item['category'] as String? ?? 'sale';
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final address = item['city'] as String? ?? item['location'] as String? ?? 'Freetown, Sierra Leone';
    final ownerId = item['ownerId'] as String? ?? '';
    final imageUrl = item['imageUrl'] as String?;
    final imageUrls = imageUrl != null ? [imageUrl] : <String>[];
    final bedrooms = (item['bedrooms'] as num?)?.toInt();
    final bathrooms = (item['bathrooms'] as num?)?.toInt();
    final isVerified = item['isVerified'] == true;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(
          id: id,
          title: title,
          description: desc,
          category: category,
          price: price,
          address: address,
          latitude: 8.4657,
          longitude: -13.2317,
          ownerId: ownerId,
          imageUrls: imageUrls,
          bedrooms: bedrooms,
          bathrooms: bathrooms,
          isVerified: isVerified,
        ),
      ),
    );
  }

  void _navigateToVehicle(Map<String, dynamic> item) {
    final id = item['id'] as String? ?? item['_id'] as String? ?? '';
    final title = item['title'] as String? ?? 'Vehicle';
    final make = item['make'] as String? ?? title.split(' ').first;
    final model = item['model'] as String? ?? (title.split(' ').length > 1 ? title.split(' ').sublist(1).join(' ') : 'Sedan');
    final year = (item['year'] as num?)?.toInt() ?? 2022;
    final category = item['category'] as String? ?? 'suv';
    final pricingType = item['pricingType'] as String? ?? 'sale';
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final imageUrl = item['imageUrl'] as String?;
    final imageUrls = imageUrl != null ? [imageUrl] : <String>[];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VehicleDetailScreen(
          id: id,
          make: make,
          model: model,
          year: year,
          vehicleType: category,
          listingIntent: _isDailyHire(pricingType) ? 'rental' : 'sale',
          salePrice: _isDailyHire(pricingType) ? null : price,
          pricePerDay: _isDailyHire(pricingType) ? price : null,
          imageUrls: imageUrls,
        ),
      ),
    );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: _maxTextScale,
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _contentWidth = constraints.maxWidth - 2 * _gutter;
              return RefreshIndicator(
                color: AppColors.emerald,
                backgroundColor: Colors.white,
                onRefresh: _loadExploreData,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    SliverToBoxAdapter(child: _buildSearchRow()),
                    SliverToBoxAdapter(child: _buildCategoryShortcuts()),
                    const SliverToBoxAdapter(child: SizedBox(height: _sectionGap)),
                    if (_isSearching)
                      SliverToBoxAdapter(child: _buildSearchResults())
                    else ...[
                      // A load failure adds a banner; every section stays in place (never replaced).
                      if (_loadError != null) SliverToBoxAdapter(child: _buildErrorBanner()),
                      SliverToBoxAdapter(child: _buildRecommendedSection()),
                      const SliverToBoxAdapter(child: SizedBox(height: _sectionGap)),
                      SliverToBoxAdapter(child: _buildPropertiesNearYouSection()),
                      const SliverToBoxAdapter(child: SizedBox(height: _sectionGap)),
                      SliverToBoxAdapter(child: _buildVehiclesSection()),
                      const SliverToBoxAdapter(child: SizedBox(height: _sectionGap)),
                      SliverToBoxAdapter(child: _buildTopAgentsSection()),
                      const SliverToBoxAdapter(child: SizedBox(height: _sectionGap)),
                      SliverToBoxAdapter(child: _buildPersonalizeFeedCard()),
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: widget.showBottomNav ? _buildStandaloneBottomNav() : null,
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // SHARED BUILDING BLOCKS
  // ═════════════════════════════════════════════════════════════════════

  /// Full-bleed horizontal row of cards. Cards scroll under the screen edge (not the page gutter),
  /// and all cards in the row take the height of the tallest one, so nothing depends on a fixed
  /// height that real fonts / larger text could overflow.
  Widget _hList(List<Widget> children, {double gap = _gap}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(_gutter, 2, _gutter, 10), // bottom room for card shadows
      physics: const BouncingScrollPhysics(),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _padded(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: _gutter),
        child: child,
      );

  /// One section: padded header, then a full-bleed body.
  Widget _section({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onSeeAll,
    required Widget body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _padded(_buildSectionHeader(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle, onSeeAll: onSeeAll)),
        const SizedBox(height: 10),
        body,
      ],
    );
  }

  /// Empty state that stays honest when the backend could not be reached.
  Widget _emptyOrUnavailable({
    required IconData icon,
    required String title,
    required String description,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (_loadError != null) {
      return _padded(_buildCompactEmptyState(
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load this section",
        description: 'Tap Retry above or pull down to refresh.',
      ));
    }
    return _padded(_buildCompactEmptyState(
      icon: icon,
      title: title,
      description: description,
      actionLabel: actionLabel,
      onAction: onAction,
    ));
  }

  // ═════════════════════════════════════════════════════════════════════
  // 1. HEADER
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 12, _gutter, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Explore',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.15,
                    color: AppColors.obsidian,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Discover properties, vehicles, agents and more',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Notification bell with unread indicator
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildHeaderIconButton(
                icon: Icons.notifications_none_rounded,
                iconColor: AppColors.emeraldDark,
                tooltip: 'Notifications',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Notifications are up to date.'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              if (_unreadNotificationsCount > 0)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          _buildHeaderIconButton(
            icon: Icons.tune_rounded,
            iconColor: AppColors.emeraldDark,
            tooltip: 'Filter & Preferences',
            onTap: _showQuickFilterSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required Color iconColor,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.emeraldSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD1FAE5), width: 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Icon(icon, size: 20, color: iconColor),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 2. SEARCH BAR & GREEN FILTER BUTTON
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildSearchRow() {
    const double barHeight = 48;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _gutter, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: barHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                // Explicit colours: typed text must be dark whatever the system appearance is.
                style: const TextStyle(fontSize: 14, color: AppColors.obsidian, fontWeight: FontWeight.w500),
                cursorColor: AppColors.emerald,
                decoration: InputDecoration(
                  hintText: 'Search properties, vehicles, agents...',
                  hintMaxLines: 1,
                  hintStyle: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.gray400,
                    fontWeight: FontWeight.w400,
                    overflow: TextOverflow.ellipsis,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.gray500, size: 21),
                  prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: barHeight),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.gray500),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: barHeight,
            height: barHeight,
            decoration: BoxDecoration(
              color: AppColors.emerald,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.emerald.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _showQuickFilterSheet,
                child: const Center(
                  child: Icon(Icons.tune_rounded, color: Colors.white, size: 21),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 3. CATEGORY SHORTCUTS — five equal cards across the screen
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildCategoryShortcuts() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 10, _gutter, 0),
      child: SizedBox(
        height: 72,
        child: Row(
          children: [
            for (var i = 0; i < _categoryItems.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _buildCategoryTile(_categoryItems[i])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryTile(_ExploreCategoryItem item) {
    final isSelected = _selectedCategory == item.label;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isSelected ? AppColors.emeraldSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.emerald : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected ? AppColors.emerald.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.02),
            blurRadius: isSelected ? 8 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onCategorySelected(item.label),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  size: 24,
                  color: isSelected ? AppColors.emerald : (item.defaultColor ?? AppColors.gray600),
                ),
                const SizedBox(height: 5),
                // One line, always: shrinks a little on narrow phones instead of wrapping.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 4. RECOMMENDED FOR YOU — two cards across
  // ═════════════════════════════════════════════════════════════════════
  double get _recommendedCardWidth => ((_contentWidth - _gap) / 2).clamp(150.0, 320.0);
  double get _carouselCardWidth => ((_contentWidth - 2 * _gap) / 2.55).clamp(124.0, 220.0);
  double get _agentCardWidth => ((_contentWidth - 2 * 8) / 3).clamp(112.0, 190.0);

  Widget _buildRecommendedSection() {
    final w = _recommendedCardWidth;
    return _section(
      icon: Icons.star_rounded,
      iconColor: AppColors.emerald,
      title: 'Recommended for You',
      subtitle: 'Properties and vehicles you may like',
      onSeeAll: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recommendations update automatically as you explore.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      body: _isLoading
          ? _hList([for (var i = 0; i < 2; i++) _skeletonCard(w)])
          : _recommended.isEmpty
              ? _emptyOrUnavailable(
                  icon: Icons.auto_awesome_outlined,
                  title: 'No recommendations yet',
                  description: 'Explore properties and vehicles to start building your recommendations.',
                  actionLabel: 'Start Exploring',
                  onAction: () {
                    _onCategorySelected('Properties');
                    _scrollToTop();
                  },
                )
              : _hList([
                  for (final item in _recommended)
                    item['type'] == 'property' ? _buildPropertyCard(item, width: w) : _buildVehicleCard(item, width: w),
                ]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 5. PROPERTIES NEAR YOU
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPropertiesNearYouSection() {
    final w = _carouselCardWidth;
    return _section(
      icon: Icons.home_work_outlined,
      iconColor: AppColors.obsidian,
      title: 'Properties Near You',
      subtitle: 'Find the best properties in your area',
      onSeeAll: () => MainNavigationShell.switchToTab(context, 2),
      body: _isLoading
          ? _hList([for (var i = 0; i < 3; i++) _skeletonCard(w)])
          : _propertiesNearYou.isEmpty
              ? _emptyOrUnavailable(
                  icon: Icons.apartment_outlined,
                  title: 'No properties nearby yet',
                  description: 'New property listings will appear here when available.',
                  actionLabel: 'Browse Real Estate Market →',
                  onAction: () => MainNavigationShell.switchToTab(context, 2),
                )
              : _hList([for (final item in _propertiesNearYou) _buildPropertyCard(item, width: w)]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 6. VEHICLES FOR SALE & HIRE
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildVehiclesSection() {
    final w = _carouselCardWidth;
    return _section(
      icon: Icons.directions_car_outlined,
      iconColor: AppColors.obsidian,
      title: 'Vehicles for Sale & Hire',
      subtitle: 'Latest cars, vans and trucks',
      onSeeAll: () => MainNavigationShell.switchToTab(context, 3),
      body: _isLoading
          ? _hList([for (var i = 0; i < 3; i++) _skeletonCard(w)])
          : _vehiclesForSaleAndHire.isEmpty
              ? _emptyOrUnavailable(
                  icon: Icons.directions_car_outlined,
                  title: 'No vehicles available yet',
                  description: 'Vehicles listed by verified dealers and owners will appear here.',
                  actionLabel: 'Browse Auto Marketplace →',
                  onAction: () => MainNavigationShell.switchToTab(context, 3),
                )
              : _hList([for (final item in _vehiclesForSaleAndHire) _buildVehicleCard(item, width: w)]),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 7. TOP AGENTS & DEALERS — three cards across
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildTopAgentsSection() {
    final w = _agentCardWidth;
    return _section(
      icon: Icons.groups_outlined,
      iconColor: AppColors.obsidian,
      title: 'Top Agents & Dealers',
      subtitle: 'Trusted professionals near you',
      onSeeAll: () => _onCategorySelected('Agents'),
      body: _isLoading
          ? _hList([for (var i = 0; i < 3; i++) _skeletonAgentCard(w)], gap: 8)
          : _topAgentsAndDealers.isEmpty
              ? _emptyOrUnavailable(
                  icon: Icons.verified_user_outlined,
                  title: 'No agents or dealers yet',
                  description: 'Verified agents and dealers will appear here as they join Vektolux.',
                )
              : _hList([for (final a in _topAgentsAndDealers) _buildAgentCard(a, width: w)], gap: 8),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 8. BUILD YOUR EXPLORE FEED (promotional card)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPersonalizeFeedCard() {
    void findAgents() {
      _onCategorySelected('Agents');
      _scrollToTop();
    }

    final button = ElevatedButton(
      onPressed: findAgents,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0F5132), // dark emerald
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Find Agents →', maxLines: 1, softWrap: false)),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Build your Explore feed',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian, letterSpacing: -0.2),
        ),
        const SizedBox(height: 2),
        Text(
          'Follow agents and dealers to personalize what you see.',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.3),
        ),
      ],
    );

    final icon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: AppColors.emerald.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: const Icon(Icons.groups_rounded, size: 21, color: AppColors.emeraldDark),
    );

    return _padded(
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEBF7EE),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD1FAE5), width: 1.2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        // Wide: icon | text | button. Narrow: the button drops below so the text never gets squeezed.
        child: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 330) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [icon, const SizedBox(width: 12), Expanded(child: text)]),
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: button),
              ],
            );
          }
          return Row(
            children: [icon, const SizedBox(width: 12), Expanded(child: text), const SizedBox(width: 10), button],
          );
        }),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // REUSABLE SECTION HEADER
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildSectionHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onSeeAll,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: AppColors.obsidian,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w400, height: 1.25, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSeeAll,
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('See All', maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.emerald)),
                SizedBox(width: 1),
                Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.emerald),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // COMPACT & POLISHED EMPTY STATE COMPONENT
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildCompactEmptyState({
    required IconData icon,
    required String title,
    required String description,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.015), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: AppColors.emerald.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 21, color: AppColors.emerald),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.obsidian),
          ),
          const SizedBox(height: 3),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.35),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.emerald, width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                backgroundColor: Colors.white,
                foregroundColor: AppColors.emerald,
              ),
              child: Text(
                actionLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.emerald),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // LISTING CARDS (one shared implementation for properties and vehicles)
  // ═════════════════════════════════════════════════════════════════════

  /// The database's pricing types are total_sale / per_day / per_trip ('daily' is accepted for older data).
  /// (Explore used to test only for 'daily', so every rental showed as "For Sale" with no "/ day".)
  bool _isDailyHire(String? pricingType) => pricingType == 'per_day' || pricingType == 'daily';

  /// A real, public place label: the backend's generalized `location` when present, otherwise the
  /// listing's public city. Never an invented default.
  String? _publicPlace(Map<String, dynamic> item) {
    final loc = (item['location'] as String?)?.trim();
    if (loc != null && loc.isNotEmpty) return loc;
    final city = (item['city'] as String?)?.trim();
    if (city == null || city.isEmpty) return null;
    return city.toLowerCase().contains('sierra leone') ? city : '$city, Sierra Leone';
  }

  Widget _buildPropertyCard(Map<String, dynamic> item, {required double width}) {
    final id = item['id'] as String? ?? item['_id'] as String? ?? '';
    final price = (item['price'] as num?)?.toDouble();
    final currency = item['currency'] as String? ?? 'SLE';
    final category = item['category'] as String?;

    // Tag and price suffix come from the real listing category; unknown → no tag (nothing invented).
    String? tag;
    Color tagColor = AppColors.emerald;
    String suffix = '';
    switch (category) {
      case 'sale':
        tag = 'For Sale';
        break;
      case 'long_term_rent':
        tag = 'For Rent';
        tagColor = const Color(0xFF2563EB);
        suffix = ' / year';
        break;
      case 'hourly_guesthouse':
        tag = 'Short Stay';
        tagColor = const Color(0xFFB45309);
        break;
    }

    final beds = (item['bedrooms'] as num?)?.toInt();
    final baths = (item['bathrooms'] as num?)?.toInt();
    final area = (item['areaSqM'] as num?)?.toDouble();
    final specs = <_CardSpec>[
      if (beds != null && beds > 0) _CardSpec(Icons.bed_outlined, '$beds'),
      if (baths != null && baths > 0) _CardSpec(Icons.bathtub_outlined, '$baths'),
      if (area != null && area > 0) _CardSpec(Icons.crop_square_rounded, '${_currencyFormat.format(area.round())} m²'),
    ];

    return _buildListingCard(
      width: width,
      id: id,
      imageUrl: item['imageUrl'] as String?,
      fallbackIcon: Icons.home_work_outlined,
      isVerified: item['isVerified'] == true,
      tag: tag,
      tagColor: tagColor,
      priceText: price == null ? null : '$currency ${_currencyFormat.format(price)}$suffix',
      title: item['title'] as String? ?? 'Property',
      place: _publicPlace(item),
      specs: specs,
      onTap: () => _navigateToProperty(item),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> item, {required double width}) {
    final id = item['id'] as String? ?? item['_id'] as String? ?? '';
    final price = (item['price'] as num?)?.toDouble();
    final currency = item['currency'] as String? ?? 'SLE';
    final pricingType = item['pricingType'] as String?;
    final isDaily = _isDailyHire(pricingType);
    final isTrip = pricingType == 'per_trip';

    final year = (item['year'] as num?)?.toInt();
    final fuel = (item['fuelType'] as String?)?.trim();
    final transmission = (item['transmission'] as String?)?.trim();
    final specs = <_CardSpec>[
      if (year != null && year > 0) _CardSpec(Icons.calendar_today_outlined, '$year'),
      if (fuel != null && fuel.isNotEmpty) _CardSpec(Icons.local_gas_station_outlined, fuel),
      if (transmission != null && transmission.isNotEmpty)
        _CardSpec(Icons.settings_outlined, transmission.toLowerCase().startsWith('auto') ? 'Auto' : transmission),
    ];

    return _buildListingCard(
      width: width,
      id: id,
      imageUrl: item['imageUrl'] as String?,
      fallbackIcon: Icons.directions_car_outlined,
      isVerified: item['isVerified'] == true,
      tag: pricingType == null ? null : (isDaily || isTrip ? 'For Hire' : 'For Sale'),
      tagColor: isDaily || isTrip ? const Color(0xFF2563EB) : AppColors.emerald,
      priceText: price == null
          ? null
          : '$currency ${_currencyFormat.format(price)}${isDaily ? ' / day' : (isTrip ? ' / trip' : '')}',
      title: item['title'] as String? ?? 'Vehicle',
      place: _publicPlace(item),
      specs: specs,
      onTap: () => _navigateToVehicle(item),
    );
  }

  Widget _buildListingCard({
    required double width,
    required String id,
    required String? imageUrl,
    required IconData fallbackIcon,
    required bool isVerified,
    required String? tag,
    required Color tagColor,
    required String? priceText,
    required String title,
    required String? place,
    required List<_CardSpec> specs,
    required VoidCallback onTap,
  }) {
    final isFavorited = _favoritedListingIds.contains(id);
    const radius = 16.0;

    Widget pill(String text, Color color, {IconData? icon, double radiusPx = 6}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radiusPx)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 10, color: Colors.white), const SizedBox(width: 2)],
              Text(text, maxLines: 1, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        );

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image: a fixed ASPECT RATIO, so every card scales with its width.
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(radius)),
                    child: AspectRatio(
                      aspectRatio: 1.45,
                      child: VxNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover, fallbackIcon: fallbackIcon),
                    ),
                  ),
                  if (isVerified)
                    Positioned(top: 8, left: 8, child: pill('Verified', AppColors.emerald, icon: Icons.check, radiusPx: 20)),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _toggleFavorite(id),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)],
                        ),
                        child: Icon(
                          isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 15,
                          color: isFavorited ? AppColors.error : AppColors.obsidian,
                        ),
                      ),
                    ),
                  ),
                  if (tag != null) Positioned(bottom: 6, left: 8, child: pill(tag, tagColor)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (priceText != null)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          priceText,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.obsidian),
                    ),
                    if (place != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 12, color: AppColors.gray400),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (specs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      // Real details only; scales down a touch rather than wrapping or overflowing.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < specs.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              _buildSpecIcon(specs[i].icon, specs[i].text),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpecIcon(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.gray500),
        const SizedBox(width: 3),
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // AGENT & DEALER CARD
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildAgentCard(Map<String, dynamic> agent, {required double width}) {
    final id = agent['id'] as String? ?? '';
    final name = agent['name'] as String? ?? 'Professional';
    final role = agent['role'] as String? ?? '';
    final avatarUrl = agent['avatarUrl'] as String?;
    final isVerified = agent['isVerified'] == true;
    final listingsCount = (agent['listingsCount'] as num?)?.toInt();
    final isFollowing = _followingUserIds.contains(id);
    final isAuto = role.toLowerCase().contains('auto') || role.toLowerCase().contains('dealer');

    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _navigateToAgent(id),
                child: VektoluxAvatar(
                  avatarUrl: avatarUrl,
                  name: name,
                  radius: 18,
                  borderColor: isVerified ? AppColors.emerald : AppColors.border,
                  borderWidth: 1.5,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 2),
                          const Icon(Icons.verified, size: 12, color: AppColors.emerald),
                        ],
                      ],
                    ),
                    if (role.isNotEmpty)
                      Text(
                        role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: isAuto ? const Color(0xFF2563EB) : AppColors.emeraldDark,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (listingsCount != null) ...[
            const SizedBox(height: 6),
            Text(
              listingsCount == 1 ? '1 listing' : '$listingsCount listings',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 28,
            child: isFollowing
                ? ElevatedButton(
                    onPressed: () => _toggleFollow(id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Following ✓', maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  )
                : OutlinedButton(
                    onPressed: () => _toggleFollow(id),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.emerald, width: 1.2),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 28),
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.emerald,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Follow', maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.emerald)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // SKELETON LOADERS (same widths and structure as the real cards)
  // ═════════════════════════════════════════════════════════════════════
  Widget _skeletonBar(double? width, double height, {Color? color}) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: color ?? AppColors.gray100, borderRadius: BorderRadius.circular(4)),
      );

  Widget _skeletonCard(double width) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.45,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _skeletonBar(width * 0.5, 14, color: AppColors.gray200),
                const SizedBox(height: 8),
                _skeletonBar(width * 0.75, 11),
                const SizedBox(height: 6),
                _skeletonBar(width * 0.55, 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonAgentCard(double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 36, height: 36, decoration: const BoxDecoration(color: AppColors.gray100, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_skeletonBar(null, 11, color: AppColors.gray200), const SizedBox(height: 5), _skeletonBar(width * 0.35, 9)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _skeletonBar(width * 0.4, 9),
          const SizedBox(height: 10),
          Container(
            height: 28,
            decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(14)),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // ERROR BANNER (sits above the sections; they stay on screen)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildErrorBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 4, _gutter, 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: AppColors.errorLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.error, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _loadError ?? 'Unable to sync Explore feed.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.error, height: 1.25),
              ),
            ),
            TextButton(
              onPressed: _loadExploreData,
              child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // LIVE SEARCH RESULTS
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildSearchResults() {
    final hasNoResults = _searchProperties.isEmpty &&
        _searchVehicles.isEmpty &&
        _searchAgents.isEmpty;

    if (hasNoResults) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off_rounded, size: 48, color: AppColors.gray400),
              const SizedBox(height: 12),
              Text(
                'No listings matching "$_searchQuery"',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try searching with a different keyword or category.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Results for "$_searchQuery"',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 12),
          if (_searchProperties.isNotEmpty) ...[
            const Text(
              'Properties',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.emeraldDark,
              ),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchProperties.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _buildSearchPropertyItem(_searchProperties[index]);
              },
            ),
            const SizedBox(height: 16),
          ],
          if (_searchVehicles.isNotEmpty) ...[
            const Text(
              'Vehicles',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchVehicles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _buildSearchVehicleItem(_searchVehicles[index]);
              },
            ),
            const SizedBox(height: 16),
          ],
          if (_searchAgents.isNotEmpty) ...[
            const Text(
              'Verified Professionals',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchAgents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return _buildSearchAgentItem(_searchAgents[index]);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchPropertyItem(Map<String, dynamic> item) {
    final title = item['title'] ?? 'Property';
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final currency = item['currency'] ?? 'SLE';
    final city = item['city'] ?? 'Sierra Leone';
    final imageUrl = item['imageUrl'] as String?;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: InkWell(
        onTap: () => _navigateToProperty(item),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 60,
                height: 60,
                child: VxNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    city,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              '$currency ${_currencyFormat.format(price)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.emeraldDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchVehicleItem(Map<String, dynamic> item) {
    final title = item['title'] ?? 'Vehicle';
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final currency = item['currency'] ?? 'SLE';
    final location = item['location'] ?? 'Sierra Leone';
    final imageUrl = item['imageUrl'] as String?;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: InkWell(
        onTap: () => _navigateToVehicle(item),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 60,
                height: 60,
                child: VxNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    location,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              '$currency ${_currencyFormat.format(price)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2563EB),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAgentItem(Map<String, dynamic> agent) {
    final id = agent['id'] as String? ?? '';
    final name = agent['name'] ?? 'Professional';
    final role = agent['role'] ?? 'Agent';
    final avatarUrl = agent['avatarUrl'] as String?;
    final isVerified = agent['isVerified'] == true;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Row(
        children: [
          VektoluxAvatar(
            avatarUrl: avatarUrl,
            name: name,
            radius: 20,
            borderColor: isVerified ? AppColors.emerald : AppColors.border,
            borderWidth: 1.5,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified, size: 14, color: AppColors.emerald),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  role,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _navigateToAgent(id),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              side: const BorderSide(color: AppColors.emerald),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'View Profile',
              style: TextStyle(fontSize: 11, color: AppColors.emerald, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // QUICK FILTER SHEET (Interactive modal)
  // ═════════════════════════════════════════════════════════════════════
  void _showQuickFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.gray300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filter & Categories',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.obsidian,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              _selectedCategory = 'Properties';
                            });
                            setState(() {
                              _selectedCategory = 'Properties';
                            });
                            Navigator.pop(ctx);
                            _loadExploreData();
                          },
                          child: const Text('Reset', style: TextStyle(color: AppColors.emerald)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Primary Marketplace Category',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _categoryItems.map((c) {
                        final isSel = _selectedCategory == c.label;
                        return ChoiceChip(
                          label: Text(c.label),
                          selected: isSel,
                          selectedColor: AppColors.emerald,
                          backgroundColor: AppColors.gray50,
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : AppColors.obsidian,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          ),
                          onSelected: (_) {
                            setModalState(() {
                              _selectedCategory = c.label;
                            });
                            setState(() {
                              _selectedCategory = c.label;
                            });
                            Navigator.pop(ctx);
                            _onCategorySelected(c.label);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.emerald,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Apply Filters',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
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

  // ═════════════════════════════════════════════════════════════════════
  // 12. BOTTOM NAVIGATION (When rendered standalone)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildStandaloneBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomNavItem(
                index: 0,
                label: 'Home',
                icon: Icons.home_outlined,
                isActive: false,
                onTap: () => MainNavigationShell.switchToTab(context, 0),
              ),
              _buildBottomNavItem(
                index: 1,
                label: 'Explore',
                icon: Icons.explore_rounded,
                isActive: true,
                onTap: _scrollToTop,
              ),
              _buildBottomNavItem(
                index: 2,
                label: 'Real Estate',
                icon: Icons.apartment_outlined,
                isActive: false,
                onTap: () => MainNavigationShell.switchToTab(context, 2),
              ),
              _buildBottomNavItem(
                index: 3,
                label: 'Auto Market',
                icon: Icons.directions_car_outlined,
                isActive: false,
                onTap: () => MainNavigationShell.switchToTab(context, 3),
              ),
              _buildBottomNavItem(
                index: 4,
                label: 'Account',
                icon: Icons.person_outline_rounded,
                isActive: false,
                onTap: () => MainNavigationShell.switchToTab(context, 4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavItem({
    required int index,
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final color = isActive ? AppColors.emerald : AppColors.gray400;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardSpec {
  final IconData icon;
  final String text;
  const _CardSpec(this.icon, this.text);
}

class _ExploreCategoryItem {
  final String label;
  final IconData icon;
  final Color activeColor;
  final Color? defaultColor;

  const _ExploreCategoryItem({
    required this.label,
    required this.icon,
    required this.activeColor,
    this.defaultColor,
  });
}
