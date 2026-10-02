// lib/core/network/convex_client_wrapper.dart
// ═══════════════════════════════════════════════════════════════════════
// Convex Client Wrapper — HTTP-based Convex API client for Flutter.
// Provides query, mutation, and action calls via Convex HTTP endpoints.
// Also manages real-time subscription polling for change detection.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

/// Result of a Convex function call.
class ConvexResult {
  final bool success;
  final dynamic value;
  final String? errorMessage;

  const ConvexResult({
    required this.success,
    this.value,
    this.errorMessage,
  });

  factory ConvexResult.fromResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          if (body['status'] == 'error') {
            String msg = body['errorMessage']?.toString() ?? 'Operation failed';
            final regex = RegExp(r'Uncaught Error:\s*([^\n]+)');
            final match = regex.firstMatch(msg);
            if (match != null && match.group(1) != null) {
              msg = match.group(1)!.trim();
            }
            return ConvexResult(
              success: false,
              errorMessage: msg,
            );
          }
          // Money functions REPORT a refused operation (bad PIN, locked wallet, …) as a returned
          // { success: false, errorCode, message } so server-side attempt counters persist.
          // Surface it as a failure so no caller can mistake it for success.
          final value = body['value'];
          if (value is Map &&
              value['success'] == false &&
              value['errorCode'] != null) {
            return ConvexResult(
              success: false,
              value: value,
              errorMessage:
                  value['message']?.toString() ?? 'The operation could not be completed.',
            );
          }
          return ConvexResult(
            success: true,
            value: body['value'] ?? body,
          );
        }
        return ConvexResult(
          success: true,
          value: body,
        );
      } catch (e) {
        return ConvexResult(
          success: false,
          errorMessage: 'Failed to parse response: $e',
        );
      }
    } else {
      String errorMsg = 'HTTP ${response.statusCode}: ${response.body}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded['code'] == 'InvalidAuthHeader') {
            errorMsg = 'Authentication session invalid or expired.';
          } else if (decoded['message'] != null) {
            errorMsg = decoded['message'].toString();
          }
        }
      } catch (_) {}
      return ConvexResult(
        success: false,
        errorMessage: errorMsg,
      );
    }
  }
}

/// HTTP-based Convex client for Flutter.
///
/// Convex deployments expose standard HTTP endpoints:
///   POST /api/query    — Read-only reactive queries
///   POST /api/mutation — Transactional writes
///   POST /api/action   — Side-effecting operations (external APIs)
class ConvexClientWrapper {
  final String deploymentUrl;
  http.Client _httpClient;

  /// True when this wrapper created its own HTTP client. An injected client (tests, custom
  /// transports) belongs to the caller: it is never closed or replaced by the retry logic.
  final bool _ownsHttpClient;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  String? _authToken;

