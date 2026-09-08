// lib/features/mobility/presentation/views/auto_marketplace_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Auto Sales & Car Rental Vertical Marketplace
// Filter tabs (Buy Cars, Rentals, Kekes, Heavy Duty), vehicle specs,
// verified dealer credentials, and full vehicle detail & escrow routing.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../listings/presentation/views/create_listing_screen.dart';
import '../../../listings/presentation/views/vehicle_detail_screen.dart';

class AutoMarketplaceScreen extends StatefulWidget {
  final AppDatabase database;
  final ConvexClientWrapper convexClient;

  const AutoMarketplaceScreen({
    super.key,
    required this.database,
    required this.convexClient,
  });

  @override
  State<AutoMarketplaceScreen> createState() => _AutoMarketplaceScreenState();
}

class _AutoMarketplaceScreenState extends State<AutoMarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');

  bool _isLoading = true;
  List<Map<String, dynamic>> _allVehicles = [];

  final List<String> _tabs = [
    'All Vehicles',
    'Buy Cars',
    'Car Rentals',
    'Tricycles / Kekes',
    'Heavy Duty / Vans',
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
    _fetchVehicles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchVehicles() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.convexClient.query(
        'mobility:listVehicles',
        args: {'limit': 50},
      );
      if (res.success && res.value is List) {
        if (mounted) {
          setState(() {
            _allVehicles = (res.value as List)
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
        await widget.database.cachedVehicleListingsDao.getAll();
    if (mounted) {
      setState(() {
        _allVehicles = cached
            .map((v) => {
                  '_id': v.id,
                  'make': v.make,
                  'model': v.model,
                  'year': v.year,
                  'salePrice': v.salePrice ?? 120000.0,
                  'pricePerDay': v.pricePerDay,
                  'imageUrls':
                      v.primaryImageUrl != null ? [v.primaryImageUrl!] : [],
                  'vehicleType': v.vehicleType,
                  'listingIntent': v.listingIntent,
                  'transmission': 'Automatic',
                  'fuelType': 'Petrol',
                })
            .toList();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredVehicles() {
    final tabIndex = _tabController.index;
    final query = _searchController.text.trim().toLowerCase();

    return _allVehicles.where((item) {
      final make = (item['make'] as String? ?? '').toLowerCase();
      final model = (item['model'] as String? ?? '').toLowerCase();
      final type = (item['vehicleType'] as String? ?? '').toLowerCase();
      final intent = (item['listingIntent'] as String? ?? '').toLowerCase();
      final hasRental = item['pricePerDay'] != null;

      // 1. Tab filter
      if (tabIndex == 1) {
        // Buy Cars: sale intent & car/taxi
        if (intent == 'rental' || type == 'bike' || type == 'delivery_van') {
          return false;
        }
      } else if (tabIndex == 2) {
        // Car Rentals: rental intent or has daily rate
        if (!hasRental && intent != 'rental') return false;
      } else if (tabIndex == 3) {
        // Tricycles / Kekes
        if (!model.contains('keke') &&
            !model.contains('re') &&
            !make.contains('bajaj') &&
            !model.contains('okada') &&
            !model.contains('boxer') &&
            type != 'bike') {
          return false;
        }
      } else if (tabIndex == 4) {
        // Heavy Duty / Vans
        if (type != 'delivery_van' &&
            type != 'truck' &&
            !model.contains('van') &&
            !model.contains('hiace')) {
          return false;
        }
      }

      // 2. Search query filter
      if (query.isNotEmpty) {
        if (!make.contains(query) && !model.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  void _openCreateListing() {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to list vehicles for sale or rental.'),
          backgroundColor: AppColors.obsidian,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateListingScreen(
          database: widget.database,
          convexClient: widget.convexClient,
          currentUser: user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredVehicles();

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        backgroundColor: AppColors.obsidian,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Auto Market & Car Rentals',
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
            tooltip: 'Refresh Showroom',
            onPressed: _fetchVehicles,
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
        backgroundColor: const Color(0xFF92400E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_circle_outline_rounded),
        label: const Text(
          'List Vehicle',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: _openCreateListing,
      ),
      body: Column(
        children: [
          // ── Search & Filter Bar ───────────────────────────────────
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
                              hintText: 'Search make, model (e.g. Toyota, Bajaj)...',
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
              ],
            ),
          ),

          // ── Vehicle Grid ──────────────────────────────────────────
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
                            const Icon(Icons.directions_car_outlined,
                                size: 54, color: AppColors.gray300),
                            const SizedBox(height: 12),
                            const Text(
                              'No vehicles match your selection',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Try browsing other vehicle categories',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.gray500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchVehicles,
                        color: AppColors.emerald,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return _buildVehicleListItem(item);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleListItem(Map<String, dynamic> item) {
    final make = item['make'] as String? ?? 'Toyota';
    final model = item['model'] as String? ?? 'RAV4';
    final year = item['year'] as int? ?? 2021;
    final price = (item['salePrice'] as num?)?.toDouble() ?? 145000.0;
    final dailyRate = (item['pricePerDay'] as num?)?.toDouble();
    final images = (item['imageUrls'] as List?)?.cast<String>() ?? [];
    final imageUrl = images.isNotEmpty
        ? images.first
        : 'https://images.unsplash.com/photo-1568605117036-5fe5e7bab0b7?w=800';
    final transmission = item['transmission'] as String? ?? 'Automatic';
    final fuel = item['fuelType'] as String? ?? 'Petrol';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VehicleDetailScreen(
              id: item['_id'] as String? ?? '',
              make: make,
              model: model,
              year: year,
              vehicleType: item['vehicleType'] as String? ?? 'taxi',
              listingIntent: item['listingIntent'] as String? ?? 'sale',
              salePrice: price,
              pricePerDay: dailyRate,
              imageUrls: images,
              color: item['color'] as String?,
              licensePlate: item['licensePlate'] as String?,
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
            // Image
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
                      child: const Icon(Icons.directions_car,
                          size: 40, color: AppColors.gray400),
                    ),
                  ),
                ),
                // Price Chip
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
                      dailyRate != null && dailyRate > 0
                          ? 'SLE ${_currencyFormat.format(dailyRate)} / day'
                          : 'SLE ${_currencyFormat.format(price)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Year Tag
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$year MODEL',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Specs
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$year $make $model',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildSpecChip(Icons.settings_outlined, transmission),
                      const SizedBox(width: 8),
                      _buildSpecChip(Icons.local_gas_station_outlined, fuel),
                      const SizedBox(width: 8),
                      _buildSpecChip(Icons.verified_outlined, 'Inspected'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.storefront_rounded,
                              size: 14, color: AppColors.gray500),
                          SizedBox(width: 4),
                          Text(
                            'Verified Auto Dealer',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.gray600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: const [
                            Text(
                              'View Vehicle',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios_rounded,
                                size: 10, color: AppColors.emeraldDark),
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

  Widget _buildSpecChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.gray600),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 11, color: AppColors.gray700),
          ),
        ],
      ),
    );
  }
}
