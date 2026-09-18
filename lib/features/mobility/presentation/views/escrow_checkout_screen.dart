// lib/features/mobility/presentation/views/escrow_checkout_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vehicle Escrow Checkout & Milestone Agreement Screen
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../../core/services/payment_methods_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import 'escrow_tracking_screen.dart';

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
  String _selectedProvider = 'moneroo_auto'; // Default to automated Moneroo
  final _phoneController = TextEditingController();
  final _txnRefController = TextEditingController();
  bool _isSubmitting = false;
  bool _isClaimSubmitted = false;
  bool _isEscrowLocked = false;
  bool _isAwaitingWebhook = false;
  String? _monerooPaymentId;
  String? _createdOrderId;
  Timer? _webhookPollingTimer;

  // Dynamic payment methods from admin config
  List<PaymentMethod> _paymentMethods = [];
  bool _isLoadingMethods = true;
  PaymentMethod? _selectedPaymentMethod;

  @override
  void initState() {
    super.initState();
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
      debugPrint('[EscrowCheckout] Error loading payment methods: $e');
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
  double get _payout60 => _netOwnerProceeds * 0.60;
  double get _payout40 => _netOwnerProceeds * 0.40;

  Future<void> _handleInitiateEscrow() async {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to initiate escrow agreement.')),
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
          'paymentProvider': _selectedProvider,
          'paymentPhone': _phoneController.text.trim(),
          'payFromWallet': _selectedProvider == 'WALLET',
        },
      );

      if (res.success && res.value != null) {
        final data = res.value as Map<String, dynamic>;
        final orderId = data['escrowOrderId']?.toString() ?? '';

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EscrowTrackingScreen(escrowOrderId: orderId),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to initialize escrow: ${res.errorMessage ?? "Unknown error"}'),
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
      // 1. Create/initiate the escrow order record in Convex
      final client = context.read<ConvexClientWrapper>();
      final endDate = _startDate.add(Duration(days: _rentalDays));

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
          'paymentProvider': 'MONEROO_SANDBOX',
          'paymentPhone': _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : user.phone,
          'payFromWallet': false,
        },
      );

      String orderId = '';
      if (orderRes.success && orderRes.value is Map) {
        orderId = (orderRes.value as Map)['escrowOrderId']?.toString() ?? '';
        _createdOrderId = orderId;
      }

      // 2. Call initializeMonerooPayment action
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
        escrowOrderId: orderId.isNotEmpty ? orderId : null,
        description: 'Vektolux Escrow: ${widget.vehicleTitle}',
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

      // 3. Launch checkout URL in-app
      if (checkoutUrl.isNotEmpty) {
        final uri = Uri.parse(checkoutUrl);
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }

      // 4. Start polling for webhook confirmation
      _startPollingWebhook(paymentId, orderId);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _startPollingWebhook(String paymentId, String orderId) {
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
                          'SLE ${currencyFmt.format(widget.dailyRate)} / day',
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

            // Financial Breakdown Card (Upfront Escrow Inflow)
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
                  _buildCostRow('Base Service Charge ($_rentalDays days)', 'SLE ${currencyFmt.format(_baseRentalAmount)}'),
                  const SizedBox(height: 8),
                  _buildCostRow(
                    widget.isPurchase ? 'Earnest Inspection Deposit' : 'Refundable Damage Deposit',
                    'SLE ${currencyFmt.format(_refundableDeposit)}',
                    isHighlight: true,
                    subtitle: widget.isPurchase ? '100% credited to purchase or refunded if failed' : '100% refunded to you upon clean return',
                  ),
                  const Divider(height: 20),
                  _buildCostRow(
                    'Total Upfront Locked in Escrow',
                    'SLE ${currencyFmt.format(_totalEscrowInflow)}',
                    isTotal: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Transparent 60/40 Split Milestone Schedule
            const Text('Automated Milestone Release Schedule', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_rounded, color: AppColors.emeraldDark, size: 20),
                      SizedBox(width: 8),
                      Text('60/40 Escrow Protection Rules', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.emeraldDark)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildMilestoneRow(
                    'Milestone 1: Vehicle Handoff (60%)',
                    'SLE ${currencyFmt.format(_payout60)} disbursed to Owner',
                    'Disbursed immediately upon pre-trip digital inspection sign-off & QR scan.',
                  ),
                  const SizedBox(height: 10),
                  _buildMilestoneRow(
                    'Milestone 2: Vehicle Return (40% + Deposit)',
                    'SLE ${currencyFmt.format(_payout40)} to Owner | SLE ${currencyFmt.format(_refundableDeposit)} to Renter',
                    'Disbursed upon vehicle return. 100% of damage deposit is automatically refunded to you.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Dynamic Payment Method Selector
            const Text('Select Payment Method', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 10),

            if (_isEscrowLocked) ...[
              // ── Payment Confirmed & Escrow Locked State ──
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
                      'SLE ${currencyFmt.format(_totalEscrowInflow)} is now securely locked in Vektolux Escrow.\nFunds are protected until inspection and milestone completion.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.gray700, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    VxButton(
                      label: 'Track Escrow Status',
                      icon: Icons.shield_rounded,
                      onPressed: () {
                        if (_createdOrderId != null && _createdOrderId!.isNotEmpty) {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => EscrowTrackingScreen(escrowOrderId: _createdOrderId!),
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
              // ── Awaiting Moneroo Webhook State ──
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
              // ── Manual Payment Claim Submitted State ──
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
                      'Your payment claim is pending admin verification.\nYou will be notified once approved.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                    ),
                    const SizedBox(height: 16),
                    VxButton(
                      label: 'Back to Listings',
                      icon: Icons.arrow_back_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ] else ...[
              if (_isLoadingMethods)
                const Center(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: AppColors.emerald),
                ))
              else
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      // Dynamic methods from admin config
                      ..._paymentMethods.asMap().entries.map((entry) {
                        final method = entry.value;
                        final isLast = entry.key == _paymentMethods.length - 1;
                        return Column(
                          children: [
                            RadioListTile<String>(
                              value: method.providerId,
                              groupValue: _selectedProvider,
                              onChanged: (val) => setState(() {
                                _selectedProvider = val!;
                                _selectedPaymentMethod = method;
                              }),
                              activeColor: AppColors.emerald,
                              title: Text(
                                method.displayName,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              subtitle: Text(
                                method.type == 'AGGREGATOR_AUTO'
                                    ? 'Secure automated payment'
                                    : method.type == 'BANK_TRANSFER'
                                        ? 'Bank wire transfer'
                                        : 'Mobile money merchant payment',
                                style: const TextStyle(fontSize: 11, color: AppColors.gray500),
                              ),
                              secondary: Icon(
                                method.type == 'AGGREGATOR_AUTO'
                                    ? Icons.credit_card_rounded
                                    : method.type == 'BANK_TRANSFER'
                                        ? Icons.account_balance_rounded
                                        : Icons.phone_android_rounded,
                                color: method.type == 'AGGREGATOR_AUTO'
                                    ? Colors.deepOrange
                                    : method.type == 'BANK_TRANSFER'
                                        ? AppColors.obsidian
                                        : Colors.blueAccent,
                              ),
                            ),
                            if (!isLast) const Divider(height: 1),
                          ],
                        );
                      }),
                      // Always show Wallet option as built-in
                      const Divider(height: 1),
                      RadioListTile<String>(
                        value: 'WALLET',
                        groupValue: _selectedProvider,
                        onChanged: (val) => setState(() {
                          _selectedProvider = val!;
                          _selectedPaymentMethod = null;
                        }),
                        activeColor: AppColors.emerald,
                        title: const Text('Vektolux Wallet Balance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        subtitle: const Text('Zero fee instant lock from available balance', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                        secondary: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.emerald),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),

              // Manual provider instructions + transaction ref field
              if (_selectedPaymentMethod != null && _selectedPaymentMethod!.isManual) ...[
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
                        _selectedPaymentMethod!.instructions ?? 'Follow your provider\'s payment process and enter the Transaction ID below.',
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
                const SizedBox(height: 14),
              ],

              // Phone number field for non-wallet, non-manual providers
              if (_selectedProvider != 'WALLET' && (_selectedPaymentMethod == null || _selectedPaymentMethod!.isAutomated)) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Mobile Money Phone Number',
                    hintText: 'e.g. 076 123456 or 077 123456',
                    prefixIcon: const Icon(Icons.phone, color: AppColors.gray500),
                    filled: true,
                    fillColor: AppColors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Confirm & Lock Action
              VxButton(
                label: _selectedPaymentMethod != null && _selectedPaymentMethod!.isManual
                    ? 'Submit Payment Claim'
                    : (_selectedPaymentMethod != null && _selectedPaymentMethod!.isAutomated) || _selectedProvider == 'moneroo_auto'
                        ? 'Pay with Moneroo (SLE ${currencyFmt.format(_totalEscrowInflow)})'
                        : 'Lock SLE ${currencyFmt.format(_totalEscrowInflow)} in Escrow',
                icon: _selectedPaymentMethod != null && _selectedPaymentMethod!.isManual
                    ? Icons.send_rounded
                    : (_selectedPaymentMethod != null && _selectedPaymentMethod!.isAutomated) || _selectedProvider == 'moneroo_auto'
                        ? Icons.open_in_browser_rounded
                        : Icons.lock_outline_rounded,
                isLoading: _isSubmitting,
                onPressed: _selectedPaymentMethod != null && _selectedPaymentMethod!.isManual
                    ? _handleManualPaymentClaim
                    : (_selectedPaymentMethod != null && _selectedPaymentMethod!.isAutomated) || _selectedProvider == 'moneroo_auto'
                        ? _handleInitiateMoneroo
                        : _handleInitiateEscrow,
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCarIcon() {
    return Container(
      width: 70,
      height: 70,
      color: AppColors.gray100,
      child: const Icon(Icons.directions_car_rounded, color: AppColors.gray400, size: 36),
    );
  }

  Widget _buildCostRow(String label, String value, {bool isHighlight = false, bool isTotal = false, String? subtitle}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isTotal ? 14 : 13,
                  fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
                  color: isHighlight ? AppColors.emeraldDark : (isTotal ? AppColors.obsidian : AppColors.gray700),
                ),
              ),
              if (subtitle != null)
                Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.gray500)),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 16 : 13,
            fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
            color: isHighlight ? AppColors.emeraldDark : (isTotal ? AppColors.obsidian : AppColors.gray800),
          ),
        ),
      ],
    );
  }

  Widget _buildMilestoneRow(String title, String amount, String explanation) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.obsidian)),
            Text(amount, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.emeraldDark)),
          ],
        ),
        const SizedBox(height: 2),
        Text(explanation, style: const TextStyle(fontSize: 11, color: AppColors.gray600)),
      ],
    );
  }
}
