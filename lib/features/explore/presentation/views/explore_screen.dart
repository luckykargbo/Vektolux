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
import '../../../social/presentation/views/public_profile_screen.dart';

class ExploreScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;

  const ExploreScreen({
    super.key,
    required this.convexClient,
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  String _selectedCategory = 'All';
  bool _isLoading = true;
  bool _isSearching = false;
  String _searchQuery = '';

  // Data collections from real database
  List<Map<String, dynamic>> _recommended = [];
  List<Map<String, dynamic>> _propertiesNearYou = [];
  List<Map<String, dynamic>> _vehiclesForSaleAndHire = [];
  List<Map<String, dynamic>> _topAgentsAndDealers = [];

  // Live search result lists
  List<Map<String, dynamic>> _searchProperties = [];
  List<Map<String, dynamic>> _searchVehicles = [];
  List<Map<String, dynamic>> _searchAgents = [];

  // Followed agents set for immediate UI updates
  final Set<String> _followingUserIds = {};

  final List<String> _categories = [
    'All',
    'Properties',
    'Vehicles',
    'Agents',
    'Dealers',
    'Rentals',
  ];

  @override
  void initState() {
    super.initState();
    _loadExploreData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadExploreData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

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
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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

  Future<void> _toggleFollow(String targetUserId) async {
    final authState = context.read<AuthBloc>().state;
    final currentUserId = authState.user?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to follow agents & dealers.')),
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
        // Revert on error
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
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.emerald,
          backgroundColor: AppColors.surface,
          onRefresh: _loadExploreData,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── 1. HEADER ───────────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildHeader(),
              ),

              // ── 2. SEARCH BAR ───────────────────────────────────────
              SliverToBoxAdapter(
                child: _buildSearchBar(),
              ),

              // ── 3. CATEGORY SHORTCUTS ───────────────────────────────
              SliverToBoxAdapter(
                child: _buildCategoryShortcuts(),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 12),
              ),

              // ── DYNAMIC BODY: SEARCH RESULTS OR EXPLORE SECTIONS ───
              if (_isSearching)
                SliverToBoxAdapter(
                  child: _buildSearchResults(),
                )
              else if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.emerald,
                      ),
                    ),
                  ),
                )
              else ...[
                // ── 4. RECOMMENDED FOR YOU ─────────────────────────────
                if (_selectedCategory == 'All' ||
                    _selectedCategory == 'Properties' ||
                    _selectedCategory == 'Vehicles')
                  SliverToBoxAdapter(
                    child: _buildRecommendedSection(),
                  ),

                // ── 5. PROPERTIES NEAR YOU ─────────────────────────────
                if (_selectedCategory == 'All' ||
                    _selectedCategory == 'Properties' ||
                    _selectedCategory == 'Rentals')
                  SliverToBoxAdapter(
                    child: _buildPropertiesNearYouSection(),
                  ),

                // ── 6. VEHICLES FOR SALE & HIRE ────────────────────────
                if (_selectedCategory == 'All' ||
                    _selectedCategory == 'Vehicles' ||
                    _selectedCategory == 'Dealers' ||
                    _selectedCategory == 'Rentals')
                  SliverToBoxAdapter(
                    child: _buildVehiclesSection(),
                  ),

                // ── 7. TOP AGENTS & DEALERS ────────────────────────────
                if (_selectedCategory == 'All' ||
                    _selectedCategory == 'Agents' ||
                    _selectedCategory == 'Dealers')
                  SliverToBoxAdapter(
                    child: _buildTopAgentsSection(),
                  ),

                // ── 8. BUILD YOUR EXPLORE FEED ─────────────────────────
                SliverToBoxAdapter(
                  child: _buildPersonalizeFeedCard(),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 32),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 1. HEADER
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.obsidian,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Discover properties, vehicles, agents and more',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Notification Bell
          _buildCircleIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notifications are up to date.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // Filter / Settings
          _buildCircleIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filter & Preferences',
            onTap: () {
              _showQuickFilterSheet();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCircleIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
  // 2. SEARCH
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.white,
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
                : IconButton(
                    icon: const Icon(Icons.tune_rounded, size: 20, color: AppColors.emerald),
                    onPressed: _showQuickFilterSheet,
                  ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 3. CATEGORY SHORTCUTS (Permanent Pills)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildCategoryShortcuts() {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _onCategorySelected(cat),
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.emerald : AppColors.white,
                    borderRadius: BorderRadius.circular(22),
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
                      cat,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppColors.white : const Color(0xFF4B5563),
                      ),
                    ),
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
  // 4. RECOMMENDED FOR YOU
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildRecommendedSection() {
    final hasData = _recommended.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Recommended for You',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Based on your interests',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.emeraldDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData)
            _buildEmptyCard(
              icon: Icons.auto_awesome_outlined,
              title: 'No recommendations yet',
              description:
                  'As you explore and interact with listings, we’ll recommend properties and vehicles tailored to your taste.',
              buttonLabel: 'Start Exploring',
              onButtonPressed: () {
                _onCategorySelected('All');
                _scrollToTop();
              },
            )
          else
            SizedBox(
              height: 240,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recommended.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = _recommended[index];
                  return _buildRecommendedCard(item);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecommendedCard(Map<String, dynamic> item) {
    final title = item['title'] ?? 'Listing';
    final subtitle = item['subtitle'] ?? '';
    final price = item['price'] ?? 0;
    final currency = item['currency'] ?? 'SLE';
    final imageUrl = item['imageUrl'] as String?;
    final location = item['location'] ?? 'Sierra Leone';
    final ownerName = item['ownerName'] ?? 'Verified Partner';
    final isVerified = item['isVerified'] == true;

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppColors.white,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: VxNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
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
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '$currency ${_currencyFormat.format(price)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.emeraldDark,
                      ),
                    ),
                    const Spacer(),
                    if (isVerified)
                      const Icon(Icons.verified, size: 14, color: AppColors.emerald),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 12, color: AppColors.gray500),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.gray500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.person_pin, size: 12, color: AppColors.gray500),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.gray600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
    final hasData = _propertiesNearYou.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Properties Near You',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                  letterSpacing: -0.3,
                ),
              ),
              InkWell(
                onTap: () => MainNavigationShell.switchToTab(context, 2),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'View All →',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.emeraldDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData)
            _buildEmptyCard(
              icon: Icons.apartment_outlined,
              title: 'No properties nearby yet',
              description:
                  'New houses, apartments, and land in Sierra Leone will appear here as agents publish listings.',
              buttonLabel: 'Browse Real Estate Market',
              onButtonPressed: () {
                MainNavigationShell.switchToTab(context, 2);
              },
            )
          else
            SizedBox(
              height: 240,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _propertiesNearYou.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final prop = _propertiesNearYou[index];
                  return _buildPropertyCard(prop);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPropertyCard(Map<String, dynamic> prop) {
    final title = prop['title'] ?? 'Property';
    final price = prop['price'] ?? 0;
    final currency = prop['currency'] ?? 'SLE';
    final imageUrl = prop['imageUrl'] as String?;
    final city = prop['city'] ?? 'Sierra Leone';
    final category = prop['category'] ?? 'House';
    final beds = prop['bedrooms'];
    final baths = prop['bathrooms'];

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: VxNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
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
                  category,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$currency ${_currencyFormat.format(price)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.emeraldDark,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 12, color: AppColors.gray500),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.gray500,
                        ),
                      ),
                    ),
                    if (beds != null) ...[
                      const Icon(Icons.bed_outlined, size: 12, color: AppColors.gray500),
                      const SizedBox(width: 2),
                      Text('$beds', style: const TextStyle(fontSize: 11, color: AppColors.gray500)),
                      const SizedBox(width: 6),
                    ],
                    if (baths != null) ...[
                      const Icon(Icons.bathtub_outlined, size: 12, color: AppColors.gray500),
                      const SizedBox(width: 2),
                      Text('$baths', style: const TextStyle(fontSize: 11, color: AppColors.gray500)),
                    ],
                  ],
                ),
              ],
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
    final hasData = _vehiclesForSaleAndHire.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Vehicles for Sale & Hire',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                  letterSpacing: -0.3,
                ),
              ),
              InkWell(
                onTap: () => MainNavigationShell.switchToTab(context, 3),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'View All →',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.emeraldDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData)
            _buildEmptyCard(
              icon: Icons.directions_car_outlined,
              title: 'No vehicles available yet',
              description:
                  'Cars, commercial trucks, and rentals from trusted dealers will be listed here soon.',
              buttonLabel: 'Explore Auto Marketplace',
              onButtonPressed: () {
                MainNavigationShell.switchToTab(context, 3);
              },
            )
          else
            SizedBox(
              height: 240,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _vehiclesForSaleAndHire.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final v = _vehiclesForSaleAndHire[index];
                  return _buildVehicleCard(v);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final title = v['title'] ?? 'Vehicle';
    final price = v['price'] ?? 0;
    final currency = v['currency'] ?? 'SLE';
    final pricingType = v['pricingType'] ?? 'total_sale';
    final imageUrl = v['imageUrl'] as String?;
    final location = v['location'] ?? 'Sierra Leone';
    final year = v['year'];
    final make = v['make'] ?? '';
    final model = v['model'] ?? '';

    final displaySpecs = [
      if (year != null) '$year',
      if (make.isNotEmpty) make,
      if (model.isNotEmpty) model,
    ].join(' ');

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: VxNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
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
                  displaySpecs.isNotEmpty ? displaySpecs : 'Commercial Vehicle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '$currency ${_currencyFormat.format(price)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.emeraldDark,
                      ),
                    ),
                    if (pricingType == 'per_day')
                      const Text(
                        ' /day',
                        style: TextStyle(fontSize: 10, color: AppColors.gray500),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 12, color: AppColors.gray500),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.gray500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
    final hasData = _topAgentsAndDealers.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Top Agents & Dealers',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                  letterSpacing: -0.3,
                ),
              ),
              InkWell(
                onTap: () {
                  _onCategorySelected('Agents');
                },
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'See All',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.emeraldDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData)
            _buildEmptyCard(
              icon: Icons.people_outline_rounded,
              title: 'No agents or dealers yet',
              description:
                  'Verified real estate agents and vehicle dealers will be showcased here.',
            )
          else
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _topAgentsAndDealers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final agent = _topAgentsAndDealers[index];
                  return _buildAgentCard(agent);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAgentCard(Map<String, dynamic> agent) {
    final id = agent['id'] ?? '';
    final name = agent['name'] ?? 'Agent';
    final role = agent['role'] ?? 'Partner';
    final businessName = agent['businessName'];
    final avatarUrl = agent['avatarUrl'] as String?;
    final isVerified = agent['isVerified'] == true;
    final listingsCount = agent['listingsCount'] ?? 0;
    final isFollowing = _followingUserIds.contains(id);

    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _navigateToAgent(id),
            child: Stack(
              children: [
                VektoluxAvatar(
                  avatarUrl: avatarUrl,
                  name: name,
                  radius: 26,
                  borderColor: isVerified ? AppColors.emerald : AppColors.border,
                  borderWidth: 1.5,
                ),
                if (isVerified)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified,
                        size: 14,
                        color: AppColors.emerald,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            businessName ?? name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            role,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$listingsCount Listings',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.gray500,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 32,
            child: OutlinedButton(
              onPressed: () => _toggleFollow(id),
              style: OutlinedButton.styleFrom(
                backgroundColor: isFollowing ? AppColors.emeraldSurface : Colors.transparent,
                side: BorderSide(
                  color: isFollowing ? AppColors.emerald : AppColors.border,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                isFollowing ? 'Following' : 'Follow',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isFollowing ? AppColors.emeraldDark : AppColors.obsidian,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // 8. BUILD YOUR EXPLORE FEED (Personalize promo card)
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildPersonalizeFeedCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5), // Soft green tint
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.emeraldLight.withValues(alpha: 0.5), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.emerald.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.explore_outlined,
                color: AppColors.emerald,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Personalize your experience',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Follow agents and dealers to personalize what you see.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () {
                _onCategorySelected('Agents');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Find Agents →',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // SHARED EMPTY CARD COMPONENT
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildEmptyCard({
    required IconData icon,
    required String title,
    required String description,
    String? buttonLabel,
    VoidCallback? onButtonPressed,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.gray50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Icon(
              icon,
              size: 24,
              color: AppColors.gray500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          if (buttonLabel != null && onButtonPressed != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onButtonPressed,
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.white,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.emeraldDark,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // SEARCH RESULTS VIEW
  // ═════════════════════════════════════════════════════════════════════
  Widget _buildSearchResults() {
    final totalResults =
        _searchProperties.length + _searchVehicles.length + _searchAgents.length;

    if (totalResults == 0) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: _buildEmptyCard(
          icon: Icons.search_off_rounded,
          title: 'No results found',
          description:
              'We could not find any properties, vehicles, or agents matching "$_searchQuery".',
          buttonLabel: 'Clear Search',
          onButtonPressed: () {
            _searchController.clear();
            _onSearchChanged('');
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Found $totalResults result${totalResults == 1 ? '' : 's'} for "$_searchQuery"',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.obsidian,
              ),
            ),
          ),
          if (_searchProperties.isNotEmpty) ...[
            const Text(
              'Properties',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 8),
            ..._searchProperties.map((p) => _buildPropertySearchTile(p)),
            const SizedBox(height: 16),
          ],
          if (_searchVehicles.isNotEmpty) ...[
            const Text(
              'Vehicles',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 8),
            ..._searchVehicles.map((v) => _buildVehicleSearchTile(v)),
            const SizedBox(height: 16),
          ],
          if (_searchAgents.isNotEmpty) ...[
            const Text(
              'Agents & Dealers',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 8),
            ..._searchAgents.map((a) => _buildAgentSearchTile(a)),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildPropertySearchTile(Map<String, dynamic> p) {
    final title = p['title'] ?? 'Property';
    final price = p['price'] ?? 0;
    final currency = p['currency'] ?? 'SLE';
    final city = p['city'] ?? 'Sierra Leone';
    final imageUrl = p['imageUrl'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
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
                  style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                ),
                const SizedBox(height: 2),
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
        ],
      ),
    );
  }

  Widget _buildVehicleSearchTile(Map<String, dynamic> v) {
    final title = v['title'] ?? 'Vehicle';
    final price = v['price'] ?? 0;
    final currency = v['currency'] ?? 'SLE';
    final location = v['location'] ?? 'Sierra Leone';
    final imageUrl = v['imageUrl'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
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
                  style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                ),
                const SizedBox(height: 2),
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
        ],
      ),
    );
  }

  Widget _buildAgentSearchTile(Map<String, dynamic> a) {
    final id = a['id'] ?? '';
    final name = a['name'] ?? 'Agent';
    final role = a['role'] ?? 'Partner';
    final avatarUrl = a['avatarUrl'] as String?;
    final isVerified = a['isVerified'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
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
                  style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => _navigateToAgent(id),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('View Profile', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════
  // QUICK FILTER SHEET
  // ═════════════════════════════════════════════════════════════════════
  void _showQuickFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.gray300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Filter by Category',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories.map((c) {
                    final isSel = _selectedCategory == c;
                    return ChoiceChip(
                      label: Text(c),
                      selected: isSel,
                      selectedColor: AppColors.emerald,
                      labelStyle: TextStyle(
                        color: isSel ? AppColors.white : AppColors.obsidian,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      ),
                      onSelected: (_) {
                        Navigator.pop(ctx);
                        _onCategorySelected(c);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
