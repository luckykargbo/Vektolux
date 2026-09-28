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
          listingIntent: pricingType == 'daily' ? 'rental' : 'sale',
          salePrice: pricingType == 'daily' ? null : price,
          pricePerDay: pricingType == 'daily' ? price : null,
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
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.emerald,
          backgroundColor: Colors.white,
          onRefresh: _loadExploreData,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── 1. HEADER ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildHeader(),
              ),

              // ── 2. SEARCH BAR & GREEN FILTER BUTTON ─────────────────
              SliverToBoxAdapter(
                child: _buildSearchRow(),
              ),

              // ── 3. CATEGORY SHORTCUTS ───────────────────────────────
              SliverToBoxAdapter(
                child: _buildCategoryShortcuts(),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 14),
              ),

              // ── DYNAMIC BODY: SEARCH RESULTS OR EXPLORE SECTIONS ───
              if (_isSearching)
                SliverToBoxAdapter(
                  child: _buildSearchResults(),
                )
              else if (_loadError != null)
                SliverToBoxAdapter(
                  child: _buildErrorBanner(),
                )
              else ...[
                // ── 4. RECOMMENDED FOR YOU ─────────────────────────────
                SliverToBoxAdapter(
                  child: _buildRecommendedSection(),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 16),
                ),

                // ── 5. PROPERTIES NEAR YOU ─────────────────────────────
                SliverToBoxAdapter(
                  child: _buildPropertiesNearYouSection(),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 16),
                ),

                // ── 6. VEHICLES FOR SALE & HIRE ────────────────────────
                SliverToBoxAdapter(
                  child: _buildVehiclesSection(),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 16),
                ),

                // ── 7. TOP AGENTS & DEALERS ────────────────────────────
                SliverToBoxAdapter(
                  child: _buildTopAgentsSection(),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 20),
                ),

                // ── 8. BUILD YOUR EXPLORE FEED ─────────────────────────
                SliverToBoxAdapter(
                  child: _buildPersonalizeFeedCard(),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 36),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: widget.showBottomNav ? _buildStandaloneBottomNav() : null,
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 1. HEADER
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
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
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: AppColors.obsidian,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Discover properties, vehicles, agents and more',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Notification Bell with unread indicator
          Stack(
            clipBehavior: Clip.none,
            children: [
              _buildHeaderIconButton(
                icon: Icons.notifications_none_rounded,
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
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          // Filter / Settings Button
          _buildHeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filter & Preferences',
            onTap: _showQuickFilterSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Icon(
            icon,
            size: 20,
            color: AppColors.obsidian,
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 2. SEARCH BAR & GREEN FILTER BUTTON
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildSearchRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          // Large Rounded Search Input Field
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
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
                decoration: InputDecoration(
                  hintText: 'Search properties, vehicles, agents...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: AppColors.gray400,
                    fontWeight: FontWeight.w400,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.gray400,
                    size: 22,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.gray500),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Dedicated Vektolux Green Filter Button on the right
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.emerald,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.emerald.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _showQuickFilterSheet,
                child: const Center(
                  child: Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 3. CATEGORY SHORTCUTS (Horizontally scrollable cards with line icons)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildCategoryShortcuts() {
    return Container(
      height: 82,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _categoryItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = _categoryItems[index];
          final isSelected = _selectedCategory == item.label;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: 80,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.emeraldSurface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppColors.emerald : AppColors.border,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.emerald.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _onCategorySelected(item.label),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.icon,
                      size: 26,
                      color: isSelected
                          ? AppColors.emerald
                          : (item.defaultColor ?? AppColors.gray600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 4. RECOMMENDED FOR YOU
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildRecommendedSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
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
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            _buildHorizontalSkeletonCarousel()
          else if (_recommended.isEmpty)
            // Empty / New User State (strictly no fake data)
            _buildCompactEmptyState(
              icon: Icons.auto_awesome_outlined,
              title: 'No recommendations yet',
              description: 'Explore properties and vehicles to start building your recommendations.',
              actionLabel: 'Start Exploring',
              onAction: () {
                _onCategorySelected('Properties');
                _scrollToTop();
              },
            )
          else
            // Real Database Data State
            SizedBox(
              height: 290,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recommended.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final item = _recommended[index];
                  final isProperty = item['type'] == 'property';
                  return isProperty
                      ? _buildPropertyCard(item, width: 260)
                      : _buildVehicleCard(item, width: 260);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 5. PROPERTIES NEAR YOU
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPropertiesNearYouSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.home_work_outlined,
            iconColor: AppColors.obsidian,
            title: 'Properties Near You',
            subtitle: 'Find properties available in your area',
            onSeeAll: () {
              MainNavigationShell.switchToTab(context, 2);
            },
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            _buildHorizontalSkeletonCarousel()
          else if (_propertiesNearYou.isEmpty)
            // Empty / New User State
            _buildCompactEmptyState(
              icon: Icons.apartment_outlined,
              title: 'No properties nearby yet',
              description: 'New property listings will appear here when available.',
              actionLabel: 'Browse Real Estate Market →',
              onAction: () {
                MainNavigationShell.switchToTab(context, 2);
              },
            )
          else
            // Real Database Data State
            SizedBox(
              height: 290,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _propertiesNearYou.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  return _buildPropertyCard(_propertiesNearYou[index], width: 250);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 6. VEHICLES FOR SALE & HIRE
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildVehiclesSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.directions_car_outlined,
            iconColor: AppColors.obsidian,
            title: 'Vehicles for Sale & Hire',
            subtitle: 'Cars, vans and trucks from verified sellers',
            onSeeAll: () {
              MainNavigationShell.switchToTab(context, 3);
            },
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            _buildHorizontalSkeletonCarousel()
          else if (_vehiclesForSaleAndHire.isEmpty)
            // Empty / New User State
            _buildCompactEmptyState(
              icon: Icons.directions_car_outlined,
              title: 'No vehicles available yet',
              description: 'Vehicles listed by verified dealers and owners will appear here.',
              actionLabel: 'Browse Auto Marketplace →',
              onAction: () {
                MainNavigationShell.switchToTab(context, 3);
              },
            )
          else
            // Real Database Data State
            SizedBox(
              height: 285,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _vehiclesForSaleAndHire.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  return _buildVehicleCard(_vehiclesForSaleAndHire[index], width: 250);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 7. TOP AGENTS & DEALERS
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildTopAgentsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.groups_outlined,
            iconColor: AppColors.obsidian,
            title: 'Top Agents & Dealers',
            subtitle: 'Trusted professionals near you',
            onSeeAll: () {
              _onCategorySelected('Agents');
            },
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            _buildAgentsSkeletonRow()
          else if (_topAgentsAndDealers.isEmpty)
            // Empty / New User State
            _buildCompactEmptyState(
              icon: Icons.verified_user_outlined,
              title: 'No agents or dealers yet',
              description: 'Verified agents and dealers will appear here as they join Vektolux.',
            )
          else
            // Real Database Data State
            SizedBox(
              height: 195,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _topAgentsAndDealers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return _buildAgentCard(_topAgentsAndDealers[index]);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 8. BUILD YOUR EXPLORE FEED (Promotional Card)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPersonalizeFeedCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEBF7EE), // Soft light-green accent
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD1FAE5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left Network / People Icon
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.groups_rounded,
                size: 22,
                color: AppColors.emeraldDark,
              ),
            ),
            const SizedBox(width: 14),
            // Middle Description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Build your Explore feed',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Follow agents and dealers to personalize what you see.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Right CTA Button
            ElevatedButton(
              onPressed: () {
                _onCategorySelected('Agents');
                _scrollToTop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5132), // Dark emerald green
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Find Agents →'),
            ),
          ],
        ),
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
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: onSeeAll,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'See All',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.emerald,
                  ),
                ),
                SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.emerald,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // COMPACT & POLISHED EMPTY STATE COMPONENT
  // (Conforms strictly to Section 9: Empty-State Design Rule)
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB), // Very light neutral gray
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 22,
              color: AppColors.emerald,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 34,
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.emerald, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: Colors.white,
                ),
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.emerald,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // REAL PROPERTY LISTING CARD (Matches Visual Reference)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPropertyCard(Map<String, dynamic> item, {required double width}) {
    final id = item['id'] as String? ?? item['_id'] as String? ?? '';
    final title = item['title'] as String? ?? 'Property';
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final currency = item['currency'] as String? ?? 'SLE';
    final imageUrl = item['imageUrl'] as String?;
    final city = item['city'] as String? ?? item['location'] as String? ?? 'Freetown, Sierra Leone';
    final bedrooms = (item['bedrooms'] as num?)?.toInt() ?? 3;
    final bathrooms = (item['bathrooms'] as num?)?.toInt() ?? 2;
    final isVerified = item['isVerified'] == true;
    final isFavorited = _favoritedListingIds.contains(id);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _navigateToProperty(item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image container with overlays
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: VxNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // Top Left: Verified Badge
                  if (isVerified)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.emerald,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check, size: 12, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'Verified',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Top Right: Favorite Button
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () => _toggleFavorite(id),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 16,
                          color: isFavorited ? AppColors.error : AppColors.obsidian,
                        ),
                      ),
                    ),
                  ),
                  // Bottom Left: For Sale / For Rent Pill
                  Positioned(
                    bottom: 8,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.emerald,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'For Sale',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Card Details
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Price
                    Text(
                      '$currency ${_currencyFormat.format(price)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Title
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Location
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 13, color: AppColors.gray400),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            city,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Specs row: Bed, Bath, Sqft
                    Row(
                      children: [
                        _buildSpecIcon(Icons.bed_outlined, '$bedrooms'),
                        const SizedBox(width: 10),
                        _buildSpecIcon(Icons.bathtub_outlined, '$bathrooms'),
                        const SizedBox(width: 10),
                        _buildSpecIcon(Icons.crop_square_rounded, '1,800 sqft'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // REAL VEHICLE LISTING CARD (Matches Visual Reference)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildVehicleCard(Map<String, dynamic> item, {required double width}) {
    final id = item['id'] as String? ?? item['_id'] as String? ?? '';
    final title = item['title'] as String? ?? 'Vehicle';
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final currency = item['currency'] as String? ?? 'SLE';
    final imageUrl = item['imageUrl'] as String?;
    final location = item['location'] as String? ?? 'Freetown, Sierra Leone';
    final year = (item['year'] as num?)?.toInt() ?? 2021;
    final pricingType = item['pricingType'] as String? ?? 'sale';
    final isVerified = item['isVerified'] == true;
    final isFavorited = _favoritedListingIds.contains(id);

    final isDaily = pricingType == 'daily';
    final tagLabel = isDaily ? 'For Hire' : 'For Sale';
    final tagColor = isDaily ? const Color(0xFF2563EB) : AppColors.emerald;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _navigateToVehicle(item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vehicle Image Stack
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: VxNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  if (isVerified)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.emerald,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.check, size: 12, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'Verified',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () => _toggleFavorite(id),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 16,
                          color: isFavorited ? AppColors.error : AppColors.obsidian,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: tagColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tagLabel,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Card Details
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Price
                    Text(
                      isDaily
                          ? '$currency ${_currencyFormat.format(price)}/day'
                          : '$currency ${_currencyFormat.format(price)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Title
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Location
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 13, color: AppColors.gray400),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Specs row: Year, Fuel, Transmission
                    Row(
                      children: [
                        _buildSpecIcon(Icons.calendar_today_outlined, '$year'),
                        const SizedBox(width: 10),
                        _buildSpecIcon(Icons.local_gas_station_outlined, 'Diesel'),
                        const SizedBox(width: 10),
                        _buildSpecIcon(Icons.settings_outlined, 'Auto'),
                      ],
                    ),
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
        Icon(icon, size: 12.5, color: AppColors.gray500),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // REAL AGENT & DEALER CARD (Matches Visual Reference)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildAgentCard(Map<String, dynamic> agent) {
    final id = agent['id'] as String? ?? '';
    final name = agent['name'] as String? ?? 'Professional';
    final role = agent['role'] as String? ?? 'Real Estate Agent';
    final avatarUrl = agent['avatarUrl'] as String?;
    final isVerified = agent['isVerified'] == true;
    final listingsCount = (agent['listingsCount'] as num?)?.toInt() ?? 0;
    final isFollowing = _followingUserIds.contains(id);

    return Container(
      width: 175,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Avatar
          GestureDetector(
            onTap: () => _navigateToAgent(id),
            child: VektoluxAvatar(
              avatarUrl: avatarUrl,
              name: name,
              radius: 26,
              borderColor: isVerified ? AppColors.emerald : AppColors.border,
              borderWidth: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          // Name with Verified Checkmark
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                  ),
                ),
              ),
              if (isVerified) ...[
                const SizedBox(width: 3),
                const Icon(Icons.verified, size: 14, color: AppColors.emerald),
              ],
            ],
          ),
          const SizedBox(height: 2),
          // Role Subtitle
          Text(
            role,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: role.toLowerCase().contains('auto')
                  ? const Color(0xFF2563EB)
                  : AppColors.emeraldDark,
            ),
          ),
          const SizedBox(height: 2),
          // Listings Count
          Text(
            '$listingsCount+ listings',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          // Follow Button
          SizedBox(
            width: double.infinity,
            height: 30,
            child: isFollowing
                ? ElevatedButton(
                    onPressed: () => _toggleFollow(id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      'Following ✓',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  )
                : OutlinedButton(
                    onPressed: () => _toggleFollow(id),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.emerald, width: 1.2),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Follow',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.emerald,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // SKELETON / SHIMMER LOADERS
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHorizontalSkeletonCarousel() {
    return SizedBox(
      height: 270,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          return Container(
            width: 250,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 90,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppColors.gray200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 160,
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.gray100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 120,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.gray100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAgentsSkeletonRow() {
    return SizedBox(
      height: 185,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return Container(
            width: 175,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 90,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.gray200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 70,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // ERROR BANNER
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildErrorBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.errorLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _loadError ?? 'Unable to sync Explore feed.',
                style: const TextStyle(fontSize: 13, color: AppColors.error),
              ),
            ),
            TextButton(
              onPressed: _loadExploreData,
              child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
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
