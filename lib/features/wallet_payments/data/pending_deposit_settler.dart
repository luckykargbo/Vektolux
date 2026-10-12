// lib/features/wallet_payments/data/pending_deposit_settler.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Settles the signed-in user's own pending Monime deposits.
//
// Monime documents no webhook for hosted-checkout payments yet, so a payment made after the app was
// closed would otherwise sit "pending" until someone checked. The server action
// `payments:checkMyPendingDeposits` re-verifies each of the caller's own pending deposits with
// Monime itself and credits only what Monime reports as completed (idempotent, budgeted per account).
//
// This class is the client-side guard rail so that calling it from several screens can never become a
// request loop:
//   • single-flight: concurrent callers for the same user share one request;
//   • throttled: at most one request per [minInterval] per user (a manual refresh may use the shorter
//     [minForcedInterval]);
//   • never throws: every outcome is a [DepositSettleResult].
// ═══════════════════════════════════════════════════════════════════════

import '../../../core/network/convex_client_wrapper.dart';

enum DepositSettleStatus {
  /// The server answered (it may have settled nothing).
  ok,

  /// Not called: asked again too soon for this user.
  throttled,

  /// The session is missing/expired. Nothing was changed; the screen's own load reports sign-in issues.
  notSignedIn,

  /// Network / provider / server problem. Nothing was changed; trying again later is safe.
  failed,
}

class DepositSettleResult {
  final DepositSettleStatus status;
  final int checked;
  final int settled;
  const DepositSettleResult(this.status, {this.checked = 0, this.settled = 0});

  bool get anySettled => settled > 0;
}

class PendingDepositSettler {
  PendingDepositSettler({
    DateTime Function()? clock,
    this.minInterval = const Duration(seconds: 30),
    this.minForcedInterval = const Duration(seconds: 5),
  }) : _clock = clock ?? DateTime.now;

  /// App-wide instance, so the home screen and the history screen share one throttle.
  static final PendingDepositSettler shared = PendingDepositSettler();

  final DateTime Function() _clock;
  final Duration minInterval;
  final Duration minForcedInterval;

  final Map<String, DateTime> _lastRun = {};
  final Map<String, Future<DepositSettleResult>> _inFlight = {};

  static final RegExp _authError = RegExp(
    r'session|authenticat|unauthori|not signed in|sign in|expired',
    caseSensitive: false,
  );

  /// Checks the user's pending deposits. [force] is for an explicit user refresh (shorter throttle).
  Future<DepositSettleResult> settle(
    ConvexClientWrapper client, {
    required String userId,
    bool force = false,
  }) {
    final running = _inFlight[userId];
    if (running != null) return running;

    final last = _lastRun[userId];
    final gap = force ? minForcedInterval : minInterval;
    if (last != null && _clock().difference(last) < gap) {
      return Future.value(const DepositSettleResult(DepositSettleStatus.throttled));
    }
    _lastRun[userId] = _clock();

    // NOTE: the callback must return void. Returning `_inFlight.remove(...)` (the very future being
    // completed) would make whenComplete wait on itself forever.
    final future = _run(client).whenComplete(() {
      _inFlight.remove(userId);
    });
    _inFlight[userId] = future;
    return future;
  }

  Future<DepositSettleResult> _run(ConvexClientWrapper client) async {
    try {
      final res = await client.action('payments:checkMyPendingDeposits', args: const {});
      if (!res.success) {
        final msg = res.errorMessage ?? '';
        return DepositSettleResult(_authError.hasMatch(msg) ? DepositSettleStatus.notSignedIn : DepositSettleStatus.failed);
      }
      final v = res.value;
      if (v is Map) {
        return DepositSettleResult(
          DepositSettleStatus.ok,
          checked: (v['checked'] as num?)?.toInt() ?? 0,
          settled: (v['settled'] as num?)?.toInt() ?? 0,
        );
      }
      return const DepositSettleResult(DepositSettleStatus.failed);
    } catch (_) {
      return const DepositSettleResult(DepositSettleStatus.failed);
    }
  }

  /// Forget throttle state (sign-out / account switch).
  void reset() {
    _lastRun.clear();
  }
}
