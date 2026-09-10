// lib/features/mobility/presentation/widgets/rental_panel.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Car & Truck Rental Panel (Mode 2)
// Daily/weekly duration picker, self-drive vs dedicated driver switch,
// category filter chips, vehicle detail views, and in-app host chat.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../domain/entities/mobility_vehicle_entity.dart';
import 'in_app_chat_modal.dart';
import 'vehicle_detail_modal.dart';

class RentalPanel extends StatefulWidget {
  final List<VehicleListingEntity> rentalVehicles;
  final bool isWithDriver;
  final int rentalDays;
  final ValueChanged<bool> onToggleDriver;
  final ValueChanged<int> onUpdateDays;
  final ValueChanged<VehicleListingEntity> onBookVehicle;

  const RentalPanel({
    super.key,
    required this.rentalVehicles,
    required this.isWithDriver,
    required this.rentalDays,
    required this.onToggleDriver,
    required this.onUpdateDays,
    required this.onBookVehicle,
  });

  @override
  State<RentalPanel> createState() => _RentalPanelState();
}

class _RentalPanelState extends State<RentalPanel> {
  String _selectedCategory = 'all';

  List<VehicleListingEntity> get _filteredVehicles {
    if (_selectedCategory == 'all') return widget.rentalVehicles;
    return widget.rentalVehicles.where((v) {
      return v.vehicleType.backendKey == _selectedCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Rental Options Card (Duration & Driver Toggle) ────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.gray50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Driver switch row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.emeraldSurface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.badge_outlined,
                              color: AppColors.emeraldDark,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Include Professional Chauffeur',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.obsidian,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  widget.isWithDriver
                                      ? 'Dedicated licensed driver (+120 SLE/day)'
                                      : 'Self-Drive (Security deposit required)',
                                  style: const TextStyle(fontSize: 11, color: AppColors.gray500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: widget.isWithDriver,
                      activeTrackColor: AppColors.emerald,
                      onChanged: widget.onToggleDriver,
                    ),
                  ],
                ),
                const Divider(height: 20),
                // Rental Duration selector
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rental Period',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildDurationChip('1 Day', 1),
                          const SizedBox(width: 6),
                          _buildDurationChip('3 Days', 3),
                          const SizedBox(width: 6),
                          _buildDurationChip('1 Week', 7),
                          const SizedBox(width: 6),
                          _buildDurationChip('1 Month', 30),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Category Filter Chips ─────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryChip('All Fleet', 'all', Icons.apps_rounded),
                const SizedBox(width: 8),
                _buildCategoryChip('Cars & Sedans', 'taxi', Icons.directions_car_rounded),
                const SizedBox(width: 8),
                _buildCategoryChip('Express Bikes', 'bike', Icons.two_wheeler_rounded),
                const SizedBox(width: 8),
                _buildCategoryChip('Delivery Vans', 'delivery_van', Icons.local_shipping_outlined),
                const SizedBox(width: 8),
                _buildCategoryChip('Heavy Trucks', 'truck', Icons.fire_truck_outlined),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Available Fleet Header ────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Available Fleet',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.obsidian,
                ),
              ),
              Text(
                '${_filteredVehicles.length} available',
                style: const TextStyle(fontSize: 12, color: AppColors.gray500),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Fleet Cards List ──────────────────────────────────────
          if (_filteredVehicles.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              alignment: Alignment.center,
              child: const Text(
                'No vehicles found in this category.',
                style: TextStyle(color: AppColors.gray500, fontSize: 13),
              ),
            )
          else
            ..._filteredVehicles.map((vehicle) {
              final dailyRate = vehicle.pricePerDay ?? 350.0;
              final driverSurcharge = widget.isWithDriver ? 120.0 * widget.rentalDays : 0.0;
              final total = (dailyRate * widget.rentalDays) + driverSurcharge;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    VehicleDetailModal.show(
                      context,
                      vehicle: vehicle,
                      isWithDriver: widget.isWithDriver,
                      rentalDays: widget.rentalDays,
                      onProceedToCheckout: () => widget.onBookVehicle(vehicle),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Vehicle Icon or Thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: vehicle.imageUrls.isNotEmpty && vehicle.imageUrls.first.isNotEmpty
                                  ? Image.network(
                                      vehicle.imageUrls.first,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: const Color(0xFF1E293B),
                                        child: Icon(
                                          vehicle.vehicleType.iconData,
                                          color: AppColors.emerald,
                                          size: 26,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: const Color(0xFF1E293B),
                                      child: Icon(
                                        vehicle.vehicleType.iconData,
                                        color: AppColors.emerald,
                                        size: 26,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Vehicle Details Column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vehicle.fullTitle,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.obsidian,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${vehicle.vehicleType.passengerCapacity} Seats • ${vehicle.color ?? "Standard"}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.gray500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  vehicle.ownerName ?? 'Vektolux Executive Fleet',
                                  style: const TextStyle(fontSize: 10, color: AppColors.gray400),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1, color: AppColors.border),
                      const SizedBox(height: 8),

                      // Bottom Action Row: Price + Chat + Book Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${vehicle.currency} ${total.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.emeraldDark,
                                ),
                              ),
                              Text(
                                '${widget.rentalDays} days • ${vehicle.currency} ${dailyRate.toStringAsFixed(0)}/day',
                                style: const TextStyle(fontSize: 10, color: AppColors.gray500),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 19,
                                  color: AppColors.obsidian,
                                ),
                                tooltip: 'Chat with host',
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  InAppChatModal.show(
                                    context,
                                    recipientName: vehicle.ownerName ?? 'Fleet Manager',
                                    recipientRole: 'Fleet Host',
                                    vehicleTitle: vehicle.fullTitle,
                                    vehiclePrice: '${vehicle.currency} ${dailyRate.toStringAsFixed(0)} / day',
                                    recipientPhone: vehicle.ownerPhone,
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 36,
                                child: VxButton.small(
                                  label: 'Rent Now',
                                  onPressed: () => widget.onBookVehicle(vehicle),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, String value, IconData icon) {
    final isSelected = _selectedCategory == value;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isSelected ? AppColors.white : AppColors.obsidian,
          ),
          const SizedBox(width: 5),
          Text(label),
        ],
      ),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? AppColors.white : AppColors.obsidian,
      ),
      selectedColor: AppColors.emerald,
      backgroundColor: AppColors.white,
      checkmarkColor: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? AppColors.emerald : AppColors.border,
        ),
      ),
      onSelected: (_) => setState(() => _selectedCategory = value),
    );
  }

  Widget _buildDurationChip(String label, int days) {
    final isSelected = widget.rentalDays == days;
    return GestureDetector(
      onTap: () => widget.onUpdateDays(days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emerald : AppColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.white : AppColors.obsidian,
          ),
        ),
      ),
    );
  }
}
