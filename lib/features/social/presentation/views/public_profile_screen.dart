// lib/features/social/presentation/views/public_profile_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Public User Profile Screen
// Displays any user's public profile: avatar, name, bio, verified badge,
// follower/following counts, and a grid of their active listings.
// Follow/Unfollow toggle. Navigable from listing cards or search.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vx_network_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../mobility/presentation/views/my_escrow_orders_screen.dart';
import '../../../real_estate/presentation/views/my_real_estate_escrows_screen.dart';
import '../../../profile/presentation/views/profile_screen.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final ConvexClientWrapper convexClient;

  const PublicProfileScreen({
    super.key,
    required this.userId,
    required this.convexClient,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');

  bool _isLoading = true;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _posts = [];
  bool _isFollowing = false;
  bool _isTogglingFollow = false;
  String _currentUserId = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final authState = context.read<AuthBloc>().state;
    _currentUserId = authState.user?.id ?? '';

    setState(() => _isLoading = true);

    try {
      // Fetch profile, posts, and follow status in parallel
      final results = await Future.wait([
        widget.convexClient.query('users:getUserProfile', args: {'userId': widget.userId}),
        widget.convexClient.query('users:getUserPosts', args: {'userId': widget.userId}),
        if (_currentUserId.isNotEmpty && _currentUserId != widget.userId)
          widget.convexClient.query('social:getFollowStatus', args: {
            'currentUserId': _currentUserId,
            'targetUserId': widget.userId,
          }),
      ]);

      if (mounted) {
        setState(() {
          if (results[0].success && results[0].value is Map) {
            _profile = Map<String, dynamic>.from(results[0].value as Map);
          }
          if (results[1].success && results[1].value is List) {
            _posts = (results[1].value as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
          if (results.length > 2 && results[2].success && results[2].value is Map) {
            _isFollowing = (results[2].value as Map)['isFollowing'] == true;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_currentUserId.isEmpty || _isTogglingFollow) return;

    final authState = context.read<AuthBloc>().state;
    final sessionToken = authState.user?.sessionToken ?? '';

    setState(() => _isTogglingFollow = true);

    try {
      final res = await widget.convexClient.mutation(
        'social:toggleFollow',
        args: {
          'currentUserId': _currentUserId,
          'targetUserId': widget.userId,
          'sessionToken': sessionToken,
        },
      );

      if (mounted && res.success && res.value is Map) {
        final nowFollowing = (res.value as Map)['isFollowing'] == true;
        setState(() {
          _isFollowing = nowFollowing;
          if (_profile != null) {
            final count = (_profile!['followersCount'] as num?)?.toInt() ?? 0;
            _profile!['followersCount'] = nowFollowing ? count + 1 : (count - 1).clamp(0, 999999);
          }
        });
      }
    } catch (e) {
      // Silently fail
    } finally {
      if (mounted) setState(() => _isTogglingFollow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _profile?['name'] ?? 'Profile',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.emerald))
          : _profile == null
              ? _buildNotFoundState()
              : _buildProfileContent(),
    );
  }

  Widget _buildNotFoundState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off_rounded, size: 56, color: AppColors.gray300),
          SizedBox(height: 16),
          Text(
            'User not found',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    final name = _profile!['name'] as String? ?? 'Unknown';
    final bio = _profile!['bio'] as String? ?? '';
    final avatarUrl = _profile!['avatarUrl'] as String?;
    final badge = _profile!['verificationBadge'] as String? ?? 'NONE';
    final followersCount = (_profile!['followersCount'] as num?)?.toInt() ?? 0;
    final followingCount = (_profile!['followingCount'] as num?)?.toInt() ?? 0;
    final role = _profile!['role'] as String? ?? 'client';
    final isOwnProfile = _currentUserId == widget.userId;
    final isVerifiedSeller = _profile!['isVerifiedSeller'] == true;

    final propertyPosts = _posts.where((p) => p['type'] == 'property').toList();
    final vehiclePosts = _posts.where((p) => p['type'] == 'vehicle').toList();

    Widget headerCard = Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        children: [
          // Avatar + Follow button row
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.emeraldSurface,
                backgroundImage: avatarUrl != null
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.emeraldDark,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    if (isVerifiedSeller)
                      _buildStatColumn(_posts.length.toString(), 'Listings')
                    else
                      _buildStatColumn('Client', 'Tier'),
                    _buildStatColumn(_formatCount(followersCount), 'Followers'),
                    _buildStatColumn(_formatCount(followingCount), 'Following'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Name + badge (badge only shown for verified sellers)
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // Green checkmark strictly restricted to verified sellers/dealers
                if (isVerifiedSeller &&
                    (badge == 'GREEN_TICK' ||
                        _profile!['sellerApprovedAt'] != null ||
                        role == 'admin')) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified_rounded, size: 18, color: AppColors.emerald),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              isVerifiedSeller
                  ? _roleName(role)
                  : 'Verified Client & Buyer',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isVerifiedSeller ? FontWeight.w600 : FontWeight.w500,
                color: isVerifiedSeller ? AppColors.emeraldDark : AppColors.textSecondary,
              ),
            ),
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                bio,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Follow / Unfollow button
          if (!isOwnProfile)
            SizedBox(
              width: double.infinity,
              height: 40,
              child: FilledButton(
                onPressed: _isTogglingFollow ? null : _toggleFollow,
                style: FilledButton.styleFrom(
                  backgroundColor: _isFollowing
                      ? AppColors.gray200
                      : AppColors.emerald,
                  foregroundColor: _isFollowing
                      ? AppColors.textPrimary
                      : AppColors.textOnEmerald,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isTogglingFollow
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textSecondary,
                        ),
                      )
                    : Text(
                        _isFollowing ? 'Following' : 'Follow',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );

    // If regular buyer/client: DO NOT SHOW SELLER STOREFRONT TABS
    if (!isVerifiedSeller) {
      return SingleChildScrollView(
        child: Column(
          children: [
            headerCard,
            _buildBuyerProfileView(isOwnProfile),
          ],
        ),
      );
    }

    // Verified Seller Storefront: Show Properties and Vehicles tabs
    return NestedScrollView(
      headerSliverBuilder: (context, _) => [
        SliverToBoxAdapter(child: headerCard),
        // Tabs: Properties | Vehicles
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            tabBar: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.emerald,
              labelColor: AppColors.textPrimary,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.apartment_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text('Properties (${propertyPosts.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_car_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text('Vehicles (${vehiclePosts.length})'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPostGrid(propertyPosts, 'property'),
          _buildPostGrid(vehiclePosts, 'vehicle'),
        ],
      ),
    );
  }

  Widget _buildBuyerProfileView(bool isOwnProfile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. "Apply to become a Verified Seller / Dealership" Banner (if own profile)
          if (isOwnProfile) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.emeraldDark, Color(0xFF0F766E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.emeraldDark.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Become a Verified Seller',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Real Estate Agencies & Auto Dealerships',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Standard buyer accounts do not have public storefront listings. Apply to get verified as a dealer or agent to unlock storefront tabs, publish listings, and accept escrow settlements.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () => _showSellerApplicationModal(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.emeraldDark,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.verified_rounded, size: 18),
                      label: const Text(
                        'Apply for Seller Verification',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // 2. Buyer Escrows & Bookings Card (if own profile)
          if (isOwnProfile) ...[
            const Text(
              'MY ESCROWS & BOOKINGS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.gray500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.directions_car_rounded, color: AppColors.emeraldDark, size: 20),
                    ),
                    title: const Text(
                      'Vehicle Escrow Orders',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    subtitle: const Text(
                      'Track vehicle purchase & rental escrow contracts',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MyEscrowOrdersScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.apartment_rounded, color: AppColors.emeraldDark, size: 20),
                    ),
                    title: const Text(
                      'Real Estate Contracts & Passes',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    subtitle: const Text(
                      'Viewing passes & property lease/purchase escrows',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.gray400),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MyRealEstateEscrowsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // 3. Buyer Trust & Activity Profile
          const Text(
            'ACCOUNT & TRUST PROFILE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.gray500,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppColors.emerald, size: 22),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verified Client Profile',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Protected by Vektolux Multi-Sig Escrow protocols',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'BUYER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isOwnProfile) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(currentUserId: _currentUserId),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: const Text('Account Details & Settings'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSellerApplicationModal(BuildContext context) {
    final businessNameController = TextEditingController();
    final tinController = TextEditingController();
    String selectedType = 'real_estate';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Apply for Seller Verification',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Unlock your public storefront, list properties and vehicles, and accept escrow payments.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Seller Type',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: const [
                    DropdownMenuItem(value: 'real_estate', child: Text('🏡 Real Estate Agent / Property Owner')),
                    DropdownMenuItem(value: 'dealership', child: Text('🚗 Auto Dealership / Fleet Operator')),
                    DropdownMenuItem(value: 'vendor', child: Text('💼 Commercial Merchant / Vendor')),
                    DropdownMenuItem(value: 'individual', child: Text('👤 Individual Verified Seller')),
                  ],
                  onChanged: (val) {
                    if (val != null) setModalState(() => selectedType = val);
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Business or Brand Name',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: businessNameController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Sierra Luxe Properties or Freetown Motors',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'NRA Tax ID / TIN Number (Optional)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: tinController,
                  decoration: InputDecoration(
                    hintText: 'e.g. 100234890',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final authState = context.read<AuthBloc>().state;
                            final userId = authState.user?.id ?? _currentUserId;
                            if (userId.isEmpty) return;

                            setModalState(() => isSubmitting = true);
                            try {
                              final res = await widget.convexClient.mutation(
                                'users:applyForSellerVerification',
                                args: {
                                  'userId': userId,
                                  'sellerType': selectedType,
                                  if (businessNameController.text.trim().isNotEmpty)
                                    'businessName': businessNameController.text.trim(),
                                  if (tinController.text.trim().isNotEmpty)
                                    'tinNumber': tinController.text.trim(),
                                },
                              );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(res.success
                                        ? 'Application submitted! Our compliance team will review your seller credentials.'
                                        : (res.errorMessage ?? 'Submission failed')),
                                    backgroundColor: res.success ? AppColors.emerald : AppColors.error,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                _loadProfile();
                              }
                            } catch (e) {
                              if (ctx.mounted) setModalState(() => isSubmitting = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error submitting application: $e'),
                                    backgroundColor: AppColors.error,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Submit Application',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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

  Widget _buildStatColumn(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildPostGrid(List<Map<String, dynamic>> posts, String type) {
    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                type == 'property'
                    ? Icons.apartment_outlined
                    : Icons.directions_car_outlined,
                size: 48,
                color: AppColors.gray300,
              ),
              const SizedBox(height: 12),
              Text(
                'No ${type == 'property' ? 'property' : 'vehicle'} listings yet',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.78,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) => _buildPostTile(posts[index], type),
    );
  }

  Widget _buildPostTile(Map<String, dynamic> post, String type) {
    final title = type == 'property'
        ? (post['title'] as String? ?? 'Property')
        : '${post['make'] ?? ''} ${post['model'] ?? ''}'.trim();
    final imageUrls = post['imageUrls'] as List? ?? [];
    final price = type == 'property'
        ? (post['price'] as num?)?.toDouble() ?? 0
        : (post['salePrice'] as num?)?.toDouble() ??
          (post['pricePerDay'] as num?)?.toDouble() ?? 0;
    final currency = post['currency'] as String? ?? 'SLE';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: imageUrls.isNotEmpty
                ? VxNetworkImage(
                    imageUrl: imageUrls.first.toString(),
                    width: double.infinity,
                    height: 120,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: double.infinity,
                    height: 120,
                    color: AppColors.gray100,
                    child: Icon(
                      type == 'property'
                          ? Icons.apartment_rounded
                          : Icons.directions_car_rounded,
                      size: 36,
                      color: AppColors.gray300,
                    ),
                  ),
          ),

          // Details
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Text(
                    '$currency ${_currencyFormat.format(price)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.emeraldDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  String _roleName(String role) {
    switch (role) {
      case 'agent':
        return 'Property Agent';
      case 'merchant':
        return 'Auto Dealer';
      case 'driver':
        return 'Driver';
      case 'seller':
        return 'Seller';
      case 'property_owner':
        return 'Property Owner';
      default:
        return role;
    }
  }
}

/// Delegate for pinning the TabBar inside the NestedScrollView.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabBarDelegate({required this.tabBar});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.surface,
      child: tabBar,
    );
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}
