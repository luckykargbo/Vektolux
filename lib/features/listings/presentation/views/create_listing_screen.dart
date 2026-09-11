// lib/features/listings/presentation/views/create_listing_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Create Listing Wizard
// 4-step listing creation for vendors/agents with media upload & offline cache.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/verified_badge.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../verification/presentation/views/identity_verification_screen.dart';
import '../../../verification/presentation/widgets/verification_gate_banner.dart';
import 'package:drift/drift.dart' show Value;

enum ListingType { property, vehicle }

class CreateListingScreen extends StatefulWidget {
  final AppDatabase database;
  final ConvexClientWrapper convexClient;
  final UserEntity currentUser;

  const CreateListingScreen({
    super.key,
    required this.database,
    required this.convexClient,
    required this.currentUser,
  });

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  int _currentStep = 0;
  bool _isSubmitting = false;

  ListingType _listingType = ListingType.property;

  // ── Property Form Controllers ─────────────────────────────────────
  final _propTitleController = TextEditingController();
  final _propDescController = TextEditingController();
  final _propPriceController = TextEditingController();
  final _propHourlyRateController = TextEditingController();
  final _propAddressController =
      TextEditingController(text: '15 Wilkinson Road');
  final _propCityController = TextEditingController(text: 'Freetown');
  final _propBedroomsController = TextEditingController(text: '3');
  final _propBathroomsController = TextEditingController(text: '2');
  final _contactPhoneController = TextEditingController();
  String _propCategory = 'sale';
  final double _propLat = 8.4840;
  final double _propLng = -13.2344;

  // ── Vehicle Form Controllers ──────────────────────────────────────
  final _vehMakeController = TextEditingController();
  final _vehModelController = TextEditingController();
  final _vehYearController = TextEditingController(text: '2022');
  final _vehColorController = TextEditingController(text: 'Silver');
  final _vehPlateController = TextEditingController(text: 'SL-AB 1024');
  final _vehPricePerKmController = TextEditingController();
  final _vehPricePerDayController = TextEditingController();
  final _vehSalePriceController = TextEditingController();
  String _vehType = 'taxi';
  String _vehIntent = 'rental';
  final double _vehLat = 8.4840;
  final double _vehLng = -13.2344;

  // ── Uploaded Images ───────────────────────────────────────────────
  final List<StagedMediaItem> _stagedImages = [];

  List<String> get _imageUrls => _stagedImages
      .map((i) => i.remoteUrl ?? i.localPath ?? '')
      .where((url) => url.isNotEmpty)
      .toList();

  List<String> get _imageStorageIds => _stagedImages
      .map((i) => i.storageId ?? 'local_media_${i.id}')
      .toList();

  // ── Verification Gate State ───────────────────────────────────────
  late bool _isUserVerified;
  String _verificationStatus = 'unverified';

  // Business verification (for agents/merchants only)
  String _businessVerificationStatus = 'unverified';

  /// True when the user has all required verifications to publish listings.
  bool get _canPublish {
    final role = widget.currentUser.role;
    if (role == UserRole.agent || role == UserRole.merchant) {
      // Agents/merchants need approved business verification (identity KYC optional)
      return _businessVerificationStatus == 'approved' ||
          _businessVerificationStatus == 'verified';
    }
    // Clients only need identity KYC
    return _isUserVerified;
  }

  /// Explanation string for the gate banner.
  String get _verificationGateStatus {
    final role = widget.currentUser.role;
    if (role == UserRole.agent || role == UserRole.merchant) {
      return _businessVerificationStatus;
    }
    return _verificationStatus;
  }

  @override
  void initState() {
    super.initState();
    _isUserVerified = widget.currentUser.isVerified;
    _verificationStatus = widget.currentUser.verificationStatus;
    _businessVerificationStatus = widget.currentUser.verificationStatus;
    _checkLiveVerificationStatus();
  }

