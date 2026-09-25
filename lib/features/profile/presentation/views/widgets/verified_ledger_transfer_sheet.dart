import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../../core/network/convex_client_wrapper.dart';
import '../../../../../core/services/carrier_detection_service.dart';
import '../../../../../core/services/payment_methods_service.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../auth/domain/entities/user_entity.dart';
import '../../../../wallet_payments/presentation/views/transaction_receipt_screen.dart';
import 'ussd_payment_sheet.dart';

/// Enhanced Verified Ledger Transfer Bottom Sheet supporting:
/// - QR Pre-population & recipient auto-resolution
/// - Live available balance indicator
/// - Secure 4-digit PIN / Transaction Password authorization
/// - Dual-mode execution:
///     • Scenario A (Sufficient Balance): Instant atomic P2P ledger transfer
///     • Scenario B (Shortfall): Automatic MoniMe USSD payment trigger for the difference
class VerifiedLedgerTransferSheet extends StatefulWidget {
  final UserEntity user;
  final double currentBalance;
  final String? initialQuery;
  final Map<String, dynamic>? initialResolvedRecipient;
  final VoidCallback onTransferCompleted;

  const VerifiedLedgerTransferSheet({
    super.key,
    required this.user,
    required this.currentBalance,
    this.initialQuery,
    this.initialResolvedRecipient,
    required this.onTransferCompleted,
  });

  /// Static helper to launch the transfer bottom sheet
  static Future<void> show(
    BuildContext context, {
    required UserEntity user,
    required double currentBalance,
    String? initialQuery,
    Map<String, dynamic>? initialResolvedRecipient,
    required VoidCallback onTransferCompleted,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => VerifiedLedgerTransferSheet(
        user: user,
        currentBalance: currentBalance,
        initialQuery: initialQuery,
        initialResolvedRecipient: initialResolvedRecipient,
        onTransferCompleted: onTransferCompleted,
      ),
    );
  }

  @override
  State<VerifiedLedgerTransferSheet> createState() =>
      _VerifiedLedgerTransferSheetState();
}

