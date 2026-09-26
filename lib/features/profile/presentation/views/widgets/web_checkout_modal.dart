import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/network/convex_client_wrapper.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../../../../core/theme/app_colors.dart';
import 'ussd_payment_sheet.dart';

/// Modal bottom sheet presenting an interactive Web Checkout confirmation
/// with real-time balance reactive polling and in-app browser trigger.
class WebCheckoutModal extends StatefulWidget {
  final String checkoutUrl;
  final String reference;
  final double amount;
  final String serviceProvider;
  final String recipient;
  final String userId;
  final String? dialCode;
  final VoidCallback? onPaymentConfirmed;

  const WebCheckoutModal({
    super.key,
    required this.checkoutUrl,
    required this.reference,
    required this.amount,
    required this.serviceProvider,
    required this.recipient,
    required this.userId,
    this.dialCode,
    this.onPaymentConfirmed,
  });

  /// Static helper to display the modal bottom sheet
  static Future<void> show(
    BuildContext context, {
    required String checkoutUrl,
    required String reference,
    required double amount,
    required String serviceProvider,
    required String recipient,
    required String userId,
    String? dialCode,
    VoidCallback? onPaymentConfirmed,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isDismissible: true,
      builder: (ctx) => WebCheckoutModal(
        checkoutUrl: checkoutUrl,
        reference: reference,
        amount: amount,
        serviceProvider: serviceProvider,
        recipient: recipient,
        userId: userId,
        dialCode: dialCode,
        onPaymentConfirmed: onPaymentConfirmed,
      ),
    );
  }

  @override
  State<WebCheckoutModal> createState() => _WebCheckoutModalState();
}

