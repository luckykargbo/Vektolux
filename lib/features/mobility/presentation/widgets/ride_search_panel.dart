// lib/features/mobility/presentation/widgets/ride_search_panel.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Passenger Ride & Delivery Booking UI Component
// Integrates Mode Switcher (Ride vs Delivery), static vector category catalog,
// real-time calculated upfront fares & ETAs, and delivery recipient fields.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/trip_delivery_entity.dart';
import '../../domain/entities/vehicle_category_catalog.dart';
import '../../domain/entities/vehicle_tier_catalog.dart';
import '../../domain/services/fare_calculation_service.dart';
import 'booking_service_mode_toggle.dart';
import 'delivery_recipient_panel.dart';
import 'isometric_vehicle_3d_render.dart';

class RideSearchPanel extends StatefulWidget {
  final String pickupAddress;
  final String dropoffAddress;
  final String activeServiceType; // 'ride' | 'delivery'
  final BookingVehicleCategory selectedCategory;
  final Map<BookingVehicleCategory, CalculatedTierEstimate> calculatedTierEstimates;
  final bool isSubmitting;
  final ValueChanged<String> onServiceTypeChanged;
  final ValueChanged<BookingVehicleCategory> onSelectCategory;
  final void Function(DeliveryPackageDetails? deliveryDetails) onConfirmBooking;
  final ValueChanged<String> onSelectQuickDestination;
  final VoidCallback? onTapPickup;
  final VoidCallback? onTapDropoff;

  const RideSearchPanel({
    super.key,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.activeServiceType,
    required this.selectedCategory,
    required this.calculatedTierEstimates,
    required this.isSubmitting,
    required this.onServiceTypeChanged,
    required this.onSelectCategory,
    required this.onConfirmBooking,
    required this.onSelectQuickDestination,
    this.onTapPickup,
    this.onTapDropoff,
  });

  @override
  State<RideSearchPanel> createState() => _RideSearchPanelState();
}

class _RideSearchPanelState extends State<RideSearchPanel> {
  late final TextEditingController _recipientNameController;
  late final TextEditingController _recipientPhoneController;
  late final TextEditingController _packageNotesController;
  bool _isFragile = false;

