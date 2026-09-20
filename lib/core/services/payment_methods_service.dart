// lib/core/services/payment_methods_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Dynamic Payment Methods Service
// Fetches admin-configured payment methods from Convex and provides
// helpers for submitting manual payment claims.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import '../network/convex_client_wrapper.dart';

/// Represents a single payment method configured by the admin.
class PaymentMethod {
  final String id;
  final String providerId;
  final String displayName;
  final String type; // "AGGREGATOR_AUTO", "MANUAL_MERCHANT", "BANK_TRANSFER"
  final bool isEnabled;
  final String? instructions;
  final String? accountNumber;
  final String? accountName;

  PaymentMethod({
    required this.id,
    required this.providerId,
    required this.displayName,
    required this.type,
    required this.isEnabled,
    this.instructions,
    this.accountNumber,
    this.accountName,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['_id'] as String? ?? '',
      providerId: json['providerId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      type: json['type'] as String? ?? 'MANUAL_MERCHANT',
      isEnabled: json['isEnabled'] as bool? ?? false,
      instructions: json['instructions'] as String?,
      accountNumber: json['accountNumber'] as String?,
      accountName: json['accountName'] as String?,
    );
  }

  bool get isAutomated => type == 'AGGREGATOR_AUTO';
  bool get isManual => type == 'MANUAL_MERCHANT' || type == 'BANK_TRANSFER';
  bool get isBankTransfer => type == 'BANK_TRANSFER';

  /// Returns the appropriate icon name for this provider.
  String get iconHint {
    if (providerId.contains('moneroo')) return 'credit_card';
    if (providerId.contains('qmoney')) return 'phone_android';
    if (providerId.contains('afrimoney')) return 'phone_android';
    if (providerId.contains('bank')) return 'account_balance';
    return 'payment';
  }
}

/// Represents a submitted payment claim.
class PaymentClaim {
  final String id;
  final String status;
  final String transactionReference;
  final double amount;
  final String providerId;
  final String? rejectionReason;

  PaymentClaim({
    required this.id,
    required this.status,
    required this.transactionReference,
    required this.amount,
    required this.providerId,
    this.rejectionReason,
  });