class _VerifiedLedgerTransferSheetState
    extends State<VerifiedLedgerTransferSheet> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _pinCtrl = TextEditingController();

  final NumberFormat _fmt = NumberFormat('#,##0.00', 'en_US');

  bool _isProcessing = false;
  bool _isResolving = false;
  bool _obscurePin = true;

  Map<String, dynamic>? _resolvedRecipient;
  String? _recipientError;
  String? _amountError;
  String? _pinError;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    if (widget.initialResolvedRecipient != null) {
      _resolvedRecipient = widget.initialResolvedRecipient;
      _codeCtrl.text = _resolvedRecipient!['phone']?.toString() ??
          _resolvedRecipient!['name']?.toString() ??
          widget.initialQuery ??
          '';
    } else if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _codeCtrl.text = widget.initialQuery!;
      _parseAndResolve(widget.initialQuery!);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _codeCtrl.dispose();
    _amountCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _validateAmount(String raw) {
    final amt = double.tryParse(raw.trim()) ?? 0;
    if (raw.trim().isEmpty) {
      _amountError = null;
    } else if (amt <= 0) {
      _amountError = 'Please enter a valid amount greater than 0 SLE.';
    } else {
      _amountError = null;
    }
    setState(() {});
  }

  void _parseAndResolve(String raw) {
    _debounceTimer?.cancel();
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _resolvedRecipient = null;
        _recipientError = null;
        _isResolving = false;
      });
      return;
    }

    String queryParam = trimmed;

    // 1. Parse JSON payloads: {"type":"vektolux_pay", "userId":"...", "name":"...", "phone":"..."}
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final parsed = jsonDecode(trimmed);
        if (parsed is Map) {
          final phone = parsed['phone'] ?? parsed['customerPhone'] ?? parsed['phoneNumber'];
          final userId = parsed['userId'] ?? parsed['id'];
          final name = parsed['name'] ?? parsed['recipientName'];
          final qrAmt = parsed['amount']?.toString();

          if (qrAmt != null && qrAmt.isNotEmpty && _amountCtrl.text.isEmpty) {
            _amountCtrl.text = qrAmt;
            _validateAmount(qrAmt);
          }

          if (userId != null && name != null) {
            setState(() {
              _resolvedRecipient = {
                'found': true,
                'recipientId': userId.toString(),
                'name': name.toString(),
                'phone': phone?.toString() ?? '',
              };
              _recipientError = null;
              _isResolving = false;
            });
            return;
          }

          if (phone != null) {
            queryParam = phone.toString();
          } else if (userId != null) {
            queryParam = userId.toString();
          }
        }
      } catch (_) {}
    }

    // 2. Parse Deep Link URLs: vektolux://pay?userId=...&phone=...&name=...
    if (trimmed.startsWith('vektolux://') ||
        trimmed.startsWith('monime://') ||
        trimmed.startsWith('http://') ||
        trimmed.startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null) {
        final phone = uri.queryParameters['phone'] ?? uri.queryParameters['customerPhone'];
        final userId = uri.queryParameters['userId'] ?? uri.queryParameters['id'];
        final name = uri.queryParameters['name'];
        final qrAmt = uri.queryParameters['amount'];

        if (qrAmt != null && qrAmt.isNotEmpty && _amountCtrl.text.isEmpty) {
          _amountCtrl.text = qrAmt;
          _validateAmount(qrAmt);
        }

        if (userId != null && name != null) {
          setState(() {
            _resolvedRecipient = {
              'found': true,
              'recipientId': userId,
              'name': Uri.decodeComponent(name),
              'phone': phone ?? '',
            };
            _recipientError = null;
            _isResolving = false;
          });
          return;
        }

        if (phone != null && phone.isNotEmpty) {
          queryParam = phone;
        } else if (userId != null && userId.isNotEmpty) {
          queryParam = userId;
        }
      }
    }

    if (queryParam.length < 3) {
      setState(() {
        _resolvedRecipient = null;
        _recipientError = 'Please enter at least 3 characters.';
        _isResolving = false;
      });
      return;
    }

    setState(() {
      _isResolving = true;
      _recipientError = null;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final client = context.read<ConvexClientWrapper>();
        final res = await client.query(
          'payments:resolveRecipient',
          args: {
            'query': queryParam,
            'senderUserId': widget.user.id,
          },
        );

        if (!mounted) return;

        if (res.success && res.value is Map) {
          final data = Map<String, dynamic>.from(res.value as Map);
          if (data['found'] == true) {
            setState(() {
              _resolvedRecipient = data;
              _recipientError = null;
              _isResolving = false;
            });
          } else {
            setState(() {
              _resolvedRecipient = null;
              _recipientError = data['error']?.toString() ?? 'Recipient not found.';
              _isResolving = false;
            });
          }
        } else {
          setState(() {
            _resolvedRecipient = null;
            _recipientError = res.errorMessage ?? 'Recipient not found.';
            _isResolving = false;
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _resolvedRecipient = null;
          _recipientError = 'Could not verify recipient.';
          _isResolving = false;
        });
      }
    });
  }

  Future<void> _handleTransferSubmit() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _amountError = 'Please enter an amount greater than 0.');
      return;
    }

    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _pinError = 'Please enter your 4-digit PIN or password.');
      return;
    }

    if (_resolvedRecipient == null) {
      setState(() => _recipientError = 'Please specify a valid recipient.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _pinError = null;
    });

    try {
      final client = context.read<ConvexClientWrapper>();

      // 1. Validate PIN / Transaction Password with Convex
      final pinRes = await client.query(
        'payments:verifyTransactionPin',
        args: {
          'userId': widget.user.id,
          'pin': pin,
        },
      );

      if (!pinRes.success || (pinRes.value is Map && pinRes.value['valid'] == false)) {
        final msg = pinRes.value is Map
            ? (pinRes.value['message']?.toString() ?? 'Incorrect security PIN or password.')
            : 'Incorrect security PIN or password.';
        setState(() {
          _isProcessing = false;
          _pinError = msg;
        });
        return;
      }

      final double available = widget.currentBalance;

      // ── SCENARIO A: SUFFICIENT WALLET BALANCE ─────────────────────────────
      if (amount <= available) {
        final res = await client.mutation(
          'payments:executeP2PTransfer',
          args: {
            'senderUserId': widget.user.id,
            'recipientQuery': _resolvedRecipient!['recipientId'] ??
                _resolvedRecipient!['phone'] ??
                _codeCtrl.text.trim(),
            'amount': amount,
            'pin': pin,
            'note': 'P2P Transfer via Vektolux Verified QR',
          },
        );

        if (!mounted) return;

        if (res.success && res.value is Map) {
          final receipt = Map<String, dynamic>.from(res.value as Map);
          Navigator.of(context).pop(); // Close transfer sheet

          // Trigger balance refresh callback
          widget.onTransferCompleted();

          // Green confirmation banner
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✓ Transferred SLE ${_fmt.format(amount)} to ${_resolvedRecipient!['name']} successfully!',
              ),
              backgroundColor: AppColors.emeraldDark,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );

          // Route to verified transaction receipt screen
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TransactionReceiptScreen(
                transactionId: receipt['transactionId']?.toString() ?? 'TX-P2P',
                amount: amount,
                feeAmount: (receipt['feeAmount'] as num?)?.toDouble() ?? 0.0,
                netAmount: amount,
                currency: receipt['currency']?.toString() ?? 'SLE',
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  receipt['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
                ),
                type: 'p2p_transfer',
                status: receipt['status']?.toString() ?? 'COMPLETED',
                senderName: widget.user.name,
                senderPhone: widget.user.phone,
                recipientName: _resolvedRecipient!['name']?.toString() ?? 'Recipient',
                recipientPhone: _resolvedRecipient!['phone']?.toString() ?? '',
              ),
            ),
          );
        } else {
          throw Exception(res.errorMessage ?? 'Transfer execution failed.');
        }
      }
      // ── SCENARIO B: INSUFFICIENT BALANCE (DUAL-MODE TOP-UP VIA USSD) ─────
      else {
        final shortfall = amount - available;
        final senderPhone = widget.user.phone;
        final detected = CarrierDetectionService.detectCarrier(senderPhone);
        final normalizedPhone = CarrierDetectionService.normalizeToSierraLeoneFormat(senderPhone);

        // Initiate MoniMe mobile money payment for the difference
        final monimeRes = await PaymentMethodsService.instance.initiateMoniMePayment(
          amount: shortfall,
          currency: 'SLE',
          phoneNumber: normalizedPhone,
          provider: detected.providerSlug,
          userId: widget.user.id,
          customerName: widget.user.name,
          customerEmail: widget.user.email,
          description: 'Vektolux Wallet Top-up for P2P Transfer (Shortfall: SLE ${_fmt.format(shortfall)})',
        );

        if (!mounted) return;

        if (monimeRes['success'] == true) {
          final rawUssd = monimeRes['ussdCode']?.toString() ?? monimeRes['dialCode']?.toString() ?? '';
          final dialCode = rawUssd.isNotEmpty
              ? rawUssd
              : (detected.providerSlug == 'orange'
                  ? '*144#'
                  : (detected.providerSlug == 'africell' ? '*161#' : '*715#'));
          final ref = monimeRes['reference']?.toString() ?? monimeRes['transactionId']?.toString() ?? '';

          // Open Native USSD bottom sheet
          final bool? ussdCompleted = await UssdPaymentSheet.show(
            context,
            dialCode: dialCode,
            reference: ref,
            amount: shortfall,
            serviceFee: 0.0,
            serviceProvider: detected.displayName,
            recipient: normalizedPhone,
            transactionType: 'Wallet Deposit (Transfer Shortfall)',
            onPaymentCompleted: () {
              widget.onTransferCompleted();
            },
          );

          if (!mounted) return;

          // If USSD payment succeeded, complete the P2P transfer
          if (ussdCompleted == true) {
            final completeRes = await client.mutation(
              'payments:executeP2PTransfer',
              args: {
                'senderUserId': widget.user.id,
                'recipientQuery': _resolvedRecipient!['recipientId'] ??
                    _resolvedRecipient!['phone'] ??
                    _codeCtrl.text.trim(),
                'amount': amount,
                'pin': pin,
                'note': 'P2P Transfer via Vektolux (Top-up + Transfer)',
              },
            );

            if (!mounted) return;

            if (completeRes.success && completeRes.value is Map) {
              Navigator.of(context).pop();
              widget.onTransferCompleted();

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '✓ Transferred SLE ${_fmt.format(amount)} to ${_resolvedRecipient!['name']} successfully!',
                  ),
                  backgroundColor: AppColors.emeraldDark,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        } else {
          final errorMsg = monimeRes['message']?.toString() ?? 'Mobile money top-up could not be initiated.';
          setState(() {
            _isProcessing = false;
            _amountError = errorMsg;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _pinError = 'Transfer error: $e';
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double currentBal = widget.currentBalance;
    final parsedAmount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final isShortfall = parsedAmount > currentBal;
    final shortfallAmt = isShortfall ? (parsedAmount - currentBal) : 0.0;

    final bool canSubmit = !_isProcessing &&
        !_isResolving &&
        _resolvedRecipient != null &&
        parsedAmount > 0 &&
        _pinCtrl.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.emeraldSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.send_rounded,
                    color: AppColors.emeraldDark, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verified Ledger Transfer',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.obsidian,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Instant, atomic transfer with PIN authorization',
                      style: TextStyle(fontSize: 12, color: AppColors.gray500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Available Balance Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your Available Balance:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
                Text(
                  'SLE ${_fmt.format(currentBal)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.obsidian,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Recipient Input
          TextField(
            controller: _codeCtrl,
            cursorColor: const Color(0xFF10B981),
            onChanged: _parseAndResolve,
            style: const TextStyle(
              color: AppColors.obsidian,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              labelText: 'Recipient Phone or User ID',
              labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              hintText: 'e.g. +232 76 123456 or User ID',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              prefixIcon: const Icon(Icons.perm_identity_rounded, color: AppColors.obsidianSoft),
              suffixIcon: _isResolving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.emerald,
                        ),
                      ),
                    )
                  : (_resolvedRecipient != null
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.emerald, size: 20)
                      : null),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _recipientError != null
                      ? AppColors.error
                      : (_resolvedRecipient != null ? AppColors.emerald : const Color(0xFFCBD5E1)),
                ),
              ),
            ),
          ),

          // Recipient Verified Card
          if (_resolvedRecipient != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.emeraldDark, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Verified: ${_resolvedRecipient!['name']} (${_resolvedRecipient!['phone']})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF065F46),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_recipientError != null) ...[
            const SizedBox(height: 6),
            Text(
              _recipientError!,
              style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],

          const SizedBox(height: 12),

          // Amount Input
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            cursorColor: const Color(0xFF10B981),
            onChanged: _validateAmount,
            style: const TextStyle(
              color: AppColors.obsidian,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              labelText: 'Amount (SLE)',
              labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              prefixText: 'SLE ',
              prefixStyle: const TextStyle(color: AppColors.obsidian, fontWeight: FontWeight.w700),
              prefixIcon: const Icon(Icons.payments_outlined, color: AppColors.obsidianSoft),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _amountError != null ? AppColors.error : const Color(0xFFCBD5E1),
                ),
              ),
            ),
          ),

          if (_amountError != null) ...[
            const SizedBox(height: 4),
            Text(
              _amountError!,
              style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],

          // Shortfall notice banner (Scenario B)
          if (isShortfall && parsedAmount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Shortfall: SLE ${_fmt.format(shortfallAmt)} will be requested via Mobile Money USSD prompt.',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Security PIN / Password Input
          TextField(
            controller: _pinCtrl,
            obscureText: _obscurePin,
            keyboardType: TextInputType.text,
            cursorColor: const Color(0xFF10B981),
            onChanged: (val) => setState(() => _pinError = null),
            style: const TextStyle(
              color: AppColors.obsidian,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: 2,
            ),
            decoration: InputDecoration(
              labelText: 'Transaction PIN / Account Password',
              labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13, letterSpacing: 0),
              hintText: 'Enter 4-digit PIN or Password',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, letterSpacing: 0),
              prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.obsidianSoft),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePin ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: const Color(0xFF64748B),
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePin = !_obscurePin),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _pinError != null ? AppColors.error : const Color(0xFFCBD5E1),
                ),
              ),
            ),
          ),

          if (_pinError != null) ...[
            const SizedBox(height: 4),
            Text(
              _pinError!,
              style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],

          const SizedBox(height: 20),

          // Confirm & Transfer Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                disabledForegroundColor: const Color(0xFF94A3B8),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: !canSubmit ? null : _handleTransferSubmit,
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          isShortfall
                              ? 'Pay Shortfall & Transfer (SLE ${_fmt.format(parsedAmount)})'
                              : 'Confirm & Transfer (SLE ${_fmt.format(parsedAmount)})',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
