// lib/features/real_estate/presentation/views/real_estate_escrow_tracking_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real Estate Escrow Tracking & Milestone Management Console
// Tracks Short Stays (24h payout countdown & check-in), Long Leases (caution vault),
// and Land Outright Purchases (10/40/50 gated milestones).
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class RealEstateEscrowTrackingScreen extends StatefulWidget {
  final String contractId;

  const RealEstateEscrowTrackingScreen({
    super.key,
    required this.contractId,
  });

  @override
  State<RealEstateEscrowTrackingScreen> createState() =>
      _RealEstateEscrowTrackingScreenState();
}

class _RealEstateEscrowTrackingScreenState
    extends State<RealEstateEscrowTrackingScreen> {
  Map<String, dynamic>? _contractData;
  bool _isLoading = true;
  bool _isActionExecuting = false;
  Timer? _countdownTimer;
  Duration _remainingTime24h = Duration.zero;
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _loadContractDetails();
    _startCountdownTimer();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_contractData != null) {
        final contract = _contractData!['contract'] as Map<String, dynamic>?;
        final checkInTime = contract?['checkInTimestamp'] as num?;
        if (checkInTime != null) {
          final maturesAt = checkInTime + (24 * 60 * 60 * 1000);
          final diff = maturesAt - DateTime.now().millisecondsSinceEpoch;
          setState(() {
            _remainingTime24h = diff > 0 ? Duration(milliseconds: diff.toInt()) : Duration.zero;
          });
        }
      }
    });
  }

  Future<void> _loadContractDetails() async {
    setState(() => _isLoading = true);
    try {
      final client = context.read<ConvexClientWrapper>();
      final res = await client.query(
        'realEstateEscrow:getRealEstateEscrowById',
        args: {'contractId': widget.contractId},
      );

      if (res.success && res.value != null) {
        setState(() {
          _contractData = Map<String, dynamic>.from(res.value as Map);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCheckIn() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Short-Stay Check-In'),
        content: const Text(
          'Confirm that you have arrived and received keys/access to the property. This starts the 24-hour escrow release timer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Check-In'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionExecuting = true);

    try {
      final client = context.read<ConvexClientWrapper>();
      final user = context.read<AuthBloc>().state.user;

      final res = await client.mutation(
        'realEstateEscrow:checkInShortStay',
        args: {
          'contractId': widget.contractId,
          'guestId': user?.id,
          'guestOdometerOrKeysVerified': true,
        },
      );

      setState(() => _isActionExecuting = false);

      if (!mounted) return;
      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-in confirmed! 24h host payout timer is running.')),
        );
        _loadContractDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorMessage ?? 'Check-in failed')),
        );
      }
    } catch (e) {
      setState(() => _isActionExecuting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _handleRelease24hPayout() async {
    setState(() => _isActionExecuting = true);

    try {
      final client = context.read<ConvexClientWrapper>();

      final res = await client.mutation(
        'realEstateEscrow:releaseShortStayPayout24h',
        args: {'contractId': widget.contractId},
      );

      setState(() => _isActionExecuting = false);

      if (!mounted) return;
      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('24h stay rent successfully released to host wallet!')),
        );
        _loadContractDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorMessage ?? 'Payout release failed')),
        );
      }
    } catch (e) {
      setState(() => _isActionExecuting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _handleRefundCautionDeposit() async {
    final deductionController = TextEditingController(text: '0');
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refund Caution Deposit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verify check-out condition. If damages occurred, enter deduction amount:'),
            const SizedBox(height: 12),
            TextField(
              controller: deductionController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Deduction Amount (SLE)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Deduction Reason (if any)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Process Refund'),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    setState(() => _isActionExecuting = true);

    try {
      final client = context.read<ConvexClientWrapper>();
      final deductions = double.tryParse(deductionController.text) ?? 0.0;

      final res = await client.mutation(
        'realEstateEscrow:refundCautionDeposit',
        args: {
          'contractId': widget.contractId,
          'deductions': deductions,
          if (reasonController.text.isNotEmpty) 'deductionReason': reasonController.text,
        },
      );

      setState(() => _isActionExecuting = false);

      if (!mounted) return;
      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caution deposit processed and refunded to client!')),
        );
        _loadContractDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorMessage ?? 'Caution refund failed')),
        );
      }
    } catch (e) {
      setState(() => _isActionExecuting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _handleReleaseLandMilestone(String milestoneId, String milestoneTitle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Release $milestoneTitle?'),
        content: const Text(
          'Confirm that legal/survey statutory documents have been registered at OARG / Ministry of Lands. This releases funds to the seller.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Verify & Release'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionExecuting = true);

    try {
      final client = context.read<ConvexClientWrapper>();

      final res = await client.mutation(
        'realEstateEscrow:verifyAndReleaseLandMilestone',
        args: {
          'milestoneId': milestoneId,
          'remarks': 'Verified via Vektolux Mobile Escrow Console',
        },
      );

      setState(() => _isActionExecuting = false);

      if (!mounted) return;
      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$milestoneTitle released successfully!')),
        );
        _loadContractDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorMessage ?? 'Milestone release failed')),
        );
      }
    } catch (e) {
      setState(() => _isActionExecuting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _handleRaiseDispute() async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise Escrow Dispute'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Raising a dispute locks all escrow funds and assigns a Vektolux Legal Arbitrator to review evidence within 48 hours.',
              style: TextStyle(fontSize: 12, color: AppColors.gray600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason for dispute',
                hintText: 'e.g. Property uninhabitable, severe damage, or defective deed...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Submit Dispute'),
          ),
        ],
      ),
    );

    if (confirmed != true || reasonController.text.trim().isEmpty || !mounted) return;

    setState(() => _isActionExecuting = true);

    try {
      final client = context.read<ConvexClientWrapper>();

      final res = await client.mutation(
        'realEstateEscrow:raiseRealEstateDispute',
        args: {
          'contractId': widget.contractId,
          'raisedByRole': 'buyer_or_tenant',
          'reason': reasonController.text.trim(),
        },
      );

      setState(() => _isActionExecuting = false);

      if (!mounted) return;
      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dispute opened. Escrow funds locked pending arbitration.')),
        );
        _loadContractDetails();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.errorMessage ?? 'Failed to open dispute')),
        );
      }
    } catch (e) {
      setState(() => _isActionExecuting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Escrow Contract Console',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: AppColors.obsidian,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading || _isActionExecuting ? null : _loadContractDetails,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.emerald))
          : _contractData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.gray400),
                      const SizedBox(height: 12),
                      const Text('Contract not found or access denied.'),
                      const SizedBox(height: 12),
                      VxButton.small(label: 'Retry', onPressed: _loadContractDetails, width: 100),
                    ],
                  ),
                )
              : _buildConsoleBody(),
    );
  }

  Widget _buildConsoleBody() {
    final contract = _contractData!['contract'] as Map<String, dynamic>;
    final property = _contractData!['property'] as Map<String, dynamic>?;
    final milestones = (_contractData!['milestones'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    final cautionDeposit = _contractData!['cautionDeposit'] as Map<String, dynamic>?;

    final contractType = contract['contractType']?.toString() ?? 'SHORT_STAY';
    final state = contract['state']?.toString() ?? 'PENDING_DEPOSIT';
    final totalInflow = (contract['totalEscrowInflow'] as num?)?.toDouble() ?? 0.0;
    final agreedPrice = (contract['agreedPriceOrRent'] as num?)?.toDouble() ?? 0.0;
    final checkInTimestamp = contract['checkInTimestamp'] as num?;

    return RefreshIndicator(
      onRefresh: _loadContractDetails,
      color: AppColors.emerald,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header Banner
            _buildStatusHeader(contractType, state),
            const SizedBox(height: 20),

            // Property Info Card
            if (property != null) _buildPropertyCard(property),
            const SizedBox(height: 20),

            // Financial Breakdown Card
            _buildFinancialCard(totalInflow, agreedPrice, cautionDeposit),
            const SizedBox(height: 20),

            // Workflow-specific section
            if (contractType == 'SHORT_STAY')
              _buildShortStaySection(state, checkInTimestamp, cautionDeposit),
            if (contractType == 'LAND_PURCHASE')
              _buildLandMilestonesSection(milestones),
            if (contractType == 'LONG_TERM_LEASE')
              _buildLongLeaseSection(cautionDeposit),
            const SizedBox(height: 20),

            // Dispute button
            if (state != 'DISPUTED' && state != 'SETTLED')
              OutlinedButton.icon(
                icon: const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.error),
                label: const Text('Raise Escrow Dispute', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isActionExecuting ? null : _handleRaiseDispute,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(String type, String state) {
    Color stateColor;
    String stateLabel;

    switch (state) {
      case 'PENDING_DEPOSIT':
        stateColor = AppColors.amber;
        stateLabel = 'Pending Payment';
        break;
      case 'FUNDS_LOCKED':
        stateColor = AppColors.emerald;
        stateLabel = 'Funds Locked in Escrow';
        break;
      case 'ACTIVE_STAY':
        stateColor = const Color(0xFF3B82F6);
        stateLabel = 'Active Guest Stay (24h Window)';
        break;
      case 'LEASE_ACTIVE':
        stateColor = AppColors.emerald;
        stateLabel = 'Lease Active & Protected';
        break;
      case 'SETTLED':
        stateColor = AppColors.emerald;
        stateLabel = 'Settled & Completed';
        break;
      case 'DISPUTED':
        stateColor = AppColors.error;
        stateLabel = 'Dispute Under Review';
        break;
      default:
        stateColor = AppColors.gray500;
        stateLabel = state;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.security_rounded, color: stateColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.replaceAll('_', ' '),
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
                ),
                const SizedBox(height: 2),
                Text(
                  stateLabel,
                  style: TextStyle(color: stateColor, fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyCard(Map<String, dynamic> property) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.apartment_rounded, color: AppColors.obsidian, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property['title']?.toString() ?? 'Property Listing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                ),
                const SizedBox(height: 2),
                Text(
                  property['location']?.toString() ?? 'Sierra Leone',
                  style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialCard(double totalInflow, double baseRent, Map<String, dynamic>? caution) {
    final cautionAmount = (caution?['amount'] as num?)?.toDouble() ?? 0.0;
    final cautionStatus = caution?['status']?.toString() ?? 'NOT_APPLICABLE';

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
          const Text('ESCROW CUSTODY DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.gray500, letterSpacing: 0.8)),
          const SizedBox(height: 12),
          _buildRow('Total Escrow Custody', 'SLE ${_currencyFormat.format(totalInflow)}', isBold: true),
          _buildRow('Agreed Base Price', 'SLE ${_currencyFormat.format(baseRent)}'),
          if (cautionAmount > 0)
            _buildRow(
              'Caution Vault ($cautionStatus)',
              'SLE ${_currencyFormat.format(cautionAmount)}',
              valueColor: AppColors.emeraldDark,
            ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: isBold ? AppColors.obsidian : AppColors.gray600, fontWeight: isBold ? FontWeight.w700 : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 13, color: valueColor ?? AppColors.obsidian, fontWeight: isBold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildShortStaySection(String state, num? checkInTime, Map<String, dynamic>? caution) {
    final hasCheckedIn = checkInTime != null;
    final is24hMature = _remainingTime24h == Duration.zero && hasCheckedIn;
    final cautionRefunded = caution?['status'] == 'REFUNDED';

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
          const Text('SHORT-STAY 24H RELEASE ENGINE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.emeraldDark, letterSpacing: 0.8)),
          const SizedBox(height: 12),

          if (!hasCheckedIn) ...[
            const Text(
              'Guest has not checked in yet. When you arrive, confirm check-in to start the 24-hour host escrow release timer.',
              style: TextStyle(fontSize: 12, color: AppColors.gray600),
            ),
            const SizedBox(height: 14),
            VxButton.primary(
              text: 'Confirm Guest Check-In',
              icon: Icons.vpn_key_rounded,
              onPressed: _isActionExecuting ? null : _handleCheckIn,
            ),
          ] else ...[
            // 24h Countdown Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: AppColors.emeraldLight, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('24H HOST RELEASE WINDOW', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          is24hMature
                              ? 'Window Matured! Eligible for release.'
                              : '${_remainingTime24h.inHours}h ${(_remainingTime24h.inMinutes % 60)}m ${(_remainingTime24h.inSeconds % 60)}s remaining',
                          style: TextStyle(
                            color: is24hMature ? AppColors.emeraldLight : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (is24hMature && state == 'ACTIVE_STAY')
              VxButton.primary(
                text: 'Release Rent to Host Wallet',
                icon: Icons.payments_rounded,
                onPressed: _isActionExecuting ? null : _handleRelease24hPayout,
              ),

            const SizedBox(height: 14),
            if (!cautionRefunded)
              VxButton(
                label: 'Process Checkout Caution Refund',
                icon: Icons.cleaning_services_rounded,
                onPressed: _isActionExecuting ? null : _handleRefundCautionDeposit,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLandMilestonesSection(List<Map<String, dynamic>> milestones) {
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
          const Text('10/40/50 LAND PURCHASE MILESTONES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.emeraldDark, letterSpacing: 0.8)),
          const SizedBox(height: 12),
          if (milestones.isEmpty)
            const Text('Milestones being initialized by legal registry...', style: TextStyle(fontSize: 12, color: AppColors.gray500))
          else
            ...milestones.map((m) {
              final id = m['_id']?.toString() ?? '';
              final title = m['title']?.toString() ?? 'Milestone';
              final pct = m['milestonePercentage'] ?? 0;
              final amount = (m['payoutAmount'] as num?)?.toDouble() ?? 0.0;
              final status = m['state']?.toString() ?? 'PENDING';
              final isPending = status == 'PENDING';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: status == 'RELEASED' ? const Color(0xFFF0FDF4) : AppColors.gray50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: status == 'RELEASED' ? AppColors.emerald : AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: status == 'RELEASED' ? AppColors.emerald : AppColors.gray200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(status == 'RELEASED' ? Icons.check : Icons.lock_outline, size: 16, color: status == 'RELEASED' ? Colors.white : AppColors.gray600),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$pct% • $title', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          Text('SLE ${_currencyFormat.format(amount)} • $status', style: const TextStyle(fontSize: 11, color: AppColors.gray600)),
                        ],
                      ),
                    ),
                    if (isPending)
                      VxButton.small(
                        label: 'Release',
                        onPressed: _isActionExecuting ? null : () => _handleReleaseLandMilestone(id, title),
                        width: 80,
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildLongLeaseSection(Map<String, dynamic>? caution) {
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
          const Text('TENANCY LEASE CUSTODY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.emeraldDark, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          const Text(
            'Base rent has been remitted to landlord. Statutory agency commission (10%) split 85/15. Caution deposit is securely locked until tenancy termination.',
            style: TextStyle(fontSize: 12, color: AppColors.gray600, height: 1.4),
          ),
          const SizedBox(height: 14),
          VxButton(
            label: 'Tenancy Termination Caution Refund',
            icon: Icons.assignment_return_outlined,
            onPressed: _isActionExecuting ? null : _handleRefundCautionDeposit,
          ),
        ],
      ),
    );
  }
}
