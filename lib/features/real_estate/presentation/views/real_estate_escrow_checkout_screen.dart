// lib/features/real_estate/presentation/views/real_estate_escrow_checkout_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Multi-Tier Real Estate Escrow Checkout Screen
// Unified Multi-Rail Escrow:
// 1. Mobile Money (Orange Money, Africell Afrimoney, QMoney) via Universal Phone Input
// 2. High-Value Commercial Bank Wire (Sierra Leone Commercial Bank clearing account)
// 3. Vektolux Escrow Wallet Balance
// Operating Standard: Sierra Leone New Leones (SLE)
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../../core/services/carrier_detection_service.dart';
import '../../../../core/widgets/universal_phone_input.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/profile/presentation/views/widgets/ussd_payment_sheet.dart';
import '../../domain/entities/property_listing_entity.dart';
import 'real_estate_escrow_tracking_screen.dart';

enum RealEstateEscrowType {
  shortStay,
  longTermLease,
  landPurchase,
}

enum EscrowPaymentRail {
  mobileMoney,
  bankWire,
  wallet,
}

class RealEstateEscrowCheckoutScreen extends StatefulWidget {
  final PropertyListingEntity listing;
  final RealEstateEscrowType initialType;

  const RealEstateEscrowCheckoutScreen({
    super.key,
    required this.listing,
    this.initialType = RealEstateEscrowType.shortStay,
  });

  @override
  State<RealEstateEscrowCheckoutScreen> createState() =>
      _RealEstateEscrowCheckoutScreenState();
}

