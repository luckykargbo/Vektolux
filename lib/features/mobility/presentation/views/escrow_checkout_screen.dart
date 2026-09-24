// lib/features/mobility/presentation/views/escrow_checkout_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Unified Multi-Rail Vehicle Escrow Checkout
// Supports:
// 1. Mobile Money (Orange Money, Africell Afrimoney, QMoney) with Universal Phone Input & Auto-Carrier Detection
// 2. Direct High-Value Bank Escrow Rails (Sierra Leone Commercial Bank clearing account)
// 3. Vektolux Escrow Wallet Balance
// Standard: Direct Deal Escrow (No pre-topup friction required)
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../../core/services/carrier_detection_service.dart';
import '../../../../core/widgets/universal_phone_input.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/profile/presentation/views/widgets/ussd_payment_sheet.dart';
import 'escrow_tracking_screen.dart';

enum EscrowPaymentRail {
  mobileMoney,
  bankWire,
  wallet,
}

class EscrowCheckoutScreen extends StatefulWidget {
  final String vehicleListingId;
  final String vehicleTitle;
  final String vehicleCategory;
  final double dailyRate;
  final String? vehicleImageUrl;
  final bool isPurchase;
  final double? purchasePrice;

  const EscrowCheckoutScreen({
    super.key,
    required this.vehicleListingId,
    required this.vehicleTitle,
    required this.vehicleCategory,
    required this.dailyRate,
    this.vehicleImageUrl,
    this.isPurchase = false,
    this.purchasePrice,
  });

  @override
  State<EscrowCheckoutScreen> createState() => _EscrowCheckoutScreenState();
}