  ConvexClientWrapper({
    required this.deploymentUrl,
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  /// Recreates the underlying HTTP client to flush corrupted or closed TCP socket pools.
  /// Only a client this wrapper created is recreated; an injected client is kept (the retry
  /// still happens, through the same injected client).
  void _resetHttpClient() {
    if (!_ownsHttpClient) return;
    try {
      _httpClient.close();
    } catch (_) {}
    _httpClient = http.Client();
  }

  // ═══════════════════════════════════════════════════════════════════
  //                        AUTH
  // ═══════════════════════════════════════════════════════════════════

  /// Current auth token (if set).
  String? get authToken => _authToken;

  /// Whether an auth token is currently configured.
  bool get hasAuthToken => _authToken != null && _authToken!.trim().isNotEmpty;

  /// Set the auth token for authenticated requests.
  void setAuthToken(String token) {
    _authToken = token;
  }

  /// Clear the auth token on logout.
  void clearAuth() {
    _authToken = null;
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     CORE API CALLS
  // ═══════════════════════════════════════════════════════════════════

  /// Execute a Convex query (read-only).
  Future<ConvexResult> query(
    String functionPath, {
    Map<String, dynamic> args = const {},
  }) async {
    return _callFunction('/api/query', functionPath, args);
  }

  /// Execute a Convex mutation (transactional write).
  Future<ConvexResult> mutation(
    String functionPath, {
    Map<String, dynamic> args = const {},
  }) async {
    return _callFunction('/api/mutation', functionPath, args);
  }

  /// Execute a Convex action (side effects allowed).
  Future<ConvexResult> action(
    String functionPath, {
    Map<String, dynamic> args = const {},
  }) async {
    return _callFunction('/api/action', functionPath, args);
  }

  // ═══════════════════════════════════════════════════════════════════
  //                  POLLING SUBSCRIPTION
  // ═══════════════════════════════════════════════════════════════════

  /// Poll a Convex query at the specified interval and emit results.
  /// This is a simplified alternative to WebSocket subscriptions.
  ///
  /// The stream emits only when the result changes (deduplication).
  Stream<dynamic> subscribe(
    String functionPath, {
    Map<String, dynamic> args = const {},
    Duration interval = const Duration(seconds: 5),
  }) {
    late StreamController<dynamic> controller;
    Timer? timer;
    dynamic lastResult;

    controller = StreamController<dynamic>.broadcast(
      onListen: () {
        // Immediately fetch
        _pollAndEmit(functionPath, args, controller, lastResult)
            .then((result) => lastResult = result);

        // Then poll periodically
        timer = Timer.periodic(interval, (_) {
          _pollAndEmit(functionPath, args, controller, lastResult)
              .then((result) => lastResult = result);
        });
      },
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  Future<dynamic> _pollAndEmit(
    String path,
    Map<String, dynamic> args,
    StreamController<dynamic> controller,
    dynamic lastResult,
  ) async {
    try {
      final result = await query(path, args: args);
      if (result.success) {
        final encoded = jsonEncode(result.value);
        final lastEncoded =
            lastResult != null ? jsonEncode(lastResult) : null;

        // Only emit if the data actually changed
        if (encoded != lastEncoded) {
          controller.add(result.value);
          return result.value;
        }
      }
    } catch (e) {
      _log.e('Subscription poll error for $path: $e');
    }
    return lastResult;
  }

  // ═══════════════════════════════════════════════════════════════════
  //                       INTERNAL
  // ═══════════════════════════════════════════════════════════════════

  Future<ConvexResult> _callFunction(
    String endpoint,
    String functionPath,
    Map<String, dynamic> args,
  ) async {
    final url = Uri.parse('$deploymentUrl$endpoint');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Vektolux/1.0.0 (Mobile; Dart/Flutter)',
    };
    // Convex Cloud HTTP API expects an OIDC / Convex Auth JWT if an Authorization header
    // is provided. If an arbitrary or session-hex token is attached, Convex Cloud immediately
    // rejects the call with HTTP 401: {"code": "InvalidAuthHeader"}.
    // Application-level session tokens are transmitted in the function args.
    if (_authToken != null && _authToken!.trim().isNotEmpty && _isValidJwt(_authToken!.trim())) {
      headers['Authorization'] = 'Bearer ${_authToken!.trim()}';
    }

    // Identity is proven by the session token, never by a user id in the args. For the
    // financial / escrow / QR / withdrawal functions (which all accept `sessionToken`), attach
    // the logged-in user's token automatically so no call site can forget it.
    final outgoingArgs = Map<String, dynamic>.from(args);
    if (hasAuthToken &&
        !outgoingArgs.containsKey('sessionToken') &&
        _acceptsSessionToken(functionPath)) {
      outgoingArgs['sessionToken'] = _authToken!.trim();
    }

    final body = jsonEncode({
      'path': functionPath,
      'args': outgoingArgs,
      'format': 'json',
    });

    int attempt = 0;
    const maxAttempts = 3;
    while (true) {
      attempt++;
      try {
        final response = await _httpClient
            .post(url, headers: headers, body: body)
            .timeout(const Duration(seconds: 25));

        return ConvexResult.fromResponse(response);
      } on TimeoutException {
        if (attempt >= maxAttempts) {
          return const ConvexResult(
            success: false,
            errorMessage: 'Request timed out. Please check your internet connection and try again.',
          );
        }
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      } catch (e) {
        final err = e.toString();
        final isSocketError = err.contains('Connection reset') ||
            err.contains('SocketException') ||
            err.contains('ClientException') ||
            err.contains('Broken pipe') ||
            err.contains('Failed host lookup') ||
            err.contains('HandshakeException');

        if (attempt < maxAttempts && isSocketError) {
          _log.w('Transient socket error on $functionPath (attempt $attempt): $err. Resetting connection pool & retrying...');
          _resetHttpClient();
          await Future.delayed(Duration(milliseconds: 300 * attempt));
          continue;
        }

        // Sanitize technical network/socket errors for clean mobile UX
        String userFriendlyMessage = 'Network error occurred. Please check your connection and try again.';
        if (err.contains('Connection reset') || err.contains('errno = 54') || err.contains('errno = 104')) {
          userFriendlyMessage = 'Server connection was interrupted. Please try again.';
        } else if (err.contains('Failed host lookup') || err.contains('No address associated')) {
          userFriendlyMessage = 'Unable to reach Vektolux servers. Please check your internet connection.';
        } else if (err.contains('SocketException')) {
          userFriendlyMessage = 'Network connection failed. Please check your mobile data or Wi-Fi.';
        }

        return ConvexResult(
          success: false,
          errorMessage: userFriendlyMessage,
        );
      }
    }
  }

  /// Backend functions that authenticate the caller via `sessionToken`.
  /// (Convex rejects unknown args, so this must list ONLY functions that declare it.)
  static const Set<String> _sessionTokenFunctions = {
    // wallet / payments
    'wallet:getUserBalance',
    'wallet:getWalletBalance',
    'walletCore:getUserTransactions',
    'walletCore:getEarningsSummary',
    'users:getWalletProfile',
    'users:getUserById',
    'users:updateUserProfile',
    'users:updateAvatar',
    'users:switchActiveRole',
    'users:applyRoleUpgrade',
    'users:applyForSellerVerification',
    'users:linkPhoneNumber',
    'users:verifyTransactionPin',
    'payments:getWalletBalance',
    'payments:getTransactionHistory',
    'payments:verifyTransactionPin',
    'payments:verifyWalletPin',
    'payments:getUserSecurityPinStatus',
    'payments:setWalletPin',
    'payments:executeP2PTransfer',
    'payments:resolveRecipient',
    'payments:createEscrowPayment',
    'payments:releaseEscrowWithSplit',
    'payments:submitManualPaymentClaim',
    'payments:getUserPaymentClaims',
    'payments:getPaymentClaimStatus',
    'payments:getUserPaymentAccounts',
    'payments:addUserPaymentAccount',
    'payments:removeUserPaymentAccount',
    'payments:setDefaultPaymentAccount',
    'payments:getTransactionReceipt',
    'payments:getPaymentStatus',
    'payments:generateBankEscrowReference',
    'payments:initiateMoniMePayment',
    'payments:createTopUpSession',
    'payments:createCheckoutSession',
    'payments:initializePayment',
    'bookings:createBooking',
    'agentVerification:submitVerification',
    'agentVerification:getVerificationStatus',
    'agentVerification:reuploadDocument',
    'notifications:getUserNotifications',
    'notifications:getUnreadNotificationCount',
    'notifications:markAsRead',
    'notifications:markAllAsRead',
    'adminPortal:getSellerContactRequests',
    'adminPortal:respondToContactRequest',
    'bookings:getUserBookings',
    'bookings:cancelBooking',
    'bookings:confirmBookingCompletion',
    'bookings:raiseBookingDispute',
    'payments:verifyAndSettleMoniMePayment',
    'payments:verifyMoniMeStatus',
    'payments:confirmBankEscrowTransfer',
    'payments:resolveManualPaymentClaim',
    'payments:updatePaymentMethod',
    'payments:seedDefaultPaymentMethods',
    'payments:getAllPaymentMethods',
    'payments:getPendingApprovalClaims',
    'payments:getAllEscrowClaims',
    'payments:getAuditLogs',
    // vehicle escrow
    'escrow:initiateEscrowOrder',
    'escrow:completeVehicleInspection',
    'escrow:releaseMilestoneHandoff60',
    'escrow:settleVehicleReturn',
    'escrow:confirmSlrsaTransfer',
    'escrow:releaseDealEscrowFunds',
    'escrow:raiseEscrowDispute',
    'escrow:getMyEscrowOrders',
    'escrow:getEscrowOrderById',
    'escrow:getAdminEscrowSummary',
    // real-estate escrow
    'realEstateEscrow:initiateInspectionPass',
    'realEstateEscrow:verifyInspectionPass',
    'realEstateEscrow:initiateRealEstateEscrow',
    'realEstateEscrow:checkInShortStay',
    'realEstateEscrow:releaseShortStayPayout24h',
    'realEstateEscrow:refundCautionDeposit',
    'realEstateEscrow:verifyAndReleaseLandMilestone',
    'realEstateEscrow:raiseRealEstateDispute',
    'realEstateEscrow:getMyRealEstateEscrows',
    'realEstateEscrow:getRealEstateEscrowById',
    'realEstateEscrow:getAdminRealEstateEscrowSummary',
    // listings, social, account and in-app admin tools (session required server-side)
    'social:toggleFollow',
    'mobility:updateVehicleListing',
    'mobility:createVehicleListing',
    'mobility:deleteVehicleListing',
    'mobility:getMyVehicleListings',
    'realEstate:createPropertyListing',
    'realEstate:updatePropertyListing',
    'realEstate:deletePropertyListing',
    'realEstate:getMyPropertyListings',
    'users:deleteUserAccount',
    'verification:mockCompleteVerification',
    'admin:getAllUsers',
    'admin:toggleUserActiveStatus',
    'adminPortal:getFinancialSummary',
    'adminPortal:getTransactionHeatmap',
    'adminPortal:getUserDemographics',
    'adminPortal:getApiHealthIncidents',
    'adminPortal:getApiKeysConfig',
    'adminPortal:rotateApiKeyMask',
    'adminPortal:seedApiKeysConfig',
    'adminPortal:deleteMerchantTerminal',
    'adminPortal:getMerchantTerminals',
    'adminPortal:toggleTerminalStatus',
    'adminPortal:upsertMerchantTerminal',
    'adminPortal:getAdminUserAuditView',
    'users:getUserProfile',
    'users:updateBio',
    'verification:getVerificationStatus',
    'verification:initiateVerification',
    'escrow:uploadSlrsaDocuments',
    'files:generateUploadUrl',
    // identity verification (KYC) — owner only
    'businessVerification:submitTieredVerification',
    'businessVerification:submitAgentVerification',
    'businessVerification:getMyVerificationStatus',
    // subscriptions
    'subscriptions:getUserActiveSubscription',
    'subscriptions:subscribeWithWallet',
    'subscriptions:getMyProfessionalStatus',
    'subscriptions:adminListSubscriptions',
    'subscriptions:adminGrantSubscription',
    // business-role applications (admin review)
    'roles:adminListRoleApplications',
    'roles:adminDecideRoleApplication',
    'subscriptions:adminUpsertPlan',
    'subscriptions:adminTogglePlanStatus',
    // vehicles
    'mobility:updateVehicleListingStatus',
  };

  static bool _acceptsSessionToken(String functionPath) =>
      functionPath.startsWith('qrPayment:') ||
      functionPath.startsWith('withdrawals:') ||
      _sessionTokenFunctions.contains(functionPath);

  /// Checks if a token matches the standard 3-part base64 JWT format.
  static bool _isValidJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    final jwtCharRegex = RegExp(r'^[A-Za-z0-9_-]+$');
    return parts[0].isNotEmpty &&
        parts[1].isNotEmpty &&
        jwtCharRegex.hasMatch(parts[0]) &&
        jwtCharRegex.hasMatch(parts[1]);
  }

  /// Dispose HTTP client resources.
  void dispose() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
