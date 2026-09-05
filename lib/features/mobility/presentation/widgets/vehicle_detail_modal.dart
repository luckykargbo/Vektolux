// lib/features/mobility/presentation/widgets/vehicle_detail_modal.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Dedicated Vehicle Detail & Specs Modal
// Full specifications, photo carousel, chauffeur options, host chat,
// and seamless rental checkout action.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../../core/theme/components/verified_badge.dart';
import '../../domain/entities/mobility_vehicle_entity.dart';
import 'in_app_chat_modal.dart';

class VehicleDetailModal extends StatefulWidget {
  final VehicleListingEntity vehicle;
  final bool initialWithDriver;
  final int initialDays;
  final ValueChanged<bool>? onDriverChanged;
  final ValueChanged<int>? onDaysChanged;
  final VoidCallback onProceedToCheckout;

  const VehicleDetailModal({
    super.key,
    required this.vehicle,
    this.initialWithDriver = false,
    this.initialDays = 1,
    this.onDriverChanged,
    this.onDaysChanged,
    required this.onProceedToCheckout,
  });

  static Future<void> show(
    BuildContext context, {
    required VehicleListingEntity vehicle,
    bool isWithDriver = false,
    int rentalDays = 1,
    ValueChanged<bool>? onDriverChanged,
    ValueChanged<int>? onDaysChanged,
    required VoidCallback onProceedToCheckout,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VehicleDetailModal(
        vehicle: vehicle,
        initialWithDriver: isWithDriver,
        initialDays: rentalDays,
        onDriverChanged: onDriverChanged,
        onDaysChanged: onDaysChanged,
        onProceedToCheckout: onProceedToCheckout,
      ),
    );
  }

  @override
  State<VehicleDetailModal> createState() => _VehicleDetailModalState();
}

class _VehicleDetailModalState extends State<VehicleDetailModal> {
  late bool _withDriver;
  late int _days;
  final int _activeImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _withDriver = widget.initialWithDriver;
    _days = widget.initialDays;
  }

  double get _dailyRate => widget.vehicle.pricePerDay ?? 350.0;
  double get _driverFeePerDay => _withDriver ? 120.0 : 0.0;
  double get _subtotal => (_dailyRate + _driverFeePerDay) * _days;
  double get _serviceFee => (_subtotal * 0.05).roundToDouble();
  double get _total => _subtotal + _serviceFee;

  @override
  Widget build(BuildContext context) {
    final images = widget.vehicle.imageUrls.isNotEmpty
        ? widget.vehicle.imageUrls
        : <String>[];

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        children: [
          // ── Drag Handle ───────────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Scrollable Body ───────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                // ── Image Header / Carousel ─────────────────────────
                Stack(
                  children: [
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.gray100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: images.isNotEmpty
                          ? Image.network(
                              images[_activeImageIndex],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildFallbackImage(),
                            )
                          : _buildFallbackImage(),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.obsidian.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield, color: AppColors.emerald, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Verified Fleet',
                              style: TextStyle(
                                color: AppColors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // ── Title & Price Header ────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.vehicle.fullTitle,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.obsidian,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.vehicle.color ?? "Standard Color"} • License: ${widget.vehicle.licensePlate ?? "Verified Fleet"}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.gray500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${widget.vehicle.currency} ${_dailyRate.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                        const Text(
                          'per day',
                          style: TextStyle(fontSize: 11, color: AppColors.gray500),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Technical Specs Grid ────────────────────────────
                const Text(
                  'Vehicle Specifications',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildSpecCard(
                      icon: Icons.people_outline,
                      title: 'Passengers',
                      value: '${widget.vehicle.vehicleType.passengerCapacity} Seats',
                    ),
                    const SizedBox(width: 8),
                    _buildSpecCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'Cargo',
                      value: widget.vehicle.vehicleType.luggageCapacity,
                    ),
                    const SizedBox(width: 8),
                    _buildSpecCard(
                      icon: Icons.settings_outlined,
                      title: 'Transmission',
                      value: 'Automatic',
                    ),
                    const SizedBox(width: 8),
                    _buildSpecCard(
                      icon: Icons.local_gas_station_outlined,
                      title: 'Fuel',
                      value: 'Petrol',
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // ── Rental Options (Period & Chauffeur) ─────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.gray50,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      // Days selector
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Rental Duration',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: _days > 1 ? AppColors.obsidian : AppColors.gray300,
                                onPressed: _days > 1
                                    ? () {
                                        setState(() => _days--);
                                        widget.onDaysChanged?.call(_days);
                                      }
                                    : null,
                              ),
                              Text(
                                '$_days ${_days == 1 ? "Day" : "Days"}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                color: AppColors.emerald,
                                onPressed: () {
                                  setState(() => _days++);
                                  widget.onDaysChanged?.call(_days);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 18),
                      // Driver Switch
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Add Dedicated Chauffeur (+120 SLE/day)',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        subtitle: const Text(
                          'Professional vetted driver for seamless urban travel',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _withDriver,
                        activeThumbColor: AppColors.emerald,
                        onChanged: (val) {
                          setState(() => _withDriver = val);
                          widget.onDriverChanged?.call(val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ── Host & Fleet Manager Card with Direct Chat ──────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.emeraldSurface,
                        child: Text(
                          (widget.vehicle.ownerName ?? 'V')[0],
                          style: const TextStyle(
                            color: AppColors.emeraldDark,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  widget.vehicle.ownerName ?? 'Sierra Fleet Co.',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const VerifiedBadge(size: VerifiedBadgeSize.small),
                              ],
                            ),
                            const Text(
                              'Verified Fleet Manager • ★ 4.9 (84 reviews)',
                              style: TextStyle(fontSize: 11, color: AppColors.gray500),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                        label: const Text('Chat', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.obsidian,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: () {
                          InAppChatModal.show(
                            context,
                            recipientName: widget.vehicle.ownerName ?? 'Sierra Fleet Co.',
                            recipientRole: 'Verified Fleet Manager',
                            vehicleTitle: widget.vehicle.fullTitle,
                            vehiclePrice: '${widget.vehicle.currency} ${_dailyRate.toStringAsFixed(0)} / day',
                            recipientPhone: widget.vehicle.ownerPhone,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // ── Sticky Checkout Action Bar ────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: AppColors.white,
              border: const Border(top: BorderSide(color: AppColors.border)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Total Payable',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      Text(
                        '${widget.vehicle.currency} ${_total.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.obsidian,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: VxButton(
                    label: 'Proceed to Rent',
                    height: 50,
                    icon: Icons.key_rounded,
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onProceedToCheckout();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.gray50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppColors.emeraldDark),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 10, color: AppColors.gray500),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackImage() {
    return Container(
      color: const Color(0xFF1E293B),
      child: Center(
        child: Icon(
          widget.vehicle.vehicleType.iconData,
          size: 56,
          color: AppColors.emerald,
        ),
      ),
    );
  }
}