class _EscrowCheckoutScreenState extends State<EscrowCheckoutScreen> {
  int _rentalDays = 3;
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));

  EscrowPaymentRail _selectedRail = EscrowPaymentRail.mobileMoney;

  final _phoneController = TextEditingController();
  final _bankSlipController = TextEditingController();
  late final String _bankEscrowReference;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final randomSuffix = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();
    _bankEscrowReference = 'VKTLX-DEAL-$randomSuffix';

    final user = context.read<AuthBloc>().state.user;
    if (user != null && user.phone.isNotEmpty) {
      _phoneController.text = user.phone;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _bankSlipController.dispose();
    super.dispose();
  }

  double get _baseRentalAmount => widget.dailyRate * _rentalDays;
  double get _refundableDeposit => widget.isPurchase
      ? 500.0 // Earnest fee
      : (_baseRentalAmount * 0.33).clamp(500.0, 10000.0);
  double get _totalEscrowInflow => widget.isPurchase
      ? (widget.purchasePrice ?? 50000.0)
      : (_baseRentalAmount + _refundableDeposit);
  double get _platformFee => widget.isPurchase
      ? (_totalEscrowInflow * 0.05)
      : (_baseRentalAmount * 0.15);
  double get _netOwnerProceeds => widget.isPurchase
      ? (_totalEscrowInflow - _platformFee)
      : (_baseRentalAmount - _platformFee);

  // ─── 1. Mobile Money Direct Deal Escrow ──────────────────────────────
  Future<void> _handleMobileMoneyCheckout() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to initiate escrow agreement.')),
      );
      return;
    }

    final rawPhone = _phoneController.text.trim();
    if (rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your mobile money phone number.')),
      );
      return;
    }

    final carrier = CarrierDetectionService.detectCarrier(rawPhone);
    final normalizedPhone = CarrierDetectionService.normalizeToSierraLeoneFormat(rawPhone);

    setState(() => _isSubmitting = true);

    try {
      final client = context.read<ConvexClientWrapper>();
      final endDate = _startDate.add(Duration(days: _rentalDays));

      // 1. Create Deal Escrow Order record
      final orderRes = await client.mutation(
        'escrow:initiateEscrowOrder',
        args: {
          'orderType': widget.isPurchase ? 'VEHICLE_PURCHASE' : 'VEHICLE_RENTAL',
          'vehicleListingId': widget.vehicleListingId,
          'renterOrBuyerId': user.id,
          'rentalStartDate': _startDate.millisecondsSinceEpoch,
          'rentalEndDate': endDate.millisecondsSinceEpoch,
          'numberOfDays': _rentalDays,
          'baseRentalAmount': _baseRentalAmount,
          'refundableDepositAmount': _refundableDeposit,
          'fullPurchaseAmount': widget.purchasePrice ?? _totalEscrowInflow,
          'paymentRail': 'MOBILE_MONEY',
          'paymentProvider': carrier.providerSlug,
          'paymentPhone': normalizedPhone,
          'payFromWallet': false,
        },
      );

      if (!orderRes.success || orderRes.value == null) {
        throw Exception(orderRes.errorMessage ?? 'Failed to initialize escrow order');
      }

      final data = orderRes.value as Map<String, dynamic>;
      final orderId = data['escrowOrderId']?.toString() ?? '';

      // 2. Dispatch to Monime API dual-header engine with auto-detected carrier
      final monimeRes = await client.action(
        'payments:initiateMoniMePayment',
        args: {
          'amount': _totalEscrowInflow,
          'phoneNumber': normalizedPhone,
          'provider': carrier.providerSlug,
          'escrowOrderId': orderId,
          'userId': user.id,
          'customerPhone': normalizedPhone,
          'customerName': user.name,
          'customerEmail': user.email,
          'description': 'Vektolux Deal Escrow: ${widget.vehicleTitle}',
        },
      );

      if (mounted) {
        if (monimeRes.success) {
          final resData = monimeRes.value is Map ? monimeRes.value as Map<String, dynamic> : {};
          final ref = resData['reference']?.toString() ?? resData['transactionId']?.toString() ?? '';
          final rawUssd = resData['ussdCode']?.toString() ?? resData['dialCode']?.toString() ?? '';
          final carrierDial = rawUssd.isNotEmpty
              ? rawUssd
              : (carrier.providerSlug == 'orange'
                  ? '*144#'
                  : (carrier.providerSlug == 'africell' ? '*161#' : '*715#'));

          final checkoutUrl = resData['checkoutUrl']?.toString() ?? '';
          if (checkoutUrl.startsWith('http')) {
            final uri = Uri.tryParse(checkoutUrl);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }

          // Trigger native USSD sheet with one-tap dialer and real-time status polling
          if (mounted) {
            await UssdPaymentSheet.show(
              context,
              dialCode: carrierDial,
              reference: ref,
              amount: _totalEscrowInflow,
              serviceFee: 0.0,
              serviceProvider: carrier.displayName,
              recipient: normalizedPhone,
              transactionType: 'Vehicle Escrow Deposit',
            );
          }
        }

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EscrowTrackingScreen(escrowOrderId: orderId),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── 2. Commercial Bank Wire Transfer ────────────────────────────────
  Future<void> _handleBankWireCheckout() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to proceed with bank transfer.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final client = context.read<ConvexClientWrapper>();
      final endDate = _startDate.add(Duration(days: _rentalDays));

      final res = await client.mutation(
        'escrow:initiateEscrowOrder',
        args: {
          'orderType': widget.isPurchase ? 'VEHICLE_PURCHASE' : 'VEHICLE_RENTAL',
          'vehicleListingId': widget.vehicleListingId,
          'renterOrBuyerId': user.id,
          'rentalStartDate': _startDate.millisecondsSinceEpoch,
          'rentalEndDate': endDate.millisecondsSinceEpoch,
          'numberOfDays': _rentalDays,
          'baseRentalAmount': _baseRentalAmount,
          'refundableDepositAmount': _refundableDeposit,
          'fullPurchaseAmount': widget.purchasePrice ?? _totalEscrowInflow,
          'paymentRail': 'BANK_TRANSFER',
          'paymentProvider': 'BANK_TRANSFER',
          'bankEscrowReference': _bankEscrowReference,
          'payFromWallet': false,
        },
      );

      if (res.success && res.value != null) {
        final data = res.value as Map<String, dynamic>;
        final orderId = data['escrowOrderId']?.toString() ?? '';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Bank Wire Registered! Reference: $_bankEscrowReference'),
              backgroundColor: AppColors.emerald,
              duration: const Duration(seconds: 4),
            ),
          );

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EscrowTrackingScreen(escrowOrderId: orderId),
            ),
          );
        }
      } else {
        throw Exception(res.errorMessage ?? 'Failed to initialize escrow');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── 3. In-App Wallet Checkout ──────────────────────────────────────
  Future<void> _handleWalletCheckout() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to proceed.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final client = context.read<ConvexClientWrapper>();
      final endDate = _startDate.add(Duration(days: _rentalDays));

      final res = await client.mutation(
        'escrow:initiateEscrowOrder',
        args: {
          'orderType': widget.isPurchase ? 'VEHICLE_PURCHASE' : 'VEHICLE_RENTAL',
          'vehicleListingId': widget.vehicleListingId,
          'renterOrBuyerId': user.id,
          'rentalStartDate': _startDate.millisecondsSinceEpoch,
          'rentalEndDate': endDate.millisecondsSinceEpoch,
          'numberOfDays': _rentalDays,
          'baseRentalAmount': _baseRentalAmount,
          'refundableDepositAmount': _refundableDeposit,
          'fullPurchaseAmount': widget.purchasePrice ?? _totalEscrowInflow,
          'paymentRail': 'WALLET',
          'paymentProvider': 'WALLET',
          'payFromWallet': true,
        },
      );

      if (res.success && res.value != null) {
        final data = res.value as Map<String, dynamic>;
        final orderId = data['escrowOrderId']?.toString() ?? '';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ SLE locked instantly from Wallet Balance!'),
              backgroundColor: AppColors.emerald,
            ),
          );

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EscrowTrackingScreen(escrowOrderId: orderId),
            ),
          );
        }
      } else {
        throw Exception(res.errorMessage ?? 'Insufficient wallet balance');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _copyBankDetails() {
    final text = '''
VEKTOLUX ESCROW CLEARING ACCOUNT:
Bank: Sierra Leone Commercial Bank (SLCB)
Account Name: Vektolux Technologies (SL) Ltd — Escrow Clearing Account
Account Number: 003001014892010184
Swift Code: SLCBSLFR
Branch: Siaka Stevens Street Head Office, Freetown
Deal Reference: $_bankEscrowReference
Amount to Transfer: SLE ${NumberFormat('#,##0.00').format(_totalEscrowInflow)}
''';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Official SLCB Escrow account details and reference copied!'),
        backgroundColor: AppColors.emerald,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          widget.isPurchase ? 'Vehicle Purchase Escrow' : 'Vehicle Rental Escrow',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vehicle Header Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: widget.vehicleImageUrl != null && widget.vehicleImageUrl!.isNotEmpty
                        ? Image.network(
                            widget.vehicleImageUrl!,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildCarIcon(),
                          )
                        : _buildCarIcon(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.vehicleTitle,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.obsidian),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.vehicleCategory.toUpperCase(),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gray500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.isPurchase
                              ? 'SLE ${currencyFmt.format(widget.purchasePrice ?? _totalEscrowInflow)} (Outright)'
                              : 'SLE ${currencyFmt.format(widget.dailyRate)} / day',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.emeraldDark),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Rental Duration Selector (If Rental)
            if (!widget.isPurchase) ...[
              const Text('Rental Duration & Schedule', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Duration (Days):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _rentalDays > 1 ? () => setState(() => _rentalDays--) : null,
                              icon: const Icon(Icons.remove_circle_outline, color: AppColors.gray600),
                            ),
                            Text('$_rentalDays Days', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            IconButton(
                              onPressed: () => setState(() => _rentalDays++),
                              icon: const Icon(Icons.add_circle_outline, color: AppColors.emerald),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_rounded, color: AppColors.emerald),
                      title: const Text('Start Date', style: TextStyle(fontSize: 12, color: AppColors.gray500)),
                      subtitle: Text(DateFormat('EEEE, MMM d, yyyy').format(_startDate), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.gray400),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _startDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 90)),
                        );
                        if (picked != null) setState(() => _startDate = picked);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Financial Breakdown Card
            const Text('Financial Breakdown & Escrow Inflow', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  _buildCostRow(
                    widget.isPurchase ? 'Agreed Purchase Price' : 'Base Service Charge ($_rentalDays days)',
                    'SLE ${currencyFmt.format(widget.isPurchase ? _totalEscrowInflow : _baseRentalAmount)}',
                  ),
                  const SizedBox(height: 8),
                  _buildCostRow(
                    widget.isPurchase ? 'Earnest Inspection Deposit' : 'Refundable Damage Deposit',
                    'SLE ${currencyFmt.format(_refundableDeposit)}',
                    isHighlight: true,
                    subtitle: widget.isPurchase
                        ? '100% credited to purchase or refunded if failed'
                        : '100% refunded to you upon clean vehicle return',
                  ),
                  const Divider(height: 20),
                  _buildCostRow(
                    'Total Upfront Escrow Inflow',
                    'SLE ${currencyFmt.format(_totalEscrowInflow)}',
                    isBold: true,
                  ),
                  const SizedBox(height: 8),
                  _buildCostRow(
                    'Net Seller Proceeds',
                    'SLE ${currencyFmt.format(_netOwnerProceeds)}',
                    subtitle: 'Released directly to seller upon vehicle inspection approval',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Unified Multi-Rail Payment Method Header
            const Text('Select Escrow Payment Rail', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 10),

            // Rail Selector Cards
            Row(
              children: [
                _buildRailTab(
                  rail: EscrowPaymentRail.mobileMoney,
                  icon: Icons.phone_android_rounded,
                  title: 'Mobile Money',
                  subtitle: 'Auto-detected',
                ),
                const SizedBox(width: 8),
                _buildRailTab(
                  rail: EscrowPaymentRail.bankWire,
                  icon: Icons.account_balance_rounded,
                  title: 'Bank Wire',
                  subtitle: 'SLCB Official',
                ),
                const SizedBox(width: 8),
                _buildRailTab(
                  rail: EscrowPaymentRail.wallet,
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'My Wallet',
                  subtitle: 'Zero fee',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Rail Content Section
            if (_selectedRail == EscrowPaymentRail.mobileMoney) ...[
              // ── Universal Mobile Money Input ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UniversalPhoneInput(
                      controller: _phoneController,
                      label: 'Enter Mobile Money Phone Number',
                      hint: '076 123456 or 077 123456',
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.bolt_rounded, color: AppColors.emerald, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Direct Deal Escrow: No wallet pre-top-up needed. Authorize the prompt on your phone to lock funds instantly.',
                              style: TextStyle(fontSize: 11, color: AppColors.gray700, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              VxButton(
                label: 'Pay SLE ${currencyFmt.format(_totalEscrowInflow)} with Mobile Money',
                icon: Icons.lock_outline_rounded,
                isLoading: _isSubmitting,
                onPressed: _handleMobileMoneyCheckout,
              ),
            ] else if (_selectedRail == EscrowPaymentRail.bankWire) ...[
              // ── Commercial Bank Wire Clearing Card ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.obsidian,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sierra Leone Commercial Bank (SLCB)',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.obsidian),
                              ),
                              Text(
                                'Official High-Value Deal Clearing Rail',
                                style: TextStyle(fontSize: 11, color: AppColors.gray500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildBankDetailRow('Account Name', 'Vektolux Technologies (SL) Ltd — Escrow Clearing'),
                    _buildBankDetailRow('Account Number', '003001014892010184', isMono: true, isBold: true),
                    _buildBankDetailRow('Branch', 'Siaka Stevens Street Head Office, Freetown'),
                    _buildBankDetailRow('SWIFT / BIC', 'SLCBSLFR', isMono: true),
                    const Divider(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MANDATORY TRANSFER MEMO / REFERENCE:',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            _bankEscrowReference,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFB45309),
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Please put this exact reference in your bank wire memo for automated reconciliation.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF78350F)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _copyBankDetails,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy Official Bank Details & Deal Reference'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.obsidian,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              VxButton(
                label: 'Confirm Bank Wire Transfer Initiated',
                icon: Icons.check_circle_outline,
                isLoading: _isSubmitting,
                onPressed: _handleBankWireCheckout,
              ),
            ] else if (_selectedRail == EscrowPaymentRail.wallet) ...[
              // ── Vektolux Wallet Balance ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.account_balance_wallet_rounded, color: AppColors.emerald, size: 36),
                    const SizedBox(height: 10),
                    const Text(
                      'Lock from Vektolux Escrow Balance',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.obsidian),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'SLE ${currencyFmt.format(_totalEscrowInflow)} will be deducted instantly from your available funds with zero processing fees.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.gray600, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              VxButton(
                label: 'Lock SLE ${currencyFmt.format(_totalEscrowInflow)} from Wallet',
                icon: Icons.lock_outline_rounded,
                isLoading: _isSubmitting,
                onPressed: _handleWalletCheckout,
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildRailTab({
    required EscrowPaymentRail rail,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedRail == rail;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRail = rail),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.obsidian : AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.obsidian : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.white : AppColors.gray600,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: isSelected ? AppColors.white : AppColors.obsidian,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? Colors.white70 : AppColors.gray500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBankDetailRow(String label, String value, {bool isMono = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.gray500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                fontFamily: isMono ? 'monospace' : null,
                color: AppColors.obsidian,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarIcon() {
    return Container(
      width: 70,
      height: 70,
      color: AppColors.gray100,
      child: const Icon(Icons.directions_car_rounded, size: 36, color: AppColors.gray400),
    );
  }

  Widget _buildCostRow(String title, String amount, {bool isHighlight = false, bool isBold = false, String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: isBold ? 13 : 12,
                fontWeight: isBold ? FontWeight.w800 : (isHighlight ? FontWeight.w700 : FontWeight.w500),
                color: isHighlight ? AppColors.emeraldDark : AppColors.obsidian,
              ),
            ),
            Text(
              amount,
              style: TextStyle(
                fontSize: isBold ? 14 : 13,
                fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
                color: isHighlight ? AppColors.emeraldDark : AppColors.obsidian,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.gray500)),
        ],
      ],
    );
  }
}
