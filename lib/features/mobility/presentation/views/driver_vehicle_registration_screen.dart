// lib/features/mobility/presentation/views/driver_vehicle_registration_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Driver Vehicle Onboarding & Multi-Step Registration Wizard
// Step 1: Vehicle Category Selection with live 3D isometric preview
// Step 2: Structured Vehicle Specs (Make suggestions, model, year, color, uppercase plate)
// Step 3: Private Verification Document Uploads (Admin only, never shown to riders)
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:image_picker/image_picker.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/vehicle_tier_catalog.dart';
import '../widgets/isometric_vehicle_3d_render.dart';
import '../widgets/top_down_vehicle_painter.dart';

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
  int _currentStep = 0; // 0: Category, 1: Specs, 2: Verification Docs

  // ── Step 1: Vehicle Category Selection ────────────────────────────
  VehicleTierId _selectedTierId = VehicleTierId.kekeBajaj;

  // ── Step 2: Vehicle Specs ─────────────────────────────────────────
  final _makeController = TextEditingController(text: 'Bajaj');
  final _modelController = TextEditingController(text: 'RE 4S');
  int _selectedYear = 2023;
  String _selectedColor = 'Yellow';
  final _plateController = TextEditingController();

  final _formKeySpecs = GlobalKey<FormState>();

  // ── Step 3: Private Verification Documents ────────────────────────
  String? _licenseFrontUrl;
  String? _licenseBackUrl;
  String? _registrationDocUrl;
  String? _insuranceDocUrl;
  String? _inspectionPhotoUrl; // Optional raw car photo for admin inspection only

  bool _isUploadingDoc = false;
  String? _activeUploadingSlot;
  bool _isSubmitting = false;

  // Year options 2005 - 2026
  late final List<int> _yearOptions =
      List.generate(22, (index) => 2026 - index);

  // Standardized exterior color palette with display names and values
  final List<Map<String, dynamic>> _colorPalette = [
    {'name': 'Yellow', 'color': const Color(0xFFF59E0B)},
    {'name': 'White', 'color': const Color(0xFFF8FAFC)},
    {'name': 'Silver', 'color': const Color(0xFF94A3B8)},
    {'name': 'Black', 'color': const Color(0xFF0F172A)},
    {'name': 'Blue', 'color': const Color(0xFF2563EB)},
    {'name': 'Green', 'color': const Color(0xFF059669)},
    {'name': 'Red', 'color': const Color(0xFFDC2626)},
  ];

  // Dynamic make suggestions tailored per vehicle category
  List<String> get _makeSuggestions {
    return switch (_selectedTierId) {
      VehicleTierId.kekeBajaj => ['Bajaj', 'TVS', 'Piaggio', 'Atul', 'Mahindra'],
      VehicleTierId.okadaBike => ['Bajaj', 'TVS', 'Senke', 'Haojue', 'Honda', 'Yamaha', 'Suzuki'],
      VehicleTierId.carStandard => ['Toyota', 'Hyundai', 'Nissan', 'Honda', 'Kia', 'Mercedes-Benz', 'Peugeot'],
      VehicleTierId.deliveryVan => ['Toyota', 'Hyundai', 'Ford', 'Nissan', 'Mercedes-Benz', 'Isuzu'],
    };
  }

  void _onCategoryChanged(VehicleTierId tier) {
    setState(() {
      _selectedTierId = tier;
      // Auto-populate sensible defaults for the selected category
      switch (tier) {
        case VehicleTierId.kekeBajaj:
          _makeController.text = 'Bajaj';
          _modelController.text = 'RE 4S';
          _selectedColor = 'Yellow';
          break;
        case VehicleTierId.okadaBike:
          _makeController.text = 'Bajaj';
          _modelController.text = 'Boxer 150';
          _selectedColor = 'Red';
          break;
        case VehicleTierId.carStandard:
          _makeController.text = 'Toyota';
          _modelController.text = 'Corolla';
          _selectedColor = 'Silver';
          break;
        case VehicleTierId.deliveryVan:
          _makeController.text = 'Toyota';
          _modelController.text = 'HiAce Cargo';
          _selectedColor = 'White';
          break;
      }
    });
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        title: const Text(
          'Register Vehicle',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.obsidian,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.obsidian),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Multi-Step Progress Indicator ──
            _buildStepperHeader(),

            // ── Active Step Body ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: switch (_currentStep) {
                  0 => _buildStep1Category(),
                  1 => _buildStep2Specs(),
                  _ => _buildStep3Documents(),
                },
              ),
            ),

            // ── Bottom Action Navigation Bar ──
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                    STEP PROGRESS HEADER
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStepperHeader() {
    final steps = ['Category', 'Specifications', 'Verification'];

    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final stepBefore = index ~/ 2;
            final isCompleted = _currentStep > stepBefore;
            return Expanded(
              child: Container(
                height: 2,
                color: isCompleted ? AppColors.emerald : AppColors.gray200,
              ),
            );
          }

          final stepIndex = index ~/ 2;
          final isCurrent = _currentStep == stepIndex;
          final isDone = _currentStep > stepIndex;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isDone
                      ? AppColors.emerald
                      : (isCurrent ? AppColors.emeraldSurface : AppColors.gray100),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone || isCurrent ? AppColors.emerald : AppColors.gray300,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, size: 14, color: AppColors.white)
                      : Text(
                          '${stepIndex + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isCurrent ? AppColors.emeraldDark : AppColors.gray500,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                steps[stepIndex],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                  color: isCurrent
                      ? AppColors.obsidian
                      : (isDone ? AppColors.emeraldDark : AppColors.gray400),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //             STEP 1: VEHICLE CATEGORY SELECTION
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStep1Category() {
    final tiers = [
      {
        'tier': VehicleTierId.kekeBajaj,
        'title': 'Tricycle / Keke',
        'subtitle': '3-wheel passenger Bajaj / TVS',
        'badge': '3 Seats',
        'categoryStr': 'keke',
        'accent': AppColors.amber,
      },
      {
        'tier': VehicleTierId.okadaBike,
        'title': 'Okada / Motorbike',
        'subtitle': '2-wheel express commuter & courier',
        'badge': '1 Passenger',
        'categoryStr': 'okada',
        'accent': const Color(0xFFF97316),
      },
      {
        'tier': VehicleTierId.carStandard,
        'title': 'Standard Ride (Taxi)',
        'subtitle': '4-door air-conditioned sedan',
        'badge': '4 Seats',
        'categoryStr': 'car',
        'accent': AppColors.emerald,
      },
      {
        'tier': VehicleTierId.deliveryVan,
        'title': 'Cargo / Delivery Van',
        'subtitle': 'High-roof freight & commercial van',
        'badge': '1 Ton Cargo',
        'categoryStr': 'van',
        'accent': const Color(0xFF3B82F6),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Vehicle Category',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.obsidian,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Selecting a category automatically assigns the system 3D isometric model and live map vector pin to your driver profile.',
          style: TextStyle(fontSize: 12, color: AppColors.gray600, height: 1.4),
        ),
        const SizedBox(height: 16),

        // ── Real-Time 3D Isometric Preview Hero Card ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.obsidian.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.emerald, width: 1),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.emerald),
                        SizedBox(width: 5),
                        Text(
                          '3D ASSET ASSIGNED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: AppColors.emerald,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Top-down pin preview
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TopDownVehicleWidget(
                          category: switch (_selectedTierId) {
                            VehicleTierId.kekeBajaj => 'keke',
                            VehicleTierId.okadaBike => 'okada',
                            VehicleTierId.deliveryVan => 'van',
                            _ => 'car',
                          },
                          size: 16,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Map Pin',
                          style: TextStyle(fontSize: 10, color: AppColors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 3D Isometric Illustration
              IsometricVehicle3DRender(
                tierId: _selectedTierId,
                width: 140,
                height: 90,
                isSelected: true,
              ),
              const SizedBox(height: 6),
              Text(
                'Public riders will see this clean 3D render and your verified badge.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── 4 Category Option Cards ──
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = tiers[index];
            final tier = item['tier'] as VehicleTierId;
            final isSelected = _selectedTierId == tier;

            return GestureDetector(
              onTap: () => _onCategoryChanged(tier),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.emeraldSurface : AppColors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? AppColors.emerald : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Mini 3D Render
                    IsometricVehicle3DRender(
                      tierId: tier,
                      width: 56,
                      height: 42,
                      isSelected: isSelected,
                    ),
                    const SizedBox(width: 14),

                    // Title & Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                item['title'] as String,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? AppColors.emeraldDark
                                      : AppColors.obsidian,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.white
                                      : AppColors.gray100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  item['badge'] as String,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? AppColors.emeraldDark
                                        : AppColors.gray600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item['subtitle'] as String,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.gray500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Radio Check Circle
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.emerald : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? AppColors.emerald : AppColors.gray300,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, size: 14, color: AppColors.white)
                          : null,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //                   STEP 2: VEHICLE SPECS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildTextInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(fontSize: 14, color: AppColors.obsidian, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.gray400, fontWeight: FontWeight.w400),
        prefixIcon: Icon(prefixIcon, color: AppColors.gray500, size: 20),
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.emerald, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildStep2Specs() {
    return Form(
      key: _formKeySpecs,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vehicle Specifications',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Provide accurate details as shown on your official vehicle registration document.',
            style: TextStyle(fontSize: 12, color: AppColors.gray600),
          ),
          const SizedBox(height: 18),

          // ── Vehicle Make / Brand ──
          const Text(
            'Vehicle Make / Brand',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
          ),
          const SizedBox(height: 6),
          _buildTextInputField(
            controller: _makeController,
            hintText: 'e.g. Bajaj, Toyota, TVS',
            prefixIcon: Icons.business_rounded,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter vehicle make' : null,
          ),
          const SizedBox(height: 8),

          // Quick Make Chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _makeSuggestions.map((make) {
              final isChosen = _makeController.text.trim().toLowerCase() == make.toLowerCase();
              return GestureDetector(
                onTap: () => setState(() => _makeController.text = make),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isChosen ? AppColors.emeraldSurface : AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isChosen ? AppColors.emerald : AppColors.border,
                    ),
                  ),
                  child: Text(
                    make,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isChosen ? FontWeight.w700 : FontWeight.w500,
                      color: isChosen ? AppColors.emeraldDark : AppColors.gray700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ── Model Name ──
          const Text(
            'Model Name',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
          ),
          const SizedBox(height: 6),
          _buildTextInputField(
            controller: _modelController,
            hintText: 'e.g. RE 4S, Corolla, Boxer 150',
            prefixIcon: Icons.directions_car_rounded,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter model name' : null,
          ),
          const SizedBox(height: 16),

          // ── Year of Manufacture Dropdown ──
          const Text(
            'Year of Manufacture',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedYear,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.gray600),
                items: _yearOptions.map((year) {
                  return DropdownMenuItem<int>(
                    value: year,
                    child: Text(
                      '$year',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.obsidian,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedYear = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Vehicle Exterior Color ──
          const Text(
            'Vehicle Exterior Color',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _colorPalette.map((colorItem) {
              final name = colorItem['name'] as String;
              final color = colorItem['color'] as Color;
              final isSelected = _selectedColor == name;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.obsidian : AppColors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.obsidian : AppColors.border,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.obsidian.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: name == 'White' ? AppColors.gray300 : Colors.transparent,
                            width: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? AppColors.white : AppColors.obsidian,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // ── License Plate Number (Auto-Uppercase) ──
          const Text(
            'License Plate Number',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
          ),
          const SizedBox(height: 6),
          _buildTextInputField(
            controller: _plateController,
            hintText: 'e.g. SL-492-KE or ABC-123',
            prefixIcon: Icons.badge_rounded,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
              UpperCaseTextFormatter(),
            ],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter license plate number';
              if (v.trim().length < 3) return 'License plate is too short';
              return null;
            },
          ),
          const SizedBox(height: 10),

          // Preview of formatted badge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 16, color: AppColors.gray600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Badge Preview: "$_selectedColor ${_makeController.text.trim()} ${_modelController.text.trim()} • ${_plateController.text.trim().isEmpty ? 'SL-XXX' : _plateController.text.trim().toUpperCase()}"',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.gray700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //             STEP 3: PRIVATE VERIFICATION DOCUMENTS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStep3Documents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Verification Documents',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.obsidian,
          ),
        ),
        const SizedBox(height: 4),

        // Explicit Privacy Assurance Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.emeraldSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_rounded, size: 18, color: AppColors.emeraldDark),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Private & Secure: These documents are encrypted for backend administrator review only. Riders will NEVER see your documents or raw vehicle photo.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.emeraldDark,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 1. Driver's License Front
        _buildDocUploadTile(
          slotId: 'license_front',
          title: "Driver's License (Front)",
          subtitle: 'Clear photo showing name, photo, and license number',
          icon: Icons.credit_card_rounded,
          uploadedUrl: _licenseFrontUrl,
          isRequired: true,
          onPicked: (url) => setState(() => _licenseFrontUrl = url),
          onRemoved: () => setState(() => _licenseFrontUrl = null),
        ),
        const SizedBox(height: 12),

        // 2. Driver's License Back
        _buildDocUploadTile(
          slotId: 'license_back',
          title: "Driver's License (Back)",
          subtitle: 'Photo showing endorsement classes and expiry',
          icon: Icons.credit_card_rounded,
          uploadedUrl: _licenseBackUrl,
          isRequired: true,
          onPicked: (url) => setState(() => _licenseBackUrl = url),
          onRemoved: () => setState(() => _licenseBackUrl = null),
        ),
        const SizedBox(height: 12),

        // 3. Vehicle Registration / Proof of Ownership
        _buildDocUploadTile(
          slotId: 'registration_doc',
          title: 'Vehicle Registration Certificate',
          subtitle: 'Official ownership / logbook certificate',
          icon: Icons.description_rounded,
          uploadedUrl: _registrationDocUrl,
          isRequired: true,
          onPicked: (url) => setState(() => _registrationDocUrl = url),
          onRemoved: () => setState(() => _registrationDocUrl = null),
        ),
        const SizedBox(height: 12),

        // 4. Vehicle Inspection / Insurance Certificate
        _buildDocUploadTile(
          slotId: 'insurance_doc',
          title: 'Inspection / Insurance Certificate',
          subtitle: 'Valid roadworthiness or commercial insurance policy',
          icon: Icons.verified_user_rounded,
          uploadedUrl: _insuranceDocUrl,
          isRequired: true,
          onPicked: (url) => setState(() => _insuranceDocUrl = url),
          onRemoved: () => setState(() => _insuranceDocUrl = null),
        ),
        const SizedBox(height: 12),

        // 5. Optional Vehicle Inspection Photo
        _buildDocUploadTile(
          slotId: 'inspection_photo',
          title: 'Vehicle Photo (Inspection Only)',
          subtitle: 'Raw photo showing license plate (Admin review only)',
          icon: Icons.camera_alt_rounded,
          uploadedUrl: _inspectionPhotoUrl,
          isRequired: false,
          onPicked: (url) => setState(() => _inspectionPhotoUrl = url),
          onRemoved: () => setState(() => _inspectionPhotoUrl = null),
        ),
      ],
    );
  }

  Widget _buildDocUploadTile({
    required String slotId,
    required String title,
    required String subtitle,
    required IconData icon,
    required String? uploadedUrl,
    required bool isRequired,
    required ValueChanged<String> onPicked,
    required VoidCallback onRemoved,
  }) {
    final isUploaded = uploadedUrl != null && uploadedUrl.isNotEmpty;
    final isCurrentSlotUploading = _isUploadingDoc && _activeUploadingSlot == slotId;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUploaded ? AppColors.emerald : AppColors.border,
          width: isUploaded ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Icon or Uploaded Image Thumbnail Preview
          if (isUploaded)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                uploadedUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 48,
                  height: 48,
                  color: AppColors.emeraldSurface,
                  child: const Icon(Icons.check_circle_rounded, color: AppColors.emerald),
                ),
              ),
            )
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.gray600, size: 22),
            ),
          const SizedBox(width: 12),

          // Title & Description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isRequired) ...[
                      const SizedBox(width: 4),
                      const Text('*', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isUploaded ? 'Document uploaded & attached' : subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isUploaded ? AppColors.emeraldDark : AppColors.gray500,
                    fontWeight: isUploaded ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Action Button
          if (isCurrentSlotUploading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.emerald),
            )
          else if (isUploaded)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
              onPressed: onRemoved,
              tooltip: 'Remove document',
            )
          else
            TextButton.icon(
              onPressed: () => _pickAndUploadDocument(slotId, onPicked),
              icon: const Icon(Icons.upload_file_rounded, size: 16),
              label: const Text('Upload', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.emeraldDark,
                backgroundColor: AppColors.emeraldSurface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadDocument(
    String slotId,
    ValueChanged<String> onUploaded,
  ) async {
    // Show modal bottom sheet to choose Camera or Gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upload Document',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.obsidian),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: AppColors.emerald),
              title: const Text('Take Photo with Camera', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.obsidian),
              title: const Text('Choose from Photo Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    setState(() {
      _isUploadingDoc = true;
      _activeUploadingSlot = slotId;
    });

    try {
      final file = source == ImageSource.camera
          ? await ImageUploadService.pickImageFromCamera()
          : await ImageUploadService.pickImageFromGallery();

      if (file != null) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        final convexClient = context.read<ConvexClientWrapper>();

        final publicUrl = await ImageUploadService.uploadImageToConvex(
          convexClient: convexClient,
          imageBytes: bytes,
        );

        if (!mounted) return;
        onUploaded(publicUrl);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Document uploaded successfully.'),
              backgroundColor: AppColors.emerald,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingDoc = false;
          _activeUploadingSlot = null;
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                    BOTTOM NAVIGATION BAR
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildBottomNav() {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            OutlinedButton(
              onPressed: () => setState(() => _currentStep--),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.obsidian,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              child: const Text('Back', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: VxButton(
              label: _currentStep == 2 ? 'Submit for Verification' : 'Continue',
              isLoading: _isSubmitting,
              onPressed: _isSubmitting ? null : _handleNextOrSubmit,
            ),
          ),
        ],
      ),
    );
  }

  void _handleNextOrSubmit() {
    if (_currentStep == 0) {
      setState(() => _currentStep = 1);
    } else if (_currentStep == 1) {
      if (_formKeySpecs.currentState?.validate() ?? false) {
        setState(() => _currentStep = 2);
      }
    } else {
      _submitRegistration();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                SUBMIT VEHICLE REGISTRATION
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _submitRegistration() async {
    // Validate required documents
    if (_licenseFrontUrl == null ||
        _licenseBackUrl == null ||
        _registrationDocUrl == null ||
        _insuranceDocUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload all required verification documents (*).'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final convexClient = context.read<ConvexClientWrapper>();

      final vehicleTypeStr = switch (_selectedTierId) {
        VehicleTierId.kekeBajaj => 'keke',
        VehicleTierId.okadaBike => 'okada',
        VehicleTierId.deliveryVan => 'van',
        _ => 'car',
      };

      final categoryEnumStr = switch (_selectedTierId) {
        VehicleTierId.kekeBajaj => 'kekeh_tricycle',
        VehicleTierId.okadaBike => 'delivery_bike',
        VehicleTierId.deliveryVan => 'delivery_van',
        _ => 'standard',
      };

      final result = await convexClient.mutation(
        'driverVehicles:registerDriverVehicle',
        args: {
          'driverId': widget.driverId,
          'vehicleType': vehicleTypeStr,
          'category': categoryEnumStr,
          'make': _makeController.text.trim(),
          'model': _modelController.text.trim(),
          'year': _selectedYear,
          'color': _selectedColor,
          'licensePlate': _plateController.text.trim().toUpperCase(),
          if (_licenseFrontUrl != null) 'licenseFrontUrl': _licenseFrontUrl,
          if (_licenseBackUrl != null) 'licenseBackUrl': _licenseBackUrl,
          if (_registrationDocUrl != null) 'registrationDocUrl': _registrationDocUrl,
          if (_insuranceDocUrl != null) 'insuranceDocUrl': _insuranceDocUrl,
          if (_inspectionPhotoUrl != null) 'inspectionPhotoUrl': _inspectionPhotoUrl,
        },
      );

      if (!result.success) {
        throw Exception(result.errorMessage ?? 'Registration failed');
      }

      final data = result.value as Map<String, dynamic>;
      final vehicleId = data['vehicleId'] as String?;

      if (!mounted) return;

      // Show confirmation dialog with instant demo approve action
      await _showRegistrationSuccessModal(vehicleId);

      widget.onRegistrationComplete?.call();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration failed: $e'),
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

  Future<void> _showRegistrationSuccessModal(String? vehicleId) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Registration Submitted!',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your vehicle details and private verification documents have been securely submitted to the administration team.',
              style: TextStyle(fontSize: 13, color: AppColors.gray700, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 16, color: AppColors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Status: PENDING REVIEW\nOnce approved, you can switch to "ONLINE & READY" to accept rides.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Demo / Dev Mode Convenience Button
            OutlinedButton.icon(
              icon: const Icon(Icons.bolt_rounded, color: AppColors.emerald, size: 18),
              label: const Text(
                'Instant Approve (Demo Mode)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.emeraldDark),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.emerald),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final convex = context.read<ConvexClientWrapper>();
                await convex.mutation(
                  'driverVehicles:mockApproveDriverVehicle',
                  args: {'driverId': widget.driverId, 'approve': true},
                );
                if (dialogCtx.mounted) {
                  Navigator.of(dialogCtx).pop();
                }
              },
            ),
          ],
        ),
        actions: [
          VxButton(
            label: 'Done',
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
        ],
      ),
    );
  }
}

/// Helper input formatter for uppercase license plates
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
