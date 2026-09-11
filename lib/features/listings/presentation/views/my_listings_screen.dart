// lib/features/listings/presentation/views/my_listings_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — My Posts & Listings Management Dashboard
// Displays posts owned by the user, enabling direct editing and soft-deletion
// with permanent local SQLite archival so the administrator can retrieve them.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/services/sqlite_post_archive_service.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vx_network_image.dart';
import '../../../auth/domain/entities/user_entity.dart';
import 'create_listing_screen.dart';

class MyListingsScreen extends StatefulWidget {
  final AppDatabase database;
  final ConvexClientWrapper convexClient;
  final UserEntity currentUser;

  const MyListingsScreen({
    super.key,
    required this.database,
    required this.convexClient,
    required this.currentUser,
  });

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late SqlitePostArchiveService _archiveService;

  bool _isLoading = true;
  List<Map<String, dynamic>> _myProperties = [];
  List<Map<String, dynamic>> _myVehicles = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _archiveService = SqlitePostArchiveService(widget.database);
    _loadMyListings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMyListings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final propRes = await widget.convexClient.query(
        'realEstate:getMyPropertyListings',
        args: {
          'ownerId': widget.currentUser.id,
          if (widget.currentUser.sessionToken != null)
            'sessionToken': widget.currentUser.sessionToken!,
        },
      );

      final vehRes = await widget.convexClient.query(
        'mobility:getMyVehicleListings',
        args: {
          'ownerId': widget.currentUser.id,
          if (widget.currentUser.sessionToken != null)
            'sessionToken': widget.currentUser.sessionToken!,
        },
      );

