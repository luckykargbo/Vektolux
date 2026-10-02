// lib/features/wallet_payments/presentation/widgets/withdraw_sheet.dart
// ═══════════════════════════════════════════════════════════════════════
// Withdraw funds — Mobile Money or Bank.
//
// The server is the only authority: this sheet only shows what
// `withdrawals:requestWithdrawal` reports. "Completed" is displayed ONLY when the
// server says the payout is confirmed; otherwise the request is shown as
// processing / pending. Only AVAILABLE funds can be withdrawn — funds protected
// in escrow are excluded by the backend.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';

enum _WithdrawPhase { form, result }

class WithdrawSheet extends StatefulWidget {
  /// The user's real available (withdrawable) balance, from the server.
  final double availableBalance;
  final String currency;
  final VoidCallback onCompleted;

  const WithdrawSheet({
    super.key,
    required this.availableBalance,
    required this.onCompleted,
    this.currency = 'SLE',
  });

  static Future<void> show(
    BuildContext context, {
    required double availableBalance,
    required VoidCallback onCompleted,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => WithdrawSheet(
        availableBalance: availableBalance,
        onCompleted: onCompleted,
      ),
    );
  }

  @override
  State<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<WithdrawSheet> {
  final _fmt = NumberFormat('#,##0.00');
  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  String _method = 'mobile_money';
  String _provider = 'orange';
  bool _submitting = false;
  bool _obscurePin = true;
  String? _error;
  _WithdrawPhase _phase = _WithdrawPhase.form;

  // One idempotency key per authorised attempt; reset after a definite failure.
  String? _attemptKey;

  String _resultStatus = 'processing';
  String _resultMessage = '';

  @override
  void dispose() {
    _amountCtrl.dispose();
    _phoneCtrl.dispose();
    _bankNameCtrl.dispose();
    _accountCtrl.dispose();
    _accountNameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountCtrl.text.trim()) ?? 0;

  String? _validate() {
    final amount = _amount;
    if (amount <= 0) return 'Enter an amount greater than 0.';
    if (amount > widget.availableBalance + 0.0001) {
      return 'You can withdraw at most ${widget.currency} ${_fmt.format(widget.availableBalance)} '
          '(funds held in escrow cannot be withdrawn).';
    }
    if (_method == 'mobile_money') {
      if (_phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length < 8) {
        return 'Enter a valid mobile money number.';
      }
    } else {
      if (_bankNameCtrl.text.trim().isEmpty) return 'Enter the bank name.';
      if (_accountCtrl.text.replaceAll(RegExp(r'\D'), '').length < 6) {
        return 'Enter a valid bank account number.';
      }
      if (_accountNameCtrl.text.trim().length < 2) return 'Enter the account holder name.';
    }
    if (_pinCtrl.text.trim().length < 4) return 'Enter your security PIN.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    _attemptKey ??= const Uuid().v4();
    try {
      final client = context.read<ConvexClientWrapper>();
      final res = await client.action(
        'withdrawals:requestWithdrawal',
        args: {
          'amount': _amount,
          'method': _method,
          'destinationProviderCode': _method == 'bank' ? _bankNameCtrl.text.trim() : _provider,
          'destinationAccountNumber':
              _method == 'bank' ? _accountCtrl.text.trim() : _phoneCtrl.text.trim(),
          if (_method == 'bank') 'bankName': _bankNameCtrl.text.trim(),
          if (_method == 'bank') 'destinationName': _accountNameCtrl.text.trim(),
          'pin': _pinCtrl.text.trim(),
          'idempotencyKey': _attemptKey,
        },
      );
      if (!mounted) return;

      if (!res.success) {
        // PIN / validation / insufficient funds: nothing was created; the same key may be retried.
        setState(() {
          _submitting = false;
          _error = res.errorMessage ?? 'The withdrawal could not be submitted.';
        });
        return;
      }

      final value = res.value is Map ? Map<String, dynamic>.from(res.value as Map) : <String, dynamic>{};
      final status = value['status']?.toString() ?? 'processing';
      if (status == 'failed') _attemptKey = null; // next attempt is a NEW withdrawal
      widget.onCompleted(); // refresh the wallet from the server
      setState(() {
        _submitting = false;
        _phase = _WithdrawPhase.result;
        _resultStatus = status;
        _resultMessage = value['message']?.toString() ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      // Ambiguous (e.g. network): KEEP the key so a retry can never double-withdraw.
      setState(() {
        _submitting = false;
        _error = 'Connection problem. Please check your balance and try again.';
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
        child: _phase == _WithdrawPhase.form ? _buildForm() : _buildResult(),
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

  InputDecoration _dec(String label, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        const Text('Withdraw funds',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
        const SizedBox(height: 6),
        Text(
          'Available to withdraw: ${widget.currency} ${_fmt.format(widget.availableBalance)}',
          style: const TextStyle(fontSize: 13, color: AppColors.emeraldDark, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Funds protected in an active escrow deal are not withdrawable.',
          style: TextStyle(fontSize: 11, color: AppColors.gray500),
        ),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'mobile_money', label: Text('Mobile Money'), icon: Icon(Icons.phone_android_rounded)),
            ButtonSegment(value: 'bank', label: Text('Bank'), icon: Icon(Icons.account_balance_rounded)),
          ],
          selected: {_method},
          onSelectionChanged: (s) => setState(() {
            _method = s.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          decoration: _dec('Amount (${widget.currency})'),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 12),
        if (_method == 'mobile_money') ...[
          DropdownButtonFormField<String>(
            initialValue: _provider,
            decoration: _dec('Provider'),
            items: const [
              DropdownMenuItem(value: 'orange', child: Text('Orange Money')),
              DropdownMenuItem(value: 'africell', child: Text('Africell Money')),
            ],
            onChanged: (v) => setState(() => _provider = v ?? 'orange'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: _dec('Mobile money number', hint: '+232 7X XXX XXX'),
          ),
        ] else ...[
          TextField(controller: _bankNameCtrl, decoration: _dec('Bank name')),
          const SizedBox(height: 12),
          TextField(
            controller: _accountCtrl,
            keyboardType: TextInputType.number,
            decoration: _dec('Account number'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _accountNameCtrl, decoration: _dec('Account holder name')),
          const SizedBox(height: 6),
          const Text(
            'Bank withdrawals are reviewed and sent by Vektolux. Funds are reserved now and '
            'leave your wallet only once the transfer is confirmed.',
            style: TextStyle(fontSize: 11, color: AppColors.gray500),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _pinCtrl,
          obscureText: _obscurePin,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: _dec(
            'Security PIN',
            suffix: IconButton(
              icon: Icon(_obscurePin ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
              onPressed: () => setState(() => _obscurePin = !_obscurePin),
            ),
          ).copyWith(counterText: ''),
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Authorize & withdraw', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final done = _resultStatus == 'completed';
    final failed = _resultStatus == 'failed';
    final color = done ? AppColors.emeraldDark : (failed ? AppColors.error : AppColors.amberDark);
    final icon = done
        ? Icons.check_circle_rounded
        : (failed ? Icons.cancel_rounded : Icons.hourglass_top_rounded);
    final title = done
        ? 'Withdrawal completed'
        : (failed ? 'Withdrawal not processed' : (_resultStatus == 'pending' ? 'Withdrawal submitted' : 'Withdrawal processing'));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _grabber(),
        Icon(icon, size: 56, color: color),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.obsidian)),
        const SizedBox(height: 6),
        Text('${widget.currency} ${_fmt.format(_amount)}',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 10),
        Text(
          _resultMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.gray600),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
