// lib/features/real_estate/presentation/views/real_estate_marketplace_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Production Real Estate Marketplace Screen
// Sierra Leone property marketplace with location-based browsing,
// privacy-first broad locations, verified agent cards, and full
// lifecycle states (loading, empty, data, error).
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vx_network_image.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../listings/presentation/views/create_listing_screen.dart';
import '../../../listings/presentation/views/property_detail_screen.dart';
import 'my_real_estate_escrows_screen.dart';

class RealEstateMarketplaceScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;

  const RealEstateMarketplaceScreen({
    super.key,
    required this.convexClient,
  });

  @override
  State<RealEstateMarketplaceScreen> createState() =>
      _RealEstateMarketplaceScreenState();
}

class _RealEstateMarketplaceScreenState
    extends State<RealEstateMarketplaceScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');
  Timer? _searchDebounce;

  // ── State ─────────────────────────────────────────────────────────
  bool _isLoading = true;
  String? _loadError;
  List<Map<String, dynamic>> _allListings = [];

  // Category tabs: 0=All, 1=For Rent, 2=For Sale, 3=Guest Houses
  int _selectedTabIndex = 0;

  // Property type filter chips
  String _selectedPropertyType = 'All Types';

  // Location selector (broad area only — NO exact addresses)
  String _selectedLocation = 'Freetown';

  // Search
  String _searchQuery = '';

  // Favorites (optimistic local state)
  final Set<String> _favoritedIds = {};

  // Sierra Leone Towns & Districts
  static const List<String> _sierraLeoneTowns = [
    'All Sierra Leone',
    'Freetown',
    'Bo',
    'Kenema',
    'Makeni',
    'Kailahun',
    'Pujehun',
    'Bombali',
    'Kono',
    'Port Loko',
    'Kambia',
    'Moyamba',
    'Tonkolili',
    'Bonthe',
    'Koinadugu',
    'Falaba',
    'Karene',
  ];

  // Category tabs matching the reference
  static const List<String> _tabs = [
    'All Properties',
    'For Rent',
    'For Sale',
    'Guest Houses',
  ];

  // Property type filter chips
  static const List<String> _propertyTypes = [
    'All Types',
    'House',
    'Apartment',
    'Guest House',
    'Land',
    'Commercial',
  ];

  @override
  void initState() {
    super.initState();
    // Use user's region preference as default location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthBloc>().state.user;
      if (user?.region != null && user!.region!.isNotEmpty) {
        final match = _sierraLeoneTowns.firstWhere(
          (t) => user.region!.toLowerCase().contains(t.toLowerCase()),
          orElse: () => 'Freetown',
        );
        setState(() => _selectedLocation = match);
      }
      _fetchProperties();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Fetch Real Properties from Convex Backend ─────────────────────
  Future<void> _fetchProperties() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final res = await widget.convexClient.query(
        'realEstate:listProperties',
        args: {'limit': 50},
      );

      if (res.success && res.value is List) {
        if (mounted) {
          setState(() {
            _allListings = (res.value as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _isLoading = false;
            _loadError = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadError = res.errorMessage ?? 'Could not load properties';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Connection failed. Please check your network.';
        });
      }
    }
  }

  // ── Multi-Layered Client-Side Filtering ───────────────────────────
  List<Map<String, dynamic>> _getFilteredListings() {
    return _allListings.where((item) {
      final category = (item['category'] as String? ?? '').toLowerCase();
      final title = (item['title'] as String? ?? '').toLowerCase();
      final city = (item['city'] as String? ?? '').toLowerCase();
      final propertyType = (item['propertyType'] as String? ?? '').toLowerCase();
      final description = (item['description'] as String? ?? '').toLowerCase();

      // 1. Tab category filter
      if (_selectedTabIndex == 1) {
        // For Rent
        if (category != 'long_term_rent' && category != 'rent') return false;
      } else if (_selectedTabIndex == 2) {
        // For Sale
        if (category != 'sale') return false;
      } else if (_selectedTabIndex == 3) {
        // Guest Houses
        if (category != 'hourly_guesthouse' && category != 'guesthouse') {
          return false;
        }
      }

      // 2. Location filter (broad town/city only)
      if (_selectedLocation != 'All Sierra Leone') {
        final locLower = _selectedLocation.toLowerCase();
        if (!city.contains(locLower) &&
            !title.contains(locLower) &&
            !description.contains(locLower)) {
          return false;
        }
      }

      // 3. Property type filter chips
      if (_selectedPropertyType != 'All Types') {
        final typeLower = _selectedPropertyType.toLowerCase();
        if (typeLower == 'house') {
          if (!propertyType.contains('house') &&
              !title.contains('house') &&
              !title.contains('bedroom') &&
              !title.contains('family')) {
            return false;
          }
        } else if (typeLower == 'apartment') {
          if (!propertyType.contains('apartment') &&
              !title.contains('apartment') &&
              !title.contains('flat') &&
              !title.contains('studio')) {
            return false;
          }
        } else if (typeLower == 'guest house') {
          if (category != 'hourly_guesthouse' &&
              category != 'guesthouse' &&
              !title.contains('guest')) {
            return false;
          }
        } else if (typeLower == 'land') {
          if (!propertyType.contains('land') &&
              !title.contains('land') &&
              !title.contains('plot')) {
            return false;
          }
        } else if (typeLower == 'commercial') {
          if (!propertyType.contains('commercial') &&
              !title.contains('commercial') &&
              !title.contains('office') &&
              !title.contains('shop')) {
            return false;
          }
        }
      }

      // 4. Search query filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!title.contains(q) &&
            !city.contains(q) &&
            !description.contains(q) &&
            !propertyType.contains(q) &&
            !category.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _searchQuery = query.trim());
      }
    });
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (_favoritedIds.contains(id)) {
        _favoritedIds.remove(id);
      } else {
        _favoritedIds.add(id);
      }
    });
  }

  // ── Navigation Helpers ──────────────────────────────────────────────
  void _navigateToPropertyDetail(Map<String, dynamic> item) {
    final id = item['_id'] as String? ?? '';
    final title = item['title'] as String? ?? 'Property';
    final desc = item['description'] as String? ?? title;
    final category = item['category'] as String? ?? 'long_term_rent';
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final hourlyRate = (item['hourlyRate'] as num?)?.toDouble();
    final city = item['city'] as String? ?? _selectedLocation;
    final broadLocation = 'Inside $city, Sierra Leone';
    final ownerId = item['ownerId'] as String? ?? '';
    final images = (item['imageUrls'] as List?)?.cast<String>() ?? [];
    final beds = (item['bedrooms'] as num?)?.toInt();
    final baths = (item['bathrooms'] as num?)?.toInt();
    final sqm = (item['areaSqM'] as num?)?.toDouble();
    final amenities = (item['amenities'] as List?)?.cast<String>() ?? [];
    final isVerified = item['isVerified'] == true;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(
          id: id,
          title: title,
          description: desc,
          category: category,
          price: price,
          hourlyRate: hourlyRate,
          address: broadLocation, // PRIVACY: Only broad area
          latitude: 8.484,
          longitude: -13.234,
          imageUrls: images,
          ownerId: ownerId,
          bedrooms: beds,
          bathrooms: baths,
          squareMeters: sqm,
          amenities: amenities,
          isVerified: isVerified,
        ),
      ),
    );
  }

  Future<void> _openCreateListing() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to publish property listings.'),
          backgroundColor: AppColors.obsidian,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!user.canPostRealEstate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verified Real Estate Agent or Seller status required to publish properties.'),
          backgroundColor: AppColors.obsidian,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateListingScreen(
          convexClient: widget.convexClient,
          currentUser: user,
        ),
      ),
    );

    if (res == true) {
      _fetchProperties();
    }
  }


  // ═════════════════════════════════════════════════════════════════════
  //                         BUILD
  // ═════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthBloc>().state.user;
    final canPost = user != null && user.canPostRealEstate;
    final filtered = _getFilteredListings();

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.emeraldDark,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_home_work_rounded),
              label: const Text(
                'List Property',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: _openCreateListing,
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── 1. HEADER ──────────────────────────────────────────
            _buildHeader(user),

            // ── Agent Verification Status Banners ──────────────────
            if (user != null && user.role == UserRole.agent) ...[
              if (user.isPendingVerification) _buildPendingBanner(),
              if (user.isRejectedVerification)
                _buildRejectedBanner(user.rejectionReason),
            ],

            // ── 2. CATEGORY TABS ───────────────────────────────────
            _buildCategoryTabs(),

            // ── SCROLLABLE BODY ────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                color: AppColors.emerald,
                backgroundColor: Colors.white,
                onRefresh: _fetchProperties,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ── 3. SEARCH BAR ──────────────────────────────
                    SliverToBoxAdapter(child: _buildSearchRow()),

                    // ── 4. LOCATION SELECTOR ───────────────────────
                    SliverToBoxAdapter(child: _buildLocationSelector()),

                    // ── 5. PROPERTY TYPE CHIPS ─────────────────────
                    SliverToBoxAdapter(child: _buildPropertyTypeChips()),

                    const SliverToBoxAdapter(child: SizedBox(height: 10)),

                    // ── 6. FEATURED PROPERTIES SECTION HEADER ──────
                    SliverToBoxAdapter(child: _buildFeaturedSectionHeader()),

                    const SliverToBoxAdapter(child: SizedBox(height: 12)),

                    // ── 7. PROPERTY CARDS GRID / EMPTY STATE ───────
                    if (_loadError != null)
                      SliverToBoxAdapter(child: _buildErrorState())
                    else if (_isLoading)
                      SliverToBoxAdapter(child: _buildLoadingSkeletons())
                    else if (filtered.isEmpty)
                      SliverToBoxAdapter(child: _buildEmptyState())
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return _buildPropertyCard(filtered[index]);
                            },
                            childCount: filtered.length,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.54,
                          ),
                        ),
                      ),

                    const SliverToBoxAdapter(child: SizedBox(height: 90)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 1. HEADER
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHeader(UserEntity? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: [
          // Shield Logo
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.emeraldSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 22,
              color: AppColors.emerald,
            ),
          ),
          const SizedBox(width: 10),
          // Title
          const Expanded(
            child: Text(
              'Real Estate',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: AppColors.obsidian,
              ),
            ),
          ),
          // Notification Icon
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
          const SizedBox(width: 8),
          // Profile / Escrows
          _buildHeaderIconButton(
            icon: Icons.person_outline_rounded,
            tooltip: 'My Escrows',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MyRealEstateEscrowsScreen(),
                ),
              );
            },
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
      width: 42,
      height: 42,
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
          child: Icon(icon, size: 20, color: AppColors.obsidian),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // VERIFICATION STATUS BANNERS
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPendingBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        children: [
          Icon(Icons.hourglass_top_rounded, size: 16, color: Color(0xFFD97706)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your business verification is under review. Listing features are restricted.',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedBanner(String? reason) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Verification rejected: ${reason ?? "Document not accepted"}. Please update and resubmit.',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 2. HORIZONTAL CATEGORY TABS
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildCategoryTabs() {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedTabIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedTabIndex = index),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? AppColors.emerald : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
              child: Text(
                _tabs[index],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.emerald : AppColors.gray400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 3. SEARCH BAR ROW
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildSearchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 50,
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
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search homes, apartments, guest houses...',
                  hintStyle: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.gray400,
                    fontWeight: FontWeight.w400,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.gray400, size: 22),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.gray500),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Green Filter Button
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _showAdvancedFilterSheet,
                child: const Center(
                  child: Icon(Icons.tune_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 4. LOCATION SELECTOR
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildLocationSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4), // Very light emerald
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD1FAE5), width: 1),
        ),
        child: Row(
          children: [
            // Location Pin Icon
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.emerald,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.place_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            // Text Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Showing properties in',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: _showLocationPicker,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_selectedLocation, Sierra Leone',
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.obsidian,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded,
                            size: 20, color: AppColors.obsidian),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Change Location Button
            OutlinedButton.icon(
              onPressed: _showLocationPicker,
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: const Text('Change Location'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.emerald,
                side: const BorderSide(color: AppColors.emerald, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 5. PROPERTY TYPE FILTER CHIPS
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPropertyTypeChips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _propertyTypes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final type = _propertyTypes[index];
          final isSelected = _selectedPropertyType == type;

          return GestureDetector(
            onTap: () => setState(() => _selectedPropertyType = type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.emerald : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.emerald : AppColors.border,
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.emerald.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  type,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : AppColors.obsidian,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 6. FEATURED PROPERTIES SECTION HEADER
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildFeaturedSectionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, size: 20, color: AppColors.emerald),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Featured Properties',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.obsidian,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Verified and trusted properties from across Sierra Leone.',
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
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All verified properties are shown below.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
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
                  Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.emerald),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 7. PROPERTY CARD (Matches Visual Reference — 2-Column Grid)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPropertyCard(Map<String, dynamic> item) {
    final id = item['_id'] as String? ?? '';
    final title = item['title'] as String? ?? 'Property';
    final price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final hourlyRate = (item['hourlyRate'] as num?)?.toDouble();
    final currency = item['currency'] as String? ?? 'SLE';
    final images = (item['imageUrls'] as List?)?.cast<String>() ?? [];
    final imageUrl = images.isNotEmpty ? images.first : null;
    final city = item['city'] as String? ?? _selectedLocation;
    final beds = (item['bedrooms'] as num?)?.toInt() ?? 0;
    final baths = (item['bathrooms'] as num?)?.toInt() ?? 0;
    final parking = (item['parking'] as num?)?.toInt() ?? 0;
    final category = item['category'] as String? ?? 'long_term_rent';
    final isVerified = item['isVerified'] == true;
    final isFavorited = _favoritedIds.contains(id);

    // Determine listing type label
    final isGuesthouse =
        category == 'hourly_guesthouse' || category == 'guesthouse';
    final isSale = category == 'sale';
    final listingLabel = isGuesthouse
        ? 'Guest House'
        : isSale
            ? 'For Sale'
            : 'For Rent';
    final listingLabelColor = isSale
        ? const Color(0xFFEA580C) // Warm orange for sale
        : AppColors.emerald;

    // Determine property type label
    String propertyTypeLabel = 'House';
    if (isGuesthouse) {
      propertyTypeLabel = 'Guest House';
    } else if (title.toLowerCase().contains('apartment') ||
        title.toLowerCase().contains('flat')) {
      propertyTypeLabel = 'Apartment';
    } else if (title.toLowerCase().contains('land') ||
        title.toLowerCase().contains('plot')) {
      propertyTypeLabel = 'Land';
    } else if (title.toLowerCase().contains('commercial') ||
        title.toLowerCase().contains('office')) {
      propertyTypeLabel = 'Commercial';
    }

    // Price display
    String priceDisplay;
    if (price <= 0) {
      priceDisplay = 'Price on request';
    } else if (isGuesthouse && hourlyRate != null && hourlyRate > 0) {
      priceDisplay = '$currency ${_currencyFormat.format(hourlyRate)} / hour';
    } else if (isSale) {
      priceDisplay = '$currency ${_currencyFormat.format(price)}';
    } else {
      priceDisplay = '$currency ${_currencyFormat.format(price)} / year';
    }

    // PRIVACY: Broad location only
    final broadLocation = 'Inside $city, Sierra Leone';

    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── IMAGE CONTAINER ──────────────────────────────────────
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: VxNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      fallbackIcon: Icons.home_work_rounded,
                      fallbackLabel: 'VEKTOLUX',
                    ),
                  ),
                ),
                // Verified Badge
                if (isVerified)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.emerald,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.check_circle, size: 11, color: Colors.white),
                          SizedBox(width: 3),
                          Text(
                            'Verified',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Favorite Heart
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => _toggleFavorite(id),
                    child: Container(
                      width: 28,
                      height: 28,
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
                        isFavorited
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 14,
                        color: isFavorited ? AppColors.error : AppColors.obsidian,
                      ),
                    ),
                  ),
                ),
                // Listing Type Badge (For Rent / For Sale)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: listingLabelColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      listingLabel,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── CARD DETAILS ─────────────────────────────────────────
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // PRIVACY: Broad Location Only
                  Row(
                    children: [
                      const Icon(Icons.place_outlined,
                          size: 12, color: AppColors.gray400),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          broadLocation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // Specs Row: Beds, Baths, Parking/Garage
                  Row(
                    children: [
                      if (beds > 0) ...[
                        _buildSmallSpec(Icons.bed_outlined, '$beds Beds'),
                        const SizedBox(width: 6),
                      ],
                      if (baths > 0) ...[
                        _buildSmallSpec(
                            Icons.bathtub_outlined, '$baths Baths'),
                        const SizedBox(width: 6),
                      ],
                      if (parking > 0)
                        _buildSmallSpec(Icons.garage_outlined,
                            '$parking Garage')
                      else if (!isGuesthouse)
                        _buildSmallSpec(
                            Icons.garage_outlined, '1 Garage'),
                    ],
                  ),
                  const Spacer(),
                  // Price
                  Text(
                    priceDisplay,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: price > 0
                          ? AppColors.emeraldDark
                          : AppColors.gray500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Bottom Row: Type Badge + View Details
                  Row(
                    children: [
                      // Property Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color:
                                AppColors.emerald.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          propertyTypeLabel,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // View Details Button
                      GestureDetector(
                        onTap: () => _navigateToPropertyDetail(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.emerald, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.visibility_outlined,
                                  size: 12, color: AppColors.emerald),
                              SizedBox(width: 3),
                              Text(
                                'View Details',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.emerald,
                                ),
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
          ),
        ],
      ),
    );
  }

  Widget _buildSmallSpec(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.gray500),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // LOADING SKELETON CARDS
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildLoadingSkeletons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 12,
          childAspectRatio: 0.54,
        ),
        itemCount: 4,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.gray100,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16)),
                    ),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.gray200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 100,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.gray100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 80,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.gray100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 90,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.gray200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
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
  // EMPTY STATE (New User / No Listings)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildEmptyState() {
    final hasActiveFilters = _selectedPropertyType != 'All Types' ||
        _selectedTabIndex != 0 ||
        _searchQuery.isNotEmpty;

    final isFilteredEmpty = hasActiveFilters && _allListings.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.emerald.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.home_work_outlined,
              size: 30,
              color: AppColors.emerald,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isFilteredEmpty
                ? 'No properties match your filters'
                : _selectedLocation == 'All Sierra Leone'
                    ? 'No properties available yet'
                    : 'No properties available in $_selectedLocation yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isFilteredEmpty
                ? 'Try changing your location, property type, or category filters.'
                : 'Verified homes and rentals will appear here as agents and owners begin listing.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (hasActiveFilters)
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _selectedPropertyType = 'All Types';
                      _selectedTabIndex = 0;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.emerald),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: const Text(
                    'Clear Filters',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.emerald),
                  ),
                ),
              if (hasActiveFilters) const SizedBox(width: 10),
              if (_selectedLocation != 'All Sierra Leone')
                ElevatedButton(
                  onPressed: _showLocationPicker,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: const Text(
                    'Change Location',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // ERROR STATE
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_off_outlined, size: 28, color: AppColors.error),
          ),
          const SizedBox(height: 14),
          Text(
            _loadError ?? 'Unable to load properties',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _fetchProperties,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // LOCATION PICKER (Bottom Sheet)
  // ═════════════════════════════════════════════════════════════════════
  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.85,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
                    const Text(
                      'Choose Property Location',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Select a town or district to browse properties.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController,
                        itemCount: _sierraLeoneTowns.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: AppColors.gray100),
                        itemBuilder: (context, index) {
                          final town = _sierraLeoneTowns[index];
                          final isSelected = _selectedLocation == town ||
                              (town == 'All Sierra Leone' &&
                                  _selectedLocation == 'All Sierra Leone');
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.emeraldSurface
                                    : AppColors.gray50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                town == 'All Sierra Leone'
                                    ? Icons.public_rounded
                                    : Icons.place_rounded,
                                size: 18,
                                color: isSelected
                                    ? AppColors.emerald
                                    : AppColors.gray400,
                              ),
                            ),
                            title: Text(
                              town == 'All Sierra Leone'
                                  ? town
                                  : '$town, Sierra Leone',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.emerald
                                    : AppColors.obsidian,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle_rounded,
                                    color: AppColors.emerald, size: 22)
                                : null,
                            onTap: () {
                              setState(() => _selectedLocation = town);
                              Navigator.pop(ctx);
                            },
                          );
                        },
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
  // ADVANCED FILTER SHEET
  // ═════════════════════════════════════════════════════════════════════
  void _showAdvancedFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
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
                          'Filter Properties',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.obsidian,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {});
                            setState(() {
                              _selectedPropertyType = 'All Types';
                              _selectedTabIndex = 0;
                              _searchQuery = '';
                              _searchController.clear();
                              _selectedLocation = 'Freetown';
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text(
                            'Clear All',
                            style: TextStyle(color: AppColors.emerald, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Location
                    const Text('Location', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _sierraLeoneTowns.take(8).map((t) {
                        final isSel = _selectedLocation == t;
                        return ChoiceChip(
                          label: Text(t, style: TextStyle(fontSize: 11)),
                          selected: isSel,
                          selectedColor: AppColors.emerald,
                          backgroundColor: AppColors.gray50,
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : AppColors.obsidian,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          ),
                          onSelected: (_) {
                            setModalState(() {});
                            setState(() => _selectedLocation = t);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    // Property Type
                    const Text('Property Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _propertyTypes.map((t) {
                        final isSel = _selectedPropertyType == t;
                        return ChoiceChip(
                          label: Text(t, style: TextStyle(fontSize: 11)),
                          selected: isSel,
                          selectedColor: AppColors.emerald,
                          backgroundColor: AppColors.gray50,
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : AppColors.obsidian,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          ),
                          onSelected: (_) {
                            setModalState(() {});
                            setState(() => _selectedPropertyType = t);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    // Listing Category
                    const Text('Listing Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _tabs.asMap().entries.map((e) {
                        final isSel = _selectedTabIndex == e.key;
                        return ChoiceChip(
                          label: Text(e.value, style: TextStyle(fontSize: 11)),
                          selected: isSel,
                          selectedColor: AppColors.emerald,
                          backgroundColor: AppColors.gray50,
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : AppColors.obsidian,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          ),
                          onSelected: (_) {
                            setModalState(() {});
                            setState(() => _selectedTabIndex = e.key);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
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
}
