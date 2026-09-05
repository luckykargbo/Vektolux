// lib/features/bookings/presentation/views/checkout_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Checkout & Fiat Payment View
// Flutterwave / Mobile Money (Orange & Africell) + Card Payment Screen
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;

import '../../../../core/database/app_database.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import 'my_bookings_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final AppDatabase database;
  final ConvexClientWrapper convexClient;
  final UserEntity currentUser;
  final String listingId;
  final String listingType;
  final String listingTitle;
  final String listingSubtitle;
  final String? primaryImageUrl;
  final String vendorId;
  final String bookingType;
  final int startTime;
  final int endTime;
  final int? hours;
  final int? days;
  final double subtotal;
  final double serviceFee;
  final double totalAmount;

  const CheckoutScreen({
    super.key,
    required this.database,
    required this.convexClient,
    required this.currentUser,
    required this.listingId,
    required this.listingType,
    required this.listingTitle,
    required this.listingSubtitle,
    this.primaryImageUrl,
    required this.vendorId,
    required this.bookingType,
    required this.startTime,
    required this.endTime,
    this.hours,
    this.days,
    required this.subtotal,
    required this.serviceFee,
    required this.totalAmount,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _paymentMethod = 'mobile_money'; // 'mobile_money' or 'card'
  String _momoProvider = 'orange_money'; // 'orange_money' or 'africell_money'
  late final TextEditingController _phoneController;
  final _cardNumberController =
      TextEditingController(text: '4111 2222 3333 4444');
  final _cardExpiryController = TextEditingController(text: '12/28');
  final _cardCvvController = TextEditingController(text: '888');

  bool _isProcessing = false;
  final _currencyFormat = NumberFormat('#,##0', 'en_US');

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.currentUser.phone);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    super.dispose();
  }

  Future<void> _processPayment() async {
    setState(() => _isProcessing = true);

    try {
      // 1. Create booking in Convex
      final createBookingResult = await widget.convexClient.mutation(
        'bookings:createBooking',
        args: {
          'listingId': widget.listingId,
          'listingType': widget.listingType,
          'listingTitle': widget.listingTitle,
          'buyerId': widget.currentUser.id,
          'buyerName': widget.currentUser.name,
          'buyerPhone': _phoneController.text.trim(),
          'vendorId': widget.vendorId,
          'bookingType': widget.bookingType,
          'startTime': widget.startTime,
          'endTime': widget.endTime,
          if (widget.hours != null) 'hours': widget.hours!,
          if (widget.days != null) 'days': widget.days!,
          'paymentMethod': _paymentMethod,
        },
      );

      if (!createBookingResult.success || createBookingResult.value == null) {
        throw Exception(createBookingResult.errorMessage ?? 'Failed to create booking');
      }

      final bookingData = createBookingResult.value as Map<String, dynamic>;
      final bookingId = bookingData['bookingId'] as String;
      final txRef = bookingData['txRef'] as String;

      // 2. Initialize Flutterwave checkout session
      await widget.convexClient.mutation(
        'payments:initializePayment',
        args: {
          'bookingId': bookingId,
          'txRef': txRef,
          'amount': widget.totalAmount,
          'currency': 'SLE',
          'customerEmail': widget.currentUser.email,
          'customerPhone': _phoneController.text.trim(),
          'customerName': widget.currentUser.name,
          'paymentOptions': _paymentMethod == 'mobile_money'
              ? 'mobilemoney'
              : 'card',
        },
      );

      // 3. Confirm Payment (simulated webhook/callback completion)
      final confirmResult = await widget.convexClient.mutation(
        'payments:confirmPayment',
        args: {
          'bookingId': bookingId,
          'txRef': txRef,
          'gatewayReference': 'FLW_${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      if (!confirmResult.success) {
        throw Exception(confirmResult.errorMessage ?? 'Payment confirmation failed');
      }

      // 4. Cache Confirmed Booking directly into Drift SQLite
      await widget.database.cachedBookingsDao.insertOrUpdate(
        CachedBookingsTableCompanion.insert(
          id: bookingId,
          listingId: widget.listingId,
          listingTitle: drift.Value(widget.listingTitle),
          buyerId: widget.currentUser.id,
          vendorId: widget.vendorId,
          bookingType: widget.bookingType,
          startTime: widget.startTime,
          endTime: widget.endTime,
          totalAmount: widget.totalAmount,
          currency: const drift.Value('SLE'),
          paymentStatus: 'completed',
          bookingStatus: const drift.Value('confirmed'),
          cachedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      if (mounted) {
        _showSuccessDialog(bookingId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment Error: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSuccessDialog(String bookingId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.emeraldSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.emerald,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Payment Confirmed!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your booking for ${widget.listingTitle} is confirmed. Funds are protected in escrow.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Reference: #$bookingId',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop(); // close dialog
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => MyBookingsScreen(
                        database: widget.database,
                        convexClient: widget.convexClient,
                        currentUser: widget.currentUser,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('View My Bookings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Checkout & Payment',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Order Summary Card ──────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.obsidian.withValues(alpha: 0.04),
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
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.gray100,
                          borderRadius: BorderRadius.circular(12),
                          image: widget.primaryImageUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(widget.primaryImageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: widget.primaryImageUrl == null
                            ? Icon(
                                widget.listingType == 'property'
                                    ? Icons.apartment_rounded
                                    : Icons.directions_car_rounded,
                                color: AppColors.gray500,
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.listingTitle,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.obsidian,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.listingSubtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Schedule',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                      Text(
                        DateFormat('EEE, MMM d, yyyy')
                            .format(DateTime.fromMillisecondsSinceEpoch(widget.startTime)),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (widget.hours != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Duration',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                        Text('${widget.hours} Hours',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                  if (widget.days != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Rental Period',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textSecondary)),
                        Text('${widget.days} Days',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 2. Payment Method Selector ─────────────────────────
            const Text(
              'Select Payment Method',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _PaymentTypeCard(
                    title: 'Mobile Money',
                    subtitle: 'Orange & Africell',
                    icon: Icons.phone_android_rounded,
                    isSelected: _paymentMethod == 'mobile_money',
                    onTap: () => setState(() => _paymentMethod = 'mobile_money'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PaymentTypeCard(
                    title: 'Bank Card',
                    subtitle: 'Visa & Mastercard',
                    icon: Icons.credit_card_rounded,
                    isSelected: _paymentMethod == 'card',
                    onTap: () => setState(() => _paymentMethod = 'card'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Method Form Inputs
            if (_paymentMethod == 'mobile_money') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mobile Network Provider',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Orange Money'),
                            selected: _momoProvider == 'orange_money',
                            selectedColor: Colors.orange.shade700,
                            labelStyle: TextStyle(
                              color: _momoProvider == 'orange_money'
                                  ? AppColors.white
                                  : AppColors.obsidian,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            onSelected: (val) {
                              if (val) {
                                setState(() => _momoProvider = 'orange_money');
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Africell Money'),
                            selected: _momoProvider == 'africell_money',
                            selectedColor: Colors.purple.shade700,
                            labelStyle: TextStyle(
                              color: _momoProvider == 'africell_money'
                                  ? AppColors.white
                                  : AppColors.obsidian,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            onSelected: (val) {
                              if (val) {
                                setState(() => _momoProvider = 'africell_money');
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Sierra Leone Phone Number',
                        prefixText: '+232 ',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    TextFormField(
                      controller: _cardNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Card Number',
                        prefixIcon: Icon(Icons.credit_card_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cardExpiryController,
                            decoration: const InputDecoration(
                              labelText: 'Expiry (MM/YY)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _cardCvvController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'CVV',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // ── 3. Total Breakdown ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal'),
                      Text('SLE ${_currencyFormat.format(widget.subtotal)}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Platform & Escrow Protection (5%)',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      Text('SLE ${_currencyFormat.format(widget.serviceFee)}',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Payable',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                      ),
                      Text(
                        'SLE ${_currencyFormat.format(widget.totalAmount)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── 4. Pay Button ──────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Pay SLE ${_currencyFormat.format(widget.totalAmount)} with Flutterwave',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTypeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentTypeCard({
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
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emeraldSurface : AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.emerald : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
