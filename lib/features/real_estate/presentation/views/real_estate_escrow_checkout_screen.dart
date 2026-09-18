// lib/features/real_estate/presentation/views/real_estate_escrow_checkout_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Multi-Tier Real Estate Escrow Checkout Screen
// Supports:
// 1. Short-Stay Bookings (Nightly rate + Caution deposit with 24h release rule)
// 2. Long-Term Lease (Base rent + 10% statutory agency fee + Locked caution deposit)
// 3. Land / House Outright Purchase (10/40/50 Gated Milestone Escrow)
// Currency: SLE (Sierra Leone New Leones) via Orange Money & Afrimoney
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../../core/services/payment_methods_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/property_listing_entity.dart';
import 'real_estate_escrow_tracking_screen.dart';

enum RealEstateEscrowType {
  shortStay,
  longTermLease,
  landPurchase,
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
  final DateTime _checkInDate = DateTime.now().add(const Duration(days: 1));

  // Long-Term Lease parameters
  int _leaseMonths = 12;

  // Land / House Purchase parameters
  late double _agreedPurchasePrice;

  // Payment rail
  String _selectedProvider = 'moneroo_auto'; // Default to automated Moneroo
  final _phoneController = TextEditingController();
  final _txnRefController = TextEditingController();
  bool _isSubmitting = false;
  bool _isClaimSubmitted = false;
  bool _isEscrowLocked = false;
  bool _isAwaitingWebhook = false;
  String? _monerooPaymentId;
  String? _createdContractId;
  Timer? _webhookPollingTimer;

  // Dynamic payment methods from admin config
  List<PaymentMethod> _paymentMethods = [];
  bool _isLoadingMethods = true;
  PaymentMethod? _selectedPaymentMethod;

  @override
  void initState() {
    super.initState();
    _contractType = widget.initialType;
    _agreedPurchasePrice = widget.listing.price;

    final user = context.read<AuthBloc>().state.user;
    if (user != null && user.phone.isNotEmpty) {
      _phoneController.text = user.phone;
    }
    _loadPaymentMethods();
  }

  Future<void> _loadPaymentMethods() async {
    try {
      final methods = await PaymentMethodsService.instance.getActivePaymentMethods();
      if (mounted) {
        setState(() {
          _paymentMethods = methods;
          _isLoadingMethods = false;
          if (methods.isNotEmpty) {
            _selectedPaymentMethod = methods.first;
            _selectedProvider = methods.first.providerId;
          }
        });
      }
    } catch (e) {
      debugPrint('[RealEstateCheckout] Error loading payment methods: $e');
      if (mounted) setState(() => _isLoadingMethods = false);
    }
  }

