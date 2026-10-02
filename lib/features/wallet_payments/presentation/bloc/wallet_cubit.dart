// lib/features/wallet_payments/presentation/bloc/wallet_cubit.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Wallet Reactive Cubit
// Orchestrates balance updates, escrow hold tracking, and transaction history.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import 'wallet_state.dart';

class WalletCubit extends Cubit<WalletState> {
  final ConvexClientWrapper _convexClient;

  WalletCubit({required ConvexClientWrapper convexClient})
      : _convexClient = convexClient,
        super(const WalletState());

  /// Fetch user's server-authoritative balance and recent transactions.
  Future<void> loadWallet({
    required String userId,
    String? sessionToken,
  }) async {
    emit(state.copyWith(isLoading: true, clearError: true));

    try {
      // 1. Fetch live balance
      final balanceRes = await _convexClient.query(
        'wallet:getUserBalance',
        args: {
          'userId': userId,
          if (sessionToken != null) 'sessionToken': sessionToken,
        },
      );

      double available = 0.0;
      double escrow = 0.0;
      double pending = 0.0;
      String currency = 'SLE';

      if (balanceRes.success && balanceRes.value is Map) {
        final data = Map<String, dynamic>.from(balanceRes.value as Map);
        available = (data['availableBalance'] as num?)?.toDouble() ?? 0.0;
        escrow = (data['escrowBalance'] as num?)?.toDouble() ?? 0.0;
        pending = (data['pendingBalance'] as num?)?.toDouble() ?? 0.0;
        currency = data['currency']?.toString() ?? 'SLE';
      }

      // 2. Fetch live transactions
      final txRes = await _convexClient.query(
        'walletCore:getUserTransactions',
        args: {
          'userId': userId,
          'limit': 50,
          if (sessionToken != null) 'sessionToken': sessionToken,
        },
      );

      final List<TransactionItem> items = [];
      if (txRes.success && txRes.value is Map) {
        final txData = Map<String, dynamic>.from(txRes.value as Map);
        final list = txData['transactions'] as List<dynamic>? ?? [];
        for (final item in list) {
          if (item is Map) {
            items.add(TransactionItem.fromMap(Map<String, dynamic>.from(item)));
          }
        }
      }

      emit(state.copyWith(
        availableBalance: available,
        escrowBalance: escrow,
        pendingBalance: pending,
        currency: currency,
        transactions: items,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load wallet data: $e',
      ));
    }
  }

  /// Fast balance refresh without wiping existing transactions.
  Future<void> refreshBalance({
    required String userId,
    String? sessionToken,
  }) async {
    try {
      final balanceRes = await _convexClient.query(
        'wallet:getUserBalance',
        args: {
          'userId': userId,
          if (sessionToken != null) 'sessionToken': sessionToken,
        },
      );

      if (balanceRes.success && balanceRes.value is Map) {
        final data = Map<String, dynamic>.from(balanceRes.value as Map);
        emit(state.copyWith(
          availableBalance: (data['availableBalance'] as num?)?.toDouble() ?? state.availableBalance,
          escrowBalance: (data['escrowBalance'] as num?)?.toDouble() ?? state.escrowBalance,
          pendingBalance: (data['pendingBalance'] as num?)?.toDouble() ?? state.pendingBalance,
          currency: data['currency']?.toString() ?? state.currency,
        ));
      }
    } catch (_) {}
  }
}
