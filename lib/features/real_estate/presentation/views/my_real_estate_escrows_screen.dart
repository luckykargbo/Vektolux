// lib/features/real_estate/presentation/views/my_real_estate_escrows_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — My Real Estate Escrow Contracts & Anti-Bypass Passes
// Displays all viewing inspection passes (with 4-digit OTPs) and
// escrow contracts (Short Stay, Long Lease, Land Purchase).
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/components/vx_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import 'inspection_pass_verification_screen.dart';
import 'real_estate_escrow_tracking_screen.dart';

class MyRealEstateEscrowsScreen extends StatefulWidget {
  const MyRealEstateEscrowsScreen({super.key});

  @override
  State<MyRealEstateEscrowsScreen> createState() =>
      _MyRealEstateEscrowsScreenState();
}

class _MyRealEstateEscrowsScreenState extends State<MyRealEstateEscrowsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  bool _isLoading = true;
  List<Map<String, dynamic>> _contracts = [];
  List<Map<String, dynamic>> _passes = [];
  String? _errorMessage;

  final List<String> _tabs = [
    'All Escrows',
    'Viewing Passes',
    'Short Stays',
    'Long Leases',
    'Land Purchases',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _fetchEscrows();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchEscrows() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = context.read<AuthBloc>().state.user;
      final client = context.read<ConvexClientWrapper>();

      final res = await client.query(
        'realEstateEscrow:getMyRealEstateEscrows',
        args: {
          if (user != null) 'userId': user.id,
        },
      );

      if (res.success && res.value != null) {
        final data = res.value as Map<String, dynamic>;
        setState(() {
          _contracts = (data['contracts'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _passes = (data['passes'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = res.errorMessage ?? 'Failed to load escrow records';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredContracts {
    final idx = _tabController.index;
    if (idx == 0) return _contracts; // All
    if (idx == 1) return []; // Viewing passes handled separately
    if (idx == 2) return _contracts.where((c) => c['contractType'] == 'SHORT_STAY').toList();
    if (idx == 3) return _contracts.where((c) => c['contractType'] == 'LONG_TERM_LEASE').toList();
    if (idx == 4) return _contracts.where((c) => c['contractType'] == 'LAND_PURCHASE').toList();
    return _contracts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Property Escrow Vault',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: AppColors.obsidian,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: 'Agent Pass Scanner',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const InspectionPassVerificationScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _fetchEscrows,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.emerald,
          unselectedLabelColor: Colors.white60,
          indicatorColor: AppColors.emerald,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.emerald))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.gray400),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: AppColors.gray600)),
                      const SizedBox(height: 12),
                      VxButton.small(label: 'Retry', onPressed: _fetchEscrows, width: 100),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchEscrows,
                  color: AppColors.emerald,
                  child: _tabController.index == 1
                      ? _buildPassesList()
                      : _buildContractsList(),
                ),
    );
  }

  Widget _buildPassesList() {
    if (_passes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.confirmation_number_outlined, size: 64, color: AppColors.gray400),
            SizedBox(height: 14),
            Text(
              'No Anti-Bypass Viewing Passes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.obsidian),
            ),
            SizedBox(height: 4),
            Text(
              'Book an inspection tour on any property to receive your OTP pass.',
              style: TextStyle(fontSize: 12, color: AppColors.gray500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _passes.length,
      itemBuilder: (ctx, i) {
        final p = _passes[i];
        final passId = p['_id']?.toString() ?? '';
        final otp = p['otpCode']?.toString() ?? '----';
        final status = p['status']?.toString() ?? 'BOOKED';
        final fee = (p['tourFee'] as num?)?.toDouble() ?? 50.0;
        final agentName = p['agentName']?.toString() ?? 'Assigned Field Agent';
        final neighborhood = p['neighborhood']?.toString() ?? 'Masked Area';
        final isVerified = status == 'VERIFIED';

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isVerified ? AppColors.emerald : AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isVerified ? AppColors.emeraldSurface : AppColors.amberSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isVerified ? 'VERIFIED & PAID' : 'PENDING VISIT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isVerified ? AppColors.emeraldDark : AppColors.amberDark,
                      ),
                    ),
                  ),
                  Text(
                    'SLE ${fee.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.obsidian),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Viewing Area: $neighborhood',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.obsidian),
              ),
              const SizedBox(height: 4),
              Text(
                'Guide: $agentName',
                style: const TextStyle(fontSize: 12, color: AppColors.gray600),
              ),
              const Divider(height: 20),

              // OTP row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('4-DIGIT VERIFICATION OTP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.gray500)),
                      const SizedBox(height: 2),
                      Text(
                        otp,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3, color: AppColors.emeraldDark),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.emerald),
                        tooltip: 'Copy OTP',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: otp));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('OTP copied to clipboard!')),
                          );
                        },
                      ),
                      if (!isVerified)
                        VxButton.small(
                          label: 'Verify (Agent)',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => InspectionPassVerificationScreen(
                                  initialPassId: passId,
                                ),
                              ),
                            );
                          },
                          width: 100,
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContractsList() {
    final list = _filteredContracts;

    if (list.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: AppColors.gray400),
            SizedBox(height: 14),
            Text(
              'No Real Estate Escrow Contracts Found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.obsidian),
            ),
            SizedBox(height: 4),
            Text(
              'Initiate a short-stay, lease, or land purchase with escrow protection.',
              style: TextStyle(fontSize: 12, color: AppColors.gray500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final c = list[i];
        final contractId = c['_id']?.toString() ?? '';
        final contractType = c['contractType']?.toString() ?? 'SHORT_STAY';
        final state = c['state']?.toString() ?? 'PENDING_DEPOSIT';
        final totalInflow = (c['totalEscrowInflow'] as num?)?.toDouble() ?? 0.0;
        final propTitle = c['propertyTitle']?.toString() ?? 'Property Listing';
        final location = c['propertyLocation']?.toString() ?? 'Sierra Leone';

        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RealEstateEscrowTrackingScreen(contractId: contractId),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        contractType.replaceAll('_', ' '),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.emeraldDark),
                      ),
                    ),
                    Text(
                      state.replaceAll('_', ' '),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: state == 'DISPUTED' ? AppColors.error : AppColors.emeraldDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  propTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.obsidian),
                ),
                const SizedBox(height: 2),
                Text(
                  location,
                  style: const TextStyle(fontSize: 12, color: AppColors.gray500),
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ESCROW CUSTODY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.gray500)),
                        const SizedBox(height: 2),
                        Text(
                          'SLE ${_currencyFormat.format(totalInflow)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.obsidian),
                        ),
                      ],
                    ),
                    const Row(
                      children: [
                        Text('Open Console', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.emerald)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.emerald),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
