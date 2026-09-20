// lib/features/social/presentation/views/social_feed_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Social / Explore Feed
// Displays latest listings from followed agents and dealers.
// Replaces the old Rides tab in the bottom navigation.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vx_network_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import 'public_profile_screen.dart';

class SocialFeedScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;

  const SocialFeedScreen({
    super.key,
    required this.convexClient,
  });

  @override
  State<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends State<SocialFeedScreen> {
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');

  bool _isLoading = true;
  List<Map<String, dynamic>> _feedItems = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFeed());
  }

  Future<void> _loadFeed() async {
    final authState = context.read<AuthBloc>().state;
    final userId = authState.user?.id ?? '';
    if (userId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await widget.convexClient.query(
        'social:getSocialFeed',
        args: {'userId': userId},
      );
      if (res.success && res.value is List) {
        if (mounted) {
          setState(() {
            _feedItems = (res.value as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Explore',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
            onPressed: () {
              // TODO: Search functionality
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.emerald))
          : _feedItems.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppColors.emerald,
                  onRefresh: _loadFeed,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    itemCount: _feedItems.length,
                    itemBuilder: (context, index) => _buildFeedCard(_feedItems[index]),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.emeraldSurface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.people_alt_rounded,
                size: 40,
                color: AppColors.emerald,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your Feed Is Empty',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Follow agents and dealers to see their latest property and vehicle listings here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedCard(Map<String, dynamic> item) {
    final type = item['type'] as String? ?? 'property';
    final title = item['title'] as String? ?? item['make'] as String? ?? 'Untitled';
    final subtitle = type == 'property'
        ? '${item['category'] ?? ''} • ${item['city'] ?? ''}'
        : '${item['make'] ?? ''} ${item['model'] ?? ''} • ${item['year'] ?? ''}';
    final price = type == 'property'
        ? (item['price'] as num?)?.toDouble() ?? 0
        : (item['salePrice'] as num?)?.toDouble() ??
          (item['pricePerDay'] as num?)?.toDouble() ?? 0;
    final currency = item['currency'] as String? ?? 'SLE';
    final imageUrls = item['imageUrls'] as List? ?? [];
    final ownerName = item['ownerName'] as String? ?? 'Unknown';
    final ownerAvatar = item['ownerAvatar'] as String?;
    final ownerId = item['ownerId'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Agent header
          InkWell(
            onTap: () => _navigateToProfile(ownerId),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.emeraldSurface,
                    backgroundImage: ownerAvatar != null
                        ? NetworkImage(ownerAvatar)
                        : null,
                    child: ownerAvatar == null
                        ? Text(
                            ownerName.isNotEmpty ? ownerName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: AppColors.emeraldDark,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ownerName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          type == 'property' ? 'Property Agent' : 'Auto Dealer',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: type == 'property'
                          ? AppColors.realEstate.withValues(alpha: 0.1)
                          : AppColors.mobility.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type == 'property'
                              ? Icons.apartment_rounded
                              : Icons.directions_car_rounded,
                          size: 14,
                          color: type == 'property'
                              ? AppColors.realEstate
                              : AppColors.mobility,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          type == 'property' ? 'Property' : 'Vehicle',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: type == 'property'
                                ? AppColors.realEstate
                                : AppColors.mobility,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Image
          if (imageUrls.isNotEmpty)
            ClipRRect(
              child: VxNetworkImage(
                imageUrl: imageUrls.first.toString(),
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$currency ${_currencyFormat.format(price)}',
                  style: const TextStyle(
                    fontSize: 18,
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

  void _navigateToProfile(String userId) {
    if (userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          userId: userId,
          convexClient: widget.convexClient,
        ),
      ),
    );
  }
}