  static const List<Map<String, dynamic>> _quickLocations = [
    {'title': 'Lumley Beach', 'sub': 'Aberdeen Peninsula', 'icon': Icons.beach_access_rounded},
    {'title': 'Cotton Tree Central', 'sub': 'Siaka Stevens St', 'icon': Icons.account_balance_rounded},
    {'title': 'Lungi Ferry Terminal', 'sub': 'Government Wharf', 'icon': Icons.directions_boat_rounded},
    {'title': 'FBC University Campus', 'sub': 'Mount Aureol', 'icon': Icons.school_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _recipientNameController = TextEditingController();
    _recipientPhoneController = TextEditingController();
    _packageNotesController = TextEditingController();
  }

  @override
  void dispose() {
    _recipientNameController.dispose();
    _recipientPhoneController.dispose();
    _packageNotesController.dispose();
    super.dispose();
  }

  void _handleConfirm() {
    final isDelivery = widget.activeServiceType == 'delivery';

    if (isDelivery) {
      if (_recipientNameController.text.trim().isEmpty ||
          _recipientPhoneController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter recipient name and phone number for delivery.'),
            backgroundColor: AppColors.obsidian,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final deliveryDetails = DeliveryPackageDetails(
        recipientName: _recipientNameController.text.trim(),
        recipientPhone: '+232 ${_recipientPhoneController.text.trim()}',
        packageDescription: _packageNotesController.text.trim().isNotEmpty
            ? _packageNotesController.text.trim()
            : 'Standard Delivery Parcel',
        isFragile: _isFragile,
      );
      widget.onConfirmBooking(deliveryDetails);
    } else {
      widget.onConfirmBooking(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDelivery = widget.activeServiceType == 'delivery';
    final categories = VehicleCategoryCatalog.categoriesForService(widget.activeServiceType);

    // Selected Tier Details
    final selectedEstimate = widget.calculatedTierEstimates[widget.selectedCategory];
    final fare = selectedEstimate?.fareAmount ?? widget.selectedCategory.baseFare + 25.0;
    final currency = selectedEstimate?.currency ?? 'SLE';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 1. Ride vs. Delivery Mode Switcher ───────────────────────
        BookingServiceModeToggle(
          activeServiceType: widget.activeServiceType,
          onServiceTypeChanged: widget.onServiceTypeChanged,
        ),
        const SizedBox(height: 14),

        // ── 2. Pickup & Destination Input Container ─────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Pickup row
                InkWell(
                  onTap: widget.onTapPickup,
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location_rounded, color: AppColors.emerald, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDelivery ? 'PACKAGE PICKUP POINT' : 'PICKUP LOCATION (TAP TO CHANGE)',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.gray500,
                              ),
                            ),
                            Text(
                              widget.pickupAddress,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.obsidian,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_location_alt_outlined, color: AppColors.gray400, size: 18),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 32, right: 12),
                  child: Divider(height: 16),
                ),
                // Dropoff row
                InkWell(
                  onTap: widget.onTapDropoff,
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: AppColors.obsidian, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDelivery ? 'DELIVERY DESTINATION' : 'WHERE TO?',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.emeraldDark,
                              ),
                            ),
                            Text(
                              widget.dropoffAddress,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.search_rounded, color: AppColors.gray400, size: 22),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── 3. Quick Suggested Locations ────────────────────────────
        SizedBox(
          height: 38,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: _quickLocations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final loc = _quickLocations[index];
              return ActionChip(
                backgroundColor: AppColors.white,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                avatar: Icon(loc['icon'] as IconData, size: 14, color: AppColors.emeraldDark),
                label: Text(
                  loc['title'].toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.obsidian,
                  ),
                ),
                onPressed: () => widget.onSelectQuickDestination(loc['title'].toString()),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // ── 4. Delivery Recipient Form (Revealed in Delivery Mode) ──
        if (isDelivery) ...[
          DeliveryRecipientPanel(
            nameController: _recipientNameController,
            phoneController: _recipientPhoneController,
            notesController: _packageNotesController,
            isFragile: _isFragile,
            onFragileChanged: (val) => setState(() => _isFragile = val),
          ),
          const SizedBox(height: 16),
        ],

        // ── 5. Categorized Vehicle Selection Cards ──────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isDelivery ? 'Select Delivery Courier Tier' : 'Select Vehicle Tier',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
              ),
              const Text(
                'Upfront Guaranteed Fare',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.emeraldDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: 168,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final category = categories[index];
              final isSelected = category == widget.selectedCategory;
              final estimate = widget.calculatedTierEstimates[category];
              final tierFare = estimate?.fareAmount ?? category.baseFare + 20.0;
              final arrivalEta = estimate?.arrivalEtaMinutes ?? 5;
              final hasDriver = estimate?.hasNearbyDriver ?? false;

              return _buildCategoryCard(
                category: category,
                isSelected: isSelected,
                fare: tierFare,
                arrivalEta: arrivalEta,
                currency: currency,
                hasDriver: hasDriver,
                onTap: () => widget.onSelectCategory(category),
              );
            },
          ),
        ),
        const SizedBox(height: 18),

        // ── 6. Primary "Confirm Booking" CTA ────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: VxButton(
            label: '${VehicleTierConfig.fromBookingCategory(widget.selectedCategory).buttonLabel} ($currency ${fare.toStringAsFixed(0)})',
            icon: isDelivery ? Icons.local_shipping_rounded : Icons.directions_car_filled_rounded,
            isLoading: widget.isSubmitting,
            onPressed: widget.isSubmitting ? null : _handleConfirm,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard({
    required BookingVehicleCategory category,
    required bool isSelected,
    required double fare,
    required int arrivalEta,
    required String currency,
    required bool hasDriver,
    required VoidCallback onTap,
  }) {
    final tierConfig = VehicleTierConfig.fromBookingCategory(category);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emeraldSurface : AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.emerald.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top: 3D Isometric Transparent Vehicle Render & Arrival ETA Pill
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IsometricVehicle3DRender(
                  tierId: tierConfig.tierId,
                  render3DUrl: tierConfig.render3DUrl,
                  width: 60,
                  height: 42,
                  isSelected: isSelected,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.emerald.withValues(alpha: 0.5) : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasDriver) ...[
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: const BoxDecoration(
                            color: AppColors.emerald,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      Text(
                        '$arrivalEta min',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? AppColors.emeraldDark : AppColors.gray600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Tier Title & Subtitle
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  category.subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.gray500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),

            // Capacity Specification
            Text(
              category.capacity,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.gray600,
              ),
            ),

            // Upfront Calculated Fare
            Text(
              '$currency ${fare.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
