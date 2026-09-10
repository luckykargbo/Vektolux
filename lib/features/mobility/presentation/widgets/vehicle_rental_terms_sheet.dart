// lib/features/mobility/presentation/widgets/vehicle_rental_terms_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Production Vehicle Rental Terms, Rules & Duration Selector
// Covers 24-hour daily cycles, hourly packages, fuel policy, security
// deposits, driver requirements, and direct vendor communication.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';

class VehicleRentalTermsSheet extends StatefulWidget {
  final String vehicleTitle;
  final double dailyRate;
  final double? hourlyRate;
  final String? vendorName;
  final String? vendorPhone;
  final Function(int days, int? hours, double subtotal, double total) onProceedToCheckout;

  const VehicleRentalTermsSheet({
    super.key,
    required this.vehicleTitle,
    required this.dailyRate,
    this.hourlyRate,
    this.vendorName,
    this.vendorPhone,
    required this.onProceedToCheckout,
  });

  static Future<void> show(
    BuildContext context, {
    required String vehicleTitle,
    required double dailyRate,
    double? hourlyRate,
    String? vendorName,
    String? vendorPhone,
    required Function(int days, int? hours, double subtotal, double total) onProceedToCheckout,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VehicleRentalTermsSheet(
        vehicleTitle: vehicleTitle,
        dailyRate: dailyRate,
        hourlyRate: hourlyRate,
        vendorName: vendorName,
        vendorPhone: vendorPhone,
        onProceedToCheckout: onProceedToCheckout,
      ),
    );
  }

  @override
  State<VehicleRentalTermsSheet> createState() => _VehicleRentalTermsSheetState();
}

class _VehicleRentalTermsSheetState extends State<VehicleRentalTermsSheet> {
  bool _isDaily = true; // true = 24h Daily, false = Hourly
  int _selectedDays = 1; // 1 to 30 days
  int _selectedHours = 6; // 4, 6, 8, 12 hours
  bool _agreedToTerms = false;
  bool _needsChauffeur = false;

  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');

  double get _subtotal {
    if (_isDaily) {
      return widget.dailyRate * _selectedDays;
    } else {
      final rate = widget.hourlyRate ?? (widget.dailyRate / 10);
      return rate * _selectedHours;
    }
  }

  double get _chauffeurFee => _needsChauffeur ? (_isDaily ? 100.0 * _selectedDays : 50.0) : 0.0;
  double get _serviceFee => (_subtotal * 0.05).roundToDouble();
  double get _total => _subtotal + _chauffeurFee + _serviceFee;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Drag Handle
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

