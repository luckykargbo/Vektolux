// lib/features/wallet_payments/presentation/views/transaction_history_screen.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Transaction History & Activity Ledger Screen
// Real-time server-authoritative audit log of all financial events.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../bloc/wallet_cubit.dart';
import '../bloc/wallet_state.dart';
import 'transaction_receipt_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  final ConvexClientWrapper convexClient;

  const TransactionHistoryScreen({
    super.key,
    required this.convexClient,
  });

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  String _selectedFilter = 'all';
  final NumberFormat _fmt = NumberFormat('#,##0.00', 'en_US');
  final DateFormat _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  void _fetchTransactions() {
    final authState = context.read<AuthBloc>().state;
    final user = authState.user;
    if (user != null) {
      context.read<WalletCubit>().loadWallet(
            userId: user.id,
            sessionToken: user.sessionToken,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authUser = context.watch<AuthBloc>().state.user;

    return Scaffold(
      backgroundColor: AppColors.gray50,
      appBar: AppBar(
        backgroundColor: AppColors.obsidian,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Transaction History',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
            onPressed: _fetchTransactions,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filter Chips ───────────────────────────────────────────
          Container(
            color: AppColors.obsidian,
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildFilterChip('all', 'All Activity'),
                  const SizedBox(width: 8),
                  _buildFilterChip('top_up', 'Deposits'),
                  const SizedBox(width: 8),
                  _buildFilterChip('p2p_transfer', 'Transfers'),
                  const SizedBox(width: 8),
                  _buildFilterChip('payment', 'Payments'),
                  const SizedBox(width: 8),
                  _buildFilterChip('withdrawal', 'Withdrawals'),
                  const SizedBox(width: 8),
                  _buildFilterChip('escrow_lock', 'Escrow Holds'),
                ],
              ),
            ),
          ),

          // ── Transaction List ────────────────────────────────────────
          Expanded(
            child: BlocBuilder<WalletCubit, WalletState>(
              builder: (context, state) {
                if (state.isLoading && state.transactions.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.emerald),
                  );
                }

                final filtered = state.transactions.where((tx) {
                  if (_selectedFilter == 'all') return true;
                  return tx.type == _selectedFilter;
                }).toList();

                if (filtered.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => _fetchTransactions(),
                    color: AppColors.emerald,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppColors.gray200,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.receipt_long_outlined,
                                  color: AppColors.gray500,
                                  size: 36,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No transactions found',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.obsidian,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _selectedFilter == 'all'
                                    ? 'Your financial activity will appear here in real-time.'
                                    : 'No ${_selectedFilter.replaceAll('_', ' ')} transactions recorded yet.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => _fetchTransactions(),
                  color: AppColors.emerald,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final tx = filtered[index];
                      return _buildTransactionCard(context, tx, authUser);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emerald : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.emerald : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.obsidian : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(
    BuildContext context,
    TransactionItem tx,
    UserEntity? currentUser,
  ) {
    final isPositive = tx.type == 'top_up' || tx.type == 'refund' || tx.type == 'payout';
    final sign = isPositive ? '+' : '-';
    final amountColor = isPositive ? AppColors.emeraldDark : AppColors.obsidian;

    IconData iconData;
    Color iconColor;
    Color iconBg;

    switch (tx.type) {
      case 'top_up':
        iconData = Icons.add_circle_outline_rounded;
        iconColor = AppColors.emeraldDark;
        iconBg = AppColors.emeraldSurface;
        break;
      case 'withdrawal':
      case 'payout':
        iconData = Icons.account_balance_wallet_outlined;
        iconColor = Colors.deepOrange;
        iconBg = Colors.deepOrange.withValues(alpha: 0.1);
        break;
      case 'p2p_transfer':
        iconData = Icons.swap_horiz_rounded;
        iconColor = Colors.blueAccent;
        iconBg = Colors.blueAccent.withValues(alpha: 0.1);
        break;
      case 'escrow_lock':
        iconData = Icons.lock_outline_rounded;
        iconColor = AppColors.amberDark;
        iconBg = AppColors.amberSurface;
        break;
      case 'escrow_release':
        iconData = Icons.lock_open_rounded;
        iconColor = AppColors.emeraldDark;
        iconBg = AppColors.emeraldSurface;
        break;
      default:
        iconData = Icons.payment_rounded;
        iconColor = AppColors.obsidian;
        iconBg = AppColors.gray200;
        break;
    }

    final title = _formatTransactionTitle(tx);

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TransactionReceiptScreen(
              transactionId: tx.transactionId,
              amount: tx.amount,
              feeAmount: tx.feeAmount ?? 0.0,
              netAmount: tx.netAmount ?? tx.amount,
              currency: tx.currency,
              timestamp: tx.timestamp,
              type: tx.type,
              status: tx.status.toUpperCase(),
              senderName: currentUser?.name ?? '',
              senderPhone: currentUser?.phone ?? '',
              recipientName: tx.counterpartyName ?? '',
              recipientPhone: tx.counterpartyPhone ?? '',
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1),
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(iconData, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.obsidian,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _dateFmt.format(tx.timestamp),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$sign SLE ${_fmt.format(tx.amount)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: amountColor,
                  ),
                ),
                const SizedBox(height: 3),
                _buildStatusBadge(tx.status),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTransactionTitle(TransactionItem tx) {
    if (tx.description != null && tx.description!.isNotEmpty) {
      return tx.description!;
    }

    switch (tx.type) {
      case 'top_up':
        return 'Deposit via ${tx.gatewayProvider ?? "MoniMe"}';
      case 'withdrawal':
        return 'Withdrawal to ${tx.counterpartyName ?? tx.gatewayProvider ?? "Mobile Money"}';
      case 'p2p_transfer':
        return tx.counterpartyName != null ? 'Transfer to ${tx.counterpartyName}' : 'P2P Transfer';
      case 'escrow_lock':
        return 'Escrow Hold';
      case 'escrow_release':
        return 'Escrow Funds Released';
      default:
        return 'Payment';
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label = status.toUpperCase();

    switch (status.toLowerCase()) {
      case 'completed':
      case 'success':
        bg = AppColors.emeraldSurface;
        fg = AppColors.emeraldDark;
        break;
      case 'pending':
        bg = AppColors.amberSurface;
        fg = AppColors.amberDark;
        break;
      case 'failed':
      case 'reversed':
        bg = AppColors.errorLight;
        fg = AppColors.error;
        break;
      default:
        bg = AppColors.gray200;
        fg = AppColors.gray700;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
