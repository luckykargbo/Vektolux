// lib/features/admin/presentation/views/admin_dev_tools_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Developer & Admin Quick-Seed & Asset Tools Screen
// Internal-only dev tool for 1-click authentic Sierra Leone test data seeding,
// direct batch asset uploading, and draft/published visibility toggling.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/services/sqlite_post_archive_service.dart';
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

  // SQLite Archive State
  bool _isLoadingArchive = false;
  List<Map<String, dynamic>> _archivedPosts = [];
  String _archiveSearch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAdminListings();
    _loadArchivedPosts();
  }

  Future<void> _loadArchivedPosts() async {
    setState(() => _isLoadingArchive = true);
    try {
      final archiveService = SqlitePostArchiveService(widget.database);
      final posts = await archiveService.getAllArchivedPosts();
      if (mounted) {
        setState(() {
          _archivedPosts = posts;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load SQLite archives: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingArchive = false);
    }
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
            Tab(icon: Icon(Icons.archive_outlined, size: 20), text: 'SQLite Archive'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildQuickSeedTab(),
          _buildAssetUploaderTab(),
          _buildListingsInspectorTab(),
          _buildSqliteArchiveTab(),
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

  // ═══════════════════════════════════════════════════════════════════
  //                    TAB 4: SQLITE ARCHIVE LEDGER
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSqliteArchiveTab() {
    final filtered = _archivedPosts.where((p) {
      if (_archiveSearch.isEmpty) return true;
      final query = _archiveSearch.toLowerCase();
      final title = (p['title'] ?? '').toString().toLowerCase();
      final phone = (p['private_contact_phone'] ?? '').toString().toLowerCase();
      final id = (p['id'] ?? '').toString().toLowerCase();
      final owner = (p['owner_id'] ?? '').toString().toLowerCase();
      final location = (p['location'] ?? '').toString().toLowerCase();
      return title.contains(query) ||
          phone.contains(query) ||
          id.contains(query) ||
          owner.contains(query) ||
          location.contains(query);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadArchivedPosts,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Explanatory Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
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
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFF34D399),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SQLite Archive Ledger',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Audit vault for user-deleted posts',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        tooltip: 'Reload SQLite Archive',
                        onPressed: _loadArchivedPosts,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'When users delete their listings, the records are wiped clean from public Convex cloud databases and permanently archived here in local SQLite storage. Administrators can retrieve seller contact phone numbers, original prices, and specifications at any time.',
                    style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'TOTAL ARCHIVED RECORDS: ${_archivedPosts.length}',
                      style: const TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search Bar
            TextField(
              onChanged: (val) => setState(() => _archiveSearch = val),
              decoration: InputDecoration(
                hintText: 'Search by title, phone, location, owner...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoadingArchive)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (filtered.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 48,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _archivedPosts.isEmpty
                          ? 'No posts currently archived in SQLite'
                          : 'No matching archived records found',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _archivedPosts.isEmpty
                          ? 'When users delete properties or vehicles, full details and private contact numbers are permanently preserved in SQLite.'
                          : 'Try adjusting your search query.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, idx) {
                  final post = filtered[idx];
                  final postType = (post['post_type'] ?? 'property').toString();
                  final title = (post['title'] ?? 'Untitled Listing').toString();
                  final category = (post['category'] ?? '').toString();
                  final price = (post['price'] as num?)?.toDouble() ?? 0.0;
                  final currency = (post['currency'] ?? 'SLE').toString();
                  final location = (post['location'] ?? 'Sierra Leone').toString();
                  final phone = (post['private_contact_phone'] ?? '').toString();
                  final ownerId = (post['owner_id'] ?? '').toString();
                  final bedrooms = post['bedrooms'] as num?;
                  final bathrooms = post['bathrooms'] as num?;
                  final archivedAt = (post['archived_at'] as num?)?.toInt() ?? 0;
                  final originalCreatedAt = (post['original_created_at'] as num?)?.toInt() ?? 0;
                  final isProperty = postType.toLowerCase() == 'property';

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Post Type & Timestamp Row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isProperty
                                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                    : const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isProperty ? Icons.home_work_outlined : Icons.directions_car_outlined,
                                    size: 13,
                                    color: isProperty ? const Color(0xFF059669) : const Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isProperty ? 'PROPERTY' : 'VEHICLE',
                                    style: TextStyle(
                                      color: isProperty ? const Color(0xFF059669) : const Color(0xFF2563EB),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (category.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  category.toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFF475569),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            Text(
                              archivedAt > 0
                                  ? 'Archived ${DateTime.fromMillisecondsSinceEpoch(archivedAt).toLocal().toString().split('.').first}'
                                  : 'Archived',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Title & Price
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '$currency ${price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF64748B)),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                location,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        if (isProperty && (bedrooms != null || bathrooms != null)) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (bedrooms != null) ...[
                                const Icon(Icons.bed_outlined, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 4),
                                Text(
                                  '$bedrooms Beds',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 12),
                              ],
                              if (bathrooms != null) ...[
                                const Icon(Icons.bathtub_outlined, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 4),
                                Text(
                                  '$bathrooms Baths',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ),
                        ],

                        const SizedBox(height: 12),

                        // ── PRIVATE SELLER CONTACT (ADMIN RETRIEVAL ONLY) ──
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lock_outline_rounded, size: 18, color: Color(0xFF16A34A)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'PRIVATE SELLER CONTACT (ADMIN RETRIEVAL ONLY)',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF15803D),
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    SelectableText(
                                      phone.isNotEmpty ? phone : 'No private phone provided',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: phone.isNotEmpty ? const Color(0xFF14532D) : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (phone.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFF16A34A)),
                                  tooltip: 'Copy Phone',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: phone));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Copied $phone to clipboard'),
                                        backgroundColor: const Color(0xFF15803D),
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Footer info: Owner ID, Creation Date, and Copy JSON
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                originalCreatedAt > 0
                                    ? 'Owner: $ownerId • Posted ${DateTime.fromMillisecondsSinceEpoch(originalCreatedAt).toLocal().toString().split(' ').first}'
                                    : 'Owner: $ownerId',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.code_rounded, size: 14),
                              label: const Text('Copy JSON', style: TextStyle(fontSize: 11)),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF475569),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: jsonEncode(post)));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Archived post JSON copied to clipboard'),
                                    backgroundColor: Color(0xFF0F172A),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
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