              // Title and Vendor Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldSurface,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.car_rental_rounded, color: AppColors.emeraldDark, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.vehicleTitle,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.obsidian,
                            fontFamily: 'Poppins',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Verified Vendor: ${widget.vendorName ?? "Vektolux Fleet"}',
                          style: const TextStyle(fontSize: 12, color: AppColors.gray600, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── 1. Duration Type Selector (24-Hour Daily vs Hourly) ──
              const Text(
                'Select Rental Duration',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.obsidian),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isDaily = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        decoration: BoxDecoration(
                          color: _isDaily ? AppColors.emeraldSurface : AppColors.gray50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isDaily ? AppColors.emerald : AppColors.border,
                            width: _isDaily ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.calendar_today_rounded, color: _isDaily ? AppColors.emeraldDark : AppColors.gray500, size: 20),
                            const SizedBox(height: 4),
                            Text(
                              '24-Hour Full Day',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: _isDaily ? FontWeight.w700 : FontWeight.w500,
                                color: _isDaily ? AppColors.emeraldDark : AppColors.obsidian,
                              ),
                            ),
                            Text(
                              'SLE ${_currencyFormat.format(widget.dailyRate)} / 24h',
                              style: const TextStyle(fontSize: 11, color: AppColors.gray500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isDaily = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        decoration: BoxDecoration(
                          color: !_isDaily ? AppColors.emeraldSurface : AppColors.gray50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: !_isDaily ? AppColors.emerald : AppColors.border,
                            width: !_isDaily ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.schedule_rounded, color: !_isDaily ? AppColors.emeraldDark : AppColors.gray500, size: 20),
                            const SizedBox(height: 4),
                            Text(
                              'Hourly Booking',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: !_isDaily ? FontWeight.w700 : FontWeight.w500,
                                color: !_isDaily ? AppColors.emeraldDark : AppColors.obsidian,
                              ),
                            ),
                            Text(
                              'SLE ${_currencyFormat.format(widget.hourlyRate ?? (widget.dailyRate / 10))} / hr',
                              style: const TextStyle(fontSize: 11, color: AppColors.gray500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Duration Stepper ──
              if (_isDaily) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Number of 24-Hour Days:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: AppColors.obsidian),
                          onPressed: _selectedDays > 1 ? () => setState(() => _selectedDays--) : null,
                        ),
                        Text(
                          '$_selectedDays ${_selectedDays == 1 ? "Day" : "Days"}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: AppColors.emerald),
                          onPressed: _selectedDays < 30 ? () => setState(() => _selectedDays++) : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Number of Hours:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    DropdownButton<int>(
                      value: _selectedHours,
                      underline: const SizedBox.shrink(),
                      items: [4, 6, 8, 12, 18, 23].map((h) {
                        return DropdownMenuItem<int>(
                          value: h,
                          child: Text('$h Hours', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedHours = v);
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // ── Chauffeur Option ──
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.person_pin_circle_outlined, color: AppColors.obsidian),
                title: const Text('Add Dedicated Chauffeur', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                subtitle: const Text('Professional Sierra Leone licensed driver provided', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                value: _needsChauffeur,
                activeThumbColor: AppColors.emerald,
                onChanged: (val) => setState(() => _needsChauffeur = val),
              ),
              const Divider(height: 24),

              // ── 2. Official Rental Policy & Handover Rules ──
              const Text(
                'Rental Conditions & Procedures',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.obsidian, letterSpacing: 0.3),
              ),
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.gray50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _buildConditionRow(
                      icon: Icons.timer_outlined,
                      title: '24-Hour Cycle',
                      detail: 'A rental day is calculated from vehicle handover time for exactly 24 continuous hours.',
                    ),
                    const Divider(height: 16),
                    _buildConditionRow(
                      icon: Icons.local_gas_station_outlined,
                      title: 'Same-to-Same Fuel',
                      detail: 'Vehicle is handed over with recorded fuel level and must be returned at identical fuel level.',
                    ),
                    const Divider(height: 16),
                    _buildConditionRow(
                      icon: Icons.badge_outlined,
                      title: 'Valid Driving License',
                      detail: 'Self-drive renters must present an authentic Sierra Leone NIN/ECOWAS driver’s license.',
                    ),
                    const Divider(height: 16),
                    _buildConditionRow(
                      icon: Icons.shield_outlined,
                      title: 'Escrow Security Deposit',
                      detail: 'Refundable deposit is locked in Vektolux escrow and released immediately upon vehicle return inspection.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 3. Price Breakdown Card ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isDaily ? 'Rental Fee ($_selectedDays Days)' : 'Rental Fee ($_selectedHours Hours)',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          'SLE ${_currencyFormat.format(_subtotal)}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (_needsChauffeur) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Chauffeur Service Fee', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Text(
                            'SLE ${_currencyFormat.format(_chauffeurFee)}',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Vektolux Protection & Escrow Fee (5%)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Text(
                          'SLE ${_currencyFormat.format(_serviceFee)}',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const Divider(height: 18, color: Colors.white24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Amount', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                        Text(
                          'SLE ${_currencyFormat.format(_total)}',
                          style: const TextStyle(color: AppColors.emerald, fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Terms Agreement Checkbox
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.emerald,
                value: _agreedToTerms,
                onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
                title: const Text(
                  'I agree to the Vektolux 24-Hour Rental Agreement and vehicle inspection terms.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.obsidian),
                ),
              ),
              const SizedBox(height: 16),

              // Action Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.gray300,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _agreedToTerms
                      ? () {
                          Navigator.of(context).pop();
                          widget.onProceedToCheckout(
                            _isDaily ? _selectedDays : 1,
                            _isDaily ? null : _selectedHours,
                            _subtotal,
                            _total,
                          );
                        }
                      : null,
                  child: Text(
                    _agreedToTerms ? 'Proceed to Escrow Checkout' : 'Accept Terms to Continue',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConditionRow({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.emeraldDark),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
              const SizedBox(height: 2),
              Text(detail, style: const TextStyle(fontSize: 11, color: AppColors.gray600)),
            ],
          ),
        ),
      ],
    );
  }
}
