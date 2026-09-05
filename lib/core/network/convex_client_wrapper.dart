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
      return ConvexResult(
        success: false,
        errorMessage: 'HTTP ${response.statusCode}: ${response.body}',
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
  final http.Client _httpClient;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  String? _authToken;

  ConvexClientWrapper({
    required this.deploymentUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  // ═══════════════════════════════════════════════════════════════════
  //                        AUTH
  // ═══════════════════════════════════════════════════════════════════

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
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }

    final body = jsonEncode({
      'path': functionPath,
      'args': args,
      'format': 'json',
    });

    try {
      final response = await _httpClient
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));

      return ConvexResult.fromResponse(response);
    } on TimeoutException {
      return const ConvexResult(
        success: false,
        errorMessage: 'Request timed out',
      );
    } catch (e) {
      return ConvexResult(
        success: false,
        errorMessage: 'Network error: $e',
      );
    }
  }

  /// Dispose HTTP client resources.
  void dispose() {
    _httpClient.close();
  }
}