class _WebCheckoutModalState extends State<WebCheckoutModal>
    with SingleTickerProviderStateMixin {
  final ConvexClientWrapper _convex =
      ConvexClientWrapper(deploymentUrl: ApiConstants.convexUrl);
  Timer? _pollingTimer;
  bool _isSuccess = false;
  double? _initialBalance;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Launch in-app webview immediately
    _launchWebCheckout();

    // Start reactive ledger settlement polling
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _launchWebCheckout() async {
    final rawUrl = widget.checkoutUrl.trim();
    if (rawUrl.isEmpty || !rawUrl.startsWith('http')) return;

    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.inAppWebView,
        );
      }
    } catch (e) {
      debugPrint('[WebCheckoutModal] Launch in-app error, fallback external: $e');
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  void _startPolling() {
    // 1. Initial snapshot of balance
    _checkStatusAndBalance(isInitial: true);

    // 2. Poll every 2 seconds
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      _checkStatusAndBalance();
    });
  }

  Future<void> _checkStatusAndBalance({bool isInitial = false}) async {
    if (_isSuccess || !mounted) return;

    try {
      // A. Query wallet balance
      if (widget.userId.isNotEmpty) {
        final balRes = await _convex.query(
          'wallet:getUserBalance',
          args: {'userId': widget.userId, 'currency': 'SLE'},
        );
        if (balRes.success && balRes.value is Map) {
          final val = balRes.value as Map<String, dynamic>;
          final currBal = (val['availableBalance'] as num?)?.toDouble() ?? 0.0;

          if (isInitial) {
            _initialBalance = currBal;
          } else if (_initialBalance != null && currBal > _initialBalance!) {
            _handleSettlementSuccess();
            return;
          }
        }
      }

      // B. Actively verify and settle with MoniMe gateway
      final settleRes = await _convex.action(
        'payments:verifyAndSettleMoniMePayment',
        args: {
          'reference': widget.reference,
          if (widget.userId.isNotEmpty) 'userId': widget.userId,
        },
      );

      if (settleRes.success && settleRes.value is Map) {
        final val = settleRes.value as Map<String, dynamic>;
        final st = val['status']?.toString().toLowerCase();
        final settled = val['settled'] == true;
        if (settled || st == 'completed' || st == 'success') {
          _handleSettlementSuccess();
          return;
        }
      }

      // C. Query payment transaction status fallback
      final statusRes = await _convex.query(
        'payments:getPaymentStatus',
        args: {'reference': widget.reference},
      );

      if (statusRes.success && statusRes.value is Map) {
        final val = statusRes.value as Map<String, dynamic>;
        final st = val['status']?.toString().toLowerCase();
        if (st == 'completed' || st == 'success') {
          _handleSettlementSuccess();
        }
      }
    } catch (e) {
      debugPrint('[WebCheckoutModal] Polling error: $e');
    }
  }

  void _handleSettlementSuccess() {
    if (_isSuccess || !mounted) return;

    _pollingTimer?.cancel();
    HapticFeedback.heavyImpact();

    setState(() {
      _isSuccess = true;
    });

    widget.onPaymentConfirmed?.call();

    // Auto dismiss after 1800ms
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: bottomInset + 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isSuccess
              ? AppColors.emerald
              : AppColors.emerald.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          if (_isSuccess)
            BoxShadow(
              color: AppColors.emerald.withValues(alpha: 0.35),
              blurRadius: 30,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _isSuccess ? _buildSuccessView() : _buildPendingView(),
        ),
      ),
    );
  }

  Widget _buildPendingView() {
    final fee = widget.amount == 5 ? 0.05 : 0.10;
    final netCredit = (widget.amount - fee).clamp(0.0, double.infinity);

    return Column(
      key: const ValueKey('pending'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.gray700,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Header with pulsing indicator
        Row(
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.open_in_browser_rounded,
                  color: AppColors.emerald,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Complete Your Payment',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Authorize in the secure portal window',
                    style: TextStyle(
                      color: AppColors.gray400,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: AppColors.gray400),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.gray900,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.gray800,
            ),
          ),
          child: Column(
            children: [
              _buildSummaryRow('Transaction Type', 'Escrow Top-Up'),
              const Divider(color: AppColors.gray800, height: 16),
              _buildSummaryRow('Payment Rail', widget.serviceProvider),
              const Divider(color: AppColors.gray800, height: 16),
              _buildSummaryRow(
                'Top-Up Amount',
                'SLE ${widget.amount.toStringAsFixed(2)}',
              ),
              const Divider(color: AppColors.gray800, height: 16),
              _buildSummaryRow(
                'Service Fee',
                'SLE ${fee.toStringAsFixed(2)}',
              ),
              const Divider(color: AppColors.gray800, height: 16),
              _buildSummaryRow(
                'Net Credit to Wallet',
                'SLE ${netCredit.toStringAsFixed(2)}',
                valueColor: AppColors.emerald,
                isBold: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Real-time status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.emerald.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.emerald,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Awaiting instant carrier confirmation...',
                  style: TextStyle(
                    color: AppColors.emeraldLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _launchWebCheckout,
                icon: const Icon(Icons.launch_rounded, size: 18),
                label: const Text('Reopen Portal'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: AppColors.obsidian,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            if (widget.dialCode != null && widget.dialCode!.isNotEmpty) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  UssdPaymentSheet.show(
                    context,
                    dialCode: widget.dialCode!,
                    reference: widget.reference,
                    amount: widget.amount,
                    serviceFee: fee,
                    serviceProvider: widget.serviceProvider,
                    recipient: widget.recipient,
                    onPaymentCompleted: widget.onPaymentConfirmed,
                  );
                },
                icon: const Icon(Icons.dialpad_rounded, size: 18),
                label: const Text('Dial USSD'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.gray300,
                  side: const BorderSide(color: AppColors.gray700),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSuccessView() {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.emerald.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.emerald,
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: AppColors.emerald,
            size: 52,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Top-Up Confirmed!',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'SLE ${widget.amount.toStringAsFixed(2)} successfully credited to your wallet balance.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.gray300,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.gray400,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.white,
            fontSize: 13,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