  @override
  void dispose() {
    _webhookPollingTimer?.cancel();
    _phoneController.dispose();
    _txnRefController.dispose();
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
        // Refundable Caution / Kitchen Deposit (25% or min 300)
        return (_baseAmount * 0.25).clamp(300.0, 5000.0);
      case RealEstateEscrowType.longTermLease:
        // 1 month rent caution deposit
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
        // 10% statutory agency fee
        return _baseAmount * 0.10;
      case RealEstateEscrowType.landPurchase:
        // 5% conveyancing / agent facilitation
        return _baseAmount * 0.05;
    }
  }

  double get _totalEscrowInflow => _baseAmount + _cautionDeposit + _agencyCommission;

  String get _convexContractType {
    switch (_contractType) {
      case RealEstateEscrowType.shortStay:
        return 'SHORT_STAY';
      case RealEstateEscrowType.longTermLease:
        return 'LONG_TERM_LEASE';
      case RealEstateEscrowType.landPurchase:
        return 'LAND_PURCHASE';
    }
  }

  Future<void> _handleInitiateEscrow() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to initiate an escrow contract.')),
      );
      return;
    }

    if (_selectedProvider != 'WALLET' && _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your mobile money phone number.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final client = context.read<ConvexClientWrapper>();

      final res = await client.mutation(
        'realEstateEscrow:initiateRealEstateEscrow',
        args: {
          'propertyListingId': widget.listing.id,
          'buyerOrTenantId': user.id,
          'contractType': _convexContractType,
          'agreedPriceOrRent': _baseAmount,
          'cautionDeposit': _cautionDeposit,
          'statutoryAgencyFee': _agencyCommission,
          if (_contractType == RealEstateEscrowType.shortStay)
            'startDate': _checkInDate.millisecondsSinceEpoch,
          if (_contractType == RealEstateEscrowType.shortStay)
            'endDate': _checkInDate.add(Duration(days: _stayNights)).millisecondsSinceEpoch,
          'paymentRail': _selectedProvider,
          'paymentPhone': _phoneController.text.trim(),
        },
      );

      if (res.success && res.value != null) {
        final contract = Map<String, dynamic>.from(res.value as Map);
        final contractId = contract['contractId'] as String;

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => RealEstateEscrowTrackingScreen(
                contractId: contractId,
              ),
            ),
          );
        }
      } else {
        setState(() => _isSubmitting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.errorMessage ?? 'Escrow initiation failed'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initiating escrow: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleManualPaymentClaim() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to submit a payment claim.')),
      );
      return;
    }

    final txnRef = _txnRefController.text.trim();
    if (txnRef.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste your Transaction ID / SMS Reference.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final result = await PaymentMethodsService.instance.submitManualPaymentClaim(
        userId: user.id,
        amount: _totalEscrowInflow,
        providerId: _selectedProvider,
        transactionReference: txnRef,
      );

      if (result['success'] == true) {
        if (mounted) {
          setState(() => _isClaimSubmitted = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment claim submitted successfully! Awaiting admin verification.'),
              backgroundColor: AppColors.emerald,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to submit claim: ${result['error'] ?? 'Unknown error'}'),
              backgroundColor: AppColors.error,
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

  Future<void> _handleInitiateMoneroo() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to initiate payment.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final client = context.read<ConvexClientWrapper>();

      // 1. Create RE escrow contract in Convex
      final res = await client.mutation(
        'realEstateEscrow:initiateRealEstateEscrow',
        args: {
          'propertyListingId': widget.listing.id,
          'buyerOrTenantId': user.id,
          'contractType': _convexContractType,
          'agreedPriceOrRent': _baseAmount,
          'cautionDeposit': _cautionDeposit,
          'statutoryAgencyFee': _agencyCommission,
          if (_contractType == RealEstateEscrowType.shortStay)
            'startDate': _checkInDate.millisecondsSinceEpoch,
          if (_contractType == RealEstateEscrowType.shortStay)
            'endDate': _checkInDate.add(Duration(days: _stayNights)).millisecondsSinceEpoch,
          'paymentRail': 'MONEROO_SANDBOX',
          'paymentPhone': _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : user.phone,
        },
      );

      String contractId = '';
      if (res.success && res.value != null) {
        final contract = Map<String, dynamic>.from(res.value as Map);
        contractId = contract['contractId']?.toString() ?? '';
        _createdContractId = contractId;
      }

      // 2. Initialize Moneroo payment session
      final nameParts = user.name.trim().split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : 'Customer';
      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : 'User';

      final initRes = await PaymentMethodsService.instance.initializeMonerooPayment(
        amount: _totalEscrowInflow,
        currency: 'SLE',
        customerEmail: user.email.isNotEmpty ? user.email : 'customer@vektolux.com',
        customerFirstName: firstName,
        customerLastName: lastName,
        customerPhone: user.phone.isNotEmpty ? user.phone : _phoneController.text.trim(),
        userId: user.id,
        reContractId: contractId.isNotEmpty ? contractId : null,
        description: 'Vektolux Property Escrow: ${widget.listing.title}',
      );

      if (initRes['success'] != true) {
        throw Exception(initRes['error'] ?? 'Failed to initialize Moneroo payment');
      }

      final checkoutUrl = initRes['checkoutUrl'] as String;
      final paymentId = initRes['paymentId'] as String;

      setState(() {
        _monerooPaymentId = paymentId;
        _isAwaitingWebhook = true;
        _isSubmitting = false;
      });

      // 3. Open in-app browser
      if (checkoutUrl.isNotEmpty) {
        final uri = Uri.parse(checkoutUrl);
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }

      // 4. Start polling for webhook
      _startPollingWebhook(paymentId, contractId);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _startPollingWebhook(String paymentId, String contractId) {
    _webhookPollingTimer?.cancel();
    _webhookPollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final statusData = await PaymentMethodsService.instance.getPaymentClaimStatus(paymentId);
      if (statusData != null && statusData['status'] == 'ESCROW_LOCKED') {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isAwaitingWebhook = false;
            _isEscrowLocked = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment Confirmed — Funds Held in Escrow!'),
              backgroundColor: AppColors.emerald,
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Escrow Agreement Checkout',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: AppColors.obsidian,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Property Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.emeraldSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.home_work_rounded, color: AppColors.emeraldDark, size: 32),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.listing.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.listing.address.isNotEmpty
                              ? '${widget.listing.address}, ${widget.listing.city}'
                              : widget.listing.city,
                          style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'SLE ${_currencyFormat.format(widget.listing.price)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.emeraldDark),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Contract Type Selector
            const Text(
              'TRANSACTION CONTRACT TIER',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gray500, letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _buildTypeTab('Short Stay', RealEstateEscrowType.shortStay),
                  _buildTypeTab('Long Lease', RealEstateEscrowType.longTermLease),
                  _buildTypeTab('Land / Buy', RealEstateEscrowType.landPurchase),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Mode-specific configuration
            if (_contractType == RealEstateEscrowType.shortStay) _buildShortStayControls(),
            if (_contractType == RealEstateEscrowType.longTermLease) _buildLongLeaseControls(),
            if (_contractType == RealEstateEscrowType.landPurchase) _buildLandPurchaseControls(),
            const SizedBox(height: 20),

            // Financial Summary Breakdown Card
            _buildFinancialBreakdownCard(),
            const SizedBox(height: 20),

            // Payment Rail Selector
            const Text(
              'FUNDING SOURCE (DYNAMIC PAYMENT & ESCROW)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gray500, letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),

            if (_isEscrowLocked) ...[
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.verified_rounded, color: AppColors.emerald, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Payment Confirmed — Held in Escrow',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.emeraldDark),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'SLE ${_currencyFormat.format(_totalEscrowInflow)} is now securely locked in Vektolux Real Estate Escrow.\nMilestone disbursement is activated.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.gray700, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    VxButton.primary(
                      text: 'Track Escrow Milestones',
                      icon: Icons.shield_rounded,
                      onPressed: () {
                        if (_createdContractId != null && _createdContractId!.isNotEmpty) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => RealEstateEscrowTrackingScreen(contractId: _createdContractId!),
                            ),
                          );
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ] else if (_isAwaitingWebhook) ...[
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF93C5FD), width: 1.5),
                ),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF2563EB)),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Awaiting Moneroo Payment Confirmation',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF1E40AF)),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Please complete the transaction in your checkout window.\nThis screen will automatically update to Held in Escrow once confirmed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF3B82F6), height: 1.4),
                    ),
                    if (_monerooPaymentId != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Reference: $_monerooPaymentId',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => setState(() => _isAwaitingWebhook = false),
                      icon: const Icon(Icons.arrow_back, size: 16, color: Color(0xFF1E40AF)),
                      label: const Text('Change Payment Method', style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ] else if (_isClaimSubmitted) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEFCE8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Payment Submitted',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF92400E)),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Your escrow payment claim is pending admin verification.\nYou will be notified once confirmed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                    ),
                    const SizedBox(height: 16),
                    VxButton.primary(
                      text: 'Back to Property Listings',
                      icon: Icons.arrow_back_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ] else ...[
              if (_isLoadingMethods)
                const Center(child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: AppColors.emerald),
                ))
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ..._paymentMethods.map((m) {
                        final isSelected = _selectedProvider == m.providerId;
                        IconData iconData = Icons.phone_android_rounded;
                        if (m.isAutomated) iconData = Icons.credit_card_rounded;
                        if (m.isBankTransfer) iconData = Icons.account_balance_rounded;
                        if (m.providerId.contains('qmoney')) iconData = Icons.cell_tower_rounded;
                        if (m.providerId.contains('afrimoney')) iconData = Icons.sim_card_outlined;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () => setState(() {
                              _selectedProvider = m.providerId;
                              _selectedPaymentMethod = m;
                            }),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.obsidian : AppColors.gray100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(iconData, size: 18, color: isSelected ? AppColors.emerald : AppColors.gray600),
                                  const SizedBox(width: 6),
                                  Text(
                                    m.displayName.split('(').first.trim(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? Colors.white : AppColors.gray700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      // Wallet chip
                      InkWell(
                        onTap: () => setState(() {
                          _selectedProvider = 'WALLET';
                          _selectedPaymentMethod = null;
                        }),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedProvider == 'WALLET' ? AppColors.obsidian : AppColors.gray100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.account_balance_wallet_outlined,
                                  size: 18, color: _selectedProvider == 'WALLET' ? AppColors.emerald : AppColors.gray600),
                              const SizedBox(width: 6),
                              Text(
                                'Wallet',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedProvider == 'WALLET' ? Colors.white : AppColors.gray700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Manual provider instructions + transaction ref field
              if (_selectedPaymentMethod != null && _selectedPaymentMethod!.isManual) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF7DD3FC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFF0284C7), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${_selectedPaymentMethod!.displayName} Instructions',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0C4A6E)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedPaymentMethod!.instructions ??
                            'Follow your provider\'s payment instructions and enter the Transaction ID below.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF0369A1), height: 1.5),
                      ),
                      if (_selectedPaymentMethod!.accountNumber != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBAE6FD)),
                          ),
                          child: Row(
                            children: [
                              const Text('Merchant/Account: ', style: TextStyle(fontSize: 12, color: AppColors.gray600)),
                              Text(
                                _selectedPaymentMethod!.accountNumber!,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.obsidian),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _txnRefController,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    labelText: 'Paste Transaction ID / SMS Reference',
                    hintText: 'e.g. TXN123456789',
                    prefixIcon: const Icon(Icons.receipt_long_rounded, color: AppColors.gray500),
                    filled: true,
                    fillColor: AppColors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                ),
              ],

              // Phone number field for non-wallet, non-manual providers
              if (_selectedProvider != 'WALLET' && (_selectedPaymentMethod == null || _selectedPaymentMethod!.isAutomated)) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Mobile Money Phone Number',
                    hintText: 'e.g. 076 000000 or 077 000000',
                    prefixIcon: const Icon(Icons.call_outlined, color: AppColors.gray500),
                    filled: true,
                    fillColor: AppColors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Submit Button
              VxButton.primary(
                text: _isSubmitting
                    ? 'Processing...'
                    : _selectedPaymentMethod != null && _selectedPaymentMethod!.isManual
                        ? 'Submit Payment Claim'
                        : (_selectedPaymentMethod != null && _selectedPaymentMethod!.isAutomated) || _selectedProvider == 'moneroo_auto'
                            ? 'Pay with Moneroo (SLE ${_currencyFormat.format(_totalEscrowInflow)})'
                            : 'Lock SLE ${_currencyFormat.format(_totalEscrowInflow)} in Escrow',
                icon: _selectedPaymentMethod != null && _selectedPaymentMethod!.isManual
                    ? Icons.send_rounded
                    : (_selectedPaymentMethod != null && _selectedPaymentMethod!.isAutomated) || _selectedProvider == 'moneroo_auto'
                        ? Icons.open_in_browser_rounded
                        : Icons.shield_rounded,
                onPressed: _isSubmitting
                    ? null
                    : _selectedPaymentMethod != null && _selectedPaymentMethod!.isManual
                        ? _handleManualPaymentClaim
                        : (_selectedPaymentMethod != null && _selectedPaymentMethod!.isAutomated) || _selectedProvider == 'moneroo_auto'
                            ? _handleInitiateMoneroo
                            : _handleInitiateEscrow,
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Funds are protected in segregated Bank of Sierra Leone compliant escrow.',
                  style: TextStyle(fontSize: 11, color: AppColors.gray500),
                ),
              ),
            ],
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
              border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
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
                  DropdownMenuItem(value: 12, child: Text('1 Year (12 Mos)')),
                  DropdownMenuItem(value: 24, child: Text('2 Years (24 Mos)')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _leaseMonths = v);
                },
              ),
            ],
          ),
          const Divider(),
          const Text(
            'Statutory agency fee (10%) is split 85% to certified agent and 15% platform fee. Caution deposit remains locked for entire lease.',
            style: TextStyle(fontSize: 11, color: AppColors.gray600),
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
          const Text('10/40/50 GATED MILESTONE STRUCTURE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.emeraldDark)),
          const SizedBox(height: 10),
          _buildMilestoneRow('1', '10% OARG Search', 'Title clearance at Registrar General'),
          _buildMilestoneRow('2', '40% Survey & Bounds', 'Cadastral survey & Ministry verification'),
          _buildMilestoneRow('3', '50% Conveyance Deed', 'Final deed sign-off & property handoff'),
        ],
      ),
    );
  }

  Widget _buildMilestoneRow(String num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: AppColors.obsidian,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
                Text(desc, style: const TextStyle(fontSize: 10, color: AppColors.gray500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialBreakdownCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildFinanceRow('Base Rent / Purchase', 'SLE ${_currencyFormat.format(_baseAmount)}'),
          if (_cautionDeposit > 0)
            _buildFinanceRow('Refundable Caution Deposit', 'SLE ${_currencyFormat.format(_cautionDeposit)}', highlightEmerald: true),
          if (_agencyCommission > 0)
            _buildFinanceRow('Statutory Commission (10%)', 'SLE ${_currencyFormat.format(_agencyCommission)}'),
          const Divider(color: Colors.white24, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Escrow Deposit',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
              ),
              Text(
                'SLE ${_currencyFormat.format(_totalEscrowInflow)}',
                style: const TextStyle(color: AppColors.emeraldLight, fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceRow(String label, String value, {bool highlightEmerald = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: highlightEmerald ? AppColors.emeraldLight : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

