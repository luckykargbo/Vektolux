// lib/features/wallet_payments/presentation/views/transaction_receipt_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Production Transaction Receipt Screen
// Displays immutable, verified ledger transaction details post-execution.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';

class TransactionReceiptScreen extends StatelessWidget {
  final String transactionId;
  final double amount;
  final double feeAmount;
  final double netAmount;
  final String currency;
  final DateTime timestamp;
  final String type; // e.g., "p2p_transfer", "escrow_lock", "top_up"
  final String status; // "COMPLETED", "LOCKED", "PENDING", "FAILED"
  final String senderName;
  final String senderPhone;
  final String recipientName;
  final String recipientPhone;
  final double? updatedBalance;
  final String? note;

  const TransactionReceiptScreen({
    super.key,
    required this.transactionId,
    required this.amount,
    this.feeAmount = 0.0,
    required this.netAmount,
    this.currency = 'SLE',
    required this.timestamp,
    required this.type,
    required this.status,
    required this.senderName,
    required this.senderPhone,
    required this.recipientName,
    required this.recipientPhone,
    this.updatedBalance,
    this.note,
  });

  String get _typeTitle {
    switch (type) {
      case 'p2p_transfer':
        return 'Peer-to-Peer Transfer';
      case 'escrow_lock':
        return 'Escrow Vault Deposit';
      case 'escrow_release':
        return 'Escrow Settlement';
      case 'top_up':
        return 'Wallet Top-Up';
      case 'withdrawal':
        return 'Bank / Telco Payout';
      default:
        return 'Ledger Transaction';
    }
  }

  Color get _statusColor {
    final s = status.toUpperCase();
    if (s == 'COMPLETED' || s == 'LOCKED') return AppColors.emerald;
    if (s == 'PENDING') return AppColors.amber;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate =
        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')} GMT';

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.obsidian),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'Official Receipt',
            style: TextStyle(
              color: AppColors.obsidian,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_rounded, color: AppColors.obsidianSoft, size: 20),
              tooltip: 'Copy Reference ID',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: transactionId));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied Reference: $transactionId'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                // Status Badge & Amount Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: _statusColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          status.toUpperCase() == 'COMPLETED' || status.toUpperCase() == 'LOCKED'
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          color: _statusColor,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _typeTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$currency ${amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _statusColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _statusColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Transaction Breakdown Table
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Audit Breakdown',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildReceiptRow('Transaction ID', transactionId, isCode: true),
                      const Divider(height: 24, color: Color(0xFFF1F5F9)),
                      _buildReceiptRow('Date & Time', formattedDate),
                      const Divider(height: 24, color: Color(0xFFF1F5F9)),
                      _buildReceiptRow('Sender', '$senderName ($senderPhone)'),
                      const Divider(height: 24, color: Color(0xFFF1F5F9)),
                      _buildReceiptRow('Recipient', '$recipientName ($recipientPhone)'),
                      if (note != null && note!.trim().isNotEmpty) ...[
                        const Divider(height: 24, color: Color(0xFFF1F5F9)),
                        _buildReceiptRow('Memo / Reference', note!),
                      ],
                      const Divider(height: 24, color: Color(0xFFF1F5F9)),
                      _buildReceiptRow('Transfer Amount', '$currency ${amount.toStringAsFixed(2)}'),
                      const Divider(height: 24, color: Color(0xFFF1F5F9)),
                      _buildReceiptRow('Platform Fee', '$currency ${feeAmount.toStringAsFixed(2)}'),
                      const Divider(height: 24, color: Color(0xFFF1F5F9)),
                      _buildReceiptRow(
                        'Total Deducted',
                        '$currency ${netAmount.toStringAsFixed(2)}',
                        isHighlighted: true,
                      ),
                      if (updatedBalance != null) ...[
                        const Divider(height: 24, color: Color(0xFFF1F5F9)),
                        _buildReceiptRow(
                          'Available Balance',
                          '$currency ${updatedBalance!.toStringAsFixed(2)}',
                          valueColor: AppColors.emeraldDark,
                          isHighlighted: true,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Compliance & Escrow Verification Seal
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified_user_rounded, color: AppColors.emeraldDark, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Verified on Vektolux Distributed Ledger Network • SLRSA & Escrow Safeguard Compliant',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF065F46),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Bottom Actions
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E293B),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text(
                      'Share Receipt',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      final summary =
                          'Vektolux Transaction Receipt\n'
                          'Ref: $transactionId\n'
                          'Type: $_typeTitle\n'
                          'Amount: $currency ${amount.toStringAsFixed(2)}\n'
                          'Recipient: $recipientName\n'
                          'Status: $status\n'
                          'Date: $formattedDate';
                      Clipboard.setData(ClipboardData(text: summary));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Receipt summary copied to clipboard.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptRow(
    String label,
    String value, {
    bool isCode = false,
    bool isHighlighted = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: isHighlighted ? 15 : 13,
              fontFamily: isCode ? 'monospace' : null,
              fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
              color: valueColor ?? (isHighlighted ? const Color(0xFF0F172A) : const Color(0xFF1E293B)),
            ),
          ),
        ),
      ],
    );
  }
}
