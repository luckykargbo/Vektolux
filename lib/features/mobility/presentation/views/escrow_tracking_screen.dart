// lib/features/mobility/presentation/views/escrow_tracking_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Real-Time Escrow Contract Tracking & Milestone Console
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import 'vehicle_inspection_screen.dart';

class EscrowTrackingScreen extends StatefulWidget {
  final String escrowOrderId;

  const EscrowTrackingScreen({
    super.key,
    required this.escrowOrderId,
  });

  @override
  State<EscrowTrackingScreen> createState() => _EscrowTrackingScreenState();
}

class _EscrowTrackingScreenState extends State<EscrowTrackingScreen> {
  Map<String, dynamic>? _orderData;
  bool _isLoading = true;
  bool _isActionExecuting = false;

  @override
  void initState() {
    super.initState();
    _loadOrderDetails();
  }

  Future<void> _loadOrderDetails() async {
    setState(() => _isLoading = true);
    try {
      final client = context.read<ConvexClientWrapper>();
      final res = await client.query(
        'escrow:getEscrowOrderById',
        args: {'escrowOrderId': widget.escrowOrderId},
      );

      if (res.success && res.value != null) {
        setState(() {
          _orderData = res.value as Map<String, dynamic>;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRelease60() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm 60% Handoff Release'),
        content: const Text(
          'This will disburse 60% of the net rental earnings to the vehicle owner. Confirm that physical vehicle handoff has occurred.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Release'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionExecuting = true);
    try {
      final client = context.read<ConvexClientWrapper>();
      final res = await client.mutation(
        'escrow:releaseMilestoneHandoff60',
        args: {'escrowOrderId': widget.escrowOrderId},
      );

      if (res.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ 60% Handoff funds disbursed to owner!'), backgroundColor: AppColors.emerald),
          );
          _loadOrderDetails();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${res.errorMessage}'), backgroundColor: AppColors.error),
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
      if (mounted) setState(() => _isActionExecuting = false);
    }
  }

  Future<void> _handleSettleReturn() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Return Settlement'),
        content: const Text(
          'This will disburse the final 40% balance to the owner and refund 100% of the damage deposit to the renter.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Settle & Refund Deposit'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionExecuting = true);
    try {
      final client = context.read<ConvexClientWrapper>();
      final res = await client.mutation(
        'escrow:settleVehicleReturn',
        args: {'escrowOrderId': widget.escrowOrderId},
      );

      if (res.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Escrow Settled! 100% Damage deposit refunded.'), backgroundColor: AppColors.emerald),
          );
          _loadOrderDetails();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${res.errorMessage}'), backgroundColor: AppColors.error),
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
      if (mounted) setState(() => _isActionExecuting = false);
    }
  }

  Future<void> _handleReleaseDealFunds() async {
    final order = _orderData?['order'] as Map<String, dynamic>?;
    final netAmount = (order?['netMerchantExpected'] as num?)?.toDouble() ?? 0.0;
    final currencyFmt = NumberFormat('#,##0.00');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Inspection & Release Funds'),
        content: Text(
          'Confirm that you have thoroughly inspected the vehicle and are satisfied.\n\nThis will release SLE ${currencyFmt.format(netAmount)} from escrow directly to the seller.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Approve & Release'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionExecuting = true);
    try {
      final client = context.read<ConvexClientWrapper>();
      final res = await client.mutation(
        'escrow:releaseDealEscrowFunds',
        args: {'escrowOrderId': widget.escrowOrderId},
      );

      if (res.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Inspection approved! Escrow funds released to seller.'),
              backgroundColor: AppColors.emerald,
            ),
          );
          _loadOrderDetails();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: ${res.errorMessage}'), backgroundColor: AppColors.error),
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
      if (mounted) setState(() => _isActionExecuting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: AppColors.emerald)),
      );
    }

    final order = _orderData?['order'] as Map<String, dynamic>?;
    final vehicle = _orderData?['vehicle'] as Map<String, dynamic>?;
    final inspections = (_orderData?['inspections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final status = order?['status']?.toString() ?? 'INITIATED';
    final currencyFmt = NumberFormat('#,##0.00');

    final grossEscrow = (order?['grossEscrowAmount'] as num?)?.toDouble() ?? 0.0;
    final deposit = (order?['refundableDepositAmount'] as num?)?.toDouble() ?? 0.0;
    final split60 = (order?['split60ReleasedAmount'] as num?)?.toDouble() ?? 0.0;
    final split40 = (order?['split40ReleasedAmount'] as num?)?.toDouble() ?? 0.0;
    final orderCode = order?['orderCode']?.toString() ?? 'VK-ESC';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Escrow Contract: $orderCode', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadOrderDetails,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _getStatusColor(status).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(_getStatusIcon(status), color: _getStatusColor(status), size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getStatusTitle(status),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _getStatusColor(status)),
                        ),
                        const SizedBox(height: 2),
                        Text(_getStatusDescription(status), style: const TextStyle(fontSize: 12, color: AppColors.gray600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Vehicle Overview Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_car_rounded, color: AppColors.obsidian, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicle?['title']?.toString() ?? 'Commercial Vehicle',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.obsidian),
                        ),
                        Text(
                          'Gross Escrow: SLE ${currencyFmt.format(grossEscrow)} (Deposit: SLE ${currencyFmt.format(deposit)})',
                          style: const TextStyle(fontSize: 12, color: AppColors.emeraldDark, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Visual Milestone Stepper
            const Text('Milestone Progress', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 12),
            _buildMilestoneStep(
              title: '1. Upfront Funds Locked in Escrow',
              subtitle: 'SLE ${currencyFmt.format(grossEscrow)} received via Mobile Money',
              isCompleted: status != 'INITIATED' && status != 'PENDING_PAYMENT',
              isActive: status == 'HELD_IN_ESCROW',
            ),
            _buildMilestoneStep(
              title: '2. Pre-Trip Inspection & 60% Handoff Release',
              subtitle: split60 > 0
                  ? 'SLE ${currencyFmt.format(split60)} disbursed to Owner'
                  : 'Awaiting pre-trip condition photos and odometer sign-off',
              isCompleted: split60 > 0 || status == 'PARTIALLY_RELEASED' || status == 'SETTLED',
              isActive: status == 'HELD_IN_ESCROW',
            ),
            _buildMilestoneStep(
              title: '3. Vehicle in Trip Custody',
              subtitle: 'Commercial freight / rental operation in progress',
              isCompleted: status == 'POST_INSPECTION_PENDING' || status == 'SETTLED',
              isActive: status == 'PARTIALLY_RELEASED',
            ),
            _buildMilestoneStep(
              title: '4. Post-Trip Return & 40% Settlement',
              subtitle: status == 'SETTLED'
                  ? 'Final 40% (SLE ${currencyFmt.format(split40)}) paid to owner; 100% deposit (SLE ${currencyFmt.format(deposit)}) refunded to renter'
                  : 'Awaiting vehicle return inspection',
              isCompleted: status == 'SETTLED',
              isActive: status == 'PARTIALLY_RELEASED' || status == 'POST_INSPECTION_PENDING',
              isLast: true,
            ),
            const SizedBox(height: 24),

            // Interactive Actions Bar
            if (status == 'HELD_IN_ESCROW' || status == 'ESCROW_LOCKED') ...[
              VxButton(
                label: '1. Take Pre-Trip Photos & Complete Inspection',
                icon: Icons.camera_alt_outlined,
                onPressed: () async {
                  final res = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => VehicleInspectionScreen(
                        escrowOrderId: widget.escrowOrderId,
                        orderCode: orderCode,
                        inspectionType: 'PRE_TRIP_RENTAL',
                      ),
                    ),
                  );
                  if (res == true) _loadOrderDetails();
                },
              ),
              const SizedBox(height: 10),
              if (order?['orderType'] == 'VEHICLE_PURCHASE' || inspections.isNotEmpty) ...[
                VxButton(
                  label: 'Approve Inspection & Release Payment to Seller',
                  icon: Icons.verified_rounded,
                  isLoading: _isActionExecuting,
                  onPressed: _handleReleaseDealFunds,
                ),
                const SizedBox(height: 10),
              ],
              if (inspections.isNotEmpty && order?['orderType'] != 'VEHICLE_PURCHASE')
                VxButton(
                  label: '2. Release 60% Handoff to Owner',
                  icon: Icons.check_circle_outline,
                  isLoading: _isActionExecuting,
                  onPressed: _handleRelease60,
                ),
            ] else if (status == 'PARTIALLY_RELEASED') ...[
              VxButton(
                label: 'Complete Post-Trip Return Inspection',
                icon: Icons.car_crash_outlined,
                onPressed: () async {
                  final res = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => VehicleInspectionScreen(
                        escrowOrderId: widget.escrowOrderId,
                        orderCode: orderCode,
                        inspectionType: 'POST_TRIP_RENTAL',
                      ),
                    ),
                  );
                  if (res == true) _loadOrderDetails();
                },
              ),
              const SizedBox(height: 10),
              VxButton(
                label: 'Settle Return & Refund Deposit (100%)',
                icon: Icons.done_all_rounded,
                isLoading: _isActionExecuting,
                onPressed: _handleSettleReturn,
              ),
            ] else if (status == 'SETTLED') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_rounded, color: AppColors.emeraldDark, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This escrow agreement has been fully settled and closed. Both parties have received their respective disbursements.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.emeraldDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneStep({
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isActive,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.emerald
                    : (isActive ? AppColors.obsidian : AppColors.gray200),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  isCompleted ? Icons.check : (isActive ? Icons.radio_button_checked : Icons.circle_outlined),
                  size: 14,
                  color: (isCompleted || isActive) ? Colors.white : AppColors.gray500,
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: isCompleted ? AppColors.emerald : AppColors.gray200,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isCompleted || isActive ? AppColors.obsidian : AppColors.gray500,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.gray600)),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'HELD_IN_ESCROW':
      case 'ESCROW_LOCKED':
        return const Color(0xFFD97706); // Amber
      case 'PARTIALLY_RELEASED':
        return const Color(0xFF2563EB); // Blue
      case 'SETTLED':
        return AppColors.emeraldDark;
      case 'DISPUTED':
        return AppColors.error;
      case 'PENDING_PAYMENT':
        return const Color(0xFF475569);
      default:
        return AppColors.gray600;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'HELD_IN_ESCROW':
      case 'ESCROW_LOCKED':
        return Icons.lock_clock_rounded;
      case 'PARTIALLY_RELEASED':
        return Icons.local_shipping_rounded;
      case 'SETTLED':
        return Icons.check_circle_rounded;
      case 'DISPUTED':
        return Icons.warning_amber_rounded;
      case 'PENDING_PAYMENT':
        return Icons.pending_actions_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  String _getStatusTitle(String status) {
    switch (status) {
      case 'HELD_IN_ESCROW':
      case 'ESCROW_LOCKED':
        return 'Funds Secured in Escrow';
      case 'PARTIALLY_RELEASED':
        return '60% Disbursed • In Trip';
      case 'SETTLED':
        return 'Contract Settled & Cleared';
      case 'DISPUTED':
        return 'Damage Dispute Opened';
      case 'PENDING_PAYMENT':
        return 'Awaiting Payment Clearance';
      default:
        return status;
    }
  }

  String _getStatusDescription(String status) {
    switch (status) {
      case 'HELD_IN_ESCROW':
      case 'ESCROW_LOCKED':
        return '100% of upfront funds are locked in platform escrow. Complete pre-trip inspection to unlock vehicle handoff or release payment.';
      case 'PARTIALLY_RELEASED':
        return '60% of base rental proceeds have been paid to owner. Vehicle is in renter custody.';
      case 'SETTLED':
        return 'Return confirmed. Payout disbursed to owner/seller and escrow closed.';
      case 'DISPUTED':
        return 'Damage reported. Deposit is held in escrow pending admin review.';
      case 'PENDING_PAYMENT':
        return 'Awaiting mobile money approval or commercial bank wire clearing.';
      default:
        return 'Status: $status';
    }
  }
}
