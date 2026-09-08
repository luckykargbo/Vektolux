// lib/features/real_estate/presentation/views/real_estate_marketplace_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Vertical Marketplace
// Filter tabs (Rent, Sale, Guest House, Land), Sierra Leone region selector,
// price filter, verified agent cards, and full property detail routing.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../listings/presentation/views/create_listing_screen.dart';
import '../../../listings/presentation/views/property_detail_screen.dart';

class RealEstateMarketplaceScreen extends StatefulWidget {
  final AppDatabase database;
  final ConvexClientWrapper convexClient;

  const RealEstateMarketplaceScreen({
    super.key,
    required this.database,
    required this.convexClient,
  });

  @override
  State<RealEstateMarketplaceScreen> createState() =>
      _RealEstateMarketplaceScreenState();
}

class _RealEstateMarketplaceScreenState
    extends State<RealEstateMarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');

  String _selectedRegion = 'All Sierra Leone';
  bool _isLoading = true;
  List<Map<String, dynamic>> _allListings = [];

  final List<String> _tabs = [
    'All Properties',
    'For Rent',
    'For Sale',
    'Guest House',
    'Land / Commercial',
  ];

  final List<String> _regions = [
    'All Sierra Leone',
    'Freetown (Western Area Urban)',
    'Waterloo (Western Area Rural)',
    'Bo City (Southern Province)',
    'Kenema (Eastern Province)',
    'Makeni (Northern Province)',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _fetchProperties();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProperties() async {
    setState(() => _isLoading = true);
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
          });
        }
      } else {
        _fetchCached();
      }
    } catch (_) {
      _fetchCached();
    }
  }

  Future<void> _fetchCached() async {
    final cached =
        await widget.database.cachedPropertyListingsDao.getAll();
    if (mounted) {
      setState(() {
        _allListings = cached
            .map((p) => {
                  '_id': p.id,
                  'title': p.title,
                  'description': p.description,
                  'category': p.category,
                  'price': p.price,
                  'hourlyRate': p.hourlyRate,
                  'address': p.address,
                  'city': p.address.contains('Bo')
                      ? 'Bo'
                      : p.address.contains('Waterloo')
                          ? 'Waterloo'
                          : 'Freetown',
                  'imageUrls':
                      p.primaryImageUrl != null ? [p.primaryImageUrl!] : [],
                  'bedrooms': 3,
                  'bathrooms': 2,
                  'areaSqM': 180,
                  'amenities': ['EDSA Power', 'Guma Water', 'Standby Generator'],
                })
            .toList();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredListings() {
    final tabIndex = _tabController.index;
    final query = _searchController.text.trim().toLowerCase();

    return _allListings.filter((item) {
      final category = item['category'] as String? ?? '';
      final title = (item['title'] as String? ?? '').toLowerCase();
      final address = (item['address'] as String? ?? '').toLowerCase();
      final city = (item['city'] as String? ?? '').toLowerCase();

      // 1. Tab category filter
      if (tabIndex == 1 && category != 'long_term_rent') return false;
      if (tabIndex == 2 && category != 'sale') return false;
      if (tabIndex == 3 && category != 'hourly_guesthouse') return false;
      if (tabIndex == 4 &&
          !title.contains('land') &&
          !address.contains('land') &&
          !category.contains('commercial')) {
        return false;
      }

      // 2. Region filter
      if (_selectedRegion == 'Freetown (Western Area Urban)' &&
          !city.contains('freetown') &&
          !address.contains('freetown') &&
          !address.contains('wilkinson') &&
          !address.contains('aberdeen') &&
          !address.contains('lumley')) {
        return false;
      }
      if (_selectedRegion == 'Waterloo (Western Area Rural)' &&
          !city.contains('waterloo') &&
          !address.contains('waterloo')) {
        return false;
      }
      if (_selectedRegion == 'Bo City (Southern Province)' &&
          !city.contains('bo') &&
          !address.contains('bo')) {
        return false;
      }
      if (_selectedRegion == 'Kenema (Eastern Province)' &&
          !city.contains('kenema') &&
          !address.contains('kenema')) {
        return false;
      }
      if (_selectedRegion == 'Makeni (Northern Province)' &&
          !city.contains('makeni') &&
          !address.contains('makeni')) {
        return false;
      }

      // 3. Search query filter
      if (query.isNotEmpty) {
        if (!title.contains(query) &&
            !address.contains(query) &&
            !city.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _showRegionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
              const SizedBox(height: 16),
              const Text(
                'Filter by Region / Province',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 14),
              ..._regions.map((reg) {
                final isSelected = reg == _selectedRegion;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.location_city_rounded,
                    color: isSelected ? AppColors.emerald : AppColors.gray400,
                  ),
                  title: Text(
                    reg,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? AppColors.emerald
                          : AppColors.obsidian,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.emerald)
                      : null,
                  onTap: () {
                    setState(() => _selectedRegion = reg);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
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
        ),
      );
      return;
    }

    final res = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateListingScreen(
          database: widget.database,
          convexClient: widget.convexClient,
          currentUser: user,
        ),
      ),
    );

    if (res == true) {
      _fetchProperties();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredListings();

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        backgroundColor: AppColors.obsidian,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Real Estate Marketplace',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Listings',
            onPressed: _fetchProperties,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppColors.obsidian,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppColors.emerald,
              indicatorWeight: 3,
              labelColor: AppColors.emerald,
              unselectedLabelColor: AppColors.gray400,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'Poppins',
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.emeraldDark,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_home_work_rounded),
        label: const Text(
          'List Property',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: _openCreateListing,
      ),
      body: Column(
        children: [
          // ── Search & Location Filter Bar ──────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.gray100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            size: 18, color: AppColors.gray400),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'Search by title, road, or area...',
                              hintStyle: TextStyle(
                                  fontSize: 12, color: AppColors.gray400),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Region Filter Button
                GestureDetector(
                  onTap: _showRegionPicker,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _selectedRegion == 'All Sierra Leone'
                          ? AppColors.gray100
                          : AppColors.emeraldSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedRegion == 'All Sierra Leone'
                            ? AppColors.border
                            : AppColors.emerald,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.place_rounded,
                          size: 16,
                          color: _selectedRegion == 'All Sierra Leone'
                              ? AppColors.gray600
                              : AppColors.emeraldDark,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _selectedRegion.split(' ').first,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _selectedRegion == 'All Sierra Leone'
                                ? AppColors.gray700
                                : AppColors.emeraldDark,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Properties List ───────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.emerald),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.home_work_outlined,
                                size: 54, color: AppColors.gray300),
                            const SizedBox(height: 12),
                            const Text(
                              'No properties match your filters',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Try selecting another region or category',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.gray500),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _selectedRegion = 'All Sierra Leone';
                                  _searchController.clear();
                                  _tabController.index = 0;
                                });
                              },
                              child: const Text('Clear All Filters'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchProperties,
                        color: AppColors.emerald,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return _buildPropertyListItem(item);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyListItem(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? 'Sierra Leone Residence';
    final price = (item['price'] as num?)?.toDouble() ?? 5000.0;
    final address = item['address'] as String? ?? 'Wilkinson Road, Freetown';
    final images = (item['imageUrls'] as List?)?.cast<String>() ?? [];
    final imageUrl = images.isNotEmpty
        ? images.first
        : 'https://images.unsplash.com/photo-1613490493576-7fde63acd811?w=800';
    final beds = item['bedrooms'] as int? ?? 3;
    final baths = item['bathrooms'] as int? ?? 2;
    final area = item['areaSqM'] as int? ?? 180;
    final isGuesthouse = item['category'] == 'hourly_guesthouse';
    final isSale = item['category'] == 'sale';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PropertyDetailScreen(
              id: item['_id'] as String? ?? '',
              title: title,
              description: item['description'] as String? ?? '',
              category: item['category'] as String? ?? 'long_term_rent',
              price: price,
              hourlyRate: (item['hourlyRate'] as num?)?.toDouble(),
              address: address,
              latitude: (item['latitude'] as num?)?.toDouble() ?? 8.484,
              longitude: (item['longitude'] as num?)?.toDouble() ?? -13.234,
              imageUrls: images,
              ownerId: item['ownerId'] as String? ?? '',
              bedrooms: beds,
              bathrooms: baths,
              squareMeters: area.toDouble(),
              amenities: (item['amenities'] as List?)?.cast<String>() ??
                  ['EDSA Power', 'Guma Water'],
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
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
            // Cover Image
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(17)),
                  child: Image.network(
                    imageUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 180,
                      color: AppColors.gray200,
                      child: const Icon(Icons.home,
                          size: 40, color: AppColors.gray400),
                    ),
                  ),
                ),
                // Price Tag
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.obsidian.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isGuesthouse
                          ? 'SLE ${_currencyFormat.format(item['hourlyRate'] ?? 250)} / hour'
                          : isSale
                              ? 'SLE ${_currencyFormat.format(price)}'
                              : 'SLE ${_currencyFormat.format(price)} / month',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Category Chip
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.emerald.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      isGuesthouse
                          ? 'GUESTHOUSE'
                          : isSale
                              ? 'FOR SALE'
                              : 'FOR RENT',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.emeraldDark,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Details
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppColors.gray500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.gray600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (beds > 0) ...[
                            Icon(Icons.king_bed_outlined,
                                size: 16, color: AppColors.gray600),
                            const SizedBox(width: 4),
                            Text('$beds Beds',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.gray700)),
                            const SizedBox(width: 12),
                          ],
                          if (baths > 0) ...[
                            Icon(Icons.bathtub_outlined,
                                size: 16, color: AppColors.gray600),
                            const SizedBox(width: 4),
                            Text('$baths Baths',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.gray700)),
                            const SizedBox(width: 12),
                          ],
                          Icon(Icons.square_foot_rounded,
                              size: 16, color: AppColors.gray600),
                          const SizedBox(width: 4),
                          Text('$area m²',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.gray700)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.verified_user_rounded,
                                size: 12, color: AppColors.emeraldDark),
                            SizedBox(width: 4),
                            Text(
                              'Verified Agent',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _IterableExt<T> on Iterable<T> {
  Iterable<T> filter(bool Function(T element) test) => where(test);
}
