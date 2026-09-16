// lib/features/mobility/presentation/views/delivery_van_booking_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Delivery Van Booking Flow
// Date-range picker, booking summary, and checkout for delivery van
// rentals within the Auto Market vertical.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vx_network_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';

class DeliveryVanBookingScreen extends StatefulWidget {
  final Map<String, dynamic> vehicle;
  final ConvexClientWrapper convexClient;

  const DeliveryVanBookingScreen({
    super.key,
    required this.vehicle,
    required this.convexClient,
  });

  @override
  State<DeliveryVanBookingScreen> createState() =>
      _DeliveryVanBookingScreenState();
}

class _DeliveryVanBookingScreenState extends State<DeliveryVanBookingScreen> {
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');
  final TextEditingController _notesController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;

  double get _pricePerDay =>
      (widget.vehicle['pricePerDay'] as num?)?.toDouble() ?? 0;
  String get _currency => widget.vehicle['currency'] as String? ?? 'SLE';

  int get _totalDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays.clamp(1, 365);
  }

  double get _subtotal => _totalDays * _pricePerDay;
  double get _serviceFee => _subtotal * 0.05; // 5% platform fee
  double get _totalAmount => _subtotal + _serviceFee;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: AppColors.lightScheme,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _submitBooking() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select rental dates')),
      );
      return;
    }

    final authState = context.read<AuthBloc>().state;
    final user = authState.user;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      final vehicleId = widget.vehicle['_id'] as String? ?? '';
      final ownerId = widget.vehicle['ownerId'] as String? ?? '';
      final title =
          '${widget.vehicle['make'] ?? ''} ${widget.vehicle['model'] ?? ''}'
              .trim();

      final res = await widget.convexClient.mutation(
        'bookings:createBooking',
        args: {
          'listingId': vehicleId,
          'listingType': 'vehicle',
          'listingTitle': title,
          'buyerId': user.id,
          'buyerName': user.name,
          'buyerPhone': user.phone,
          'vendorId': ownerId,
          'bookingType': 'vehicle_rental',
          'startTime': _startDate!.millisecondsSinceEpoch,
          'endTime': _endDate!.millisecondsSinceEpoch,
          'days': _totalDays,
          'subtotal': _subtotal,
          'serviceFee': _serviceFee,
          'totalAmount': _totalAmount,
          'currency': _currency,
          'notes': _notesController.text.trim(),
        },
      );

      if (mounted) {
        if (res.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking submitted successfully!'),
              backgroundColor: AppColors.emerald,
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Booking failed: ${res.error ?? 'Unknown error'}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final make = widget.vehicle['make'] as String? ?? '';
    final model = widget.vehicle['model'] as String? ?? '';
    final year = widget.vehicle['year'] as num? ?? 0;
    final imageUrls = widget.vehicle['imageUrls'] as List? ?? [];
    final dateFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Book Delivery Van',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vehicle card
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageUrls.isNotEmpty)
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      child: VxNetworkImage(
                        imageUrl: imageUrls.first.toString(),
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.local_shipping_rounded,
                                size: 20, color: AppColors.mobility),
                            const SizedBox(width: 8),
                            Text(
                              '$make $model ($year)',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$_currency ${_currencyFormat.format(_pricePerDay)} / day',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Date picker
            const Text(
              'Rental Period',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickDateRange,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded,
                        size: 22, color: AppColors.emerald),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _startDate != null && _endDate != null
                          ? Text(
                              '${dateFormat.format(_startDate!)} — ${dateFormat.format(_endDate!)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            )
                          : Text(
                              'Select start and end dates',
                              style: TextStyle(
                                fontSize: 15,
                                color: AppColors.textSecondary,
                              ),
                            ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.gray400),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Notes
            const Text(
              'Notes (optional)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Pickup location, delivery details, etc.',
                hintStyle: TextStyle(color: AppColors.textDisabled),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.emerald, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Booking summary
            if (_totalDays > 0) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow('Duration', '$_totalDays day${_totalDays > 1 ? 's' : ''}'),
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      'Subtotal',
                      '$_currency ${_currencyFormat.format(_subtotal)}',
                    ),
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      'Service Fee (5%)',
                      '$_currency ${_currencyFormat.format(_serviceFee)}',
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(color: AppColors.emerald, height: 1),
                    ),
                    _buildSummaryRow(
                      'Total',
                      '$_currency ${_currencyFormat.format(_totalAmount)}',
                      isBold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),

      // Bottom CTA
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isSubmitting || _totalDays == 0 ? null : _submitBooking,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emerald,
                disabledBackgroundColor: AppColors.gray200,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _totalDays > 0
                          ? 'Confirm Booking • $_currency ${_currencyFormat.format(_totalAmount)}'
                          : 'Select Dates to Continue',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: isBold ? AppColors.emeraldDark : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
