// lib/core/network/connectivity_monitor.dart
// ═══════════════════════════════════════════════════════════════════════
// Network Connectivity Monitor
// Wraps connectivity_plus to provide a reactive stream of online/offline
// state and automatic reconnection event firing.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';

/// Simplified connectivity state.
enum NetworkStatus { online, offline }

/// Monitors device network connectivity and exposes reactive streams.
///
/// Usage:
/// ```dart
/// final monitor = ConnectivityMonitor();
/// monitor.statusStream.listen((status) {
///   if (status == NetworkStatus.online) syncEngine.triggerSync();
/// });
/// ```
class ConnectivityMonitor {
  final Connectivity _connectivity;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  final StreamController<NetworkStatus> _statusController =
      StreamController<NetworkStatus>.broadcast();

  final StreamController<void> _reconnectedController =
      StreamController<void>.broadcast();

  NetworkStatus _currentStatus = NetworkStatus.offline;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  ConnectivityMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  // ═══════════════════════════════════════════════════════════════════
  //                        PUBLIC API
  // ═══════════════════════════════════════════════════════════════════

  /// Current connectivity status (synchronous read).
  NetworkStatus get currentStatus => _currentStatus;

  /// Whether the device is currently online.
  bool get isOnline => _currentStatus == NetworkStatus.online;

  /// Reactive stream of connectivity status changes.
  Stream<NetworkStatus> get statusStream => _statusController.stream;

  /// Fires when the device transitions from offline → online.
  /// Use this to trigger sync engine flushes.
  Stream<void> get onReconnected => _reconnectedController.stream;

  /// Initialize the monitor and start listening for connectivity changes.
  Future<void> initialize() async {
    // Check initial state
    final results = await _connectivity.checkConnectivity();
    _updateStatus(results);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen(
      _updateStatus,
      onError: (error) {
        _log.e('Connectivity monitor error: $error');
      },
    );

    _log.i('ConnectivityMonitor initialized: $_currentStatus');
  }

  /// Manually check connectivity (e.g., before a critical operation).
  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    _updateStatus(results);
    return isOnline;
  }

  /// Dispose all subscriptions and streams.
  void dispose() {
    _subscription?.cancel();
    _statusController.close();
    _reconnectedController.close();
  }

  // ═══════════════════════════════════════════════════════════════════
  //                       INTERNAL
  // ═══════════════════════════════════════════════════════════════════

  void _updateStatus(List<ConnectivityResult> results) {
    final newStatus = _isConnected(results)
        ? NetworkStatus.online
        : NetworkStatus.offline;

    if (newStatus != _currentStatus) {
      final wasOffline = _currentStatus == NetworkStatus.offline;
      _currentStatus = newStatus;
      _statusController.add(newStatus);

      if (wasOffline && newStatus == NetworkStatus.online) {
        _log.i('Network RECONNECTED — triggering sync');
        _reconnectedController.add(null);
      } else if (newStatus == NetworkStatus.offline) {
        _log.w('Network OFFLINE — operating in local-first mode');
      }
    }
  }

  bool _isConnected(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
  }
}
