// lib/features/discovery/presentation/views/discovery_feed_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Marketplace Discovery Feed
// Tabbed browsing for Real Estate & Mobility with Drift SQLite offline cache.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' show Value;

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../listings/presentation/views/create_listing_screen.dart';
import '../../../bookings/presentation/widgets/booking_modals.dart';
import '../../../bookings/presentation/views/my_bookings_screen.dart';

class DiscoveryFeedScreen extends StatefulWidget {
  final AppDatabase database;
  final ConvexClientWrapper convexClient;

  const DiscoveryFeedScreen({
    super.key,
    required this.database,
    required this.convexClient,
  });

  @override
  State<DiscoveryFeedScreen> createState() => _DiscoveryFeedScreenState();
}

class _DiscoveryFeedScreenState extends State<DiscoveryFeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPropertyCategory = 'all';
  String _selectedMobilityIntent = 'all';
  bool _isSyncing = false;

  final _currencyFormat = NumberFormat('#,##0', 'en_US');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });

    // Background sync from Convex cloud
    _syncFromConvex();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Sync listings from Convex cloud and update local SQLite cache.
  Future<void> _syncFromConvex() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      // 1. Fetch Real Estate listings
      final propertiesResult = await widget.convexClient.query(
        'realEstate:listProperties',
        args: {},
      );

      if (propertiesResult.success && propertiesResult.value is List) {
        final rawList = propertiesResult.value as List;
        final companions = rawList.map((item) {
          final m = item as Map<String, dynamic>;
          final images = (m['imageUrls'] as List?)?.cast<String>() ?? [];
          return CachedPropertyListingsTableCompanion.insert(
            id: m['_id'] as String,
            ownerId: m['ownerId'] as String,
            title: m['title'] as String,
            description: m['description'] as String,
            category: m['category'] as String,
            price: (m['price'] as num).toDouble(),
            hourlyRate: Value(m['hourlyRate'] != null
                ? (m['hourlyRate'] as num).toDouble()
                : null),
            address: m['address'] as String,
            latitude: (m['latitude'] as num).toDouble(),
            longitude: (m['longitude'] as num).toDouble(),
            primaryImageUrl: Value(images.isNotEmpty ? images.first : null),
            cachedAt: DateTime.now().millisecondsSinceEpoch,
          );
        }).toList();

        await widget.database.cachedPropertyListingsDao.insertAll(companions);
      }

      // 2. Fetch Vehicle listings
      final vehiclesResult = await widget.convexClient.query(
        'mobility:listVehicles',
        args: {},
      );

      if (vehiclesResult.success && vehiclesResult.value is List) {
        final rawList = vehiclesResult.value as List;
        final companions = rawList.map((item) {
          final m = item as Map<String, dynamic>;
          final images = (m['imageUrls'] as List?)?.cast<String>() ?? [];
          return CachedVehicleListingsTableCompanion.insert(
            id: m['_id'] as String,
            ownerId: m['ownerId'] as String,
            vehicleType: m['vehicleType'] as String,
            listingIntent: m['listingIntent'] as String,
            make: m['make'] as String,
            model: m['model'] as String,
            year: (m['year'] as num).toInt(),
            pricePerKm: Value(m['pricePerKm'] != null
                ? (m['pricePerKm'] as num).toDouble()
                : null),
            pricePerDay: Value(m['pricePerDay'] != null
                ? (m['pricePerDay'] as num).toDouble()
                : null),
            salePrice: Value(m['salePrice'] != null
                ? (m['salePrice'] as num).toDouble()
                : null),
            primaryImageUrl: Value(images.isNotEmpty ? images.first : null),
            cachedAt: DateTime.now().millisecondsSinceEpoch,
          );
        }).toList();

        await widget.database.cachedVehicleListingsDao.insertAll(companions);
      }
    } catch (_) {
      // Offline fallback: SQLite already holds cached items
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final role = authState.user?.role;
        final canCreateListing = role == UserRole.agent ||
            role == UserRole.merchant ||
            role == UserRole.driver ||
            role == UserRole.admin;

        return Scaffold(
          backgroundColor: AppColors.gray50,
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  expandedHeight: 140,
                  floating: false,
                  pinned: true,
                  backgroundColor: AppColors.obsidian,
                  title: const Text(
                    'Vektolux Marketplace',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                      fontSize: 18,
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.confirmation_number_outlined,
                          color: AppColors.emerald),
                      tooltip: 'My Bookings & Trips',
                      onPressed: () {
                        final user = authState.user;
                        if (user == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Please log in to view your bookings'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MyBookingsScreen(
                              database: widget.database,
                              convexClient: widget.convexClient,
                              currentUser: user,
                            ),
                          ),
                        );
                      },
                    ),
                    if (_isSyncing)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.emerald,
                            ),
                          ),
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.sync, color: AppColors.gray300),
                        tooltip: 'Refresh feed',
                        onPressed: _syncFromConvex,
                      ),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(48),
                    child: Container(
                      color: AppColors.obsidian,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.obsidianLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicator: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: AppColors.emerald,
                          ),
                          labelColor: AppColors.white,
                          unselectedLabelColor: AppColors.gray400,
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          tabs: const [
                            Tab(text: '🏡  Real Estate'),
                            Tab(text: '🚗  Mobility & Fleets'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildRealEstateTab(),
                _buildMobilityTab(),
              ],
            ),
          ),
          floatingActionButton: canCreateListing
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    final created = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => CreateListingScreen(
                          database: widget.database,
                          convexClient: widget.convexClient,
                          currentUser: authState.user!,
                        ),
                      ),
                    );
                    if (created == true) {
                      _syncFromConvex();
                    }
                  },
                  backgroundColor: AppColors.emerald,
                  icon: const Icon(Icons.add, color: AppColors.white),
                  label: const Text(
                    'Create Listing',
                    style: TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     REAL ESTATE TAB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildRealEstateTab() {
    final categories = [
      {'label': 'All', 'value': 'all'},
      {'label': 'For Sale', 'value': 'sale'},
      {'label': 'Annual Rent', 'value': 'long_term_rent'},
      {'label': 'Hourly Guest House', 'value': 'hourly_guesthouse'},
    ];

    return Column(
      children: [
        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: categories.map((cat) {
              final isSelected = _selectedPropertyCategory == cat['value'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isSelected,
                  label: Text(cat['label']!),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? AppColors.white : AppColors.obsidian,
                  ),
                  selectedColor: AppColors.emerald,
                  backgroundColor: AppColors.white,
                  checkmarkColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? AppColors.emerald : AppColors.border,
                    ),
                  ),
                  onSelected: (selected) {
                    setState(() {
                      _selectedPropertyCategory = cat['value']!;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),

        // Reactive SQLite Stream
        Expanded(
          child: StreamBuilder<List<CachedPropertyListing>>(
            stream: _selectedPropertyCategory == 'all'
                ? widget.database.cachedPropertyListingsDao.watchAll()
                : widget.database.cachedPropertyListingsDao
                    .watchByCategory(_selectedPropertyCategory),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.emerald),
                );
              }

              final listings = snapshot.data ?? [];
              if (listings.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.home_work_outlined,
                  title: 'No properties found',
                  subtitle: _isSyncing
                      ? 'Fetching from cloud...'
                      : 'Check back soon or adjust filters.',
                );
              }

              return RefreshIndicator(
                onRefresh: _syncFromConvex,
                color: AppColors.emerald,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: listings.length,
                  itemBuilder: (context, index) {
                    return _PropertyListingCard(
                      listing: listings[index],
                      currencyFormat: _currencyFormat,
                      database: widget.database,
                      convexClient: widget.convexClient,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     MOBILITY TAB
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildMobilityTab() {
    final intents = [
      {'label': 'All', 'value': 'all'},
      {'label': 'Book Rides', 'value': 'ride_hailing'},
      {'label': 'Daily Rentals', 'value': 'rental'},
      {'label': 'Vehicles for Sale', 'value': 'sale'},
    ];

    return Column(
      children: [
        // Intent Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: intents.map((intent) {
              final isSelected = _selectedMobilityIntent == intent['value'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isSelected,
                  label: Text(intent['label']!),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? AppColors.white : AppColors.obsidian,
                  ),
                  selectedColor: AppColors.emerald,
                  backgroundColor: AppColors.white,
                  checkmarkColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? AppColors.emerald : AppColors.border,
                    ),
                  ),
                  onSelected: (selected) {
                    setState(() {
                      _selectedMobilityIntent = intent['value']!;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),

        // Reactive SQLite Stream
        Expanded(
          child: StreamBuilder<List<CachedVehicleListing>>(
            stream: _selectedMobilityIntent == 'all'
                ? widget.database.cachedVehicleListingsDao.watchAll()
                : widget.database.cachedVehicleListingsDao
                    .watchByIntent(_selectedMobilityIntent),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.emerald),
                );
              }

              final vehicles = snapshot.data ?? [];
              if (vehicles.isEmpty) {
                return _buildEmptyState(
                  icon: Icons.directions_car_outlined,
                  title: 'No vehicles found',
                  subtitle: _isSyncing
                      ? 'Fetching from cloud...'
                      : 'Check back soon or adjust filters.',
                );
              }

              return RefreshIndicator(
                onRefresh: _syncFromConvex,
                color: AppColors.emerald,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: vehicles.length,
                  itemBuilder: (context, index) {
                    return _VehicleListingCard(
                      vehicle: vehicles[index],
                      currencyFormat: _currencyFormat,
                      database: widget.database,
                      convexClient: widget.convexClient,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: AppColors.gray400),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//                    PROPERTY LISTING CARD
// ═══════════════════════════════════════════════════════════════════

class _PropertyListingCard extends StatelessWidget {
  final CachedPropertyListing listing;
  final NumberFormat currencyFormat;
  final AppDatabase database;
  final ConvexClientWrapper convexClient;

  const _PropertyListingCard({
    required this.listing,
    required this.currencyFormat,
    required this.database,
    required this.convexClient,
  });

  String get _categoryBadgeText => switch (listing.category) {
        'sale' => 'FOR SALE',
        'long_term_rent' => 'ANNUAL RENT',
        'hourly_guesthouse' => 'HOURLY GUESTHOUSE',
        _ => listing.category.toUpperCase(),
      };

  String get _priceText {
    if (listing.category == 'hourly_guesthouse' && listing.hourlyRate != null) {
      return 'SLE ${currencyFormat.format(listing.hourlyRate)}/hr';
    }
    return 'SLE ${currencyFormat.format(listing.price)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image / Thumbnail
          Stack(
            children: [
              Container(
                height: 160,
                width: double.infinity,
                color: AppColors.gray100,
                child: listing.primaryImageUrl != null &&
                        listing.primaryImageUrl!.isNotEmpty
                    ? Image.network(
                        listing.primaryImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildFallbackImage(),
                      )
                    : _buildFallbackImage(),
              ),
              // Category Chip
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.obsidian.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _categoryBadgeText,
                    style: const TextStyle(
                      color: AppColors.emerald,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              // Price Tag
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.emerald,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _priceText,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Details Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  style: const TextStyle(
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
                    const Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: AppColors.gray500,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        listing.address,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Details for: ${listing.title}'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.obsidian,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text('View Details',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final user = context.read<AuthBloc>().state.user;
                          if (user == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please log in to book or schedule a visit.'),
                                backgroundColor: AppColors.obsidian,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }

                          if (listing.category == 'hourly_guesthouse') {
                            HourlyBookingModal.show(
                              context,
                              property: listing,
                              currentUser: user,
                              database: database,
                              convexClient: convexClient,
                            );
                          } else {
                            PropertyInspectionModal.show(
                              context,
                              property: listing,
                              currentUser: user,
                              database: database,
                              convexClient: convexClient,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.emerald,
                          foregroundColor: AppColors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          listing.category == 'hourly_guesthouse'
                              ? 'Instant Book'
                              : 'Schedule Visit',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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

  Widget _buildFallbackImage() {
    return Container(
      color: const Color(0xFF1E293B),
      child: const Center(
        child: Icon(
          Icons.apartment_outlined,
          size: 48,
          color: AppColors.emerald,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//                     VEHICLE LISTING CARD
// ═══════════════════════════════════════════════════════════════════

class _VehicleListingCard extends StatelessWidget {
  final CachedVehicleListing vehicle;
  final NumberFormat currencyFormat;
  final AppDatabase database;
  final ConvexClientWrapper convexClient;

  const _VehicleListingCard({
    required this.vehicle,
    required this.currencyFormat,
    required this.database,
    required this.convexClient,
  });

  String get _intentBadgeText => switch (vehicle.listingIntent) {
        'ride_hailing' => 'RIDE HAILING',
        'rental' => 'DAILY RENTAL',
        'sale' => 'FOR SALE',
        _ => vehicle.listingIntent.toUpperCase(),
      };

  String get _priceText {
    if (vehicle.listingIntent == 'ride_hailing' &&
        vehicle.pricePerKm != null) {
      return 'SLE ${currencyFormat.format(vehicle.pricePerKm)}/km';
    }
    if (vehicle.listingIntent == 'rental' && vehicle.pricePerDay != null) {
      return 'SLE ${currencyFormat.format(vehicle.pricePerDay)}/day';
    }
    if (vehicle.salePrice != null) {
      return 'SLE ${currencyFormat.format(vehicle.salePrice)}';
    }
    return 'Contact for Price';
  }

  IconData get _vehicleIcon => switch (vehicle.vehicleType) {
        'bike' => Icons.two_wheeler_outlined,
        'taxi' => Icons.local_taxi_outlined,
        'delivery_van' => Icons.local_shipping_outlined,
        'truck' => Icons.rv_hookup_outlined,
        _ => Icons.directions_car_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image / Thumbnail
          Stack(
            children: [
              Container(
                height: 160,
                width: double.infinity,
                color: AppColors.gray100,
                child: vehicle.primaryImageUrl != null &&
                        vehicle.primaryImageUrl!.isNotEmpty
                    ? Image.network(
                        vehicle.primaryImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildFallbackImage(),
                      )
                    : _buildFallbackImage(),
              ),
              // Intent Badge
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.obsidian.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _intentBadgeText,
                    style: const TextStyle(
                      color: AppColors.emerald,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              // Price Tag
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.emerald,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _priceText,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Details Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${vehicle.make} ${vehicle.model}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${vehicle.year}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(_vehicleIcon, size: 16, color: AppColors.gray500),
                    const SizedBox(width: 4),
                    Text(
                      vehicle.vehicleType.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Details: ${vehicle.make} ${vehicle.model}'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.obsidian,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: const Text('View Specs',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final user = context.read<AuthBloc>().state.user;
                          if (user == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please log in to rent or book this vehicle.'),
                                backgroundColor: AppColors.obsidian,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }

                          if (vehicle.listingIntent == 'rental') {
                            VehicleRentalModal.show(
                              context,
                              vehicle: vehicle,
                              currentUser: user,
                              database: database,
                              convexClient: convexClient,
                            );
                          } else if (vehicle.listingIntent == 'ride_hailing') {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Ride-hailing for ${vehicle.make} ${vehicle.model} - Opening driver dispatch...'),
                                backgroundColor: AppColors.emerald,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Purchase inquiry for ${vehicle.make} ${vehicle.model} sent to dealer.'),
                                backgroundColor: AppColors.emerald,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.emerald,
                          foregroundColor: AppColors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(
                          vehicle.listingIntent == 'ride_hailing'
                              ? 'Book Ride'
                              : (vehicle.listingIntent == 'rental'
                                  ? 'Rent Now'
                                  : 'Buy Vehicle'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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

  Widget _buildFallbackImage() {
    return Container(
      color: const Color(0xFF1E293B),
      child: Center(
        child: Icon(
          _vehicleIcon,
          size: 48,
          color: AppColors.emerald,
        ),
      ),
    );
  }
}
