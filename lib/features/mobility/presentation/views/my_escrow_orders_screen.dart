// lib/features/mobility/presentation/views/my_escrow_orders_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — My Escrow Contracts & Milestone Orders
// Real-time tracking of Vehicle Rentals (60/40 Split + Damage Deposit)
// and Vehicle Purchases (Earnest Deposit + SLRSA Title Transfer).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vx_network_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import 'escrow_tracking_screen.dart';
import 'vehicle_inspection_screen.dart';

class MyEscrowOrdersScreen extends StatefulWidget {
  const MyEscrowOrdersScreen({super.key});

  @override
  State<MyEscrowOrdersScreen> createState() => _MyEscrowOrdersScreenState();
}

class _MyEscrowOrdersScreenState extends State<MyEscrowOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final NumberFormat _currencyFormat = NumberFormat('#,##0', 'en_US');

  bool _isLoading = true;
  List<Map<String, dynamic>> _orders = [];
  String? _errorMessage;

  final List<String> _filterTabs = [
    'All Contracts',
    'Active in Escrow',
    'Rentals (60/40)',
    'Purchases (SLRSA)',
    'Settled & Closed',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _filterTabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _fetchEscrowOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchEscrowOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = context.read<AuthBloc>().state.user;
      final client = context.read<ConvexClientWrapper>();

      final res = await client.query(
        'escrow:getMyEscrowOrders',
        args: {
          if (user != null) 'userId': user.id,
        },
      );

      if (res.success && res.value is List) {
        if (mounted) {
          setState(() {
            _orders = (res.value as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = res.errorMessage ?? 'Unable to retrieve escrow orders';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Network connection error: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    final tabIndex = _tabController.index;
    return _orders.where((order) {
      final status = (order['status'] as String? ?? '').toUpperCase();
      final type = (order['orderType'] as String? ?? '').toUpperCase();

      switch (tabIndex) {
        case 1: // Active in Escrow
          return status != 'SETTLED' && status != 'CANCELLED_REFUNDED';
        case 2: // Rentals
          return type == 'RENTAL';
        case 3: // Purchases
          return type == 'PURCHASE';
        case 4: // Settled
          return status == 'SETTLED' || status == 'CANCELLED_REFUNDED';
        default:
          return true;
      }
    }).toList();
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'SETTLED':
        return AppColors.emeraldDark;
      case 'HELD_IN_ESCROW':
        return const Color(0xFF2563EB); // Royal blue
      case 'IN_RENTAL_ACTIVE':
        return const Color(0xFF7C3AED); // Purple
      case 'PARTIALLY_RELEASED':
        return const Color(0xFF0284C7); // Cyan
      case 'PRE_INSPECTION_PENDING':
      case 'POST_INSPECTION_PENDING':
      case 'INITIATED_PENDING_DEPOSIT':
        return const Color(0xFFD97706); // Amber
      case 'DISPUTED':
        return AppColors.error;
      default:
        return AppColors.gray500;
    }
  }

  String _formatStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'INITIATED_PENDING_DEPOSIT':
        return 'Pending Telco Deposit';
      case 'HELD_IN_ESCROW':
        return 'Locked in Escrow';
      case 'PRE_INSPECTION_PENDING':
        return 'Pre-Trip Inspection Required';
      case 'IN_RENTAL_ACTIVE':
        return 'Vehicle Handed Over (60% Paid)';
      case 'PARTIALLY_RELEASED':
        return '60% Disbursed • 40% Held';
      case 'POST_INSPECTION_PENDING':
        return 'Return Inspection Pending';
      case 'SETTLED':
        return 'Settled & 100% Released';
      case 'DISPUTED':
        return 'Dispute In Review';
      case 'CANCELLED_REFUNDED':
        return 'Cancelled & Refunded';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOrders;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.white,
        title: const Text(
          'Escrow Contracts & Orders',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppColors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.white),
            tooltip: 'Refresh Orders',
            onPressed: _fetchEscrowOrders,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppColors.obsidian,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppColors.emerald,
              indicatorWeight: 3,
              labelColor: AppColors.emerald,
              unselectedLabelColor: AppColors.gray400,
              labelStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              tabs: _filterTabs.map((t) => Tab(text: t)).toList(),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.emerald),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.obsidian,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchEscrowOrders,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: AppColors.emerald,
                      onRefresh: _fetchEscrowOrders,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          return _buildOrderCard(filtered[index]);
                        },
                      ),
                    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.emeraldSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 56,
                color: AppColors.emeraldDark,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Escrow Contracts Found',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'All vehicle rentals and auto purchases in Sierra Leone are secured through Vektolux escrow rails with milestone payouts.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.gray600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.directions_car_rounded),
              label: const Text('Browse Auto Marketplace'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = order['_id'] as String? ?? '';
    final orderCode = order['orderCode'] as String? ?? 'VK-ESC';
    final orderType = (order['orderType'] as String? ?? 'RENTAL').toUpperCase();
    final status = (order['status'] as String? ?? 'INITIATED').toUpperCase();
    final vehicleTitle = order['vehicleTitle'] as String? ?? 'Commercial Vehicle';
    final vehicleImage = order['vehicleImage'] as String? ?? '';
    final isOwner = order['isOwner'] as bool? ?? false;

    final grossAmount = (order['grossEscrowAmount'] as num?)?.toDouble() ?? 0.0;
    final split60 = (order['split60Amount'] as num?)?.toDouble() ?? 0.0;
    final deposit = (order['refundableDepositAmount'] as num?)?.toDouble() ?? 0.0;
    final createdAt = (order['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final dateStr = DateFormat('MMM d, yyyy • h:mm a').format(DateTime.fromMillisecondsSinceEpoch(createdAt));

    final statusColor = _getStatusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EscrowTrackingScreen(escrowOrderId: orderId),
            ),
          );
          _fetchEscrowOrders();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Type badge, Order Code, and User Role
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: orderType == 'RENTAL'
                              ? const Color(0xFFEFF6FF)
                              : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          orderType == 'RENTAL' ? 'RENTAL (60/40)' : 'PURCHASE (SLRSA)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: orderType == 'RENTAL'
                                ? const Color(0xFF1E40AF)
                                : const Color(0xFF92400E),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        orderCode,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.obsidian,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isOwner ? const Color(0xFFF3F4F6) : AppColors.emeraldSurface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isOwner ? 'Merchant / Owner' : 'Buyer / Renter',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isOwner ? AppColors.gray700 : AppColors.emeraldDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Vehicle Thumb + Details
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: VxNetworkImage(
                      imageUrl: vehicleImage,
                      width: 72,
                      height: 56,
                      fit: BoxFit.cover,
                      fallbackIcon: Icons.directions_car_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicleTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.obsidian,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.gray500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Financial stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Escrow Custody',
                        style: TextStyle(fontSize: 10, color: AppColors.gray500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SLE ${_currencyFormat.format(grossAmount)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.obsidian,
                        ),
                      ),
                    ],
                  ),
                  if (orderType == 'RENTAL') ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          '60% Handoff Split',
                          style: TextStyle(fontSize: 10, color: AppColors.gray500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SLE ${_currencyFormat.format(split60)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.emeraldDark,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Refundable Deposit',
                          style: TextStyle(fontSize: 10, color: AppColors.gray500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SLE ${_currencyFormat.format(deposit)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Title Transfer',
                          style: TextStyle(fontSize: 10, color: AppColors.gray500),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'SLRSA Form C',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),

              // Status Pill & Action Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatStatusLabel(status),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (status == 'HELD_IN_ESCROW' || status == 'PRE_INSPECTION_PENDING')
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => VehicleInspectionScreen(
                                    escrowOrderId: orderId,
                                    orderCode: orderCode,
                                    inspectionType: 'PRE_TRIP_RENTAL',
                                  ),
                                ),
                              );
                              _fetchEscrowOrders();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFF59E0B)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.camera_alt_outlined, size: 12, color: Color(0xFFB45309)),
                                  SizedBox(width: 4),
                                  Text(
                                    'Inspect',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const Text(
                        'Details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.emeraldDark,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.emeraldDark),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