      if (mounted) {
        setState(() {
          _myProperties = propRes.success && propRes.value != null
              ? (propRes.value as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList()
              : [];
          _myVehicles = vehRes.success && vehRes.value != null
              ? (vehRes.value as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList()
              : [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                        DELETE & ARCHIVE
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _confirmDeletePost({
    required Map<String, dynamic> item,
    required bool isProperty,
  }) async {
    final title = isProperty
        ? (item['title'] ?? 'Property')
        : ('${item['year'] ?? ''} ${item['make'] ?? ''} ${item['model'] ?? ''}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 24),
            SizedBox(width: 8),
            Text('Sold or Remove Post', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Did a client buy or rent "$title", or do you want to remove it?',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: AppColors.emeraldDark, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The post will immediately be removed from Convex public search and permanently archived into your local encrypted SQLite storage for future reference.',
                      style: TextStyle(fontSize: 11, color: AppColors.obsidianSoft, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sold? Delete & Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Deleting post and writing to local SQLite archive...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      final listingId = item['_id']?.toString() ?? '';
      if (isProperty) {
        final res = await widget.convexClient.mutation(
          'realEstate:deletePropertyListing',
          args: {
            'listingId': listingId,
            'ownerId': widget.currentUser.id,
            if (widget.currentUser.sessionToken != null)
              'sessionToken': widget.currentUser.sessionToken!,
          },
        );

        final archiveData = (res.value as Map<String, dynamic>?)?['archivedData'] ?? item;
        await _archiveService.archivePost(
          id: listingId,
          postType: 'property',
          ownerId: widget.currentUser.id,
          title: archiveData['title']?.toString() ?? 'Untitled Property',
          description: archiveData['description']?.toString() ?? '',
          category: archiveData['category']?.toString() ?? 'sale',
          price: (archiveData['price'] as num?)?.toDouble() ?? 0.0,
          currency: archiveData['currency']?.toString() ?? 'SLE',
          location: archiveData['location']?.toString() ?? '${item['address'] ?? ''}, ${item['city'] ?? ''}',
          bedrooms: (archiveData['bedrooms'] as num?)?.toInt() ?? (item['bedrooms'] as num?)?.toInt(),
          bathrooms: (archiveData['bathrooms'] as num?)?.toInt() ?? (item['bathrooms'] as num?)?.toInt(),
          privateContactPhone: archiveData['privateContactPhone']?.toString() ?? item['privateContactPhone']?.toString(),
          imageUrls: (archiveData['imageUrls'] as List?)?.map((e) => e.toString()).toList(),
          originalCreatedAt: (archiveData['originalCreatedAt'] as num?)?.toInt(),
        );
      } else {
        final res = await widget.convexClient.mutation(
          'mobility:deleteVehicleListing',
          args: {
            'listingId': listingId,
            'ownerId': widget.currentUser.id,
            if (widget.currentUser.sessionToken != null)
              'sessionToken': widget.currentUser.sessionToken!,
          },
        );

        final archiveData = (res.value as Map<String, dynamic>?)?['archivedData'] ?? item;
        await _archiveService.archivePost(
          id: listingId,
          postType: 'vehicle',
          ownerId: widget.currentUser.id,
          title: archiveData['title']?.toString() ?? '${item['year'] ?? ''} ${item['make'] ?? ''} ${item['model'] ?? ''}',
          description: archiveData['description']?.toString() ?? '',
          category: archiveData['category']?.toString() ?? item['listingIntent']?.toString() ?? 'rental',
          price: (archiveData['price'] as num?)?.toDouble() ?? 0.0,
          currency: archiveData['currency']?.toString() ?? 'SLE',
          location: archiveData['location']?.toString() ?? 'Sierra Leone',
          bedrooms: null,
          bathrooms: null,
          privateContactPhone: archiveData['privateContactPhone']?.toString() ?? item['privateContactPhone']?.toString(),
          imageUrls: (archiveData['imageUrls'] as List?)?.map((e) => e.toString()).toList(),
          originalCreatedAt: (archiveData['originalCreatedAt'] as num?)?.toInt(),
        );
      }

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('✓ Post removed from public and permanently archived in SQLite.'),
          backgroundColor: AppColors.emeraldDark,
        ),
      );

      _loadMyListings();
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error deleting post: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                        QUICK PRICE UPDATE MODAL
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildQuickAdjustChip(String label, VoidCallback onTap, {required bool isDiscount}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isDiscount ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isDiscount ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: isDiscount ? AppColors.errorDark : AppColors.emeraldDark,
          ),
        ),
      ),
    );
  }

  void _openQuickPriceModal({
    required Map<String, dynamic> item,
    required bool isProperty,
  }) {
    final title = isProperty
        ? (item['title'] ?? 'Property')
        : ('${item['year'] ?? ''} ${item['make'] ?? ''} ${item['model'] ?? ''}');
    final currentPriceNum = (isProperty
        ? item['price']
        : (item['salePrice'] ?? item['pricePerDay'])) as num?;
    final initialPrice = currentPriceNum?.toDouble() ?? 0.0;
    final currency = item['currency']?.toString() ?? 'SLE';

    final priceController = TextEditingController(
      text: initialPrice > 0 ? initialPrice.toStringAsFixed(0) : '',
    );
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void applyPercentage(double percent) {
              final currentVal = double.tryParse(priceController.text.trim()) ?? initialPrice;
              if (currentVal > 0) {
                final adjusted = (currentVal * (1.0 + percent)).roundToDouble();
                setModalState(() {
                  priceController.text = adjusted.toStringAsFixed(0);
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.gray300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.price_change_rounded, color: AppColors.emeraldDark, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Update Price: $title',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Text(
                              'Adjust selling or rental price. Public search reflects this instantly.',
                              style: TextStyle(fontSize: 11, color: AppColors.gray500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 16),

                  // Quick Adjust Chips
                  Row(
                    children: [
                      const Text('Quick Adjust:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gray600)),
                      const Spacer(),
                      _buildQuickAdjustChip('-10%', () => applyPercentage(-0.10), isDiscount: true),
                      const SizedBox(width: 6),
                      _buildQuickAdjustChip('-5%', () => applyPercentage(-0.05), isDiscount: true),
                      const SizedBox(width: 6),
                      _buildQuickAdjustChip('+5%', () => applyPercentage(0.05), isDiscount: false),
                      const SizedBox(width: 6),
                      _buildQuickAdjustChip('+10%', () => applyPercentage(0.10), isDiscount: false),
                    ],
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.obsidian),
                    decoration: InputDecoration(
                      labelText: 'New Price ($currency)',
                      prefixText: '$currency  ',
                      prefixStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.emeraldDark),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final newPrice = double.tryParse(priceController.text.trim());
                              if (newPrice == null || newPrice < 0) {
                                ScaffoldMessenger.of(modalCtx).showSnackBar(
                                  const SnackBar(content: Text('Please enter a valid price amount.')),
                                );
                                return;
                              }

                              setModalState(() => isSaving = true);
                              final listingId = item['_id']?.toString() ?? '';

                              try {
                                if (isProperty) {
                                  await widget.convexClient.mutation(
                                    'realEstate:updatePropertyListing',
                                    args: {
                                      'listingId': listingId,
                                      'ownerId': widget.currentUser.id,
                                      if (widget.currentUser.sessionToken != null)
                                        'sessionToken': widget.currentUser.sessionToken!,
                                      'price': newPrice,
                                    },
                                  );
                                } else {
                                  final isRental = item['listingIntent'] == 'rental';
                                  final args = <String, dynamic>{
                                    'listingId': listingId,
                                    'ownerId': widget.currentUser.id,
                                    if (widget.currentUser.sessionToken != null)
                                      'sessionToken': widget.currentUser.sessionToken!,
                                  };
                                  if (isRental) {
                                    args['pricePerDay'] = newPrice;
                                  } else {
                                    args['salePrice'] = newPrice;
                                  }
                                  await widget.convexClient.mutation(
                                    'mobility:updateVehicleListing',
                                    args: args,
                                  );
                                }

                                if (modalCtx.mounted) Navigator.of(modalCtx).pop();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('✓ Price updated to $currency ${newPrice.toStringAsFixed(0)}! Buyers browsing see this updated price.'),
                                      backgroundColor: AppColors.emeraldDark,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  _loadMyListings();
                                }
                              } catch (e) {
                                setModalState(() => isSaving = false);
                                if (modalCtx.mounted) {
                                  ScaffoldMessenger.of(modalCtx).showSnackBar(
                                    SnackBar(content: Text('Update failed: $e'), backgroundColor: AppColors.error),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald,
                        foregroundColor: AppColors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Save & Publish Updated Price', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                        EDIT MODAL
  // ═══════════════════════════════════════════════════════════════════

  void _openEditModal({
    required Map<String, dynamic> item,
    required bool isProperty,
  }) {
    final titleController = TextEditingController(
      text: isProperty ? (item['title'] ?? '') : ('${item['make'] ?? ''} ${item['model'] ?? ''}'),
    );
    final priceController = TextEditingController(
      text: (item['price'] ?? item['salePrice'] ?? item['pricePerDay'] ?? '').toString(),
    );
    final descController = TextEditingController(text: item['description'] ?? '');
    final bedsController = TextEditingController(text: (item['bedrooms'] ?? 3).toString());
    final bathsController = TextEditingController(text: (item['bathrooms'] ?? 2).toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isProperty ? 'Edit Property Post' : 'Edit Vehicle Post',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.obsidian),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              TextFormField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title / Headline'),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Price (SLE)', prefixText: 'SLE  '),
              ),
              const SizedBox(height: 12),

              if (isProperty) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: bedsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Bedrooms / Rooms'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: bathsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Bathrooms'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              TextFormField(
                controller: descController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final price = double.tryParse(priceController.text.trim()) ?? 0;
                    final listingId = item['_id']?.toString() ?? '';

                    try {
                      if (isProperty) {
                        await widget.convexClient.mutation(
                          'realEstate:updatePropertyListing',
                          args: {
                            'listingId': listingId,
                            'ownerId': widget.currentUser.id,
                            if (widget.currentUser.sessionToken != null)
                              'sessionToken': widget.currentUser.sessionToken!,
                            'title': titleController.text.trim(),
                            'price': price,
                            'description': descController.text.trim(),
                            'bedrooms': int.tryParse(bedsController.text.trim()) ?? 3,
                            'bathrooms': int.tryParse(bathsController.text.trim()) ?? 2,
                          },
                        );
                      } else {
                        await widget.convexClient.mutation(
                          'mobility:updateVehicleListing',
                          args: {
                            'listingId': listingId,
                            'ownerId': widget.currentUser.id,
                            if (widget.currentUser.sessionToken != null)
                              'sessionToken': widget.currentUser.sessionToken!,
                            'salePrice': price,
                            'pricePerDay': price,
                          },
                        );
                      }

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✓ Post updated successfully'),
                          backgroundColor: AppColors.emeraldDark,
                        ),
                      );
                      _loadMyListings();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Update failed: $e'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                        BUILD UI
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: const Text(
          'My Listings & Posts',
          style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w700, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.obsidian, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.obsidian),
            onPressed: _loadMyListings,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.emeraldDark),
            tooltip: 'Create New Post',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CreateListingScreen(
                    database: widget.database,
                    convexClient: widget.convexClient,
                    currentUser: widget.currentUser,
                  ),
                ),
              ).then((_) => _loadMyListings());
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.emeraldDark,
          unselectedLabelColor: AppColors.gray500,
          indicatorColor: AppColors.emerald,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: [
            Tab(
              icon: const Icon(Icons.home_work_rounded, size: 20),
              text: 'Properties (${_myProperties.length})',
            ),
            Tab(
              icon: const Icon(Icons.directions_car_rounded, size: 20),
              text: 'Vehicles (${_myVehicles.length})',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.emerald),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                        const SizedBox(height: 12),
                        Text('Error loading listings: $_errorMessage', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadMyListings,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPropertiesList(),
                    _buildVehiclesList(),
                  ],
                ),
    );
  }

  Widget _buildPropertiesList() {
    if (_myProperties.isEmpty) {
      return _buildEmptyState(
        title: 'No Properties Posted Yet',
        subtitle: 'Post a house, apartment, land, or guest house. Specify rooms, bathrooms, and keep your phone private.',
        isProperty: true,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myProperties.length,
      itemBuilder: (context, index) {
        final item = _myProperties[index];
        final title = item['title']?.toString() ?? 'Untitled Property';
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final currency = item['currency']?.toString() ?? 'SLE';
        final address = item['address']?.toString() ?? 'Freetown';
        final beds = item['bedrooms'] ?? 0;
        final baths = item['bathrooms'] ?? 0;
        final category = item['category']?.toString() ?? 'sale';
        final images = (item['imageUrls'] as List?)?.cast<String>() ?? [];
        final imageUrl = images.isNotEmpty ? images.first : null;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Media thumbnail or branded fallback
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 84,
                        height: 84,
                        child: VxNetworkImage(
                          imageUrl: imageUrl,
                          fallbackIcon: Icons.home_work_outlined,
                          fallbackLabel: 'PROPERTY',
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.emerald.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  category.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.emeraldDark,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const Icon(Icons.circle, color: AppColors.emerald, size: 8),
                              const SizedBox(width: 4),
                              const Text('Live', style: TextStyle(fontSize: 11, color: AppColors.emeraldDark, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.obsidian),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$currency ${price.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.emeraldDark),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$address • $beds Beds • $baths Baths',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.price_change_outlined, size: 15, color: AppColors.emeraldDark),
                      label: const Text('Update Price', style: TextStyle(color: AppColors.emeraldDark, fontWeight: FontWeight.w700, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.emerald, width: 1.2),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _openQuickPriceModal(item: item, isProperty: true),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 15, color: AppColors.obsidian),
                      label: const Text('Edit Details', style: TextStyle(color: AppColors.obsidian, fontSize: 12)),
                      onPressed: () => _openEditModal(item: item, isProperty: true),
                    ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.error),
                      label: const Text('Sold? Delete', style: TextStyle(color: AppColors.error, fontSize: 12)),
                      onPressed: () => _confirmDeletePost(item: item, isProperty: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVehiclesList() {
    if (_myVehicles.isEmpty) {
      return _buildEmptyState(
        title: 'No Vehicles Posted Yet',
        subtitle: 'Post your car, taxi, tricycle, or van for rent or sale. Control pricing and protect your contact info.',
        isProperty: false,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _myVehicles.length,
      itemBuilder: (context, index) {
        final item = _myVehicles[index];
        final make = item['make']?.toString() ?? 'Vehicle';
        final model = item['model']?.toString() ?? '';
        final year = item['year']?.toString() ?? '';
        final price = (item['salePrice'] ?? item['pricePerDay'] as num?)?.toDouble() ?? 0.0;
        final currency = item['currency']?.toString() ?? 'SLE';
        final intent = item['listingIntent']?.toString() ?? 'rental';
        final images = (item['imageUrls'] as List?)?.cast<String>() ?? [];
        final imageUrl = images.isNotEmpty ? images.first : null;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 84,
                        height: 84,
                        child: VxNetworkImage(
                          imageUrl: imageUrl,
                          fallbackIcon: Icons.directions_car_outlined,
                          fallbackLabel: 'VEHICLE',
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.amberDark.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  intent.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.obsidian,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const Icon(Icons.circle, color: AppColors.emerald, size: 8),
                              const SizedBox(width: 4),
                              const Text('Live', style: TextStyle(fontSize: 11, color: AppColors.emeraldDark, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$year $make $model',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.obsidian),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$currency ${price.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.emeraldDark),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Plate: ${item['licensePlate'] ?? 'N/A'} • Color: ${item['color'] ?? 'N/A'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.price_change_outlined, size: 15, color: AppColors.emeraldDark),
                      label: const Text('Update Price', style: TextStyle(color: AppColors.emeraldDark, fontWeight: FontWeight.w700, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.emerald, width: 1.2),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _openQuickPriceModal(item: item, isProperty: false),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 15, color: AppColors.obsidian),
                      label: const Text('Edit Details', style: TextStyle(color: AppColors.obsidian, fontSize: 12)),
                      onPressed: () => _openEditModal(item: item, isProperty: false),
                    ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.error),
                      label: const Text('Sold? Delete', style: TextStyle(color: AppColors.error, fontSize: 12)),
                      onPressed: () => _confirmDeletePost(item: item, isProperty: false),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required bool isProperty,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isProperty ? Icons.home_work_outlined : Icons.directions_car_outlined,
                size: 48,
                color: AppColors.emeraldDark,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.obsidian),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.gray600, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(isProperty ? 'Post a Property' : 'Post a Vehicle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CreateListingScreen(
                      database: widget.database,
                      convexClient: widget.convexClient,
                      currentUser: widget.currentUser,
                    ),
                  ),
                ).then((_) => _loadMyListings());
              },
            ),
          ],
        ),
      ),
    );
  }
}
