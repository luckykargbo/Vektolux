// lib/features/wallet_payments/presentation/bloc/wallet_state.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Wallet State Definition
// Represents live, server-authoritative balance and transaction records.
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';

class TransactionItem extends Equatable {
  final String id;
  final String transactionId;
  final String type;
  final double amount;
  final String currency;
  final String status;
  final String? description;
  final String? counterpartyName;
  final String? counterpartyPhone;
  final double? feeAmount;
  final double? netAmount;
  final String? gatewayProvider;
  final String? gatewayReference;
  final DateTime timestamp;

  const TransactionItem({
    required this.id,
    required this.transactionId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.status,
    this.description,
    this.counterpartyName,
    this.counterpartyPhone,
    this.feeAmount,
    this.netAmount,
    this.gatewayProvider,
    this.gatewayReference,
    required this.timestamp,
  });

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    final rawTs = map['createdAt'];
    DateTime dt;
    if (rawTs is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else if (rawTs is String) {
      dt = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      dt = DateTime.now();
    }

    return TransactionItem(
      id: map['id']?.toString() ?? '',
      transactionId: map['transactionId']?.toString() ?? '',
      type: map['type']?.toString() ?? 'payment',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency']?.toString() ?? 'SLE',
      status: map['status']?.toString() ?? 'completed',
      description: map['description']?.toString(),
      counterpartyName: map['counterpartyName']?.toString(),
      counterpartyPhone: map['counterpartyPhone']?.toString(),
      feeAmount: (map['feeAmount'] as num?)?.toDouble(),
      netAmount: (map['netAmount'] as num?)?.toDouble(),
      gatewayProvider: map['gatewayProvider']?.toString(),
      gatewayReference: map['gatewayReference']?.toString(),
      timestamp: dt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        transactionId,
        type,
        amount,
        currency,
        status,
        timestamp,
      ];
}

class WalletState extends Equatable {
  final double availableBalance;
  final double escrowBalance;
  final double pendingBalance;
  final String currency;
  final bool isLoading;
  final String? errorMessage;
  final List<TransactionItem> transactions;

  const WalletState({
    this.availableBalance = 0.0,
    this.escrowBalance = 0.0,
    this.pendingBalance = 0.0,
    this.currency = 'SLE',
    this.isLoading = false,
    this.errorMessage,
    this.transactions = const [],
  });

  WalletState copyWith({
    double? availableBalance,
    double? escrowBalance,
    double? pendingBalance,
    String? currency,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    List<TransactionItem>? transactions,
  }) {
    return WalletState(
      availableBalance: availableBalance ?? this.availableBalance,
      escrowBalance: escrowBalance ?? this.escrowBalance,
      pendingBalance: pendingBalance ?? this.pendingBalance,
      currency: currency ?? this.currency,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      transactions: transactions ?? this.transactions,
    );
  }

  @override
  List<Object?> get props => [
        availableBalance,
        escrowBalance,
        pendingBalance,
        currency,
        isLoading,
        errorMessage,
        transactions,
      ];
}
