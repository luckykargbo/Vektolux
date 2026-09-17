// lib/features/mobility/presentation/views/escrow_checkout_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Vehicle Escrow Checkout & Milestone Agreement Screen
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
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
  String _selectedProvider = 'ORANGE_MONEY_SL'; // ORANGE_MONEY_SL, AFRICELL_AFRIMONEY_SL, WALLET
  final _phoneController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
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

            // Mobile Money Payment Method Selector
            const Text('Select Payment Method', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'ORANGE_MONEY_SL',
                    groupValue: _selectedProvider,
                    onChanged: (val) => setState(() => _selectedProvider = val!),
                    activeColor: AppColors.emerald,
                    title: const Text('Orange Money Sierra Leone', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    subtitle: const Text('USSD STK Push prompt to your phone (*144#)', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                    secondary: const Icon(Icons.phone_android_rounded, color: Colors.deepOrange),
                  ),
                  const Divider(height: 1),
                  RadioListTile<String>(
                    value: 'AFRICELL_AFRIMONEY_SL',
                    groupValue: _selectedProvider,
                    onChanged: (val) => setState(() => _selectedProvider = val!),
                    activeColor: AppColors.emerald,
                    title: const Text('Africell Afrimoney', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    subtitle: const Text('Instant prompt on Afrimoney wallet (*161#)', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                    secondary: const Icon(Icons.mobile_friendly_rounded, color: Colors.purple),
                  ),
                  const Divider(height: 1),
                  RadioListTile<String>(
                    value: 'WALLET',
                    groupValue: _selectedProvider,
                    onChanged: (val) => setState(() => _selectedProvider = val!),
                    activeColor: AppColors.emerald,
                    title: const Text('Vektolux Wallet Balance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    subtitle: const Text('Zero fee instant lock from available balance', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                    secondary: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.emerald),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (_selectedProvider != 'WALLET') ...[
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
              label: 'Lock SLE ${currencyFmt.format(_totalEscrowInflow)} in Escrow',
              icon: Icons.lock_outline_rounded,
              isLoading: _isSubmitting,
              onPressed: _handleInitiateEscrow,
            ),
            const SizedBox(height: 20),
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