class _RealEstateEscrowCheckoutScreenState
    extends State<RealEstateEscrowCheckoutScreen> {
  late RealEstateEscrowType _contractType;
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  // Short-Stay parameters
  int _stayNights = 2;

  // Long-Term Lease parameters
  int _leaseMonths = 12;

  // Land / House Purchase parameters
  late double _agreedPurchasePrice;

  // Payment rails
  EscrowPaymentRail _selectedRail = EscrowPaymentRail.mobileMoney;

  final _phoneController = TextEditingController();
  late final String _bankEscrowReference;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _contractType = widget.initialType;
    _agreedPurchasePrice = widget.listing.price;

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
    super.dispose();
  }

  // ─── Financial Calculations ─────────────────────────────────────────

  double get _baseAmount {
    switch (_contractType) {
      case RealEstateEscrowType.shortStay:
        return widget.listing.price * _stayNights;
      case RealEstateEscrowType.longTermLease:
        return (widget.listing.price / 12) * _leaseMonths;
      case RealEstateEscrowType.landPurchase:
        return _agreedPurchasePrice;
    }
  }

  double get _cautionDeposit {
    switch (_contractType) {
      case RealEstateEscrowType.shortStay:
        return (_baseAmount * 0.25).clamp(300.0, 5000.0);
      case RealEstateEscrowType.longTermLease:
        return (widget.listing.price / 12).clamp(500.0, 50000.0);
      case RealEstateEscrowType.landPurchase:
        return 0.0;
    }
  }

  double get _agencyCommission {
    switch (_contractType) {
      case RealEstateEscrowType.shortStay:
        return 0.0;
      case RealEstateEscrowType.longTermLease:
        return _baseAmount * 0.10;
      case RealEstateEscrowType.landPurchase:
        return _baseAmount * 0.05;
    }
  }

  double get _totalEscrowInflow => _baseAmount + _cautionDeposit + _agencyCommission;

  String get _convexContractType {
    switch (_contractType) {
      case RealEstateEscrowType.shortStay:
        return 'SHORT_STAY_BOOKING';
      case RealEstateEscrowType.longTermLease:
        return 'LONG_TERM_LEASE';
      case RealEstateEscrowType.landPurchase:
        return 'LAND_PURCHASE_MILESTONE';
    }
  }

  // ─── 1. Mobile Money Direct Escrow ──────────────────────────────────
  Future<void> _handleMobileMoneyCheckout() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to initiate an escrow contract.')),
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

      final res = await client.mutation(
        'realEstateEscrow:initiateRealEstateEscrow',
        args: {
          'contractType': _convexContractType,
          'propertyListingId': widget.listing.id,
          'clientId': user.id,
          'baseAmount': _baseAmount,
          'cautionDepositAmount': _cautionDeposit,
          'nightsCount': _contractType == RealEstateEscrowType.shortStay ? _stayNights : null,
          'leaseDurationMonths': _contractType == RealEstateEscrowType.longTermLease ? _leaseMonths : null,
          'paymentRail': 'MOBILE_MONEY',
          'paymentPhone': normalizedPhone,
        },
      );

      if (res.success && res.value != null) {
        final contract = Map<String, dynamic>.from(res.value as Map);
        final contractId = contract['contractId'] as String;

        // Dispatch directly to Monime API
        final monimeRes = await client.action(
          'payments:initiateMoniMePayment',
          args: {
            'amount': _totalEscrowInflow,
            'phoneNumber': normalizedPhone,
            'provider': carrier.providerSlug,
            'reContractId': contractId,
            'userId': user.id,
            'customerPhone': normalizedPhone,
            'customerName': user.name,
            'customerEmail': user.email,
            'description': 'Real Estate Escrow: ${widget.listing.title}',
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
                transactionType: 'Real Estate Escrow Deposit',
              );
            }
          }

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => RealEstateEscrowTrackingScreen(contractId: contractId),
              ),
            );
          }
        }
      } else {
        throw Exception(res.errorMessage ?? 'Escrow initiation failed');
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

      final res = await client.mutation(
        'realEstateEscrow:initiateRealEstateEscrow',
        args: {
          'contractType': _convexContractType,
          'propertyListingId': widget.listing.id,
          'clientId': user.id,
          'baseAmount': _baseAmount,
          'cautionDepositAmount': _cautionDeposit,
          'nightsCount': _contractType == RealEstateEscrowType.shortStay ? _stayNights : null,
          'leaseDurationMonths': _contractType == RealEstateEscrowType.longTermLease ? _leaseMonths : null,
          'paymentRail': 'BANK_TRANSFER',
          'bankEscrowReference': _bankEscrowReference,
        },
      );

      if (res.success && res.value != null) {
        final contract = Map<String, dynamic>.from(res.value as Map);
        final contractId = contract['contractId'] as String;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ Bank Wire Registered! Reference: $_bankEscrowReference'),
              backgroundColor: AppColors.emerald,
            ),
          );

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => RealEstateEscrowTrackingScreen(contractId: contractId),
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

      final res = await client.mutation(
        'realEstateEscrow:initiateRealEstateEscrow',
        args: {
          'contractType': _convexContractType,
          'propertyListingId': widget.listing.id,
          'clientId': user.id,
          'baseAmount': _baseAmount,
          'cautionDepositAmount': _cautionDeposit,
          'nightsCount': _contractType == RealEstateEscrowType.shortStay ? _stayNights : null,
          'leaseDurationMonths': _contractType == RealEstateEscrowType.longTermLease ? _leaseMonths : null,
          'paymentRail': 'WALLET',
        },
      );

      if (res.success && res.value != null) {
        final contract = Map<String, dynamic>.from(res.value as Map);
        final contractId = contract['contractId'] as String;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ SLE locked instantly from Wallet Balance!'),
              backgroundColor: AppColors.emerald,
            ),
          );

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => RealEstateEscrowTrackingScreen(contractId: contractId),
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
Amount to Transfer: SLE ${_currencyFormat.format(_totalEscrowInflow)}
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Real Estate Escrow Agreement',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Property Header Card
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
                    child: widget.listing.imageUrls.isNotEmpty
                        ? Image.network(
                            widget.listing.imageUrls.first,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPropPlaceholder(),
                          )
                        : _buildPropPlaceholder(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.listing.title,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.obsidian),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.listing.address,
                          style: const TextStyle(fontSize: 11, color: AppColors.gray500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'SLE ${_currencyFormat.format(widget.listing.price)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.emeraldDark),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Escrow Type Selector
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildTypeTab('Short Stay', RealEstateEscrowType.shortStay),
                  _buildTypeTab('Long Lease', RealEstateEscrowType.longTermLease),
                  _buildTypeTab('Land Purchase', RealEstateEscrowType.landPurchase),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Context-specific controls
            if (_contractType == RealEstateEscrowType.shortStay) _buildShortStayControls(),
            if (_contractType == RealEstateEscrowType.longTermLease) _buildLongLeaseControls(),
            if (_contractType == RealEstateEscrowType.landPurchase) _buildLandPurchaseControls(),
            const SizedBox(height: 20),

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
                  _buildCostRow('Base Transaction Amount', 'SLE ${_currencyFormat.format(_baseAmount)}'),
                  if (_cautionDeposit > 0) ...[
                    const SizedBox(height: 8),
                    _buildCostRow(
                      'Segregated Caution Vault Deposit',
                      'SLE ${_currencyFormat.format(_cautionDeposit)}',
                      isHighlight: true,
                      subtitle: 'Held safely in platform escrow. 100% refunded upon clean inspection.',
                    ),
                  ],
                  if (_agencyCommission > 0) ...[
                    const SizedBox(height: 8),
                    _buildCostRow(
                      'Agency Facilitation / Legal Fee',
                      'SLE ${_currencyFormat.format(_agencyCommission)}',
                    ),
                  ],
                  const Divider(height: 20),
                  _buildCostRow(
                    'Total Upfront Escrow Inflow',
                    'SLE ${_currencyFormat.format(_totalEscrowInflow)}',
                    isBold: true,
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
                label: 'Pay SLE ${_currencyFormat.format(_totalEscrowInflow)} with Mobile Money',
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
                      'SLE ${_currencyFormat.format(_totalEscrowInflow)} will be deducted instantly from your available funds with zero processing fees.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.gray600, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              VxButton(
                label: 'Lock SLE ${_currencyFormat.format(_totalEscrowInflow)} from Wallet',
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

  Widget _buildTypeTab(String label, RealEstateEscrowType type) {
    final isSelected = _contractType == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _contractType = type),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.obsidian : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppColors.gray600,
            ),
          ),
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

  Widget _buildShortStayControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Number of Nights', style: TextStyle(fontWeight: FontWeight.w700)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: AppColors.emeraldDark),
                    onPressed: _stayNights > 1 ? () => setState(() => _stayNights--) : null,
                  ),
                  Text('$_stayNights Nights', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: AppColors.emeraldDark),
                    onPressed: () => setState(() => _stayNights++),
                  ),
                ],
              ),
            ],
          ),
          const Divider(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.hourglass_top_rounded, color: AppColors.emerald, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '24-Hour Check-In Rule: Rent is released to host 24 hours after check-in. Caution deposit is returned upon check-out inspection.',
                    style: TextStyle(fontSize: 11, color: AppColors.emeraldDark, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLongLeaseControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Lease Duration', style: TextStyle(fontWeight: FontWeight.w700)),
              DropdownButton<int>(
                value: _leaseMonths,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 6, child: Text('6 Months')),
                  DropdownMenuItem(value: 12, child: Text('1 Year (12 Months)')),
                  DropdownMenuItem(value: 24, child: Text('2 Years (24 Months)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _leaseMonths = val);
                },
              ),
            ],
          ),
          const Divider(),
          const Text(
            '10% Statutory Agency Fee included per Sierra Leone Real Estate regulations.',
            style: TextStyle(fontSize: 11, color: AppColors.gray500),
          ),
        ],
      ),
    );
  }

  Widget _buildLandPurchaseControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '10/40/50 Gated Milestone Schedule:',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _buildMilestoneRow('1. Root Title Search (Ministry of Lands)', '10%'),
          _buildMilestoneRow('2. Cadastral Survey & Pillar Confirmation', '40%'),
          _buildMilestoneRow('3. Deed Registration & Handover', '50%'),
        ],
      ),
    );
  }

  Widget _buildMilestoneRow(String title, String percentage) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12, color: AppColors.gray700))),
          Text(percentage, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.emeraldDark)),
        ],
      ),
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

  Widget _buildPropPlaceholder() {
    return Container(
      width: 70,
      height: 70,
      color: AppColors.gray100,
      child: const Icon(Icons.apartment_rounded, size: 36, color: AppColors.gray400),
    );
  }
}
