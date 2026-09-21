// lib/features/bookings/presentation/widgets/booking_modals.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Booking Modals
// Quick-action bottom sheets for:
//   1. Free Site-Visit / Test-Drive Inspection Scheduling
//   2. Hourly Guest House Duration Slider & Live Pricing
//   3. Vehicle Rental Duration & Dedicated Driver Picker
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../mobility/domain/entities/mobility_vehicle_entity.dart';
import '../../../real_estate/domain/entities/property_listing_entity.dart';
import '../views/checkout_screen.dart';

// ═══════════════════════════════════════════════════════════════════════
//                     1. PROPERTY INSPECTION MODAL
// ═══════════════════════════════════════════════════════════════════════

class PropertyInspectionModal extends StatefulWidget {
  final PropertyListingEntity property;
  final UserEntity currentUser;
  final ConvexClientWrapper convexClient;

  const PropertyInspectionModal({
    super.key,
    required this.property,
    required this.currentUser,
    required this.convexClient,
  });

  static Future<void> show(
    BuildContext context, {
    required PropertyListingEntity property,
    required UserEntity currentUser,
    required ConvexClientWrapper convexClient,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PropertyInspectionModal(
        property: property,
        currentUser: currentUser,
        convexClient: convexClient,
      ),
    );
  }

  @override
  State<PropertyInspectionModal> createState() =>
      _PropertyInspectionModalState();
}

