// lib/features/mobility/presentation/views/auto_marketplace_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Auto Sales, Car Rental & Commercial Fleet Marketplace
// Filter tabs (All, Car Sales, Rentals, Delivery Vans, Sand Dump Trucks, Container Freight),
// vehicle specs, verified dealer credentials, and full vehicle detail & escrow routing.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vx_network_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../listings/presentation/views/create_listing_screen.dart';
import '../../../listings/presentation/views/vehicle_detail_screen.dart';
import '../../../social/presentation/views/public_profile_screen.dart';
import 'delivery_van_booking_screen.dart';
import 'my_escrow_orders_screen.dart';

class AutoMarketplaceScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;

  const AutoMarketplaceScreen({
    super.key,
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
    'Car Sales',
    'Car Rentals',
    'Delivery Vans',
    'Sand Dump Trucks',
    'Container Freight',
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
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _getFilteredVehicles() {
    final tabIndex = _tabController.index;
    final query = _searchController.text.trim().toLowerCase();

    return _allVehicles.where((item) {
      final category = (item['category'] as String? ?? '').toLowerCase();
      final title = (item['title'] as String? ?? '').toLowerCase();
      final make = (item['make'] as String? ?? '').toLowerCase();
      final model = (item['model'] as String? ?? '').toLowerCase();
      final capacity = (item['capacity'] as String? ?? '').toLowerCase();
      final location = (item['location'] as String? ?? '').toLowerCase();
      final type = (item['vehicleType'] as String? ?? '').toLowerCase();
      final intent = (item['listingIntent'] as String? ?? '').toLowerCase();

      // 1. Tab filter
      if (tabIndex == 1) {
        // Car Sales
        if (category.isNotEmpty) {
          if (category != 'car_sale') return false;
        } else if (intent == 'rental' || type == 'delivery_van' || type == 'truck') {
          return false;
        }
      } else if (tabIndex == 2) {
        // Car Rentals
        if (category.isNotEmpty) {
          if (category != 'car_rental') return false;
        } else if (intent != 'rental') {
          return false;
        }
      } else if (tabIndex == 3) {
        // Delivery Vans
        if (category.isNotEmpty) {
          if (category != 'delivery_van') return false;
        } else if (type != 'delivery_van' && !title.contains('van') && !model.contains('van')) {
          return false;
        }
      } else if (tabIndex == 4) {
        // Sand Dump Trucks
        if (category.isNotEmpty) {
          if (category != 'sand_dump_truck') return false;
        } else if (!title.contains('tipper') && !title.contains('dump') && !title.contains('sand') && !model.contains('tipper') && type != 'truck') {
          return false;
        }
      } else if (tabIndex == 5) {
        // Container Freight Trucks
        if (category.isNotEmpty) {
          if (category != 'container_freight_truck') return false;
        } else if (!title.contains('container') && !title.contains('flatbed') && !title.contains('freight')) {
          return false;
        }
      }

      // 2. Search query filter
      if (query.isNotEmpty) {
        if (!title.contains(query) &&
            !make.contains(query) &&
            !model.contains(query) &&
            !capacity.contains(query) &&
            !location.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Future<void> _openCreateListing() async {
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

    if (!user.canPostVehicle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verified Auto Dealer or Seller status required to list vehicles.'),
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
      _fetchVehicles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredVehicles();
    final user = context.watch<AuthBloc>().state.user;
    final canPost = user != null && user.canPostVehicle;

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
            icon: const Icon(Icons.shield_outlined, color: AppColors.emerald),
            tooltip: 'My Escrow Contracts',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MyEscrowOrdersScreen(),
                ),
              );
            },
          ),
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
      floatingActionButton: canPost
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF92400E),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text(
                'List Vehicle',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: _openCreateListing,
            )
          : null,
      body: Column(
        children: [
          // ── Search & Filter Bar ───────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
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
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.directions_car_outlined,
                                size: 54, color: AppColors.gray300),
                            SizedBox(height: 12),
                            Text(
                              'No vehicles match your selection',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
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
    final category = item['category'] as String? ?? 'car_sale';
    final title = (item['title'] as String? ?? '').isNotEmpty
        ? item['title'] as String
        : '${item['year'] ?? 2022} ${item['make'] ?? "Toyota"} ${item['model'] ?? "RAV4"}';
    final make = item['make'] as String? ?? 'Toyota';
    final model = item['model'] as String? ?? 'RAV4';
    final year = (item['year'] as num?)?.toInt() ?? 2022;
    final price = (item['price'] as num?)?.toDouble() ??
        (item['salePrice'] as num?)?.toDouble() ??
        145000.0;
    final dailyRate = (item['pricePerDay'] as num?)?.toDouble();
    final pricingType = item['pricingType'] as String? ??
        (dailyRate != null && dailyRate > 0 ? 'per_day' : 'total_sale');
    final capacity = item['capacity'] as String?;
    final images = (item['images'] as List?)?.cast<String>() ??
        (item['imageUrls'] as List?)?.cast<String>() ??
        [];
    final imageUrl = images.isNotEmpty ? images.first : null;
    final transmission = item['transmission'] as String? ?? 'Automatic';
    final fuel = item['fuelType'] as String? ?? 'Petrol';
    final ownerId = item['ownerId'] as String?;
    final isDeliveryVan = category == 'delivery_van';

    String priceText;
    if (pricingType == 'per_trip') {
      priceText = 'SLE ${_currencyFormat.format(price)} / trip';
    } else if (pricingType == 'per_day' || (dailyRate != null && dailyRate > 0)) {
      priceText = 'SLE ${_currencyFormat.format(dailyRate ?? price)} / day';
    } else {
      priceText = 'SLE ${_currencyFormat.format(price)} Total';
    }

    final categoryLabel = switch (category) {
      'car_sale' => 'CAR SALE',
      'car_rental' => 'CAR RENTAL',
      'delivery_van' => 'DELIVERY VAN',
      'sand_dump_truck' => 'SAND TIPPER',
      'container_freight_truck' => 'CONTAINER TRUCK',
      _ => 'COMMERCIAL',
    };

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VehicleDetailScreen(
              id: item['_id'] as String? ?? '',
              make: make,
              model: model,
              year: year,
              vehicleType: category,
              listingIntent: pricingType == 'per_day' ? 'rental' : 'sale',
              salePrice: price,
              pricePerDay: dailyRate ?? (pricingType == 'per_day' ? price : null),
              imageUrls: images,
              ownerId: item['ownerId'] as String?,
              ownerName: item['ownerName'] as String?,
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
                  child: VxNetworkImage(
                    imageUrl: imageUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    fallbackIcon: Icons.local_shipping_rounded,
                    fallbackLabel: 'VEKTOLUX COMMERCIAL',
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
                      priceText,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Category Tag
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldDark.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      categoryLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
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
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (capacity != null && capacity.isNotEmpty)
                        _buildSpecChip(Icons.scale_rounded, capacity),
                      _buildSpecChip(Icons.settings_outlined, transmission),
                      _buildSpecChip(Icons.local_gas_station_outlined, fuel),
                      _buildSpecChip(Icons.verified_outlined, 'Inspected'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: ownerId != null && ownerId.isNotEmpty
                            ? () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PublicProfileScreen(
                                      userId: ownerId,
                                      convexClient: widget.convexClient,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        child: Row(
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
                      ),
                      Row(
                        children: [
                          if (isDeliveryVan) ...[
                            InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DeliveryVanBookingScreen(
                                      vehicle: item,
                                      convexClient: widget.convexClient,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.mobility.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.calendar_today_rounded,
                                        size: 10, color: AppColors.mobility),
                                    SizedBox(width: 4),
                                    Text(
                                      'Book Van',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.mobility,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.emeraldSurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
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
