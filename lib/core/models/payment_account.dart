// lib/core/models/payment_account.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Per-User Linked Payment Account Model
// Replaces the in-file SavedPaymentMethodItem class that previously
// lived inside profile_screen.dart and was never persisted to Convex.
// ═══════════════════════════════════════════════════════════════════════

/// Represents a single payment account linked by a user (Mobile Money number
/// or bank account). Backed by the Convex `user_payment_accounts` table.
class PaymentAccount {
  final String id;           // Convex document _id
  final String providerCode; // "orange" | "africell" | "qmoney" | "slcb"
  final String providerName; // Display name
  final String accountNumber;// Raw number (phone / BBAN)
  final String maskedNumber; // "+232 76 ••• 761"
  final bool isDefault;
  final bool isActive;

  const PaymentAccount({
    required this.id,
    required this.providerCode,
    required this.providerName,
    required this.accountNumber,
    required this.maskedNumber,
    required this.isDefault,
    required this.isActive,
  });

  factory PaymentAccount.fromJson(Map<String, dynamic> json) {
    return PaymentAccount(
      id: json['_id'] as String? ?? '',
      providerCode: json['providerCode'] as String? ?? '',
      providerName: json['providerName'] as String? ?? '',
      accountNumber: json['accountNumber'] as String? ?? '',
      maskedNumber: json['maskedNumber'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'providerCode': providerCode,
        'providerName': providerName,
        'accountNumber': accountNumber,
        'maskedNumber': maskedNumber,
        'isDefault': isDefault,
        'isActive': isActive,
      };

  PaymentAccount copyWith({
    String? id,
    String? providerCode,
    String? providerName,
    String? accountNumber,
    String? maskedNumber,
    bool? isDefault,
    bool? isActive,
  }) {
    return PaymentAccount(
      id: id ?? this.id,
      providerCode: providerCode ?? this.providerCode,
      providerName: providerName ?? this.providerName,
      accountNumber: accountNumber ?? this.accountNumber,
      maskedNumber: maskedNumber ?? this.maskedNumber,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
    );
  }
}
