import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/network/convex_client_wrapper.dart';
import '../../../../../core/theme/app_colors.dart';

/// Modal bottom sheet presenting a Flot/MoniMe-styled USSD payment prompt,
/// automatically opening the native phone dialer with encoded `#` (%23),
/// and polling Convex for real-time completion.
class UssdPaymentSheet extends StatefulWidget {
  final String dialCode;
  final String reference;
  final double amount;
  final double serviceFee;
  final String serviceProvider;
  final String recipient;
  final String transactionType;
  final VoidCallback? onPaymentCompleted;
  final VoidCallback? onDismissed;

  const UssdPaymentSheet({
    super.key,
    required this.dialCode,
    required this.reference,
    required this.amount,
    this.serviceFee = 0.0,
    required this.serviceProvider,
    required this.recipient,
    this.transactionType = 'Wallet Deposit',
    this.onPaymentCompleted,
    this.onDismissed,
  });

  /// Static helper to display the sheet easily from any screen
  static Future<bool?> show(
    BuildContext context, {
    required String dialCode,
    required String reference,
    required double amount,
    double serviceFee = 0.0,
    required String serviceProvider,
    required String recipient,
    String transactionType = 'Wallet Deposit',
    VoidCallback? onPaymentCompleted,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UssdPaymentSheet(
        dialCode: dialCode,
        reference: reference,
        amount: amount,
        serviceFee: serviceFee,
        serviceProvider: serviceProvider,
        recipient: recipient,
        transactionType: transactionType,
        onPaymentCompleted: onPaymentCompleted,
      ),
    );
  }

  @override
  State<UssdPaymentSheet> createState() => _UssdPaymentSheetState();
}

