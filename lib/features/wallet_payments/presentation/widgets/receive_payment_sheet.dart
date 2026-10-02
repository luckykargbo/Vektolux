// lib/features/wallet_payments/presentation/widgets/receive_payment_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// Receive Payment — generates a secure Vektolux payment QR.
//
// The QR contains ONLY an opaque server-issued token (vektolux://pay?r=<token>):
// no user id, phone, name, balance, secret or amount. The recipient and the
// (optional) fixed amount are resolved server-side when the payer scans.
// "Payment Received" is shown ONLY after the server reports the request as paid.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';

enum _ReceivePhase { form, qr, received }

class ReceivePaymentSheet extends StatefulWidget {
  final VoidCallback? onPaymentReceived;

  const ReceivePaymentSheet({super.key, this.onPaymentReceived});

  static Future<void> show(BuildContext context, {VoidCallback? onPaymentReceived}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ReceivePaymentSheet(onPaymentReceived: onPaymentReceived),
    );
  }

  @override
  State<ReceivePaymentSheet> createState() => _ReceivePaymentSheetState();
}

class _ReceivePaymentSheetState extends State<ReceivePaymentSheet> {
  final _fmt = NumberFormat('#,##0.00');
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  _ReceivePhase _phase = _ReceivePhase.form;
  bool _busy = false;
  String? _error;

  String? _token;
  String? _qrPayload;
  double? _fixedAmount;
  String _currency = 'SLE';

  Timer? _poll;
  String? _payerName;
  String? _transactionId;
  double? _paidAmount;

  @override
  void dispose() {
    _poll?.cancel();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final raw = _amountCtrl.text.trim();
    final amount = raw.isEmpty ? null : double.tryParse(raw);
    if (raw.isNotEmpty && (amount == null || amount <= 0)) {
      setState(() => _error = 'Enter a valid amount, or leave it empty to let the payer choose.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = context.read<ConvexClientWrapper>();
      final res = await client.mutation(
        'qrPayment:createReceiveQR',
        args: {
          if (amount != null) 'amount': amount,
          if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      if (!res.success || res.value is! Map) {
        setState(() {
          _busy = false;
          _error = res.errorMessage ?? 'Could not create the payment code.';
        });
        return;
      }
      final v = Map<String, dynamic>.from(res.value as Map);
      setState(() {
        _busy = false;
        _token = v['token']?.toString();
        _qrPayload = v['qrPayload']?.toString();
        _fixedAmount = (v['amount'] as num?)?.toDouble();
        _currency = v['currency']?.toString() ?? 'SLE';
        _phase = _ReceivePhase.qr;
      });
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _checkStatus());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Connection problem. Please try again.';
      });
    }
  }

  Future<void> _checkStatus() async {
    final token = _token;
    if (token == null || !mounted) return;
    try {
      final client = context.read<ConvexClientWrapper>();
      final res = await client.query('qrPayment:getMyQRStatus', args: {'token': token});
      if (!mounted || !res.success || res.value is! Map) return;
      final v = Map<String, dynamic>.from(res.value as Map);
      if (v['status'] == 'paid') {
        _poll?.cancel();
        setState(() {
          _payerName = v['payerName']?.toString();
          _transactionId = v['transactionId']?.toString();
          _paidAmount = (v['paidAmount'] as num?)?.toDouble() ?? _fixedAmount;
          _phase = _ReceivePhase.received;
        });
        widget.onPaymentReceived?.call();
      }
    } catch (_) {
      // transient — the next poll retries
    }
  }

  Future<void> _cancelRequest() async {
    final token = _token;
    _poll?.cancel();
    if (token != null) {
      try {
        await context.read<ConvexClientWrapper>().mutation('qrPayment:cancelReceiveQR', args: {'token': token});
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: switch (_phase) {
          _ReceivePhase.form => _buildForm(),
          _ReceivePhase.qr => _buildQr(),
          _ReceivePhase.received => _buildReceived(),
        },
      ),
    );
  }

  Widget _grabber() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: AppColors.gray300, borderRadius: BorderRadius.circular(2)),
        ),
      );

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        const Text('Receive payment',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
        const SizedBox(height: 4),
        const Text(
          'Create a secure QR code. The payer scans it, reviews the amount and confirms.',
          style: TextStyle(fontSize: 12, color: AppColors.gray500),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          decoration: InputDecoration(
            labelText: 'Amount (optional)',
            helperText: 'Leave empty to let the payer choose the amount',
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteCtrl,
          maxLength: 140,
          decoration: InputDecoration(
            labelText: 'Note (optional)',
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _busy ? null : _generate,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_2_rounded),
            label: const Text('Generate QR code', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildQr() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _grabber(),
        const Text('Scan to pay Vektolux',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
        const SizedBox(height: 4),
        Text(
          _fixedAmount != null
              ? 'Amount: $_currency ${_fmt.format(_fixedAmount)}'
              : 'The payer chooses the amount',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.emeraldDark),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: QrImageView(
            data: _qrPayload ?? '',
            size: 230,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 12),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Waiting for payment…', style: TextStyle(fontSize: 12, color: AppColors.gray500)),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'This code contains no account details. Payments appear in your transaction history.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.gray500),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _cancelRequest,
                child: const Text('Cancel request'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.obsidian, foregroundColor: Colors.white),
                onPressed: () {
                  _poll?.cancel();
                  Navigator.of(context).pop();
                },
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReceived() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _grabber(),
        const Icon(Icons.check_circle_rounded, size: 60, color: AppColors.emeraldDark),
        const SizedBox(height: 10),
        const Text('Payment Received',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
        const SizedBox(height: 6),
        Text(
          '$_currency ${_fmt.format(_paidAmount ?? 0)}',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.emeraldDark),
        ),
        const SizedBox(height: 12),
        if (_payerName != null) _kv('From', _payerName!),
        if (_transactionId != null) _kv('Transaction ID', _transactionId!),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.obsidian, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 12, color: AppColors.gray500)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.obsidian)),
            ),
          ],
        ),
      );
}
