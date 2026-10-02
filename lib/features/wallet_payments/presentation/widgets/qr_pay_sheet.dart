// lib/features/wallet_payments/presentation/widgets/qr_pay_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// Scan & Pay.
//
// Scanning NEVER moves money. The scanned code is resolved read-only on the server
// (`qrPayment:resolveQR`) which returns the recipient's name and any fixed amount.
// Nothing shown here comes from the QR itself. Payment happens only after the
// payer reviews the details, enters their PIN and taps "Confirm & pay".
// The payment is idempotent (one key per attempt) and the receipt is shown only
// when the server reports success.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';

enum _PayPhase { resolving, invalid, confirm, success }

/// True when a scanned string is a Vektolux token payment code.
bool isVektoluxPaymentCode(String raw) {
  final t = raw.trim();
  return t.startsWith('vektolux://pay?r=') || t.contains('vektolux://pay?r=');
}

class QrPaySheet extends StatefulWidget {
  final String payload;
  final VoidCallback onPaid;

  const QrPaySheet({super.key, required this.payload, required this.onPaid});

  static Future<void> show(BuildContext context, {required String payload, required VoidCallback onPaid}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => QrPaySheet(payload: payload, onPaid: onPaid),
    );
  }

  @override
  State<QrPaySheet> createState() => _QrPaySheetState();
}

class _QrPaySheetState extends State<QrPaySheet> {
  final _fmt = NumberFormat('#,##0.00');
  final _amountCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  _PayPhase _phase = _PayPhase.resolving;
  String _invalidMessage = '';
  String? _error;
  bool _paying = false;
  bool _obscurePin = true;

  String _recipientName = '';
  bool _recipientVerified = false;
  double? _fixedAmount;
  String? _note;
  String _currency = 'SLE';

  // One idempotency key per payment attempt: a retry can never pay twice.
  String? _attemptKey;

  double? _paidAmount;
  String? _transactionId;
  DateTime? _paidAt;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    try {
      final client = context.read<ConvexClientWrapper>();
      final res = await client.query('qrPayment:resolveQR', args: {'payload': widget.payload});
      if (!mounted) return;
      if (!res.success || res.value is! Map) {
        setState(() {
          _phase = _PayPhase.invalid;
          _invalidMessage = res.errorMessage ?? 'Could not verify this payment code.';
        });
        return;
      }
      final v = Map<String, dynamic>.from(res.value as Map);
      if (v['valid'] != true) {
        setState(() {
          _phase = _PayPhase.invalid;
          _invalidMessage = v['message']?.toString() ?? 'This payment code cannot be used.';
        });
        return;
      }
      setState(() {
        _recipientName = v['recipientName']?.toString() ?? 'Recipient';
        _recipientVerified = v['recipientIsVerified'] == true;
        _fixedAmount = (v['fixedAmount'] as num?)?.toDouble();
        _note = v['note']?.toString();
        _currency = v['currency']?.toString() ?? 'SLE';
        _phase = _PayPhase.confirm;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _PayPhase.invalid;
        _invalidMessage = 'Connection problem. Please try scanning again.';
      });
    }
  }

  Future<void> _pay() async {
    final amount = _fixedAmount ?? double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount to pay.');
      return;
    }
    if (_pinCtrl.text.trim().length < 4) {
      setState(() => _error = 'Enter your security PIN to authorize this payment.');
      return;
    }
    setState(() {
      _paying = true;
      _error = null;
    });
    _attemptKey ??= const Uuid().v4();
    try {
      final client = context.read<ConvexClientWrapper>();
      final res = await client.mutation(
        'qrPayment:payQR',
        args: {
          'payload': widget.payload,
          if (_fixedAmount == null) 'amount': amount,
          'pin': _pinCtrl.text.trim(),
          'idempotencyKey': _attemptKey,
        },
      );
      if (!mounted) return;
      if (!res.success || res.value is! Map) {
        // Wrong PIN / insufficient funds / expired: nothing was paid.
        setState(() {
          _paying = false;
          _error = res.errorMessage ?? 'The payment could not be completed.';
        });
        return;
      }
      final v = Map<String, dynamic>.from(res.value as Map);
      widget.onPaid();
      setState(() {
        _paying = false;
        _paidAmount = (v['amount'] as num?)?.toDouble() ?? amount;
        _transactionId = v['transactionId']?.toString();
        _paidAt = DateTime.fromMillisecondsSinceEpoch(
          (v['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        );
        _phase = _PayPhase.success;
      });
    } catch (_) {
      if (!mounted) return;
      // Ambiguous: keep the key. Retrying is safe and cannot charge twice.
      setState(() {
        _paying = false;
        _error = 'Connection problem. Your payment may have gone through — check your '
            'transaction history, or tap confirm again (it will not charge twice).';
      });
    }
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
          _PayPhase.resolving => _buildResolving(),
          _PayPhase.invalid => _buildInvalid(),
          _PayPhase.confirm => _buildConfirm(),
          _PayPhase.success => _buildSuccess(),
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

  Widget _buildResolving() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );

  Widget _buildInvalid() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grabber(),
          const Icon(Icons.error_outline_rounded, size: 52, color: AppColors.error),
          const SizedBox(height: 10),
          const Text('Payment code unavailable',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
          const SizedBox(height: 6),
          Text(_invalidMessage,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.gray600)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          ),
        ],
      );

  Widget _buildConfirm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        const Text('Confirm payment',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paying', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(
                    child: Text(_recipientName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
                  ),
                  if (_recipientVerified) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified_rounded, size: 16, color: AppColors.emeraldDark),
                  ],
                ],
              ),
              if (_note != null && _note!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('“$_note”', style: const TextStyle(fontSize: 12, color: AppColors.gray600)),
              ],
              const SizedBox(height: 10),
              if (_fixedAmount != null) ...[
                const Text('Amount (set by recipient)', style: TextStyle(fontSize: 11, color: AppColors.gray500)),
                Text('$_currency ${_fmt.format(_fixedAmount)}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.emeraldDark)),
              ],
            ],
          ),
        ),
        if (_fixedAmount == null) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
            decoration: InputDecoration(
              labelText: 'Amount ($_currency)',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _pinCtrl,
          obscureText: _obscurePin,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: 'Security PIN',
            counterText: '',
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            suffixIcon: IconButton(
              icon: Icon(_obscurePin ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
              onPressed: () => setState(() => _obscurePin = !_obscurePin),
            ),
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _paying ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _paying ? null : _pay,
                child: _paying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Confirm & pay', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final when = _paidAt == null ? '' : DateFormat('d MMM yyyy, HH:mm').format(_paidAt!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _grabber(),
        const Icon(Icons.check_circle_rounded, size: 60, color: AppColors.emeraldDark),
        const SizedBox(height: 10),
        const Text('Payment sent',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
        const SizedBox(height: 6),
        Text('$_currency ${_fmt.format(_paidAmount ?? 0)}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.emeraldDark)),
        const SizedBox(height: 12),
        _kv('To', _recipientName),
        if (_transactionId != null) _kv('Transaction ID', _transactionId!),
        if (when.isNotEmpty) _kv('Date', when),
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
