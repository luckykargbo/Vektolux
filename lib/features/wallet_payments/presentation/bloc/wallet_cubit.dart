// lib/features/wallet_payments/presentation/bloc/wallet_cubit.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Wallet Reactive Cubit
// Orchestrates balance updates, escrow hold tracking, and transaction history.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../data/pending_deposit_settler.dart';
import 'wallet_state.dart';

class WalletCubit extends Cubit<WalletState> {
  final ConvexClientWrapper _convexClient;
  final PendingDepositSettler _settler;

  WalletCubit({required ConvexClientWrapper convexClient, PendingDepositSettler? settler})
      : _convexClient = convexClient,
        _settler = settler ?? PendingDepositSettler.shared,
        super(const WalletState());

  /// Fetch user's server-authoritative balance and recent transactions.
  ///
  /// Also checks the user's own pending Monime deposits in the background (never blocking or failing
  /// the wallet itself); if one was confirmed, the balance and history are refreshed once more.
  /// [force] marks an explicit user refresh (shorter client-side throttle).
  Future<void> loadWallet({
    required String userId,
    String? sessionToken,
    bool force = false,
  }) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    final check = _checkPendingDeposits(userId: userId, sessionToken: sessionToken, force: force);
    await _fetchAndEmit(userId: userId, sessionToken: sessionToken);
    await check;
  }

  Future<void> _checkPendingDeposits({
    required String userId,
    String? sessionToken,
    required bool force,
  }) async {
    emit(state.copyWith(isCheckingDeposits: true, depositCheckFailed: false, settledDeposits: 0));
    final result = await _settler.settle(_convexClient, userId: userId, force: force);
    if (isClosed) return;
    if (result.anySettled) {
      // Money was confirmed: show the new balance and history (a plain fetch, never another check).
      await _fetchAndEmit(userId: userId, sessionToken: sessionToken);
      if (isClosed) return;
    }
    emit(state.copyWith(
      isCheckingDeposits: false,
      settledDeposits: result.settled,
      depositCheckFailed: result.status == DepositSettleStatus.failed,
    ));
  }

  // Each fetch is numbered when it STARTS. A result is applied only if no fetch started later has
  // already been applied: a slow, older response (e.g. the first load, still in flight when a deposit
  // was confirmed and the wallet was re-read) must never overwrite the newer balance/history.
  int _fetchSeq = 0;
  int _appliedSeq = 0;

  Future<void> _fetchAndEmit({required String userId, String? sessionToken}) async {
    final seq = ++_fetchSeq;
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

      if (isClosed) return;
      if (seq < _appliedSeq) return; // a newer read was already applied
      _appliedSeq = seq;
      emit(state.copyWith(
        availableBalance: available,
        escrowBalance: escrow,
        pendingBalance: pending,
        currency: currency,
        transactions: items,
        isLoading: false,
      ));
    } catch (e) {
      if (isClosed) return;
      if (seq < _appliedSeq) return;
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
