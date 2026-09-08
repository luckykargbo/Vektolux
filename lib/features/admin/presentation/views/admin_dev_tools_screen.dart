// lib/features/admin/presentation/views/admin_dev_tools_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Developer & Admin Quick-Seed & Asset Tools Screen
// Internal-only dev tool for 1-click authentic Sierra Leone test data seeding,
// direct batch asset uploading, and draft/published visibility toggling.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';

class AdminDevToolsScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;
  final AppDatabase database;
  final UserEntity currentUser;

  const AdminDevToolsScreen({
    super.key,
    required this.convexClient,
    required this.database,
    required this.currentUser,
  });

  @override
  State<AdminDevToolsScreen> createState() => _AdminDevToolsScreenState();
}

class _UploadedAssetResult {
  final String filename;
  final String storageId;
  final String publicUrl;
  final Uint8List? bytes;

  _UploadedAssetResult({
    required this.filename,
    required this.storageId,
    required this.publicUrl,
    this.bytes,
  });
}

class _AdminDevToolsScreenState extends State<AdminDevToolsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSeeding = false;
  bool _seedAsPublished = false; // Default: private drafts (isPublished: false)

  // Asset Uploader State
  bool _isBatchUploading = false;
  final List<_UploadedAssetResult> _uploadedAssets = [];

  // Listings Inspector State
  bool _isLoadingListings = false;
  List<Map<String, dynamic>> _adminListings = [];
  String _listingsFilter = 'all'; // all, draft, published, property, vehicle

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAdminListings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminListings() async {
    setState(() => _isLoadingListings = true);
    try {
      final res = await widget.convexClient.query(
        'admin:getAdminListings',
        args: {'vertical': 'all'},
      );

      if (res.success && res.value != null && mounted) {
        final rawList = res.value as List<dynamic>;
        setState(() {
          _adminListings = rawList
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load listings: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingListings = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                   QUICK SEED EXECUTION
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _runQuickSeed({
    required String vertical,
    required String city,
    required String label,
  }) async {
    setState(() => _isSeeding = true);

    try {
      final res = await widget.convexClient.mutation(
        'admin:quickSeedListings',
        args: {
          'vertical': vertical,
          'city': city,
          'isPublished': _seedAsPublished,
        },
      );

      if (mounted) {
        if (res.success && res.value != null) {
          final data = res.value as Map<String, dynamic>;
          final msg = data['message'] as String? ?? 'Seeding completed!';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $msg'),
              backgroundColor: AppColors.emerald,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
          // Reload admin listings
          _loadAdminListings();
        } else {
          throw Exception(res.errorMessage ?? 'Seed mutation failed');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Seed failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                   BATCH ASSET UPLOADER
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _pickAndBatchUpload() async {
    final files = await ImageUploadService.pickMultipleImages();
    if (files.isEmpty) return;

    setState(() => _isBatchUploading = true);

    try {
      int successCount = 0;
      for (final file in files) {
        final bytes = await file.readAsBytes();
        final uploadRes =
            await ImageUploadService.uploadImageBinaryWithStorageId(
          convexClient: widget.convexClient,
          imageBytes: bytes,
          contentType: file.mimeType ?? 'image/jpeg',
        );

        if (mounted) {
          setState(() {
            _uploadedAssets.insert(
              0,
              _UploadedAssetResult(
                filename: file.name,
                storageId: uploadRes.storageId,
                publicUrl: uploadRes.publicUrl,
                bytes: bytes,
              ),
            );
          });
          successCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploaded $successCount image(s) to Convex storage!'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Batch upload error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBatchUploading = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //              TOGGLE LISTING PUBLISHED VISIBILITY
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _togglePublishStatus(
      String listingType, String listingId, bool currentPublished) async {
    final newPublished = !currentPublished;

    try {
      final res = await widget.convexClient.mutation(
        'admin:toggleListingPublished',
        args: {
          'listingType': listingType,
          'listingId': listingId,
          'isPublished': newPublished,
        },
      );

      if (res.success && mounted) {
        setState(() {
          final idx = _adminListings.indexWhere((l) => l['id'] == listingId);
          if (idx != -1) {
            _adminListings[idx]['isPublished'] = newPublished;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newPublished
                  ? 'Listing is now PUBLISHED (visible to public discovery)'
                  : 'Listing moved to PRIVATE DRAFT (hidden from discovery)',
            ),
            backgroundColor:
                newPublished ? AppColors.emerald : AppColors.amberDark,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Toggle failed: $e')),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                    DELETE TEST LISTING
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _deleteListing(String listingType, String listingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Test Listing'),
        content: const Text(
          'Are you sure you want to permanently delete this listing from Convex?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final res = await widget.convexClient.mutation(
        'admin:deleteAdminListing',
        args: {
          'listingType': listingType,
          'listingId': listingId,
        },
      );

      if (res.success && mounted) {
        setState(() {
          _adminListings.removeWhere((l) => l['id'] == listingId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing deleted successfully'),
            backgroundColor: AppColors.obsidian,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate 100
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Dev & Admin Tools',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'DEV ONLY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.obsidian,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF059669),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF059669),
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.flash_on, size: 20), text: 'Quick Seed'),
            Tab(icon: Icon(Icons.cloud_upload, size: 20), text: 'Asset Uploader'),
            Tab(icon: Icon(Icons.view_list, size: 20), text: 'Listings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildQuickSeedTab(),
          _buildAssetUploaderTab(),
          _buildListingsInspectorTab(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                        TAB 1: QUICK SEED
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildQuickSeedTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Visibility Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Seed Visibility Status',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _seedAsPublished
                            ? 'Listings will be PUBLIC immediately in discovery'
                            : 'Listings will be PRIVATE DRAFTS (hidden from public discovery)',
                        style: TextStyle(
                          fontSize: 12,
                          color: _seedAsPublished
                              ? const Color(0xFF059669)
                              : const Color(0xFFD97706),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _seedAsPublished,
                  activeThumbColor: const Color(0xFF059669),
                  onChanged: (val) => setState(() => _seedAsPublished = val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            '1-Click Seed Buttons (Sierra Leone Hubs)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 12),

          if (_isSeeding)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Color(0xFF059669)),
                    SizedBox(height: 12),
                    Text('Injecting authentic test data...'),
                  ],
                ),
              ),
            )
          else ...[
            _SeedActionCard(
              title: 'Seed Freetown Real Estate (3 Properties)',
              subtitle:
                  'Spur Loop Executive Villa, Lumley Ocean Suite & Regent Mountain Ridge',
              icon: Icons.apartment,
              badge: _seedAsPublished ? 'PUBLIC' : 'PRIVATE DRAFT',
              badgeColor: _seedAsPublished
                  ? const Color(0xFF059669)
                  : const Color(0xFFF59E0B),
              onTap: () => _runQuickSeed(
                vertical: 'property',
                city: 'Freetown',
                label: 'Freetown Real Estate',
              ),
            ),
            const SizedBox(height: 12),
            _SeedActionCard(
              title: 'Seed Bo Town Real Estate (2 Properties)',
              subtitle: 'Bo-Tajama Highway Residency & Commercial Gated Compound',
              icon: Icons.home_work,
              badge: _seedAsPublished ? 'PUBLIC' : 'PRIVATE DRAFT',
              badgeColor: _seedAsPublished
                  ? const Color(0xFF059669)
                  : const Color(0xFFF59E0B),
              onTap: () => _runQuickSeed(
                vertical: 'property',
                city: 'Bo',
                label: 'Bo Real Estate',
              ),
            ),
            const SizedBox(height: 12),
            _SeedActionCard(
              title: 'Seed Freetown Vehicles (3 Vehicles)',
              subtitle:
                  'Toyota Land Cruiser Prado (Sale), TVS King Keke & Hyundai Santa Fe (Rental)',
              icon: Icons.directions_car,
              badge: _seedAsPublished ? 'PUBLIC' : 'PRIVATE DRAFT',
              badgeColor: _seedAsPublished
                  ? const Color(0xFF059669)
                  : const Color(0xFFF59E0B),
              onTap: () => _runQuickSeed(
                vertical: 'vehicle',
                city: 'Freetown',
                label: 'Freetown Vehicles',
              ),
            ),
            const SizedBox(height: 12),
            _SeedActionCard(
              title: 'Seed Makeni & Waterloo Hubs (Vehicles & Villas)',
              subtitle:
                  'Toyota Hilux 4x4, TVS Star Okada & Waterloo Gated Compound',
              icon: Icons.local_shipping,
              badge: _seedAsPublished ? 'PUBLIC' : 'PRIVATE DRAFT',
              badgeColor: _seedAsPublished
                  ? const Color(0xFF059669)
                  : const Color(0xFFF59E0B),
              onTap: () => _runQuickSeed(
                vertical: 'both',
                city: 'Makeni',
                label: 'Makeni / Waterloo Catalog',
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                    TAB 2: ASSET UPLOADER
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildAssetUploaderTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Upload button trigger card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_upload_outlined,
                      size: 36, color: Color(0xFF059669)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Direct Multi-Image Asset Uploader',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select multiple high-res photos to upload directly to Convex storage without creating a full listing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isBatchUploading ? null : _pickAndBatchUpload,
                  icon: _isBatchUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.add_photo_alternate, size: 18),
                  label: Text(_isBatchUploading
                      ? 'Uploading to Cloud...'
                      : 'Choose Images to Upload'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Uploaded assets list header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Uploaded CDN Assets (${_uploadedAssets.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
              ),
              if (_uploadedAssets.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _uploadedAssets.clear()),
                  child: const Text('Clear List', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Assets List
          Expanded(
            child: _uploadedAssets.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined,
                            size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        const Text(
                          'No assets uploaded yet in this session',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _uploadedAssets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final asset = _uploadedAssets[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: asset.bytes != null
                                  ? Image.memory(
                                      asset.bytes!,
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 60,
                                      height: 60,
                                      color: AppColors.gray200,
                                      child: const Icon(Icons.image),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    asset.filename,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'ID: ${asset.storageId}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    asset.publicUrl,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF059669),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'Copy Public URL',
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: asset.publicUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Copied URL to clipboard!'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                   TAB 3: LISTINGS INSPECTOR
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildListingsInspectorTab() {
    // Filter listings
    final filtered = _adminListings.where((l) {
      if (_listingsFilter == 'draft') return l['isPublished'] == false;
      if (_listingsFilter == 'published') return l['isPublished'] == true;
      if (_listingsFilter == 'property') return l['type'] == 'property';
      if (_listingsFilter == 'vehicle') return l['type'] == 'vehicle';
      return true;
    }).toList();

    return Column(
      children: [
        // Filter chips bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All (${_adminListings.length})', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Drafts (${_adminListings.where((l) => l['isPublished'] == false).length})',
                  'draft',
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Published (${_adminListings.where((l) => l['isPublished'] == true).length})',
                  'published',
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Properties (${_adminListings.where((l) => l['type'] == 'property').length})',
                  'property',
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Vehicles (${_adminListings.where((l) => l['type'] == 'vehicle').length})',
                  'vehicle',
                ),
              ],
            ),
          ),
        ),

        // Listings List
        Expanded(
          child: _isLoadingListings
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF059669)),
                )
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No listings matching this filter',
                            style: TextStyle(
                                fontSize: 14, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _loadAdminListings,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Refresh'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadAdminListings,
                      color: const Color(0xFF059669),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final id = item['id'] as String;
                          final type = item['type'] as String;
                          final title = item['title'] as String? ?? 'Untitled';
                          final subtitle = item['subtitle'] as String? ?? '';
                          final price = item['price'] as num? ?? 0;
                          final currency =
                              item['currency'] as String? ?? 'SLE';
                          final isPublished =
                              item['isPublished'] as bool? ?? true;
                          final imageUrl = item['imageUrl'] as String? ?? '';

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isPublished
                                    ? const Color(0xFFE2E8F0)
                                    : const Color(0xFFFDE68A), // yellow tint
                                width: isPublished ? 1 : 1.5,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: imageUrl.isNotEmpty
                                      ? Image.network(
                                          imageUrl,
                                          width: 70,
                                          height: 70,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                            width: 70,
                                            height: 70,
                                            color: AppColors.gray200,
                                            child: const Icon(Icons.broken_image),
                                          ),
                                        )
                                      : Container(
                                          width: 70,
                                          height: 70,
                                          color: AppColors.gray200,
                                          child: const Icon(Icons.image),
                                        ),
                                ),
                                const SizedBox(width: 12),

                                // Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isPublished
                                                  ? const Color(0xFFECFDF5)
                                                  : const Color(0xFFFEF3C7),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isPublished
                                                  ? 'PUBLISHED'
                                                  : 'PRIVATE DRAFT',
                                              style: TextStyle(
                                                color: isPublished
                                                    ? const Color(0xFF059669)
                                                    : const Color(0xFFD97706),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            type.toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$currency ${price.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF059669),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Actions: Toggle Switch & Delete
                                Column(
                                  children: [
                                    Switch(
                                      value: isPublished,
                                      activeThumbColor: const Color(0xFF059669),
                                      onChanged: (val) => _togglePublishStatus(
                                        type,
                                        id,
                                        isPublished,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18, color: Color(0xFFEF4444)),
                                      tooltip: 'Delete Test Listing',
                                      onPressed: () =>
                                          _deleteListing(type, id),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _listingsFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF059669),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF475569),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => setState(() => _listingsFilter = value),
    );
  }
}

class _SeedActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String badge;
  final Color badgeColor;
  final VoidCallback onTap;

  const _SeedActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF059669), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}