class _PropertyInspectionModalState extends State<PropertyInspectionModal> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String _selectedTimeSlot = '10:00 AM';
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _timeSlots = [
    '09:00 AM',
    '10:30 AM',
    '01:00 PM',
    '03:00 PM',
    '05:00 PM',
  ];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitInspection() async {
    setState(() => _isSubmitting = true);

    try {
      final startDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        int.parse(_selectedTimeSlot.split(':')[0]) +
            (_selectedTimeSlot.contains('PM') &&
                    !_selectedTimeSlot.startsWith('12')
                ? 12
                : 0),
      );
      final endDateTime = startDateTime.add(const Duration(hours: 1));

      // 1. Convex Mutation
      await widget.convexClient.mutation(
        'bookings:createBooking',
        args: {
          'listingId': widget.property.id,
          'listingType': 'property',
          'listingTitle': widget.property.title,
          'buyerId': widget.currentUser.id,
          'buyerName': widget.currentUser.name,
          'buyerPhone': widget.currentUser.phone,
          'vendorId': widget.property.ownerId,
          'bookingType': 'property_inspection',
          'startTime': startDateTime.millisecondsSinceEpoch,
          'endTime': endDateTime.millisecondsSinceEpoch,
          'notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        },
      );


      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Site visit booked for ${DateFormat('EEE, MMM d').format(_selectedDate)} at $_selectedTimeSlot!',
            ),
            backgroundColor: AppColors.emerald,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking error: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : AppColors.white;
    final primaryTextColor = isDark ? AppColors.white : AppColors.obsidian;
    final secondaryTextColor = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
    final unselectedChipBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF475569) : AppColors.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title & Free Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Schedule Site Visit',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: primaryTextColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF064E3B) : AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_rounded, size: 14, color: AppColors.emerald),
                    const SizedBox(width: 4),
                    Text(
                      'FREE VISIT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.emeraldLight : AppColors.emeraldDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.property.title,
            style: TextStyle(fontSize: 13, color: secondaryTextColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),

          // Date Selector Chips
          Text(
            'Select Preferred Date',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(7, (index) {
                final date = DateTime.now().add(Duration(days: index + 1));
                final isSelected = _selectedDate.day == date.day &&
                    _selectedDate.month == date.month;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      index == 0
                          ? 'Tomorrow'
                          : DateFormat('EEE, d MMM').format(date),
                    ),
                    selected: isSelected,
                    selectedColor: AppColors.emerald,
                    backgroundColor: unselectedChipBg,
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.white : primaryTextColor,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _selectedDate = date);
                    },
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 20),

          // Time Slot Grid
          Text(
            'Select Time Window',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _timeSlots.map((slot) {
              final isSelected = _selectedTimeSlot == slot;
              return ChoiceChip(
                label: Text(slot),
                selected: isSelected,
                selectedColor: AppColors.emerald,
                backgroundColor: unselectedChipBg,
                labelStyle: TextStyle(
                  color: isSelected ? AppColors.white : primaryTextColor,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 12,
                ),
                onSelected: (val) {
                  if (val) setState(() => _selectedTimeSlot = slot);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Notes
          TextField(
            controller: _notesController,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              hintText: 'Special instructions or questions for the agent...',
              hintStyle: TextStyle(fontSize: 13, color: isDark ? const Color(0xFF94A3B8) : AppColors.gray400),
              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : AppColors.border),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 24),

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitInspection,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.white),
                      ),
                    )
                  : const Text(
                      'Confirm Free Inspection',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//                     2. HOURLY GUEST HOUSE STAY MODAL
// ═══════════════════════════════════════════════════════════════════════

class HourlyBookingModal extends StatefulWidget {
  final PropertyListingEntity property;
  final UserEntity currentUser;
  final ConvexClientWrapper convexClient;

  const HourlyBookingModal({
    super.key,
    required this.property,
    required this.currentUser,
    required this.convexClient,
  });

  static Future<void> show(
    BuildContext context, {
    required PropertyListingEntity property,
    required UserEntity currentUser,
    required ConvexClientWrapper convexClient,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HourlyBookingModal(
        property: property,
        currentUser: currentUser,
        convexClient: convexClient,
      ),
    );
  }

  @override
  State<HourlyBookingModal> createState() => _HourlyBookingModalState();
}

class _HourlyBookingModalState extends State<HourlyBookingModal> {
  int _selectedHours = 4;
  final _currencyFormat = NumberFormat('#,##0', 'en_US');

  double get _hourlyRate => widget.property.hourlyRate ?? 50.0;
  double get _subtotal => _hourlyRate * _selectedHours;
  double get _serviceFee => (_subtotal * 0.05).roundToDouble();
  double get _totalAmount => _subtotal + _serviceFee;

  void _proceedToCheckout() {
    Navigator.of(context).pop(); // Close bottom sheet

    final now = DateTime.now();
    final startTime = now.millisecondsSinceEpoch;
    final endTime = now.add(Duration(hours: _selectedHours)).millisecondsSinceEpoch;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          convexClient: widget.convexClient,
          currentUser: widget.currentUser,
          listingId: widget.property.id,
          listingType: 'property',
          listingTitle: widget.property.title,
          listingSubtitle: '${widget.property.address}, ${widget.property.category.displayName.toUpperCase()}',
          primaryImageUrl: widget.property.primaryImageUrl,
          vendorId: widget.property.ownerId,
          bookingType: 'hourly_guesthouse',
          startTime: startTime,
          endTime: endTime,
          hours: _selectedHours,
          subtotal: _subtotal,
          serviceFee: _serviceFee,
          totalAmount: _totalAmount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF475569) : AppColors.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Short Stay / Hourly Booking',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.white : AppColors.obsidian,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.emeraldDark.withValues(alpha: 0.3)
                      : AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'SLE ${_currencyFormat.format(_hourlyRate)}/hr',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFF34D399) : AppColors.emeraldDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.property.title,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),

          // Duration Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Duration of Stay:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.white : AppColors.obsidian,
                ),
              ),
              Text(
                '$_selectedHours ${_selectedHours == 1 ? 'Hour' : 'Hours'}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.emerald,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.emerald,
              inactiveTrackColor: isDark ? const Color(0xFF334155) : AppColors.gray200,
              thumbColor: isDark ? AppColors.white : AppColors.obsidian,
              overlayColor: AppColors.emerald.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: _selectedHours.toDouble(),
              min: 1,
              max: 24,
              divisions: 23,
              label: '$_selectedHours hrs',
              onChanged: (val) {
                setState(() => _selectedHours = val.toInt());
              },
            ),
          ),

          // Quick preset buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [2, 4, 8, 24].map((hrs) {
              final isSelected = _selectedHours == hrs;
              return OutlinedButton(
                onPressed: () => setState(() => _selectedHours = hrs),
                style: OutlinedButton.styleFrom(
                  backgroundColor: isSelected
                      ? (isDark ? AppColors.white : AppColors.obsidian)
                      : Colors.transparent,
                  foregroundColor: isSelected
                      ? (isDark ? AppColors.obsidian : AppColors.white)
                      : (isDark ? const Color(0xFFCBD5E1) : AppColors.obsidian),
                  side: BorderSide(
                    color: isSelected
                        ? (isDark ? AppColors.white : AppColors.obsidian)
                        : (isDark ? const Color(0xFF334155) : AppColors.border),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(hrs == 24 ? 'Full Day' : '$hrs hrs'),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Live Price Breakdown Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : AppColors.gray50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : AppColors.border,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$_selectedHours hrs @ SLE ${_currencyFormat.format(_hourlyRate)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? const Color(0xFFCBD5E1) : AppColors.obsidian,
                      ),
                    ),
                    Text(
                      'SLE ${_currencyFormat.format(_subtotal)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.white : AppColors.obsidian,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Platform & Security Fee (5%)',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'SLE ${_currencyFormat.format(_serviceFee)}',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Divider(
                  height: 18,
                  color: isDark ? const Color(0xFF1E293B) : AppColors.border,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Estimated Total',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? AppColors.white : AppColors.obsidian,
                      ),
                    ),
                    Text(
                      'SLE ${_currencyFormat.format(_totalAmount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDark ? const Color(0xFF34D399) : AppColors.emeraldDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Proceed Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _proceedToCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Proceed to Payment',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//                     3. VEHICLE RENTAL MODAL
// ═══════════════════════════════════════════════════════════════════════

class VehicleRentalModal extends StatefulWidget {
  final VehicleListingEntity vehicle;
  final UserEntity currentUser;
  final ConvexClientWrapper convexClient;

  const VehicleRentalModal({
    super.key,
    required this.vehicle,
    required this.currentUser,
    required this.convexClient,
  });

  static Future<void> show(
    BuildContext context, {
    required VehicleListingEntity vehicle,
    required UserEntity currentUser,
    required ConvexClientWrapper convexClient,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VehicleRentalModal(
        vehicle: vehicle,
        currentUser: currentUser,
        convexClient: convexClient,
      ),
    );
  }

  @override
  State<VehicleRentalModal> createState() => _VehicleRentalModalState();
}

class _VehicleRentalModalState extends State<VehicleRentalModal> {
  int _rentalDays = 2;
  bool _includeDriver = false;
  final _currencyFormat = NumberFormat('#,##0', 'en_US');

  double get _pricePerDay => widget.vehicle.pricePerDay ?? 300.0;
  double get _driverFeePerDay => _includeDriver ? 120.0 : 0.0;
  double get _subtotal => (_pricePerDay + _driverFeePerDay) * _rentalDays;
  double get _serviceFee => (_subtotal * 0.05).roundToDouble();
  double get _totalAmount => _subtotal + _serviceFee;

  void _proceedToCheckout() {
    Navigator.of(context).pop();

    final now = DateTime.now();
    final startTime = now.millisecondsSinceEpoch;
    final endTime = now.add(Duration(days: _rentalDays)).millisecondsSinceEpoch;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(
          convexClient: widget.convexClient,
          currentUser: widget.currentUser,
          listingId: widget.vehicle.id,
          listingType: 'vehicle',
          listingTitle: '${widget.vehicle.make} ${widget.vehicle.model} (${widget.vehicle.year})',
          listingSubtitle: '${widget.vehicle.vehicleType.displayName.toUpperCase()} · ${_includeDriver ? 'With Dedicated Driver' : 'Self-Drive'}',
          primaryImageUrl: widget.vehicle.primaryImageUrl,
          vendorId: widget.vehicle.ownerId,
          bookingType: 'vehicle_rental',
          startTime: startTime,
          endTime: endTime,
          days: _rentalDays,
          subtotal: _subtotal,
          serviceFee: _serviceFee,
          totalAmount: _totalAmount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF475569) : AppColors.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Vehicle Rental',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.white : AppColors.obsidian,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.emeraldDark.withValues(alpha: 0.3)
                      : AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'SLE ${_currencyFormat.format(_pricePerDay)}/day',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFF34D399) : AppColors.emeraldDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.vehicle.make} ${widget.vehicle.model} (${widget.vehicle.year})',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // Days Stepper
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rental Duration',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.white : AppColors.obsidian,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.remove_circle_outline,
                      color: _rentalDays > 1
                          ? (isDark ? const Color(0xFFCBD5E1) : AppColors.obsidian)
                          : (isDark ? const Color(0xFF475569) : AppColors.gray300),
                    ),
                    onPressed: _rentalDays > 1
                        ? () => setState(() => _rentalDays--)
                        : null,
                  ),
                  Text(
                    '$_rentalDays ${_rentalDays == 1 ? 'Day' : 'Days'}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.white : AppColors.obsidian,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: isDark ? const Color(0xFFCBD5E1) : AppColors.obsidian,
                    ),
                    onPressed: () => setState(() => _rentalDays++),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Dedicated Driver Toggle
          SwitchListTile(
            title: Text(
              'Add Dedicated Driver (+120 SLE/day)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.white : AppColors.obsidian,
              ),
            ),
            subtitle: Text(
              'Professional vetted chauffeur for the trip',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
              ),
            ),
            value: _includeDriver,
            activeThumbColor: AppColors.emerald,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _includeDriver = val),
          ),
          const SizedBox(height: 16),

          // Breakdown Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : AppColors.gray50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : AppColors.border,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$_rentalDays days vehicle rental',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? const Color(0xFFCBD5E1) : AppColors.obsidian,
                      ),
                    ),
                    Text(
                      'SLE ${_currencyFormat.format(_pricePerDay * _rentalDays)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.white : AppColors.obsidian,
                      ),
                    ),
                  ],
                ),
                if (_includeDriver) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Dedicated Driver ($_rentalDays days)',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? const Color(0xFFCBD5E1) : AppColors.obsidian,
                        ),
                      ),
                      Text(
                        'SLE ${_currencyFormat.format(_driverFeePerDay * _rentalDays)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.white : AppColors.obsidian,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Service & Insurance Fee (5%)',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'SLE ${_currencyFormat.format(_serviceFee)}',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Divider(
                  height: 18,
                  color: isDark ? const Color(0xFF1E293B) : AppColors.border,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Payable',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? AppColors.white : AppColors.obsidian,
                      ),
                    ),
                    Text(
                      'SLE ${_currencyFormat.format(_totalAmount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDark ? const Color(0xFF34D399) : AppColors.emeraldDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _proceedToCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Proceed to Checkout',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
