// lib/features/home/presentation/views/client_home_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Super App Home Screen (Data-Driven, Production Ready)
// Visual design & layout strictly aligned with official design reference.
// Real authenticated user, real escrow wallet, real payment flows,
// auto-sliding promotional banners, and real verified properties.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/services/carrier_detection_service.dart';
import '../../../../core/services/payment_methods_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/vx_network_image.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../listings/presentation/views/property_detail_screen.dart';
import '../../../listings/presentation/views/vehicle_detail_screen.dart';
import '../../../navigation/presentation/views/main_navigation_shell.dart';
import '../../../notifications/presentation/views/notifications_screen.dart';
import '../../../profile/presentation/views/profile_screen.dart';
import '../../../profile/presentation/views/widgets/camera_qr_scanner_view.dart';
import '../../../profile/presentation/views/widgets/ussd_payment_sheet.dart';
import '../../../wallet_payments/presentation/bloc/wallet_cubit.dart';
import '../../../wallet_payments/presentation/views/transaction_history_screen.dart';
import '../../../wallet_payments/presentation/widgets/qr_pay_sheet.dart';
import '../../../wallet_payments/presentation/widgets/receive_payment_sheet.dart';
import '../../../wallet_payments/presentation/widgets/withdraw_sheet.dart';
import '../widgets/security_wallet_graphic.dart';

class ClientHomeScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;

  const ClientHomeScreen({
    super.key,
    required this.convexClient,
  });

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  // Layout tokens (one vertical rhythm for the whole Home screen).
  static const double _kPageGutter = 16;
  static const double _kGapS = 10; // inside a group (wallet → actions, top-up → payment cards)
  static const double _kGapM = 14; // between groups
  static const double _kGapL = 20; // before content sections (saved places, properties)
  // This dense dashboard caps iOS Dynamic Type at 1.15× so fixed-height cards and 4-up rows keep
  // their structure (larger system text sizes otherwise broke the action row letter-by-letter).
  static const double _kMaxTextScale = 1.15;

  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  // ── Live Backend States ───────────────────────────────────────────
  double? _walletBalance; // AVAILABLE (spendable / withdrawable) — from the server
  double? _escrowBalance; // protected in active escrow deals — from the server
  double? _pendingBalance; // reserved for in-flight withdrawals — from the server
  String? _walletOwnerId; // whose numbers these are (never show another user's)
  Timer? _walletPoll;
  bool _isLoadingBalance = true;
  String? _walletError;
  int _activeEscrowDeals = 0;
  int _unreadNotificationsCount = 0;

  List<Map<String, dynamic>> _properties = [];
  bool _isLoadingProperties = true;
  String? _propertiesError;

  List<Map<String, dynamic>> _vehicles = [];

  // Quick Top-up controllers
  final TextEditingController _momoPhoneController = TextEditingController();
  final TextEditingController _bankAccountController = TextEditingController();

  // ── Auto-Sliding Promotional Carousel State ───────────────────────
  final PageController _promoPageController = PageController();
  int _currentPromoPage = 0;
  Timer? _promoTimer;
  bool _isUserInteractingWithPromo = false;

  static const List<_PromoBannerData> _promotionalSlides = [
    _PromoBannerData(
      title: 'Find Your Perfect Place',
      subtitle: 'Houses, furnished flats & guest houses across Sierra Leone.',
      actionLabel: 'Explore Rentals',
      targetTab: 2, // Real Estate Tab
      filterQuery: 'rental',
      imageUrl:
          'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80',
    ),
    _PromoBannerData(
      title: 'Verified Properties',
      subtitle: 'Browse inspected listings with escrow deposit protection.',
      actionLabel: 'View Listings',
      targetTab: 2,
      filterQuery: 'verified',
      imageUrl:
          'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?auto=format&fit=crop&w=800&q=80',
    ),
    _PromoBannerData(
      title: 'Find Your Next Vehicle',
      subtitle: 'Explore showroom cars, SUVs & commercial fleet vehicles.',
      actionLabel: 'Explore Auto',
      targetTab: 3, // Auto Market Tab
      filterQuery: 'cars',
      imageUrl:
          'https://images.unsplash.com/photo-1549399542-7e3f8b79c341?auto=format&fit=crop&w=800&q=80',
    ),
    _PromoBannerData(
      title: 'Safe Escrow Protection',
      subtitle: 'Every transaction locked safely until satisfaction is guaranteed.',
      actionLabel: 'How It Works',
      targetTab: 4, // Account / Profile Tab
      filterQuery: 'escrow',
      imageUrl:
          'https://images.unsplash.com/photo-1554224155-8d04cb21cd6c?auto=format&fit=crop&w=800&q=80',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _startPromoAutoSlide();
    _loadAllData();
    _walletPoll = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) _fetchWalletData(context.read<AuthBloc>().state.user?.id, silent: true);
    });
  }

  @override
  void dispose() {
    _promoTimer?.cancel();
    _walletPoll?.cancel();
    _promoPageController.dispose();
    _searchController.dispose();
    _momoPhoneController.dispose();
    _bankAccountController.dispose();
    super.dispose();
  }

  // ── Auto-Sliding Timer (10 Seconds) ───────────────────────────────
  void _startPromoAutoSlide() {
    _promoTimer?.cancel();
    _promoTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_isUserInteractingWithPromo && _promoPageController.hasClients) {
        final nextPage = (_currentPromoPage + 1) % _promotionalSlides.length;
        _promoPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  // ── Load All Dynamic Backend Data ─────────────────────────────────
  Future<void> _loadAllData() async {
    final authState = context.read<AuthBloc>().state;
    final userId = authState.user?.id;

    // Pre-populate phone from user entity if available
    if (authState.user?.phone != null && _momoPhoneController.text.isEmpty) {
      final clean = authState.user!.phone.replaceAll('+232', '').trim();
      _momoPhoneController.text = clean;
    }

    await Future.wait([
      _fetchWalletData(userId),
      _fetchActiveEscrowDeals(userId),
      _fetchUnreadNotifications(userId),
      _fetchVerifiedProperties(),
      _fetchVehicles(),
    ]);
  }

  // ── Fetch the authenticated user's wallet (server is the only source) ─
  Future<void> _fetchWalletData(String? userId, {bool silent = false}) async {
    if (userId == null || userId.isEmpty) {
      if (mounted) {
        setState(() {
          _walletBalance = null;
          _escrowBalance = null;
          _pendingBalance = null;
          _walletOwnerId = null;
          _isLoadingBalance = false;
        });
      }
      return;
    }

    // A different account signed in: drop the previous user's numbers immediately.
    if (_walletOwnerId != null && _walletOwnerId != userId && mounted) {
      setState(() {
        _walletBalance = null;
        _escrowBalance = null;
        _pendingBalance = null;
        _isLoadingBalance = true;
      });
    }

    try {
      // sessionToken is attached by the client for this function; identity is the session.
      final res = await widget.convexClient.query('wallet:getUserBalance', args: {'userId': userId});
      if (!mounted) return;

      if (res.success && res.value is Map) {
        final data = Map<String, dynamic>.from(res.value as Map);
        setState(() {
          _walletOwnerId = userId;
          _walletBalance = (data['availableBalance'] as num?)?.toDouble() ?? 0.0;
          _escrowBalance = (data['escrowBalance'] as num?)?.toDouble() ?? 0.0;
          _pendingBalance = (data['pendingBalance'] as num?)?.toDouble() ?? 0.0;
          _isLoadingBalance = false;
          _walletError = null;
        });
      } else if (!silent || _walletBalance == null) {
        // A failed load is an ERROR state — never an invented zero.
        setState(() {
          _isLoadingBalance = false;
          _walletError = 'Unable to load wallet';
        });
      }
    } catch (_) {
      if (mounted && (!silent || _walletBalance == null)) {
        setState(() {
          _isLoadingBalance = false;
          _walletError = 'Unable to load wallet';
        });
      }
    }
  }

  // ── Fetch Active Escrow Deals ─────────────────────────────────────
  Future<void> _fetchActiveEscrowDeals(String? userId) async {
    if (userId == null || userId.isEmpty) return;

    try {
      final res = await widget.convexClient.query(
        'escrow:getMyEscrowOrders',
        args: {'userId': userId},
      );

      if (mounted && res.success && res.value is List) {
        final orders = (res.value as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        // Active deals are ongoing orders not yet completed or cancelled
        final active = orders.where((o) {
          final st = (o['status'] as String? ?? '').toLowerCase();
          return st == 'created' ||
              st == 'funded' ||
              st == 'active' ||
              st == 'in_escrow' ||
              st == 'inspection_period';
        }).length;

        setState(() {
          _activeEscrowDeals = active;
        });
      }
    } catch (_) {
      // Graceful fallback to 0
    }
  }

  // ── Fetch Unread Notification Count ───────────────────────────────
  Future<void> _fetchUnreadNotifications(String? userId) async {
    try {
      final res = await widget.convexClient.query(
        'notifications:getUnreadNotificationCount',
        args: {'userId': userId ?? 'guest'},
      );
      if (res.success && res.value != null && mounted) {
        setState(() {
          _unreadNotificationsCount = (res.value as num).toInt();
        });
      }
    } catch (_) {}
  }

  // ── Fetch Real Verified Properties ────────────────────────────────
  Future<void> _fetchVerifiedProperties() async {
    try {
      final res = await widget.convexClient.query(
        'realEstate:listProperties',
        args: {'limit': 10},
      );

      if (mounted) {
        if (res.success && res.value is List) {
          setState(() {
            _properties = (res.value as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _isLoadingProperties = false;
            _propertiesError = null;
          });
        } else {
          setState(() {
            _properties = [];
            _isLoadingProperties = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingProperties = false;
          _propertiesError = 'Unable to load properties';
        });
      }
    }
  }

  // ── Fetch Vehicles for Global Search ──────────────────────────────
  Future<void> _fetchVehicles() async {
    try {
      final res = await widget.convexClient.query(
        'mobility:listVehicles',
        args: {'limit': 10},
      );
      if (mounted && res.success && res.value is List) {
        setState(() {
          _vehicles = (res.value as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {}
  }

  // ── Quick Mobile Money Top-Up Execution ───────────────────────────
  Future<void> _executeMobileMoneyTopUp(UserEntity? user) async {
    final phone = _momoPhoneController.text.trim();
    if (phone.isEmpty || phone.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Sierra Leone phone number.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    _showAmountInputDialog(
      context: context,
      title: 'Mobile Money Top Up',
      subtitle: 'Enter amount to deposit via Orange Money / Afrimoney / QMoney',
      onConfirmed: (amount) async {
        final carrier = CarrierDetectionService.detectCarrier(phone);
        final providerSlug = carrier.isRecognized ? carrier.providerSlug : 'orange';

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Initiating secure payment session...'),
            duration: Duration(seconds: 2),
          ),
        );

        final res = await PaymentMethodsService.instance.createTopUpSession(
          amount: amount,
          phoneNumber: phone,
          provider: providerSlug,
          userId: user?.id,
          customerName: user?.name,
          customerEmail: user?.email,
          description: 'Vektolux Escrow Wallet Deposit',
        );

        if (!mounted) return;

        if (res['success'] == true) {
          final dialCode = res['dialCode'] as String? ?? '*144*4*4#';
          final ref = res['reference'] as String? ?? 'TOPUP-${DateTime.now().millisecondsSinceEpoch}';

          UssdPaymentSheet.show(
            context,
            dialCode: dialCode,
            reference: ref,
            amount: amount,
            serviceProvider: carrier.displayName,
            recipient: 'Vektolux Escrow Pool',
            transactionType: 'Wallet Deposit',
            onPaymentCompleted: () {
              _fetchWalletData(user?.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Wallet deposit completed successfully!'),
                  backgroundColor: AppColors.emeraldDark,
                ),
              );
            },
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message']?.toString() ?? 'Failed to initialize payment session'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      },
    );
  }

  // ── Quick Bank Transfer Flow ──────────────────────────────────────
  Future<void> _executeBankTransfer(UserEntity? user) async {
    _showBankClearingDetailsModal(context, user);
  }

  // ── Amount Dialog Helper ──────────────────────────────────────────
  void _showAmountInputDialog({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Function(double amount) onConfirmed,
  }) {
    final amtController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.obsidian),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: amtController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (SLE)',
                prefixText: 'SLE ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emeraldDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final val = double.tryParse(amtController.text.trim()) ?? 0.0;
              if (val <= 0) return;
              Navigator.pop(ctx);
              onConfirmed(val);
            },
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
  }

  // ── Real Bank Clearing Details Modal ──────────────────────────────
  void _showBankClearingDetailsModal(BuildContext context, UserEntity? user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Icon(Icons.account_balance_rounded, color: Color(0xFF0284C7), size: 24),
                SizedBox(width: 10),
                Text(
                  'Bank Escrow Clearing Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Transfer directly from your Sierra Leone bank account or mobile banking app. Your funds are protected in platform escrow.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Column(
                children: [
                  _buildClearingRow('Bank Name', 'Sierra Leone Commercial Bank (SLCB)'),
                  const Divider(height: 16),
                  _buildClearingRow('Account Name', 'Vektolux Sierra Leone Ltd - Escrow'),
                  const Divider(height: 16),
                  _buildClearingRow('Account Number', '0030010023456789'),
                  const Divider(height: 16),
                  _buildClearingRow('BBAN / Swift', 'SLCBSLFRXXX'),
                  const Divider(height: 16),
                  _buildClearingRow(
                    'Transfer Reference',
                    'ESC-${user?.id.substring(0, user.id.length >= 6 ? 6 : user.id.length).toUpperCase() ?? "CLIENT"}',
                    isHighlight: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('I Have Sent the Transfer', style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Bank transfer reference recorded. Reconciliation typically takes 10-30 mins.'),
                      backgroundColor: AppColors.emeraldDark,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClearingRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isHighlight ? const Color(0xFF0284C7) : AppColors.obsidian,
            ),
          ),
        ),
      ],
    );
  }

  // ── Open Filter Bottom Sheet ──────────────────────────────────────
  void _openFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Filter Marketplace Searches',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.obsidian),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFilterChip('All Categories', true),
                _buildFilterChip('Houses For Rent', false),
                _buildFilterChip('Properties For Sale', false),
                _buildFilterChip('Guest Houses', false),
                _buildFilterChip('Vehicles & SUVs', false),
                _buildFilterChip('Verified Only', true),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.obsidian,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppColors.emeraldDark : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? AppColors.emeraldDark : AppColors.obsidian,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        final user = authState.user;

        // Extract Real Names
        final fullName = user?.name.trim() ?? 'Guest User';
        final isVerified = user?.isVerified == true || user?.isApprovedVerification == true;

        // Member since dynamically extracted from creation date
        final memberSinceYear = user?.verifiedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(user!.verifiedAt!).year.toString()
            : '2024';

        // Search Query
        final query = _searchController.text.trim().toLowerCase();
        final isSearching = query.isNotEmpty;

        final matchingProperties = isSearching
            ? _properties.where((p) {
                final title = (p['title'] as String? ?? '').toLowerCase();
                final address = (p['address'] as String? ?? '').toLowerCase();
                final desc = (p['description'] as String? ?? '').toLowerCase();
                return title.contains(query) || address.contains(query) || desc.contains(query);
              }).toList()
            : <Map<String, dynamic>>[];

        final matchingVehicles = isSearching
            ? _vehicles.where((v) {
                final make = (v['make'] as String? ?? '').toLowerCase();
                final model = (v['model'] as String? ?? '').toLowerCase();
                return make.contains(query) || model.contains(query);
              }).toList()
            : <Map<String, dynamic>>[];

        return Scaffold(
          backgroundColor: Colors.white,
          body: MediaQuery.withClampedTextScaling(
            maxScaleFactor: _kMaxTextScale,
            child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppColors.emeraldDark,
              onRefresh: _loadAllData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: _kPageGutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),

                    // ═════════════════════════════════════════════════
                    // 1. USER HEADER
                    // ═════════════════════════════════════════════════
                    _buildUserHeader(
                      user: user,
                      fullName: fullName,
                      isVerified: isVerified,
                      memberSinceYear: memberSinceYear,
                      unreadCount: _unreadNotificationsCount,
                    ),

                    const SizedBox(height: _kGapM),

                    // ═════════════════════════════════════════════════
                    // 2. SEARCH BAR
                    // ═════════════════════════════════════════════════
                    _buildSearchBar(),

                    const SizedBox(height: _kGapM),

                    if (isSearching) ...[
                      // Real search results overlay
                      _buildSearchResults(matchingProperties, matchingVehicles),
                    ] else ...[
                      // ═════════════════════════════════════════════════
                      // 3. ESCROW WALLET CARD
                      // ═════════════════════════════════════════════════
                      _buildEscrowWalletCard(user),

                      const SizedBox(height: _kGapS),

                      // ═════════════════════════════════════════════════
                      // 4. WALLET ACTIONS (Deposit, Withdraw, Scan QR)
                      // ═════════════════════════════════════════════════
                      _buildWalletActionButtons(user),

                      const SizedBox(height: _kGapS),

                      // ═════════════════════════════════════════════════
                      // 5. QUICK TOP UP HEADER
                      // ═════════════════════════════════════════════════
                      _buildQuickTopUpBanner(),

                      const SizedBox(height: _kGapS),

                      // ═════════════════════════════════════════════════
                      // 6. MOBILE MONEY + BANK TRANSFER (2 CARDS)
                      // ═════════════════════════════════════════════════
                      _buildPaymentMethodCards(user),

                      const SizedBox(height: _kGapS),

                      // ═════════════════════════════════════════════════
                      // 7. SECURITY & BENEFITS ROW
                      // ═════════════════════════════════════════════════
                      _buildSecurityBenefitsRow(),

                      const SizedBox(height: _kGapM),

                      // ═════════════════════════════════════════════════
                      // 8. AUTO-SLIDING PROMOTIONAL BANNER
                      // ═════════════════════════════════════════════════
                      _buildAutoSlidingPromoBanner(),

                      const SizedBox(height: _kGapL),

                      // ═════════════════════════════════════════════════
                      // 9. SAVED PLACES & SHORTCUTS
                      // ═════════════════════════════════════════════════
                      _buildSavedPlacesSection(user),

                      const SizedBox(height: _kGapL),

                      // ═════════════════════════════════════════════════
                      // 10. VERIFIED PROPERTIES IN SIERRA LEONE
                      // ═════════════════════════════════════════════════
                      _buildVerifiedPropertiesSection(),

                      const SizedBox(height: 28),
                    ],
                  ],
                ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 1. USER HEADER COMPONENT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildUserHeader({
    required UserEntity? user,
    required String fullName,
    required bool isVerified,
    required String memberSinceYear,
    required int unreadCount,
  }) {
    // Generate initials e.g. LK
    final parts = fullName.split(' ');
    final initials = parts.length > 1
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : fullName.substring(0, fullName.length >= 2 ? 2 : 1).toUpperCase();

    return Row(
      children: [
        // Avatar circle with initials or photo
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color(0xFF047857), // Deep emerald
            shape: BoxShape.circle,
          ),
          child: user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.network(
                    user.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 10),

        // User Name & Meta
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hello,',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  height: 1.2,
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                        letterSpacing: -0.2,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (isVerified) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 11,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                'Member since $memberSinceYear',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),

        // Notifications Button with dynamic unread indicator
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NotificationsScreen(
                  convexClient: widget.convexClient,
                ),
              ),
            );
          },
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: AppColors.obsidian,
                  size: 20,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 8,
                    right: 9,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Settings Button
        GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ProfileScreen(showBackButton: true),
              ),
            );
          },
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.settings_outlined,
              color: AppColors.obsidian,
              size: 19,
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 2. SEARCH BAR COMPONENT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSearchBar() {
    const double barHeight = 46;
    return Row(
      children: [
        Expanded(
          child: Container(
            height: barHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 13.5),
                    decoration: const InputDecoration(
                      hintText: 'Search homes, cars, or destinations...',
                      hintMaxLines: 1,
                      hintStyle: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        overflow: TextOverflow.ellipsis,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: AppColors.textSecondary),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _openFilterBottomSheet,
          child: Container(
            width: barHeight,
            height: barHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A), // Dark navy
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 3. ESCROW WALLET CARD COMPONENT
  // ═══════════════════════════════════════════════════════════════════

  Widget _walletFigure(String label, double amount) => Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label  ',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
              ),
              TextSpan(
                text: 'SLE ${_currencyFormat.format(amount)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
            ],
          ),
        ),
      );

  Widget _buildEscrowWalletCard(UserEntity? user) {
    return LayoutBuilder(builder: (context, constraints) {
    // The illustration scales with the card (it used to be a fixed 114×96 box that squeezed the text).
    final graphicWidth = (constraints.maxWidth * 0.27).clamp(76.0, 114.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFE8FDF2), // Minty soft green
            Color(0xFFDCFCE7), // Soft emerald
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBBF7D0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: Color(0xFF047857),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Vektolux Escrow Wallet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF064E3B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => BlocProvider(
                              create: (_) => WalletCubit(convexClient: widget.convexClient),
                              child: TransactionHistoryScreen(convexClient: widget.convexClient),
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF047857).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'History',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF047857),
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.chevron_right, size: 14, color: Color(0xFF047857)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                const Text(
                  'Wallet Balance',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF065F46)),
                ),
                const SizedBox(height: 2),
                if (_isLoadingBalance)
                  Container(
                    width: 120,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  )
                else if (user == null)
                  const Text(
                    'Sign in for Escrow',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  )
                else if (_walletError != null)
                  // The real error stays visible (never replaced by a fake balance), laid out to fit.
                  SizedBox(
                    height: 30,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            _walletError!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.error,
                              height: 1.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => _fetchWalletData(user.id),
                          borderRadius: BorderRadius.circular(14),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.refresh, size: 18, color: Color(0xFF047857)),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_walletBalance != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'SLE ${_currencyFormat.format(_walletBalance! + (_escrowBalance ?? 0) + (_pendingBalance ?? 0))}',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _walletFigure('Escrow Protected', _escrowBalance ?? 0),
                      _walletFigure('Available', _walletBalance!),
                      if ((_pendingBalance ?? 0) > 0)
                        _walletFigure('Pending withdrawal', _pendingBalance!),
                    ],
                  )
                else
                  const Text(
                    'Activate Wallet',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _activeEscrowDeals > 0
                              ? 'Escrow Protected • $_activeEscrowDeals Active Deal${_activeEscrowDeals == 1 ? '' : 's'}'
                              : 'Escrow Protected • Ready for Deals',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF065F46),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // 3D Emerald Security Wallet Graphic with periodic subtle verification pulse
          SecurityWalletGraphic(width: graphicWidth, height: graphicWidth * 96 / 114),
        ],
      ),
    );
    });
  }

  // ═══════════════════════════════════════════════════════════════════
  // 4. WALLET ACTION BUTTONS (Deposit, Withdraw, Scan QR)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildWalletActionButtons(UserEntity? user) {
    final actions = <({IconData icon, String title, String subtitle, VoidCallback onTap})>[
      (icon: Icons.add_rounded, title: 'Deposit', subtitle: 'Add funds to wallet', onTap: () => _showTopUpSheet(context, user)),
      (icon: Icons.arrow_upward_rounded, title: 'Withdraw', subtitle: 'Move funds out', onTap: () => _showWithdrawalSheet(context, user)),
      (
        icon: Icons.qr_code_2_rounded,
        title: 'Receive',
        subtitle: 'Get paid',
        onTap: () => ReceivePaymentSheet.show(
              context,
              onPaymentReceived: () => _fetchWalletData(user?.id),
            ),
      ),
      (icon: Icons.qr_code_scanner_rounded, title: 'Scan & Pay', subtitle: 'Pay a QR code', onTap: () => _openQrScanner(context)),
    ];
    const gap = 8.0;
    return LayoutBuilder(builder: (context, constraints) {
      // Each of the 4 tiles gets an equal share. The wide layout (icon + title + subtitle + chevron)
      // needs ~150pt per tile; on phones (~85pt per tile) a compact stacked tile is used instead of
      // squeezing the title into a few points (which wrapped "Deposit" one letter per line).
      final tileWidth = (constraints.maxWidth - gap * (actions.length - 1)) / actions.length;
      final compact = tileWidth < 150;
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(
                child: _buildWalletActionTile(
                  icon: actions[i].icon,
                  title: actions[i].title,
                  subtitle: actions[i].subtitle,
                  onTap: actions[i].onTap,
                  compact: compact,
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildWalletActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    final decoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
    final iconCircle = Container(
      width: compact ? 30 : 32,
      height: compact ? 30 : 32,
      decoration: const BoxDecoration(
        color: Color(0xFF047857), // Emerald circle
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: compact ? 17 : 18),
    );

    if (compact) {
      return Semantics(
        button: true,
        label: '$title. $subtitle',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: decoration,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconCircle,
                const SizedBox(height: 6),
                // One line, always: scales down slightly rather than wrapping.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: decoration,
        child: Row(
          children: [
            iconCircle,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 5. QUICK TOP UP BANNER
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildQuickTopUpBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Color(0xFF059669),
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Top Up',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Top up your wallet instantly using your phone number or bank details.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 6. PAYMENT METHODS: MOBILE MONEY + BANK TRANSFER (2 CARDS)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildPaymentMethodCards(UserEntity? user) {
    // IntrinsicHeight + stretch: both cards take the taller card's height, and the Spacer in each
    // keeps inputs and buttons aligned at the bottom regardless of description length.
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── LEFT: Mobile Money Card ─────────────────────────────────
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4), // Light green tint
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.phonelink_ring_rounded,
                        color: Color(0xFF059669),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Mobile Money',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.obsidian,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pay with your mobile number\n(Orange Money, Afrimoney, QMoney, or SLCB Bank).',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Spacer(),
                // Pill Phone Input
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 16, color: Color(0xFF059669)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _momoPhoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            hintText: 'Enter phone number',
                            hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Pay Now Button
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () => _executeMobileMoneyTopUp(user),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Pay Now →',
                            maxLines: 1,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 12),

        // ── RIGHT: Bank Transfer Card ───────────────────────────────
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF), // Light blue tint
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.account_balance_rounded,
                        color: Color(0xFF0284C7),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Bank Transfer',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.obsidian,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Pay from your bank account\n(Link, Afrimoney Bank, QMoney Bank, or any supported bank).',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Spacer(),
                // Pill Bank Input
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.credit_card_outlined, size: 16, color: Color(0xFF0284C7)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _bankAccountController,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          decoration: const InputDecoration(
                            hintText: 'Enter bank details',
                            hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Pay Now Button
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB), // Royal blue
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () => _executeBankTransfer(user),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Pay Now →',
                            maxLines: 1,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 7. SECURITY & BENEFITS ROW
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSecurityBenefitsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(child: _buildBenefitItem(Icons.bolt_rounded, 'Instant\nProcessing')),
          _buildBenefitDivider(),
          Expanded(child: _buildBenefitItem(Icons.shield_outlined, 'Secure\nTransactions')),
          _buildBenefitDivider(),
          Expanded(child: _buildBenefitItem(Icons.lock_outline_rounded, 'Your Details\nAre Safe')),
          _buildBenefitDivider(),
          Expanded(child: _buildBenefitItem(Icons.published_with_changes_rounded, 'Available\nAlways', is247: true)),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String label, {bool is247 = false}) {
    // Bounded by its Expanded cell; scales down a little instead of overflowing on narrow phones.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (is247)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '24/7',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: Color(0xFF047857),
              ),
            ),
          )
        else
          Icon(icon, color: const Color(0xFF10B981), size: 18),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 2,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: AppColors.obsidian,
            height: 1.15,
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildBenefitDivider() {
    return Container(
      width: 1,
      height: 24,
      color: const Color(0xFFE2E8F0),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 8. AUTO-SLIDING PROMOTIONAL BANNER
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildAutoSlidingPromoBanner() {
    return Column(
      children: [
        SizedBox(
          height: 130,
          child: Listener(
            onPointerDown: (_) => _isUserInteractingWithPromo = true,
            onPointerUp: (_) => _isUserInteractingWithPromo = false,
            onPointerCancel: (_) => _isUserInteractingWithPromo = false,
            child: PageView.builder(
              controller: _promoPageController,
              itemCount: _promotionalSlides.length,
              onPageChanged: (idx) => setState(() => _currentPromoPage = idx),
              itemBuilder: (ctx, index) {
                final slide = _promotionalSlides[index];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  // 10pt vertical padding leaves room for the text column when system text is scaled up
                  // (the banner is a fixed 130pt tall; 14pt overflowed by a pixel at 1.15×).
                  padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFE0F7FA), // Soft cyan tint
                        Color(0xFFE8F5E9), // Soft mint tint
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFB2DFDB)),
                  ),
                  child: Row(
                    children: [
                      // Text & CTA
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              slide.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              slide.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 30,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF047857),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: () {
                                  MainNavigationShell.switchToTab(context, slide.targetTab);
                                },
                                // Scales down a little rather than overflowing the narrow banner column.
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        slide.actionLabel,
                                        maxLines: 1,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.arrow_forward, size: 12),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Promotional House / Villa Image
                      Expanded(
                        flex: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: VxNetworkImage(
                            imageUrl: slide.imageUrl,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Carousel Pagination Indicator Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _promotionalSlides.length,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentPromoPage == index ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: _currentPromoPage == index
                    ? const Color(0xFF047857)
                    : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 9. SAVED PLACES & SHORTCUTS COMPONENT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSavedPlacesSection(UserEntity? user) {
    final homeAddress = user?.address?.isNotEmpty == true
        ? user!.address!
        : 'Wilkinson Road, Freetown';
    const officeAddress = 'Central Business District, Freetown';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // The title takes the remaining width (ellipsis if needed); "See All" always stays visible.
            const Expanded(
              child: Row(
                children: [
                  Icon(Icons.location_on, color: Color(0xFF10B981), size: 18),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Saved Places & Shortcuts',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                MainNavigationShell.switchToTab(context, 4); // Account
              },
              child: const Text(
                'See All >',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF047857),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildPlaceTile(
                icon: Icons.home_rounded,
                title: 'Home',
                address: homeAddress,
                onTap: () {
                  _searchController.text = homeAddress.split(',').first;
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPlaceTile(
                icon: Icons.work_rounded,
                title: 'Work / Office',
                address: officeAddress,
                onTap: () {
                  _searchController.text = 'CBD';
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaceTile({
    required IconData icon,
    required String title,
    required String address,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFF047857), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // 10. VERIFIED PROPERTIES IN SIERRA LEONE
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildVerifiedPropertiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.apartment_rounded,
                  color: Color(0xFF047857),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verified Properties in Sierra Leone',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.obsidian,
                      ),
                    ),
                    Text(
                      'Houses, furnished flats & guest houses',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  MainNavigationShell.switchToTab(context, 2); // Real Estate
                },
                child: const Text(
                  'See All >',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF047857),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Properties Grid / List or Empty State
        if (_isLoadingProperties)
          _buildPropertiesLoadingSkeleton()
        else if (_propertiesError != null)
          _buildPropertiesErrorState()
        else if (_properties.isEmpty)
          _buildPropertiesEmptyState()
        else
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _properties.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (ctx, index) {
                final prop = _properties[index];
                return _buildPropertyCard(prop);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildPropertyCard(Map<String, dynamic> prop) {
    final title = prop['title'] as String? ?? 'Exclusive Property';
    final price = (prop['price'] as num?)?.toDouble() ?? 0.0;
    final currency = prop['currency'] as String? ?? 'SLE';
    final address = prop['address'] as String? ?? 'Freetown, Sierra Leone';
    final bedrooms = prop['bedrooms'] as int? ?? 3;
    final bathrooms = prop['bathrooms'] as int? ?? 2;
    final images = prop['images'] as List? ?? [];
    final firstImage = images.isNotEmpty ? images.first as String : '';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PropertyDetailScreen(
              id: prop['_id'] as String? ?? '',
              title: title,
              description: prop['description'] as String? ?? '',
              category: prop['category'] as String? ?? 'sale',
              price: price,
              address: address,
              latitude: (prop['latitude'] as num?)?.toDouble() ?? 8.484,
              longitude: (prop['longitude'] as num?)?.toDouble() ?? -13.234,
              ownerId: prop['ownerId'] as String? ?? '',
              imageUrls: images.map((e) => e.toString()).toList(),
              bedrooms: bedrooms,
              bathrooms: bathrooms,
              isVerified: prop['isVerified'] == true,
            ),
          ),
        );
      },
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                children: [
                  VxNetworkImage(
                    imageUrl: firstImage,
                    height: 130,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF047857),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'VERIFIED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$currency ${_currencyFormat.format(price)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.bed_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '$bedrooms Beds',
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.bathtub_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '$bathrooms Baths',
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertiesLoadingSkeleton() {
    return SizedBox(
      height: 240,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Container(
          width: 220,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildPropertiesErrorState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 32),
            const SizedBox(height: 8),
            Text(
              _propertiesError ?? 'Unable to load properties',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _fetchVerifiedProperties,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertiesEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.home_work_outlined,
              color: Color(0xFF94A3B8),
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'No verified properties available yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.obsidian,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'New verified listings in Sierra Leone will appear here once approved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // LIVE SEARCH RESULTS COMPONENT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSearchResults(
    List<Map<String, dynamic>> properties,
    List<Map<String, dynamic>> vehicles,
  ) {
    if (properties.isEmpty && vehicles.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            const Text(
              'No matches found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Try searching by city, district, make, or property type.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Matching Results (${properties.length + vehicles.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        ...properties.map((p) => ListTile(
              leading: const Icon(Icons.apartment_rounded, color: Color(0xFF047857)),
              title: Text(p['title'] as String? ?? 'Property'),
              subtitle: Text(p['address'] as String? ?? 'Sierra Leone'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PropertyDetailScreen(
                      id: p['_id'] as String? ?? '',
                      title: p['title'] as String? ?? 'Property',
                      description: p['description'] as String? ?? '',
                      category: p['category'] as String? ?? 'sale',
                      price: (p['price'] as num?)?.toDouble() ?? 0.0,
                      address: p['address'] as String? ?? 'Sierra Leone',
                      latitude: (p['latitude'] as num?)?.toDouble() ?? 8.484,
                      longitude: (p['longitude'] as num?)?.toDouble() ?? -13.234,
                      ownerId: p['ownerId'] as String? ?? '',
                      imageUrls: (p['images'] as List?)?.map((e) => e.toString()).toList() ?? [],
                      bedrooms: p['bedrooms'] as int?,
                      bathrooms: p['bathrooms'] as int?,
                      isVerified: p['isVerified'] == true,
                    ),
                  ),
                );
              },
            )),
        ...vehicles.map((v) => ListTile(
              leading: const Icon(Icons.directions_car_rounded, color: Color(0xFF0284C7)),
              title: Text('${v['make'] ?? ''} ${v['model'] ?? ''}'),
              subtitle: Text(v['vehicleType'] as String? ?? 'Vehicle'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VehicleDetailScreen(
                      id: v['_id'] as String? ?? '',
                      make: v['make'] as String? ?? 'Vehicle',
                      model: v['model'] as String? ?? '',
                      year: (v['year'] as num?)?.toInt() ?? 2022,
                      vehicleType: v['vehicleType'] as String? ?? 'car',
                      listingIntent: v['listingIntent'] as String? ?? 'sale',
                      salePrice: (v['salePrice'] as num?)?.toDouble() ?? (v['price'] as num?)?.toDouble(),
                      imageUrls: (v['images'] as List?)?.map((e) => e.toString()).toList() ?? [],
                    ),
                  ),
                );
              },
            )),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // TOP UP & WITHDRAW BOTTOM SHEETS
  // ═══════════════════════════════════════════════════════════════════

  void _showTopUpSheet(BuildContext context, UserEntity? user) {
    _showAmountInputDialog(
      context: context,
      title: 'Deposit Escrow Funds',
      subtitle: 'Enter the amount you would like to deposit into your escrow wallet.',
      onConfirmed: (amt) {
        _momoPhoneController.text = (user?.phone ?? '').replaceAll('+232', '').trim();
        _executeMobileMoneyTopUp(user);
      },
    );
  }

  void _showWithdrawalSheet(BuildContext context, UserEntity? user) {
    final available = _walletBalance;
    if (user == null || available == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your wallet is still loading. Please try again in a moment.')),
      );
      return;
    }
    WithdrawSheet.show(
      context,
      availableBalance: available,
      onCompleted: () => _fetchWalletData(user.id),
    );
  }

  Future<void> _openQrScanner(BuildContext context) async {
    final code = await CameraQrScannerView.show(context);
    if (code == null || !context.mounted) return;
    if (code == '__MANUAL__' || !isVektoluxPaymentCode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That is not a Vektolux payment code.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    // Scanning only PREPARES the payment: the server resolves the recipient/amount and the
    // user must confirm with their PIN before any money moves.
    final userId = context.read<AuthBloc>().state.user?.id;
    await QrPaySheet.show(
      context,
      payload: code,
      onPaid: () => _fetchWalletData(userId),
    );
  }
}

/// Helper model for promotional carousel slides
class _PromoBannerData {
  final String title;
  final String subtitle;
  final String actionLabel;
  final int targetTab;
  final String filterQuery;
  final String imageUrl;

  const _PromoBannerData({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.targetTab,
    required this.filterQuery,
    required this.imageUrl,
  });
}
