// lib/features/home/presentation/views/client_home_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Client / Customer Super App Discovery Home Feed
// Modern curated discovery feed with quick-launch grid, showroom
// carousels for verified properties & vehicles, and quick ride shortcuts.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vektolux_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../listings/presentation/views/property_detail_screen.dart';
import '../../../listings/presentation/views/vehicle_detail_screen.dart';
import '../../../mobility/presentation/bloc/mobility_bloc.dart';
import '../../../mobility/presentation/bloc/mobility_event.dart';
import '../../../navigation/presentation/views/main_navigation_shell.dart';

class ClientHomeScreen extends StatefulWidget {
  final AppDatabase database;
  final ConvexClientWrapper convexClient;

  const ClientHomeScreen({
    super.key,
    required this.database,
    required this.convexClient,
  });

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  String _selectedCity = 'Freetown Central';
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');

  List<Map<String, dynamic>> _properties = [];
  List<Map<String, dynamic>> _vehicles = [];
  bool _isLoadingProperties = true;
  bool _isLoadingVehicles = true;

  final List<Map<String, dynamic>> _quickDestinations = [
    {
      'name': 'Lumley Beach',
      'area': 'Aberdeen Peninsula',
      'icon': Icons.beach_access_rounded,
      'color': Color(0xFF0284C7),
    },
    {
      'name': 'Cotton Tree / CBD',
      'area': 'Central Freetown',
      'icon': Icons.park_rounded,
      'color': Color(0xFF10B981),
    },
    {
      'name': 'Aberdeen Ferry Terminal',
      'area': 'Sir Samuel Lewis Rd',
      'icon': Icons.directions_boat_rounded,
      'color': Color(0xFF6366F1),
    },
    {
      'name': 'Waterloo Central Junction',
      'area': 'Western Area Rural',
      'icon': Icons.alt_route_rounded,
      'color': Color(0xFFF59E0B),
    },
    {
      'name': 'Lungi Airport Ferry',
      'area': 'Government Wharf',
      'icon': Icons.flight_takeoff_rounded,
      'color': Color(0xFF8B5CF6),
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadDiscoveryData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDiscoveryData() async {
    // 1. Fetch properties from Convex
    try {
      final propResult = await widget.convexClient.query(
        'realEstate:listProperties',
        args: {'limit': 10},
      );
      if (propResult.success && propResult.value is List) {
        if (mounted) {
          setState(() {
            _properties = (propResult.value as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _isLoadingProperties = false;
          });
        }
      } else {
        _loadCachedProperties();
      }
    } catch (_) {
      _loadCachedProperties();
    }

    // 2. Fetch vehicles from Convex
    try {
      final vehResult = await widget.convexClient.query(
        'mobility:listVehicles',
        args: {'limit': 10},
      );
      if (vehResult.success && vehResult.value is List) {
        if (mounted) {
          setState(() {
            _vehicles = (vehResult.value as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _isLoadingVehicles = false;
          });
        }
      } else {
        _loadCachedVehicles();
      }
    } catch (_) {
      _loadCachedVehicles();
    }
  }

  Future<void> _loadCachedProperties() async {
    final cached = await widget.database.cachedPropertyListingsDao.getAll();
    if (mounted) {
      setState(() {
        _properties = cached.map((p) => {
          '_id': p.id,
          'title': p.title,
          'description': p.description,
          'category': p.category,
          'price': p.price,
          'hourlyRate': p.hourlyRate,
          'address': p.address,
          'imageUrls': p.primaryImageUrl != null ? [p.primaryImageUrl!] : [],
          'bedrooms': 3,
          'bathrooms': 2,
          'areaSqM': 180,
          'amenities': ['EDSA Power', 'Guma Water'],
        }).toList();
        _isLoadingProperties = false;
      });
    }
  }

  Future<void> _loadCachedVehicles() async {
    final cached = await widget.database.cachedVehicleListingsDao.getAll();
    if (mounted) {
      setState(() {
        _vehicles = cached.map((v) => {
          '_id': v.id,
          'make': v.make,
          'model': v.model,
          'year': v.year,
          'salePrice': v.salePrice ?? 120000.0,
          'pricePerDay': v.pricePerDay,
          'imageUrls': v.primaryImageUrl != null ? [v.primaryImageUrl!] : [],
          'vehicleType': v.vehicleType,
        }).toList();
        _isLoadingVehicles = false;
      });
    }
  }

  void _showLocationPicker() {
    final regions = [
      {'name': 'Freetown Central', 'sub': 'Western Area Urban'},
      {'name': 'Lumley & Aberdeen', 'sub': 'Beachfront & Tourism Zone'},
      {'name': 'Wilkinson Road & Congo Cross', 'sub': 'Commercial Corridor'},
      {'name': 'Hill Station & Regent', 'sub': 'Diplomatic Mountain Zone'},
      {'name': 'Waterloo & Goderich', 'sub': 'Western Area Rural'},
      {'name': 'Bo City', 'sub': 'Southern Province Hub'},
      {'name': 'Kenema', 'sub': 'Eastern Province Hub'},
      {'name': 'Makeni', 'sub': 'Northern Province Hub'},
    ];

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
                'Select Your Region in Sierra Leone',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Browse rides, properties, and vehicles tailored to your area.',
                style: TextStyle(fontSize: 13, color: AppColors.gray500),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: regions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final r = regions[idx];
                    final isSelected = r['name'] == _selectedCity;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.location_on_rounded,
                        color: isSelected ? AppColors.emerald : AppColors.gray400,
                      ),
                      title: Text(
                        r['name']!,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? AppColors.emerald : AppColors.obsidian,
                        ),
                      ),
                      subtitle: Text(
                        r['sub']!,
                        style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.emerald)
                          : null,
                      onTap: () {
                        setState(() => _selectedCity = r['name']!);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleQuickDestinationTap(Map<String, dynamic> destination) {
    final destName = destination['name'] as String;
    final destArea = destination['area'] as String;
    final fullDropoff = '$destName, $destArea, Sierra Leone';

    // 1. Dispatch update to MobilityBloc
    context.read<MobilityBloc>().add(
          UpdateLocationsEvent(dropoffAddress: fullDropoff),
        );

    // 2. Switch to Rides tab (Tab Index 1)
    MainNavigationShell.switchToTab(context, 1);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Destination set to $destName! Select your ride tier.'),
        backgroundColor: AppColors.emeraldDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user = authState.user;
        final userName = user?.name.split(' ').first ?? 'Friend';

        return Scaffold(
          backgroundColor: AppColors.gray50,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.emerald,
              onRefresh: _loadDiscoveryData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // ── 1. Top Super App Header ───────────────────────
                  SliverToBoxAdapter(
                    child: _buildHeader(userName, user?.avatarUrl),
                  ),

                  // ── 2. Global Search Bar ──────────────────────────
                  SliverToBoxAdapter(
                    child: _buildSearchBar(),
                  ),

                  // ── 3. Quick Launch Service Grid ──────────────────
                  SliverToBoxAdapter(
                    child: _buildQuickLaunchGrid(),
                  ),

                  // ── 4. Showroom Carousel: Properties ──────────────
                  SliverToBoxAdapter(
                    child: _buildPropertiesCarousel(),
                  ),

                  // ── 5. Showroom Carousel: Vehicles ────────────────
                  SliverToBoxAdapter(
                    child: _buildVehiclesCarousel(),
                  ),

                  // ── 6. Quick Ride Shortcuts ───────────────────────
                  SliverToBoxAdapter(
                    child: _buildQuickDestinationsSection(),
                  ),

                  // Bottom padding for persistent navigation bar
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 100),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                         UI COMPONENTS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildHeader(String firstName, String? avatarUrl) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Greeting & Active Location
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$greeting, $firstName',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('👋', style: TextStyle(fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: _showLocationPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldSurface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.emerald.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 13,
                          color: AppColors.emeraldDark,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _selectedCity,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: AppColors.emeraldDark,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Avatar linking to Account
          GestureDetector(
            onTap: () => MainNavigationShell.switchToTab(context, 4),
            child: VektoluxAvatar(
              avatarUrl: avatarUrl,
              name: firstName,
              radius: 24,
              borderWidth: 2,
              borderColor: AppColors.emerald,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search homes, cars, or destinations in Sierra Leone...',
            hintStyle: TextStyle(
              fontSize: 13,
              color: AppColors.gray400,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.gray400),
            suffixIcon: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.obsidian,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tune_rounded, size: 16, color: Colors.white),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickLaunchGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.emerald,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'SERVICES & TRANSPORT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.gray500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              // 🛺 1. Ride Hail
              _buildServiceCard(
                title: 'Ride Hail',
                subtitle: 'Keke • Okada • Taxi',
                badgeText: 'INSTANT',
                icon: Icons.local_taxi_rounded,
                accentColor: AppColors.emerald,
                gradientColors: [
                  const Color(0xFF065F46),
                  const Color(0xFF047857),
                ],
                onTap: () => MainNavigationShell.switchToTab(context, 1),
              ),

              // 🏡 2. Real Estate
              _buildServiceCard(
                title: 'Real Estate',
                subtitle: 'Rent • Buy • Lodging',
                badgeText: 'VERIFIED',
                icon: Icons.apartment_rounded,
                accentColor: const Color(0xFF38BDF8),
                gradientColors: [
                  const Color(0xFF0F172A),
                  const Color(0xFF1E293B),
                ],
                onTap: () => MainNavigationShell.switchToTab(context, 2),
              ),

              // 🚗 3. Buy / Sell Cars
              _buildServiceCard(
                title: 'Auto Market',
                subtitle: 'Showroom & Fleet',
                badgeText: 'DEALERS',
                icon: Icons.directions_car_filled_rounded,
                accentColor: const Color(0xFFF59E0B),
                gradientColors: [
                  const Color(0xFF78350F),
                  const Color(0xFF92400E),
                ],
                onTap: () => MainNavigationShell.switchToTab(context, 3),
              ),

              // 🔑 4. Rentals
              _buildServiceCard(
                title: 'Rentals',
                subtitle: 'Daily Cars & Stays',
                badgeText: 'HOT',
                icon: Icons.key_rounded,
                accentColor: const Color(0xFFA855F7),
                gradientColors: [
                  const Color(0xFF581C87),
                  const Color(0xFF6B21A8),
                ],
                onTap: () => MainNavigationShell.switchToTab(context, 3),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required IconData icon,
    required Color accentColor,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: Colors.white),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertiesCarousel() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Verified Properties in Sierra Leone',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Houses, furnished flats & guest houses',
                      style: TextStyle(fontSize: 12, color: AppColors.gray500),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => MainNavigationShell.switchToTab(context, 2),
                  child: const Text(
                    'See All',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.emeraldDark,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 240,
            child: _isLoadingProperties
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.emerald),
                  )
                : _properties.isEmpty
                    ? const Center(child: Text('No property listings found.'))
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _properties.length,
                        itemBuilder: (context, idx) {
                          final item = _properties[idx];
                          return _buildPropertyCard(item);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyCard(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? 'Sierra Leone Residence';
    final price = (item['price'] as num?)?.toDouble() ?? 5000.0;
    final address = item['address'] as String? ?? 'Wilkinson Road, Freetown';
    final images = (item['imageUrls'] as List?)?.cast<String>() ?? [];
    final imageUrl = images.isNotEmpty
        ? images.first
        : 'https://images.unsplash.com/photo-1613490493576-7fde63acd811?w=800';
    final beds = item['bedrooms'] as int? ?? 3;
    final baths = item['bathrooms'] as int? ?? 2;
    final isGuesthouse = item['category'] == 'hourly_guesthouse';

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
              amenities: (item['amenities'] as List?)?.cast<String>() ?? ['EDSA Power', 'Guma Water'],
            ),
          ),
        );
      },
      child: Container(
        width: 230,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with Price Badge
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  child: Image.network(
                    imageUrl,
                    height: 125,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 125,
                      color: AppColors.gray200,
                      child: const Icon(Icons.home, color: AppColors.gray400),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.obsidian.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isGuesthouse
                          ? 'SLE ${_currencyFormat.format(item['hourlyRate'] ?? 250)} / hr'
                          : 'SLE ${_currencyFormat.format(price)} / mo',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: AppColors.gray400),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(fontSize: 11, color: AppColors.gray500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.king_bed_outlined, size: 13, color: AppColors.gray500),
                      const SizedBox(width: 3),
                      Text('$beds Beds', style: const TextStyle(fontSize: 11, color: AppColors.gray600)),
                      const SizedBox(width: 10),
                      Icon(Icons.bathtub_outlined, size: 13, color: AppColors.gray500),
                      const SizedBox(width: 3),
                      Text('$baths Baths', style: const TextStyle(fontSize: 11, color: AppColors.gray600)),
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

  Widget _buildVehiclesCarousel() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Featured Vehicles for Sale & Hire',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Cars, kekes & vans from verified Sierra Leone dealers',
                      style: TextStyle(fontSize: 12, color: AppColors.gray500),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => MainNavigationShell.switchToTab(context, 3),
                  child: const Text(
                    'See All',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.emeraldDark,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 230,
            child: _isLoadingVehicles
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.emerald),
                  )
                : _vehicles.isEmpty
                    ? const Center(child: Text('No vehicles found.'))
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _vehicles.length,
                        itemBuilder: (context, idx) {
                          final item = _vehicles[idx];
                          return _buildVehicleCard(item);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> item) {
    final make = item['make'] as String? ?? 'Toyota';
    final model = item['model'] as String? ?? 'RAV4';
    final year = item['year'] as int? ?? 2021;
    final price = (item['salePrice'] as num?)?.toDouble() ?? 145000.0;
    final images = (item['imageUrls'] as List?)?.cast<String>() ?? [];
    final imageUrl = images.isNotEmpty
        ? images.first
        : 'https://images.unsplash.com/photo-1568605117036-5fe5e7bab0b7?w=800';

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
              pricePerDay: (item['pricePerDay'] as num?)?.toDouble(),
              imageUrls: images,
              color: item['color'] as String?,
              licensePlate: item['licensePlate'] as String?,
            ),
          ),
        );
      },
      child: Container(
        width: 220,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                  child: Image.network(
                    imageUrl,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 120,
                      color: AppColors.gray200,
                      child: const Icon(Icons.directions_car, color: AppColors.gray400),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.obsidian.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'SLE ${_currencyFormat.format(price)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$year $make $model',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Verified Dealer',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.emeraldDark,
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
      ),
    );
  }

  Widget _buildQuickDestinationsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.emerald,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'QUICK RIDE SHORTCUTS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.gray500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _quickDestinations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final dest = _quickDestinations[idx];
              final color = dest['color'] as Color;

              return InkWell(
                onTap: () => _handleQuickDestinationTap(dest),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(dest['icon'] as IconData, size: 20, color: color),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dest['name'] as String,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              dest['area'] as String,
                              style: const TextStyle(fontSize: 11, color: AppColors.gray500),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: const [
                            Text(
                              'Book Ride',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppColors.emeraldDark),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