  void _checkLiveVerificationStatus() async {
    final role = widget.currentUser.role;

    // Always check identity KYC
    final res = await widget.convexClient.query(
      'verification:getVerificationStatus',
      args: {'userId': widget.currentUser.id},
    );
    if (res.success && res.value != null && mounted) {
      final data = res.value as Map<String, dynamic>;
      setState(() {
        _isUserVerified = data['isVerified'] as bool? ?? false;
        _verificationStatus = data['status'] as String? ?? 'unverified';
      });
    }

    // For agents/merchants also check business verification
    if (role == UserRole.agent || role == UserRole.merchant) {
      final bizRes = await widget.convexClient.query(
        'businessVerification:getMyVerificationStatus',
        args: {
          'userId': widget.currentUser.id,
          if (widget.currentUser.sessionToken != null)
            'sessionToken': widget.currentUser.sessionToken,
        },
      );
      if (bizRes.success && bizRes.value != null && mounted) {
        final bizData = bizRes.value as Map<String, dynamic>;
        setState(() {
          _businessVerificationStatus =
              bizData['verificationStatus'] as String? ?? 'pending';
        });
      }
    }
  }

  void _openVerificationWizard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => IdentityVerificationScreen(
          convexClient: widget.convexClient,
          currentUser: widget.currentUser,
          usersDao: widget.database.cachedUsersDao,
          onVerificationComplete: () {
            Navigator.of(ctx).pop();
            setState(() {
              _isUserVerified = true;
              _verificationStatus = 'verified';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Identity verified! Green Tick trust badge activated. You can now publish listings.'),
                backgroundColor: AppColors.emerald,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _propTitleController.dispose();
    _propDescController.dispose();
    _propPriceController.dispose();
    _propHourlyRateController.dispose();
    _propAddressController.dispose();
    _propCityController.dispose();
    _vehMakeController.dispose();
    _vehModelController.dispose();
    _vehYearController.dispose();
    _vehColorController.dispose();
    _vehPlateController.dispose();
    _vehPricePerKmController.dispose();
    _vehPricePerDayController.dispose();
    _vehSalePriceController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Pick and upload a single photo for a named preset slot
  Future<void> _pickAndUploadForSlot(String slotLabel) async {
    final option = await ImageUploadService.showImageSourceDialog(context, allowMulti: false);
    if (option == null) return;

    final XFile? file = option == ImageSourceOption.camera
        ? await ImageUploadService.pickImageFromCamera()
        : await ImageUploadService.pickImageFromGallery();

    if (file == null) return;

    await _processAndUploadFile(file, slotLabel: slotLabel);
  }

  /// Pick multiple photos from gallery or camera for central staging
  Future<void> _pickAndUploadMultiple({String defaultSlot = 'Photo'}) async {
    final option = await ImageUploadService.showImageSourceDialog(context, allowMulti: true);
    if (option == null) return;

    if (option == ImageSourceOption.camera) {
      final file = await ImageUploadService.pickImageFromCamera();
      if (file != null) {
        await _processAndUploadFile(file, slotLabel: defaultSlot);
      }
    } else {
      final files = await ImageUploadService.pickMultipleImages();
      if (files.isEmpty) {
        // Fallback to single picker if multi returns empty
        final single = await ImageUploadService.pickImageFromGallery();
        if (single != null) {
          await _processAndUploadFile(single, slotLabel: defaultSlot);
        }
        return;
      }
      for (int i = 0; i < files.length; i++) {
        final label = files.length == 1 ? defaultSlot : '$defaultSlot ${i + 1}';
        await _processAndUploadFile(files[i], slotLabel: label);
      }
    }
  }

  /// Read file bytes, stage thumbnail immediately, and trigger background Convex upload
  Future<void> _processAndUploadFile(XFile file, {required String slotLabel}) async {
    final bytes = await file.readAsBytes();
    final item = StagedMediaItem(
      id: 'img_${DateTime.now().microsecondsSinceEpoch}',
      slotLabel: slotLabel,
      localBytes: bytes,
      localPath: file.path,
      isUploading: true,
    );

    setState(() {
      _stagedImages.add(item);
    });

    try {
      final uploadRes = await ImageUploadService.uploadImageBinaryWithStorageId(
        convexClient: widget.convexClient,
        imageBytes: bytes,
        contentType: file.mimeType ?? 'image/jpeg',
      );

      if (mounted) {
        setState(() {
          item.storageId = uploadRes.storageId;
          item.remoteUrl = uploadRes.publicUrl;
          item.isUploading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploaded "$slotLabel" to Convex cloud storage!'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          item.isUploading = false;
          item.error = e.toString();
          item.storageId = 'local_${DateTime.now().millisecondsSinceEpoch}';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed for "$slotLabel": $e (Staged locally)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _removeStagedImage(StagedMediaItem item) {
    setState(() {
      _stagedImages.removeWhere((i) => i.id == item.id);
    });
  }

  Future<void> _retryUpload(StagedMediaItem item) async {
    if (item.localBytes == null) return;
    setState(() {
      item.isUploading = true;
      item.error = null;
    });

    try {
      final uploadRes = await ImageUploadService.uploadImageBinaryWithStorageId(
        convexClient: widget.convexClient,
        imageBytes: item.localBytes!,
        contentType: 'image/jpeg',
      );
      if (mounted) {
        setState(() {
          item.storageId = uploadRes.storageId;
          item.remoteUrl = uploadRes.publicUrl;
          item.isUploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          item.isUploading = false;
          item.error = e.toString();
        });
      }
    }
  }

  /// Final submit: save to Convex backend & cache directly to SQLite
  Future<void> _submitListing() async {
    if (!_canPublish) {
      _openVerificationWizard();
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (_listingType == ListingType.property) {
        final price = double.tryParse(_propPriceController.text.trim()) ?? 0;
        final hourlyRate = _propCategory == 'hourly_guesthouse'
            ? double.tryParse(_propHourlyRateController.text.trim())
            : null;

        // 1. Convex Mutation
        final result = await widget.convexClient.mutation(
          'realEstate:createPropertyListing',
          args: {
            'ownerId': widget.currentUser.id,
            if (widget.currentUser.sessionToken != null)
              'sessionToken': widget.currentUser.sessionToken!,
            'title': _propTitleController.text.trim(),
            'description': _propDescController.text.trim(),
            'category': _propCategory,
            'price': price,
            if (hourlyRate != null) 'hourlyRate': hourlyRate,
            'currency': 'SLE',
            'address': _propAddressController.text.trim(),
            'city': _propCityController.text.trim(),
            'country': 'Sierra Leone',
            'latitude': _propLat,
            'longitude': _propLng,
            'imageStorageIds': _imageStorageIds,
            'bedrooms': int.tryParse(_propBedroomsController.text.trim()) ?? 3,
            'bathrooms': int.tryParse(_propBathroomsController.text.trim()) ?? 2,
            if (_contactPhoneController.text.trim().isNotEmpty)
              'privateContactPhone': _contactPhoneController.text.trim(),
          },
        );

        final listingId = result.success && result.value != null
            ? result.value as String
            : 'local_${DateTime.now().millisecondsSinceEpoch}';

        // 2. Cache into SQLite for instant offline availability
        await widget.database.cachedPropertyListingsDao.insertOrUpdate(
          CachedPropertyListingsTableCompanion.insert(
            id: listingId,
            ownerId: widget.currentUser.id,
            title: _propTitleController.text.trim(),
            description: _propDescController.text.trim(),
            category: _propCategory,
            price: price,
            hourlyRate: Value(hourlyRate),
            address: _propAddressController.text.trim(),
            latitude: _propLat,
            longitude: _propLng,
            primaryImageUrl:
                Value(_imageUrls.isNotEmpty ? _imageUrls.first : null),
            cachedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      } else {
        // Vehicle Listing
        final pricePerKm =
            double.tryParse(_vehPricePerKmController.text.trim());
        final pricePerDay =
            double.tryParse(_vehPricePerDayController.text.trim());
        final salePrice =
            double.tryParse(_vehSalePriceController.text.trim());
        final year = int.tryParse(_vehYearController.text.trim()) ?? 2022;

        // 1. Convex Mutation
        final result = await widget.convexClient.mutation(
          'mobility:createVehicleListing',
          args: {
            'ownerId': widget.currentUser.id,
            if (widget.currentUser.sessionToken != null)
              'sessionToken': widget.currentUser.sessionToken!,
            'vehicleType': _vehType,
            'listingIntent': _vehIntent,
            'make': _vehMakeController.text.trim(),
            'model': _vehModelController.text.trim(),
            'year': year,
            'color': _vehColorController.text.trim(),
            'licensePlate': _vehPlateController.text.trim(),
            if (pricePerKm != null) 'pricePerKm': pricePerKm,
            if (pricePerDay != null) 'pricePerDay': pricePerDay,
            if (salePrice != null) 'salePrice': salePrice,
            'currency': 'SLE',
            'latitude': _vehLat,
            'longitude': _vehLng,
            'imageStorageIds': _imageStorageIds,
            if (_contactPhoneController.text.trim().isNotEmpty)
              'privateContactPhone': _contactPhoneController.text.trim(),
          },
        );

        final listingId = result.success && result.value != null
            ? result.value as String
            : 'local_${DateTime.now().millisecondsSinceEpoch}';

        // 2. Cache into SQLite
        await widget.database.cachedVehicleListingsDao.insertOrUpdate(
          CachedVehicleListingsTableCompanion.insert(
            id: listingId,
            ownerId: widget.currentUser.id,
            vehicleType: _vehType,
            listingIntent: _vehIntent,
            make: _vehMakeController.text.trim(),
            model: _vehModelController.text.trim(),
            year: year,
            pricePerKm: Value(pricePerKm),
            pricePerDay: Value(pricePerDay),
            salePrice: Value(salePrice),
            primaryImageUrl:
                Value(_imageUrls.isNotEmpty ? _imageUrls.first : null),
            cachedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing published and cached successfully!'),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('New Marketplace Listing'),
            if (_canPublish) ...[ 
              const SizedBox(width: 8),
              const VerifiedBadge(size: VerifiedBadgeSize.small, showLabel: true),
            ],
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Step Progress
          _StepIndicator(currentStep: _currentStep),

          // Wizard Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep1Type(),
                _buildStep2Details(),
                _buildStep3Media(),
                _buildStep4Review(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     STEP 1: LISTING TYPE
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStep1Type() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_canPublish) ...[
            VerificationGateBanner(
              onStartVerification: _openVerificationWizard,
              pendingStatus: _verificationGateStatus,
            ),
            const SizedBox(height: 24),
          ],
          Text(
            'What are you listing?',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select the marketplace category for your offering',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 32),

          // Property Option Card
          _TypeOptionCard(
            title: 'Real Estate Property',
            subtitle: 'Houses, apartments, lands, or hourly guest houses',
            icon: Icons.apartment_outlined,
            isSelected: _listingType == ListingType.property,
            onTap: () => setState(() => _listingType = ListingType.property),
          ),
          const SizedBox(height: 16),

          // Vehicle Option Card
          _TypeOptionCard(
            title: 'Vehicle / Fleet Asset',
            subtitle: 'Bikes, standard taxis, delivery vans, or heavy trucks',
            icon: Icons.directions_car_outlined,
            isSelected: _listingType == ListingType.vehicle,
            onTap: () => setState(() => _listingType = ListingType.vehicle),
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _canPublish ? () => _goToStep(1) : _openVerificationWizard,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canPublish ? AppColors.emerald : AppColors.amber,
              ),
              child: Text(
                _canPublish ? 'Continue to Details' : 'Verify to Continue',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     STEP 2: FORM DETAILS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStep2Details() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _listingType == ListingType.property
                  ? 'Property Specifications'
                  : 'Vehicle Specifications',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                  ),
            ),
            const SizedBox(height: 20),

            if (_listingType == ListingType.property) ...[
              // Property Category Dropdown
              DropdownButtonFormField<String>(
                initialValue: _propCategory,
                dropdownColor: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                elevation: 4,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.obsidian),
                style: const TextStyle(
                  color: AppColors.obsidian,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  labelText: 'Category',
                  hintText: 'Select property category',
                  prefixIcon: Icon(Icons.apartment_rounded),
                ),
                selectedItemBuilder: (context) {
                  return const [
                    Text('For Sale (Outright)', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                    Text('Long-Term / Annual Rent', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                    Text('Hourly Guest House', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                  ];
                },
                items: const [
                  DropdownMenuItem(
                    value: 'sale',
                    child: Text('For Sale (Outright)', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w500)),
                  ),
                  DropdownMenuItem(
                    value: 'long_term_rent',
                    child: Text('Long-Term / Annual Rent', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w500)),
                  ),
                  DropdownMenuItem(
                    value: 'hourly_guesthouse',
                    child: Text('Hourly Guest House', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w500)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _propCategory = v);
                },
              ),
              const SizedBox(height: 16),

              // Title
              TextFormField(
                controller: _propTitleController,
                decoration: const InputDecoration(
                  labelText: 'Listing Title',
                  hintText: 'e.g. Modern 3-Bedroom Villa in Aberdeen',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _propDescController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe amenities, views, security...',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Description is required'
                    : null,
              ),
              const SizedBox(height: 16),

              // Price
              TextFormField(
                controller: _propPriceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _propCategory == 'hourly_guesthouse'
                      ? 'Base / Overnight Price (SLE)'
                      : 'Total Price (SLE)',
                  prefixText: 'SLE  ',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Price is required' : null,
              ),
              const SizedBox(height: 16),

              if (_propCategory == 'hourly_guesthouse') ...[
                TextFormField(
                  controller: _propHourlyRateController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Hourly Rate (SLE/hr)',
                    prefixText: 'SLE  ',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Hourly rate is required'
                      : null,
                ),
                const SizedBox(height: 16),
              ],

              // Address & City
              TextFormField(
                controller: _propAddressController,
                decoration: const InputDecoration(
                  labelText: 'Street Address',
                  hintText: 'e.g. 15 Wilkinson Road',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _propCityController,
                decoration: const InputDecoration(
                  labelText: 'City / District',
                  hintText: 'e.g. Freetown',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // Bedrooms & Bathrooms Row
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _propBedroomsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Bedrooms / Rooms',
                        hintText: 'e.g. 3',
                        prefixIcon: Icon(Icons.bed_rounded),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _propBathroomsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Bathrooms',
                        hintText: 'e.g. 2',
                        prefixIcon: Icon(Icons.bathtub_rounded),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Private Owner Phone Input & Privacy Banner
              TextFormField(
                controller: _contactPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Owner / Agent Phone Number',
                  hintText: 'e.g. +232 76 123 456',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.emerald.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: AppColors.emeraldDark),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '🔒 Private Contact: Stored safely in our database for admin contact only. Never published or displayed to public viewers.',
                        style: TextStyle(fontSize: 11, color: AppColors.emeraldDark, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Vehicle Type
              DropdownButtonFormField<String>(
                initialValue: _vehType,
                dropdownColor: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                elevation: 4,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.obsidian),
                style: const TextStyle(
                  color: AppColors.obsidian,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  labelText: 'Vehicle Type',
                  hintText: 'Select vehicle category',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                ),
                selectedItemBuilder: (context) {
                  return const [
                    Text('Standard Taxi', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                    Text('Motorcycle (Bike)', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                    Text('Delivery Van', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                    Text('Heavy Transport Truck', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                  ];
                },
                items: const [
                  DropdownMenuItem(
                    value: 'taxi',
                    child: Text('Standard Taxi', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w500)),
                  ),
                  DropdownMenuItem(
                    value: 'bike',
                    child: Text('Motorcycle (Bike)', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w500)),
                  ),
                  DropdownMenuItem(
                    value: 'delivery_van',
                    child: Text('Delivery Van', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w500)),
                  ),
                  DropdownMenuItem(
                    value: 'truck',
                    child: Text('Heavy Transport Truck', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w500)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _vehType = v);
                },
              ),
              const SizedBox(height: 16),

              // Listing Intent
              DropdownButtonFormField<String>(
                initialValue: _vehIntent,
                dropdownColor: AppColors.white,
                borderRadius: BorderRadius.circular(12),
                elevation: 4,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.obsidian),
                style: const TextStyle(
                  color: AppColors.obsidian,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  labelText: 'Listing Intent',
                  hintText: 'Select listing intent',
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
                selectedItemBuilder: (context) {
                  return const [
                    Text('Daily / Weekly Rental', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                    Text('Ride-Hailing Fleet', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                    Text('Vehicle for Sale', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w600)),
                  ];
                },
                items: const [
                  DropdownMenuItem(
                    value: 'rental',
                    child: Text('Daily / Weekly Rental', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w500)),
                  ),
                  DropdownMenuItem(
                    value: 'ride_hailing',
                    child: Text('Ride-Hailing Fleet', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w500)),
                  ),
                  DropdownMenuItem(
                    value: 'sale',
                    child: Text('Vehicle for Sale', style: TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w500)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _vehIntent = v);
                },
              ),
              const SizedBox(height: 16),

              // Make & Model
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _vehMakeController,
                      decoration: const InputDecoration(
                        labelText: 'Make',
                        hintText: 'e.g. Toyota',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _vehModelController,
                      decoration: const InputDecoration(
                        labelText: 'Model',
                        hintText: 'e.g. RAV4',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Year & Color
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _vehYearController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Year'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _vehColorController,
                      decoration: const InputDecoration(labelText: 'Color'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Pricing based on intent
              if (_vehIntent == 'rental')
                TextFormField(
                  controller: _vehPricePerDayController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Daily Rental Rate (SLE)',
                    prefixText: 'SLE  ',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Rental rate required'
                      : null,
                )
              else if (_vehIntent == 'ride_hailing')
                TextFormField(
                  controller: _vehPricePerKmController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Rate per Km (SLE)',
                    prefixText: 'SLE  ',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Rate required' : null,
                )
              else
                TextFormField(
                  controller: _vehSalePriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sale Price (SLE)',
                    prefixText: 'SLE  ',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Price required' : null,
                ),
              const SizedBox(height: 16),

              // Private Owner Phone Input & Privacy Banner
              TextFormField(
                controller: _contactPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Seller / Dealer Phone Number',
                  hintText: 'e.g. +232 76 123 456',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.emerald.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: AppColors.emeraldDark),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '🔒 Private Contact: Stored safely in our database for admin contact only. Never published or displayed to public viewers.',
                        style: TextStyle(fontSize: 11, color: AppColors.emeraldDark, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _goToStep(0),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState?.validate() == true) {
                        _goToStep(2);
                      }
                    },
                    child: const Text('Next: Media'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     STEP 3: MULTI-IMAGE PICKER
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStep3Media() {
    final samplePhotos = _listingType == ListingType.property
        ? [
            'Exterior Front View',
            'Master Living Room',
            'Modern Kitchen',
            'Balcony View'
          ]
        : [
            'Vehicle Front 3/4',
            'Interior Dashboard',
            'Rear View',
            'Odometer & Engine'
          ];

    final hasImages = _stagedImages.isNotEmpty;
    final isAnyUploading = _stagedImages.any((i) => i.isUploading);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upload Photos',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'High-quality media increases inquiries by up to 3x on Vektolux',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Upload action cards
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Quick Upload Presets:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.obsidian,
                ),
              ),
              Text(
                '${_stagedImages.length} photo(s)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.emeraldDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: samplePhotos.map((photo) {
              final isUploaded =
                  _stagedImages.any((img) => img.slotLabel == photo);
              return ActionChip(
                avatar: Icon(
                  isUploaded ? Icons.check_circle : Icons.camera_alt_outlined,
                  size: 16,
                  color: isUploaded ? AppColors.emerald : AppColors.gray600,
                ),
                backgroundColor: isUploaded ? const Color(0xFFECFDF5) : null,
                side: isUploaded
                    ? const BorderSide(color: AppColors.emerald)
                    : null,
                label: Text(photo),
                onPressed: () => _pickAndUploadForSlot(photo),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Staged photos container or thumbnail grid
          Expanded(
            child: !hasImages
                ? GestureDetector(
                    onTap: () => _pickAndUploadMultiple(defaultSlot: 'Photo'),
                    child: CustomPaint(
                      painter: _DashedBorderPainter(
                        color: const Color(0xFFCBD5E1),
                        strokeWidth: 2,
                        dash: 6,
                        gap: 4,
                        radius: 16,
                      ),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669)
                                    .withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.cloud_upload_outlined,
                                size: 42,
                                color: Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No photos uploaded yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Tap any slot above or choose from gallery to upload images',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF475569),
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _pickAndUploadMultiple(defaultSlot: 'Photo'),
                              icon: const Icon(Icons.add_photo_alternate,
                                  size: 18),
                              label: const Text('Choose from Gallery'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: _stagedImages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == _stagedImages.length) {
                          // "+ Add More" tile
                          return InkWell(
                            onTap: () =>
                                _pickAndUploadMultiple(defaultSlot: 'Photo'),
                            borderRadius: BorderRadius.circular(12),
                            child: CustomPaint(
                              painter: _DashedBorderPainter(
                                color: const Color(0xFFCBD5E1),
                                strokeWidth: 1.5,
                                dash: 5,
                                gap: 3,
                                radius: 12,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined,
                                        size: 28, color: Color(0xFF059669)),
                                    SizedBox(height: 6),
                                    Text(
                                      'Add More',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        final item = _stagedImages[index];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Image preview
                              if (item.localBytes != null)
                                Image.memory(
                                  item.localBytes!,
                                  fit: BoxFit.cover,
                                )
                              else if (item.remoteUrl != null &&
                                  item.remoteUrl!.startsWith('http'))
                                Image.network(
                                  item.remoteUrl!,
                                  fit: BoxFit.cover,
                                )
                              else
                                Container(
                                  color: AppColors.gray200,
                                  child: const Icon(Icons.image,
                                      color: AppColors.gray400),
                                ),

                              // Slot Label Tag (Top-Left)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xCC0F172A),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item.slotLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),

                              // Delete Button (Top-Right)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: InkWell(
                                  onTap: () => _removeStagedImage(item),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Color(0xCCEF4444),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),

                              // Uploading overlay
                              if (item.isUploading)
                                Container(
                                  color: Colors.black54,
                                  child: const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(height: 6),
                                        Text(
                                          'Uploading...',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // Success checkmark (Bottom-Right)
                              if (!item.isUploading &&
                                  item.storageId != null &&
                                  item.error == null)
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF059669),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),

                              // Error overlay with retry
                              if (item.error != null && !item.isUploading)
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    color: const Color(0xDDDC2626),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 2, horizontal: 4),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Text(
                                          'Retry',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: () => _retryUpload(item),
                                          child: const Icon(Icons.refresh,
                                              color: Colors.white, size: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),

          const SizedBox(height: 12),

          // Validation guidance message if empty
          if (!hasImages)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 15, color: Color(0xFFDC2626)),
                  SizedBox(width: 6),
                  Text(
                    'Please upload at least 1 image to proceed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
            ),

          if (isAnyUploading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF059669)),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Uploading images to Convex cloud storage...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF059669),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _goToStep(1),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (!hasImages || isAnyUploading)
                      ? null
                      : () => _goToStep(3),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                  ),
                  child: const Text('Review Listing'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     STEP 4: REVIEW & SUBMIT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStep4Review() {
    final title = _listingType == ListingType.property
        ? _propTitleController.text
        : '${_vehMakeController.text} ${_vehModelController.text}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm & Publish',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Review all listing data. Once published, your listing will sync to cloud and be cached offline.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReviewRow(
                  label: 'Type',
                  value: _listingType == ListingType.property
                      ? 'Real Estate'
                      : 'Vehicle / Fleet',
                ),
                const Divider(),
                _ReviewRow(label: 'Title', value: title),
                const Divider(),
                _ReviewRow(
                  label: 'Category',
                  value: _listingType == ListingType.property
                      ? _propCategory
                      : '$_vehType ($_vehIntent)',
                ),
                const Divider(),
                _ReviewRow(
                  label: 'Photos',
                  value: '${_imageUrls.length} photo(s) staged',
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : () => _goToStep(2),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitListing,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Text('Publish Listing'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: List.generate(4, (index) {
          final isDone = index <= currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDone ? AppColors.emerald : AppColors.gray200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (index < 3) const SizedBox(width: 6),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _TypeOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emeraldSurface : AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.emerald.withValues(alpha: 0.15)
                    : AppColors.gray100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.emerald : AppColors.gray600,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isSelected
                          ? AppColors.emeraldDark
                          : AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
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

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.obsidian,
                  fontSize: 13)),
        ],
      ),
    );
  }
}

/// Represents a media item in the multi-image staging pipeline
class StagedMediaItem {
  final String id;
  final String slotLabel;
  final Uint8List? localBytes;
  final String? localPath;
  String? storageId;
  String? remoteUrl;
  bool isUploading;
  String? error;

  StagedMediaItem({
    required this.id,
    required this.slotLabel,
    this.localBytes,
    this.localPath,
    this.storageId,
    this.remoteUrl,
    this.isUploading = false,
    this.error,
  });
}

/// Custom painter for dashed borders (used in empty upload staging & add tile)
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;
  final double radius;

  _DashedBorderPainter({
    this.color = const Color(0xFFCBD5E1),
    this.strokeWidth = 2,
    this.dash = 6,
    this.gap = 4,
    this.radius = 16,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        strokeWidth / 2,
        strokeWidth / 2,
        size.width - strokeWidth,
        size.height - strokeWidth,
      ),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final pathMetrics = path.computeMetrics();

    for (final metric in pathMetrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double len =
            distance + dash > metric.length ? metric.length - distance : dash;
        final extractPath = metric.extractPath(distance, distance + len);
        canvas.drawPath(extractPath, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap ||
      oldDelegate.radius != radius;
}

