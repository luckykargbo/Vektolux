// lib/features/mobility/presentation/views/driver_vehicle_registration_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Commercial Vehicle & Fleet Registration Wizard
// Multi-step registration for:
// 1. Car for Sale / Car Rental (Dealership / Private Auto Seller)
// 2. Cargo & Delivery Van (Light & Medium Freight Logistics)
// 3. Sand / Dump Tipper Truck (Quarry Aggregate & Construction Haulage)
// 4. Container / Flatbed Cargo Truck (Port Containers & Heavy Industrial Freight)
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/commercial_vehicle_catalog.dart';

class DriverVehicleRegistrationScreen extends StatefulWidget {
  final String driverId;
  final VoidCallback? onRegistrationComplete;

  const DriverVehicleRegistrationScreen({
    super.key,
    required this.driverId,
    this.onRegistrationComplete,
  });

  static Future<bool?> open(BuildContext context, {required String driverId}) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DriverVehicleRegistrationScreen(driverId: driverId),
      ),
    );
  }

  @override
  State<DriverVehicleRegistrationScreen> createState() =>
      _DriverVehicleRegistrationScreenState();
}

class _DriverVehicleRegistrationScreenState
    extends State<DriverVehicleRegistrationScreen> {
  int _currentStep = 0; // 0: Category & Specs, 1: Pricing & Logistics, 2: Photos

  // ── Commercial Category ───────────────────────────────────────────
  CommercialVehicleCategory _selectedCategory = CommercialVehicleCategory.carSale;

  // ── Step 1: Specs Controllers ─────────────────────────────────────
  final _makeController = TextEditingController(text: 'Toyota');
  final _modelController = TextEditingController(text: 'RAV4');
  int _selectedYear = 2022;
  String _selectedColor = 'Silver';
  final _plateController = TextEditingController(text: 'SL-AB 1024');
  final _capacityController = TextEditingController();
  final _mileageController = TextEditingController(text: '45,000 km');
  String _transmission = 'Automatic';
  String _fuelType = 'Petrol';
  final _serviceAreaController = TextEditingController(text: 'Freetown & Western Area');

  final _formKeyStep1 = GlobalKey<FormState>();

  // ── Step 2: Pricing & Logistics Controllers ───────────────────────
  final _titleController = TextEditingController();
  final _priceController = TextEditingController(text: '250000');
  late String _pricingType;
  final _locationController = TextEditingController(text: 'Wilkinson Road, Freetown');
  final _descriptionController = TextEditingController();
  final _contactPhoneController = TextEditingController();

  final _formKeyStep2 = GlobalKey<FormState>();

  // ── Step 3: Photos ────────────────────────────────────────────────
  final List<StagedMediaItem> _stagedPhotos = [];
  bool _isUploadingPhoto = false;
  bool _isSubmitting = false;

  late final List<int> _yearOptions =
      List.generate(26, (index) => 2026 - index);

  final List<Map<String, dynamic>> _colorPalette = [
    {'name': 'White', 'color': const Color(0xFFF8FAFC)},
    {'name': 'Silver', 'color': const Color(0xFF94A3B8)},
    {'name': 'Black', 'color': const Color(0xFF0F172A)},
    {'name': 'Blue', 'color': const Color(0xFF2563EB)},
    {'name': 'Green', 'color': const Color(0xFF059669)},
    {'name': 'Red', 'color': const Color(0xFFDC2626)},
    {'name': 'Yellow', 'color': const Color(0xFFF59E0B)},
  ];

  @override
  void initState() {
    super.initState();
    _pricingType = _selectedCategory.defaultPricingType;
    _updateFormForCategory(_selectedCategory);
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _plateController.dispose();
    _capacityController.dispose();
    _mileageController.dispose();
    _serviceAreaController.dispose();
    _titleController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _contactPhoneController.dispose();
    super.dispose();
  }

  void _updateFormForCategory(CommercialVehicleCategory cat) {
    _pricingType = cat.defaultPricingType;
    switch (cat) {
      case CommercialVehicleCategory.carSale:
        _makeController.text = 'Toyota';
        _modelController.text = 'RAV4';
        _priceController.text = '250000';
        _capacityController.text = '5 Seats SUV';
        _serviceAreaController.text = 'Freetown & Western Area';
        break;
      case CommercialVehicleCategory.carRental:
        _makeController.text = 'Toyota';
        _modelController.text = 'Prado TXL';
        _priceController.text = '1500';
        _capacityController.text = '7 Seats 4x4';
        _serviceAreaController.text = 'Freetown Airport & Upcountry';
        break;
      case CommercialVehicleCategory.deliveryVan:
        _makeController.text = 'Toyota HiAce';
        _modelController.text = 'Commuter Van';
        _priceController.text = '1200';
        _capacityController.text = '2.5 Tons (High Roof)';
        _serviceAreaController.text = 'Greater Freetown Courier Route';
        break;
      case CommercialVehicleCategory.sandDumpTruck:
        _makeController.text = 'Howo SinoTruck';
        _modelController.text = '371 10-Wheeler Tipper';
        _priceController.text = '3500';
        _capacityController.text = '20 Tons (12 Cubic Meters)';
        _serviceAreaController.text = 'Waterloo Quarry to Freetown Construction Sites';
        break;
      case CommercialVehicleCategory.containerFreightTruck:
        _makeController.text = 'Mercedes-Benz Actros';
        _modelController.text = '3340 Articulated Flatbed';
        _priceController.text = '6000';
        _capacityController.text = '40ft Container (30 Tons)';
        _serviceAreaController.text = 'Queen Elizabeth II Quay Port to Inland Depots';
        break;
    }
    _autoGenerateTitle();
  }

  void _autoGenerateTitle() {
    final make = _makeController.text.trim();
    final model = _modelController.text.trim();
    final cap = _capacityController.text.trim();
    if (_selectedCategory == CommercialVehicleCategory.sandDumpTruck ||
        _selectedCategory == CommercialVehicleCategory.containerFreightTruck) {
      _titleController.text = '$_selectedYear $make $model ($cap)'.trim();
    } else {
      _titleController.text = '$_selectedYear $make $model'.trim();
    }
  }

  // ── Photo Picker & Upload ─────────────────────────────────────────
  Future<void> _pickAndUploadPhoto() async {
    if (_isUploadingPhoto) return;
    try {
      final client = context.read<ConvexClientWrapper>();
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1200,
        imageQuality: 82,
      );
      if (picked == null) return;
      if (!mounted) return;

      setState(() => _isUploadingPhoto = true);

      final bytes = await picked.readAsBytes();
      final item = StagedMediaItem(
        id: 'veh_${DateTime.now().microsecondsSinceEpoch}',
        slotLabel: 'Photo ${_stagedPhotos.length + 1}',
        localBytes: bytes,
        localPath: picked.path,
        isUploading: true,
      );

      setState(() {
        _stagedPhotos.add(item);
      });

      try {
        final uploadRes = await ImageUploadService.uploadImageBinaryWithStorageId(
          convexClient: client,
          imageBytes: bytes,
          contentType: picked.mimeType ?? 'image/jpeg',
        );
        item.storageId = uploadRes.storageId;
        item.remoteUrl = uploadRes.publicUrl;
        item.isUploading = false;
      } catch (e) {
        item.isUploading = false;
        item.error = e.toString();
        item.storageId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      }

      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo upload failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _stagedPhotos.removeAt(index);
    });
  }

  // ── Final Submission ──────────────────────────────────────────────
  Future<void> _submitCommercialVehicle() async {
    if (_stagedPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload at least 1 photo of the vehicle.'),
          backgroundColor: AppColors.amber,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final client = context.read<ConvexClientWrapper>();
      final priceNum = double.tryParse(_priceController.text.trim()) ?? 0;
      final photoUrls = _stagedPhotos
          .map((p) => p.remoteUrl ?? p.localPath ?? '')
          .where((u) => u.isNotEmpty)
          .toList();

      final res = await client.mutation(
        'mobility:registerVehicleListing',
        args: {
          'ownerId': widget.driverId,
          'title': _titleController.text.trim().isNotEmpty
              ? _titleController.text.trim()
              : '$_selectedYear ${_makeController.text} ${_modelController.text}',
          'category': _selectedCategory.id,
          'price': priceNum,
          'pricingType': _pricingType,
          'capacity': _capacityController.text.trim(),
          'location': _locationController.text.trim(),
          'images': photoUrls,
          'make': _makeController.text.trim(),
          'model': _modelController.text.trim(),
          'year': _selectedYear,
          'color': _selectedColor,
          'licensePlate': _plateController.text.trim().toUpperCase(),
          'mileage': _mileageController.text.trim(),
          'transmission': _transmission,
          'fuelType': _fuelType,
          'serviceArea': _serviceAreaController.text.trim(),
          'description': _descriptionController.text.trim(),
          'contactPhone': _contactPhoneController.text.trim(),
          'currency': 'SLE',
        },
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        if (res.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_selectedCategory.title} successfully registered!',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.emeraldDark,
              duration: const Duration(seconds: 3),
            ),
          );

          widget.onRegistrationComplete?.call();
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Registration failed: ${res.errorMessage ?? "Unknown error"}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        title: const Text(
          'Register Commercial Vehicle',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.obsidian,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Step Progress Bar
          _buildStepHeader(),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: switch (_currentStep) {
                0 => _buildStep1CategoryAndSpecs(),
                1 => _buildStep2PricingAndLogistics(),
                2 => _buildStep3PhotosAndPublish(),
                _ => const SizedBox.shrink(),
              },
            ),
          ),

          // Bottom Action Bar
          _buildBottomActionBar(),
        ],
      ),
    );
  }

  // ── Step Navigation Header ────────────────────────────────────────
  Widget _buildStepHeader() {
    final steps = ['Category & Specs', 'Rates & Location', 'Photos & Publish'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isActive = index == _currentStep;
          final isDone = index < _currentStep;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.emerald
                        : isActive
                            ? AppColors.obsidian
                            : AppColors.gray200,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isActive ? Colors.white : AppColors.gray600,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps[index],
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      color: isActive ? AppColors.obsidian : AppColors.gray500,
                    ),
                  ),
                ),
                if (index < steps.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.gray400),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Step 1: Category & Specs ──────────────────────────────────────
  Widget _buildStep1CategoryAndSpecs() {
    return Form(
      key: _formKeyStep1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Commercial Vehicle Type',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose the category matching your fleet, dealership, or heavy haulage truck.',
            style: TextStyle(fontSize: 13, color: AppColors.gray600),
          ),
          const SizedBox(height: 14),

          // 5 Commercial Category Cards
          ...CommercialVehicleCategory.values.map((cat) {
            final isSelected = _selectedCategory == cat;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setState(() {
                    _selectedCategory = cat;
                    _updateFormForCategory(cat);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.emerald.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.emerald : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.emerald : AppColors.gray100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          cat.icon,
                          color: isSelected ? Colors.white : AppColors.obsidian,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cat.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: isSelected
                                    ? AppColors.emeraldDark
                                    : AppColors.obsidian,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              cat.subtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.gray600,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Radio<CommercialVehicleCategory>(
                        value: cat,
                        groupValue: _selectedCategory,
                        activeColor: AppColors.emerald,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _selectedCategory = v;
                              _updateFormForCategory(v);
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          const Text(
            'Vehicle Specifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 14),

          // Make suggestions
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedCategory.makeSuggestions.map((m) {
              final isMatch = _makeController.text.trim() == m;
              return ChoiceChip(
                label: Text(m, style: const TextStyle(fontSize: 12)),
                selected: isMatch,
                selectedColor: AppColors.emerald,
                labelStyle: TextStyle(
                  color: isMatch ? Colors.white : AppColors.obsidian,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _makeController.text = m;
                      _autoGenerateTitle();
                    });
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Make & Model Row
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _makeController,
                  decoration: const InputDecoration(
                    labelText: 'Make / Manufacturer',
                    hintText: 'e.g. Howo, Toyota, MAN',
                    prefixIcon: Icon(Icons.business_rounded),
                  ),
                  onChanged: (_) => _autoGenerateTitle(),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    hintText: 'e.g. SinoTruck 371',
                    prefixIcon: Icon(Icons.car_crash_rounded),
                  ),
                  onChanged: (_) => _autoGenerateTitle(),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Year & License Plate Row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedYear,
                  decoration: const InputDecoration(
                    labelText: 'Year of Manufacture',
                    prefixIcon: Icon(Icons.calendar_today_rounded),
                  ),
                  items: _yearOptions.map((y) {
                    return DropdownMenuItem(value: y, child: Text('$y'));
                  }).toList(),
                  onChanged: (y) {
                    if (y != null) {
                      setState(() {
                        _selectedYear = y;
                        _autoGenerateTitle();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _plateController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'License Plate',
                    hintText: 'e.g. SL-AB 1024',
                    prefixIcon: Icon(Icons.confirmation_number_rounded),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Capacity Preset Chips
          const Text(
            'Payload / Haulage Capacity',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedCategory.capacityPresets.map((cap) {
              final isMatch = _capacityController.text.trim() == cap;
              return ChoiceChip(
                label: Text(cap, style: const TextStyle(fontSize: 12)),
                selected: isMatch,
                selectedColor: AppColors.emerald,
                labelStyle: TextStyle(
                  color: isMatch ? Colors.white : AppColors.obsidian,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _capacityController.text = cap;
                      _autoGenerateTitle();
                    });
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _capacityController,
            decoration: const InputDecoration(
              labelText: 'Capacity Detail',
              hintText: 'e.g. 20 Tons, 12 Cubic Meters, 2.5 Tons Payload',
              prefixIcon: Icon(Icons.scale_rounded),
            ),
            onChanged: (_) => _autoGenerateTitle(),
          ),
          const SizedBox(height: 14),

          // Exterior Color Palette
          const Text(
            'Exterior Color',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _colorPalette.map((item) {
                final isSelected = _selectedColor == item['name'];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _selectedColor = item['name']),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.obsidian
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppColors.obsidian : AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: item['color'] as Color,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.border),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item['name'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : AppColors.obsidian,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Cars specific specs
          if (_selectedCategory == CommercialVehicleCategory.carSale ||
              _selectedCategory == CommercialVehicleCategory.carRental) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _transmission,
                    decoration: const InputDecoration(labelText: 'Transmission'),
                    items: const [
                      DropdownMenuItem(value: 'Automatic', child: Text('Automatic')),
                      DropdownMenuItem(value: 'Manual', child: Text('Manual')),
                    ],
                    onChanged: (v) => setState(() => _transmission = v ?? 'Automatic'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _fuelType,
                    decoration: const InputDecoration(labelText: 'Fuel Type'),
                    items: const [
                      DropdownMenuItem(value: 'Petrol', child: Text('Petrol')),
                      DropdownMenuItem(value: 'Diesel', child: Text('Diesel')),
                      DropdownMenuItem(value: 'Hybrid', child: Text('Hybrid')),
                      DropdownMenuItem(value: 'Electric', child: Text('Electric')),
                    ],
                    onChanged: (v) => setState(() => _fuelType = v ?? 'Petrol'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _mileageController,
              decoration: const InputDecoration(
                labelText: 'Mileage (Odometer)',
                hintText: 'e.g. 45,000 km',
                prefixIcon: Icon(Icons.speed_rounded),
              ),
            ),
          ] else ...[
            // Heavy Logistics / Trucks specific fields
            TextFormField(
              controller: _serviceAreaController,
              decoration: const InputDecoration(
                labelText: 'Operating Service Area / Route',
                hintText: 'e.g. Quarry Sand Route / Port Container Depot',
                prefixIcon: Icon(Icons.alt_route_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 2: Pricing & Logistics ───────────────────────────────────
  Widget _buildStep2PricingAndLogistics() {
    return Form(
      key: _formKeyStep2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pricing & Logistics Model',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Set your commercial terms, rates, and pickup / depot location.',
            style: TextStyle(fontSize: 13, color: AppColors.gray600),
          ),
          const SizedBox(height: 16),

          // Listing Title
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Listing Headline',
              hintText: 'e.g. 2022 Howo SinoTruck 20 Tons Tipper',
              prefixIcon: Icon(Icons.title_rounded),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Title required' : null,
          ),
          const SizedBox(height: 14),

          // Pricing Type Selector
          DropdownButtonFormField<String>(
            value: _pricingType,
            decoration: const InputDecoration(
              labelText: 'Pricing Model',
              prefixIcon: Icon(Icons.payments_rounded),
            ),
            items: const [
              DropdownMenuItem(value: 'total_sale', child: Text('Outright Sale Price (Total SLE)')),
              DropdownMenuItem(value: 'per_day', child: Text('Daily Commercial Hire (SLE / Day)')),
              DropdownMenuItem(value: 'per_trip', child: Text('Per Trip Haulage Rate (SLE / Trip)')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _pricingType = v);
            },
          ),
          const SizedBox(height: 14),

          // Price Input
          TextFormField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: switch (_pricingType) {
                'total_sale' => 'Sale Price (SLE)',
                'per_day' => 'Daily Rental Rate (SLE / Day)',
                'per_trip' => 'Haulage Rate per Trip (SLE / Trip)',
                _ => 'Price (SLE)',
              },
              prefixText: 'SLE  ',
              prefixIcon: const Icon(Icons.price_change_rounded),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Price required';
              if (double.tryParse(v.trim()) == null) return 'Invalid number';
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Location / Depot
          TextFormField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Depot / Vehicle Location',
              hintText: 'e.g. Wilkinson Road, Freetown or Waterloo Yard',
              prefixIcon: Icon(Icons.location_on_rounded),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Location required' : null,
          ),
          const SizedBox(height: 14),

          // Private Contact Phone
          TextFormField(
            controller: _contactPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Direct Contact Phone (WhatsApp/Call)',
              hintText: 'e.g. +232 76 123 456',
              prefixIcon: Icon(Icons.phone_rounded),
            ),
          ),
          const SizedBox(height: 14),

          // Detailed Description
          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Vehicle Description & Operational Notes',
              hintText: 'State engine condition, tipper hydraulics, driver availability, cargo insurance...',
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Photos & Gallery ──────────────────────────────────────
  Widget _buildStep3PhotosAndPublish() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vehicle Photo Gallery',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.obsidian,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Upload exterior and interior photos of the vehicle for client inspection.',
          style: TextStyle(fontSize: 13, color: AppColors.gray600),
        ),
        const SizedBox(height: 16),

        // Photo Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
          ),
          itemCount: _stagedPhotos.length + 1,
          itemBuilder: (context, index) {
            if (index == _stagedPhotos.length) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickAndUploadPhoto,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.emerald,
                      style: BorderStyle.solid,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: _isUploadingPhoto
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_rounded, color: AppColors.emerald, size: 28),
                              SizedBox(height: 6),
                              Text(
                                'Add Photo',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.emeraldDark,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            }

            final photo = _stagedPhotos[index];
            final url = photo.remoteUrl ?? photo.localPath ?? '';

            return Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: url.startsWith('http')
                      ? Image.network(url, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                      : Container(color: AppColors.gray200, child: const Icon(Icons.image)),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: InkWell(
                    onTap: () => _removePhoto(index),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_selectedCategory.icon, color: AppColors.emerald),
                  const SizedBox(width: 8),
                  Text(
                    _selectedCategory.title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _titleController.text,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Rate: SLE ${_priceController.text} ${_selectedCategory.pricingSuffix} • ${_capacityController.text}',
                style: const TextStyle(fontSize: 13, color: AppColors.emeraldDark, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Location: ${_locationController.text}',
                style: const TextStyle(fontSize: 12, color: AppColors.gray600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Bottom Action Bar ─────────────────────────────────────────────
  Widget _buildBottomActionBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: VxButton(
                label: _currentStep == 2
                    ? 'Publish Vehicle Listing'
                    : 'Continue',
                isLoading: _isSubmitting,
                onPressed: () {
                  if (_currentStep == 0) {
                    if (_formKeyStep1.currentState?.validate() == true) {
                      setState(() => _currentStep = 1);
                    }
                  } else if (_currentStep == 1) {
                    if (_formKeyStep2.currentState?.validate() == true) {
                      setState(() => _currentStep = 2);
                    }
                  } else {
                    _submitCommercialVehicle();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