class _UssdPaymentSheetState extends State<UssdPaymentSheet>
    with SingleTickerProviderStateMixin {
  final NumberFormat _currencyFmt = NumberFormat('#,##0.00', 'en_US');
  Timer? _pollingTimer;
  bool _isCompleted = false;
  bool _isDialing = false;
  int _pollCount = 0;
  static const int _maxPolls = 60; // 2 minutes (every 2s)

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  double get _totalDebit => widget.amount + widget.serviceFee;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );

    // 1. Auto-trigger native phone dialer immediately after frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerUssdDial();
      _startStatusPolling();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  /// Launch native carrier phone dialer with encoded '#' as '%23'
  Future<void> _triggerUssdDial() async {
    if (!mounted || widget.dialCode.isEmpty) return;

    setState(() => _isDialing = true);
    try {
      final cleanCode = widget.dialCode.trim();
      final encodedCode = cleanCode.replaceAll('#', '%23');
      final uri = Uri.parse('tel:$encodedCode');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        debugPrint('[USSD Dialer] Could not launch tel:$encodedCode');
      }
    } catch (e) {
      debugPrint('[USSD Dialer Error] $e');
    } finally {
      if (mounted) setState(() => _isDialing = false);
    }
  }

  /// Poll Convex and actively query MoniMe gateway for real-time completion
  void _startStatusPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted || _isCompleted) {
        timer.cancel();
        return;
      }

      _pollCount++;
      if (_pollCount > _maxPolls) {
        timer.cancel();
        return;
      }

      try {
        final client = context.read<ConvexClientWrapper>();

        // 1. Actively verify and settle with MoniMe gateway
        final settleRes = await client.action(
          'payments:verifyAndSettleMoniMePayment',
          args: {'reference': widget.reference},
        );

        if (settleRes.success && settleRes.value is Map) {
          final data = Map<String, dynamic>.from(settleRes.value as Map);
          final status = (data['status'] as String? ?? '').toLowerCase();
          final settled = data['settled'] == true;

          if (settled || status == 'completed' || status == 'success') {
            timer.cancel();
            _handleSuccess();
            return;
          } else if (status == 'failed') {
            timer.cancel();
            return;
          }
        }

        // 2. Secondary check against Convex database status query
        final res = await client.query(
          'payments:getPaymentStatus',
          args: {'reference': widget.reference},
        );

        if (res.success && res.value != null) {
          final data = Map<String, dynamic>.from(res.value as Map);
          final status = (data['status'] as String? ?? '').toLowerCase();

          if (status == 'completed' || status == 'success') {
            timer.cancel();
            _handleSuccess();
          } else if (status == 'failed') {
            timer.cancel();
          }
        }
      } catch (err) {
        debugPrint('[USSD Polling Error]: $err');
      }
    });
  }

  Future<void> _handleSuccess() async {
    if (!mounted || _isCompleted) return;

    setState(() => _isCompleted = true);
    _animController.forward();

    // Haptic vibration feedback
    await HapticFeedback.heavyImpact();

    // Notify listeners
    widget.onPaymentCompleted?.call();

    // Auto-dismiss after celebration
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _isCompleted ? _buildSuccessView() : _buildPromptView(),
      ),
    );
  }

  /// Main Flot/MoniMe prompt UI
  Widget _buildPromptView() {
    return Column(
      key: const ValueKey('prompt_view'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Drag handle
        Container(
          width: 44,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFCBD5E1),
            borderRadius: BorderRadius.circular(4),
          ),
        ),

        // Brand Icon & Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldSurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.phone_android_rounded,
                    color: AppColors.emerald,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Complete Your Payment',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.obsidian,
                  ),
                ),
              ],
            ),
            IconButton(
              onPressed: () {
                _pollingTimer?.cancel();
                widget.onDismissed?.call();
                Navigator.of(context).pop(false);
              },
              icon: const Icon(Icons.close_rounded, color: AppColors.gray500, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),

        const SizedBox(height: 6),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Approve the mobile money prompt on your phone with your PIN. Your Vektolux wallet is credited instantly.',
            style: TextStyle(fontSize: 12, color: AppColors.gray600),
          ),
        ),

        const SizedBox(height: 16),

        // ── Summary Card (Flot/MoniMe style) ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _buildSummaryRow('Transaction Type', widget.transactionType),
              const SizedBox(height: 8),
              _buildSummaryRow('Service', widget.serviceProvider, isProvider: true),
              const SizedBox(height: 8),
              _buildSummaryRow(
                'Amount',
                'SLE ${_currencyFmt.format(widget.amount)}',
              ),
              if (widget.serviceFee > 0) ...[
                const SizedBox(height: 8),
                _buildSummaryRow(
                  'Service Fee (1%)',
                  'SLE ${_currencyFmt.format(widget.serviceFee)}',
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: Color(0xFFE2E8F0)),
              ),
              _buildSummaryRow(
                'Total Debit',
                'SLE ${_currencyFmt.format(_totalDebit)}',
                isBold: true,
                isTotal: true,
              ),
              const SizedBox(height: 8),
              _buildSummaryRow('To', widget.recipient),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // ── Prominent USSD Code Display Card ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.emerald.withOpacity(0.4), width: 1.5),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bolt_rounded, size: 14, color: AppColors.emeraldDark),
                  const SizedBox(width: 4),
                  const Text(
                    'INSTANT AUTOMATIC SETTLEMENT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: AppColors.emeraldDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                widget.dialCode,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppColors.obsidian,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Funds are credited automatically upon entering your PIN.\nNo codes to copy or save!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.gray700, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.emerald,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Listening for carrier settlement...',
                    style: TextStyle(fontSize: 11, color: AppColors.gray600),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // ── One-Tap Dialer CTA Button ──
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _isDialing ? null : _triggerUssdDial,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.phone_in_talk_rounded, size: 20),
            label: Text(
              _isDialing ? 'Connecting Dialer...' : 'Re-open Phone Dialer',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Manual dismissal / dismiss button
        TextButton(
          onPressed: () {
            _pollingTimer?.cancel();
            widget.onDismissed?.call();
            Navigator.of(context).pop(false);
          },
          child: const Text(
            'I will dial later / Cancel',
            style: TextStyle(fontSize: 12, color: AppColors.gray500, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  /// Real-time Success Animation View
  Widget _buildSuccessView() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Padding(
        key: const ValueKey('success_view'),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.emerald, width: 2),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.emerald,
                size: 64,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Payment Confirmed!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.obsidian,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'SLE ${_currencyFmt.format(widget.amount)} has been successfully received.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.gray600),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.receipt_long_rounded, size: 16, color: AppColors.gray600),
                  const SizedBox(width: 6),
                  Text(
                    widget.reference,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: AppColors.obsidian,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    bool isTotal = false,
    bool isProvider = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 13 : 12,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
            color: isTotal ? AppColors.obsidian : AppColors.gray500,
          ),
        ),
        if (isProvider)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2F6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.obsidian,
              ),
            ),
          )
        else
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 15 : 12,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              color: isTotal ? AppColors.emeraldDark : AppColors.obsidian,
            ),
          ),
      ],
    );
  }
}