  factory PaymentClaim.fromJson(Map<String, dynamic> json) {
    return PaymentClaim(
      id: json['_id'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING_APPROVAL',
      transactionReference: json['transactionReference'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      providerId: json['providerId'] as String? ?? '',
      rejectionReason: json['rejectionReason'] as String?,
    );
  }

  bool get isPending => status == 'PENDING_APPROVAL' || status == 'PENDING_PAYMENT';
  bool get isLocked => status == 'ESCROW_LOCKED';
  bool get isRejected => status == 'REJECTED';
}

/// Singleton service for fetching and caching dynamic payment methods.
class PaymentMethodsService {
  PaymentMethodsService._();
  static final PaymentMethodsService instance = PaymentMethodsService._();

  ConvexClientWrapper? _convexClient;

  /// Initialize with a shared Convex client instance.
  void initialize({required ConvexClientWrapper convexClient}) {
    _convexClient = convexClient;
  }

  ConvexClientWrapper get _client =>
      _convexClient ?? ConvexClientWrapper(deploymentUrl: ApiConstants.convexUrl);

  List<PaymentMethod> _cachedMethods = [];
  DateTime? _lastFetchTime;
  static const _cacheDuration = Duration(minutes: 5);

  /// Fetch active (enabled) payment methods from Convex.
  /// Uses a 5-minute cache to avoid excessive API calls.
  Future<List<PaymentMethod>> getActivePaymentMethods({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedMethods.isNotEmpty &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      return _cachedMethods;
    }

    try {
      final res = await _client.query(
        'payments:getActivePaymentMethods',
        args: {},
      );

      if (res.success && res.value is List) {
        _cachedMethods = (res.value as List)
            .map((item) => PaymentMethod.fromJson(item as Map<String, dynamic>))
            .toList();
        _lastFetchTime = DateTime.now();
        debugPrint('[PaymentMethodsService] Fetched ${_cachedMethods.length} active methods');
      }
    } catch (e) {
      debugPrint('[PaymentMethodsService] Error fetching methods: $e');
      if (_cachedMethods.isNotEmpty) {
        return _cachedMethods;
      }
    }

    return _cachedMethods;
  }

  /// Submit a manual payment claim (QMoney, Afrimoney, Bank Transfer).
  /// Returns the claim result with status and claimId.
  Future<Map<String, dynamic>> submitManualPaymentClaim({
    required String userId,
    required double amount,
    required String providerId,
    required String transactionReference,
    String? bookingId,
    String? escrowOrderId,
    String? reContractId,
  }) async {
    try {
      final args = <String, dynamic>{
        'userId': userId,
        'amount': amount,
        'providerId': providerId,
        'transactionReference': transactionReference,
      };

      if (bookingId != null) args['bookingId'] = bookingId;
      if (escrowOrderId != null) args['escrowOrderId'] = escrowOrderId;
      if (reContractId != null) args['reContractId'] = reContractId;

      final res = await _client.mutation(
        'payments:submitManualPaymentClaim',
        args: args,
      );

      debugPrint('[PaymentMethodsService] Manual claim submitted: ${res.value}');
      if (res.success) {
        return res.value is Map<String, dynamic>
            ? (res.value as Map<String, dynamic>)
            : {'success': true, 'claimId': res.value.toString()};
      } else {
        return {'success': false, 'error': res.errorMessage ?? 'Submission failed'};
      }
    } catch (e) {
      debugPrint('[PaymentMethodsService] Error submitting claim: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get payment claims for a specific user.
  Future<List<PaymentClaim>> getUserPaymentClaims(String userId) async {
    try {
      final res = await _client.query(
        'payments:getUserPaymentClaims',
        args: {'userId': userId},
      );

      if (res.success && res.value is List) {
        return (res.value as List)
            .map((item) => PaymentClaim.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[PaymentMethodsService] Error fetching claims: $e');
    }
    return [];
  }

  /// Initialize an automated Moneroo sandbox payment session.
  /// Calls payments:initializeMonerooPayment action and returns checkoutUrl & paymentId.
  Future<Map<String, dynamic>> initializeMonerooPayment({
    required double amount,
    String currency = 'SLE',
    required String customerEmail,
    required String customerFirstName,
    required String customerLastName,
    String? customerPhone,
    required String userId,
    String? bookingId,
    String? escrowOrderId,
    String? reContractId,
    String? returnUrl,
    String? description,
  }) async {
    try {
      final res = await _client.action(
        'payments:initializeMonerooPayment',
        args: {
          'amount': amount,
          'currency': currency,
          'customerEmail': customerEmail,
          'customerFirstName': customerFirstName,
          'customerLastName': customerLastName,
          if (customerPhone != null && customerPhone.isNotEmpty) 'customerPhone': customerPhone,
          'userId': userId,
          if (bookingId != null) 'bookingId': bookingId,
          if (escrowOrderId != null) 'escrowOrderId': escrowOrderId,
          if (reContractId != null) 'reContractId': reContractId,
          if (returnUrl != null) 'returnUrl': returnUrl,
          if (description != null) 'description': description,
        },
      );

      if (res.success && res.value is Map) {
        final val = res.value as Map;
        final bool isSuccess = val['success'] == true;
        if (isSuccess) {
          return {
            'success': true,
            'code': val['code']?.toString() ?? 'PAYMENT_INITIATED',
            'message': val['message']?.toString() ?? 'Push prompt sent. Please approve on your phone.',
            'transactionId': val['transactionId']?.toString() ?? val['paymentId']?.toString() ?? '',
            'checkoutUrl': val['checkout_url']?.toString() ?? val['checkoutUrl']?.toString() ?? '',
            'paymentId': val['paymentId']?.toString() ?? '',
            'reference': val['reference']?.toString() ?? '',
          };
        } else {
          return {
            'success': false,
            'code': val['code']?.toString() ?? 'PAYMENT_FAILED',
            'message': val['message']?.toString() ?? val['error']?.toString() ?? 'Payment initialization failed',
            'error': val['message']?.toString() ?? val['error']?.toString() ?? 'Payment initialization failed',
            'rawError': val['rawError'],
          };
        }
      } else {
        final errMsg = res.errorMessage ?? 'Failed to initialize Moneroo payment';
        return {
          'success': false,
          'code': 'GATEWAY_ERROR',
          'message': errMsg,
          'error': errMsg,
        };
      }
    } catch (e) {
      debugPrint('[PaymentMethodsService] Moneroo init error: $e');
      return {
        'success': false,
        'code': 'NETWORK_ERROR',
        'message': e.toString(),
        'error': e.toString(),
      };
    }
  }

  /// Get status of a payment claim by transaction reference or paymentId.
  Future<Map<String, dynamic>?> getPaymentClaimStatus(String transactionReference) async {
    try {
      final res = await _client.query(
        'payments:getPaymentClaimStatus',
        args: {'transactionReference': transactionReference},
      );

      if (res.success && res.value is Map) {
        return Map<String, dynamic>.from(res.value as Map);
      }
    } catch (e) {
      debugPrint('[PaymentMethodsService] Error fetching claim status: $e');
    }
    return null;
  }

  /// Clear the cached payment methods (e.g., on logout).
  void clearCache() {
    _cachedMethods = [];
    _lastFetchTime = null;
  }
}

