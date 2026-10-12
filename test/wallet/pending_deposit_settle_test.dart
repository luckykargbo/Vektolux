import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/auth/domain/repositories/auth_repository.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/wallet_payments/data/pending_deposit_settler.dart';
import 'package:vektolux/features/wallet_payments/presentation/bloc/wallet_cubit.dart';
import 'package:vektolux/features/wallet_payments/presentation/bloc/wallet_state.dart';
import 'package:vektolux/features/wallet_payments/presentation/views/transaction_history_screen.dart';

/// Fake backend: answers by function path, counts calls, can delay / fail.
class _Backend extends http.BaseClient {
  final Map<String, int> counts = {};
  double balance = 0;
  List<Map<String, dynamic>> transactions = [];
  Map<String, dynamic> Function() settle = () => {'checked': 0, 'settled': 0};
  Duration settleDelay = Duration.zero;
  String? settleHttpError; // makes the action answer with an error status
  bool settleThrows = false;
  void Function()? onSettled; // runs when a settle call reports settled > 0 (credits the balance)

  /// Delays applied, in order, to successive getUserBalance calls. The answer is the balance AT THE
  /// MOMENT THE REQUEST ARRIVED, so a delayed call returns stale data like a slow network would.
  final List<Duration> balanceDelays = [];

  int count(String path) => counts[path] ?? 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonDecode(request is http.Request ? request.body : '{}') as Map<String, dynamic>;
    final path = body['path'] as String;
    counts[path] = count(path) + 1;
    Object? value;
    var status = 200;
    switch (path) {
      case 'wallet:getUserBalance':
        final snapshot = balance;
        if (balanceDelays.isNotEmpty) await Future<void>.delayed(balanceDelays.removeAt(0));
        value = {'availableBalance': snapshot, 'escrowBalance': 0, 'pendingBalance': 0, 'currency': 'SLE'};
      case 'walletCore:getUserTransactions':
        value = {'transactions': transactions};
      case 'payments:checkMyPendingDeposits':
        if (settleDelay > Duration.zero) await Future<void>.delayed(settleDelay);
        if (settleThrows) throw Exception('network down');
        if (settleHttpError != null) {
          status = 400;
          value = settleHttpError;
        } else {
          final r = settle();
          if ((r['settled'] as int) > 0) onSettled?.call();
          value = r;
        }
      default:
        value = null;
    }
    final text = status == 200
        ? jsonEncode({'status': 'success', 'value': value})
        : jsonEncode({'status': 'error', 'errorMessage': value});
    return http.StreamedResponse(Stream.value(utf8.encode(text)), status,
        headers: {'content-type': 'application/json'}, request: request);
  }
}

class _Clock {
  DateTime now = DateTime(2026, 10, 12, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _Backend backend;
  late ConvexClientWrapper client;
  late _Clock clock;
  late PendingDepositSettler settler;

  setUp(() {
    backend = _Backend();
    client = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: backend);
    client.setAuthToken('t' * 64);
    clock = _Clock();
    settler = PendingDepositSettler(clock: clock.call);
  });

  group('PendingDepositSettler', () {
    test('sends the authenticated action with the session token and parses the answer', () async {
      backend.settle = () => {'checked': 2, 'settled': 1};
      final r = await settler.settle(client, userId: 'u1');
      expect(r.status, DepositSettleStatus.ok);
      expect(r.checked, 2);
      expect(r.settled, 1);
      expect(backend.count('payments:checkMyPendingDeposits'), 1);
    });

    test('single-flight: simultaneous callers share one request', () async {
      backend.settleDelay = const Duration(milliseconds: 50);
      final results = await Future.wait([
        settler.settle(client, userId: 'u1'),
        settler.settle(client, userId: 'u1'),
        settler.settle(client, userId: 'u1', force: true),
      ]);
      expect(backend.count('payments:checkMyPendingDeposits'), 1);
      expect(results.every((r) => r.status == DepositSettleStatus.ok), isTrue);
    });

    test('throttled: repeated calls inside the interval do not reach the server', () async {
      await settler.settle(client, userId: 'u1');
      clock.advance(const Duration(seconds: 10));
      final again = await settler.settle(client, userId: 'u1');
      expect(again.status, DepositSettleStatus.throttled);
      expect(backend.count('payments:checkMyPendingDeposits'), 1);
      clock.advance(const Duration(seconds: 25)); // 35 s since the first
      expect((await settler.settle(client, userId: 'u1')).status, DepositSettleStatus.ok);
      expect(backend.count('payments:checkMyPendingDeposits'), 2);
    });

    test('an explicit refresh uses the shorter interval, never a request loop', () async {
      await settler.settle(client, userId: 'u1');
      clock.advance(const Duration(seconds: 2));
      expect((await settler.settle(client, userId: 'u1', force: true)).status, DepositSettleStatus.throttled);
      clock.advance(const Duration(seconds: 4)); // 6 s
      expect((await settler.settle(client, userId: 'u1', force: true)).status, DepositSettleStatus.ok);
      expect(backend.count('payments:checkMyPendingDeposits'), 2);
    });

    test('throttle is per user (an account switch is not blocked, nor shared)', () async {
      await settler.settle(client, userId: 'u1');
      expect((await settler.settle(client, userId: 'u2')).status, DepositSettleStatus.ok);
      expect(backend.count('payments:checkMyPendingDeposits'), 2);
    });

    test('failures never throw: network error -> failed; expired session -> notSignedIn', () async {
      backend.settleThrows = true;
      expect((await settler.settle(client, userId: 'u1')).status, DepositSettleStatus.failed);
      backend.settleThrows = false;
      backend.settleHttpError = 'Authentication required: session expired';
      clock.advance(const Duration(minutes: 1));
      expect((await settler.settle(client, userId: 'u1')).status, DepositSettleStatus.notSignedIn);
      backend.settleHttpError = 'Something broke on the server';
      clock.advance(const Duration(minutes: 1));
      expect((await settler.settle(client, userId: 'u1')).status, DepositSettleStatus.failed);
    });

    test('a failed attempt is not retried in a tight loop (it counts toward the throttle)', () async {
      backend.settleThrows = true;
      await settler.settle(client, userId: 'u1');
      final again = await settler.settle(client, userId: 'u1');
      expect(again.status, DepositSettleStatus.throttled);
      expect(backend.count('payments:checkMyPendingDeposits'), 1);
    });
  });

  group('WalletCubit', () {
    test('opening the wallet loads it AND checks pending deposits once; nothing settled -> no extra reload', () async {
      final cubit = WalletCubit(convexClient: client, settler: settler);
      await cubit.loadWallet(userId: 'u1', sessionToken: 's');
      expect(backend.count('payments:checkMyPendingDeposits'), 1);
      expect(backend.count('wallet:getUserBalance'), 1);
      expect(backend.count('walletCore:getUserTransactions'), 1);
      expect(cubit.state.isCheckingDeposits, isFalse);
      expect(cubit.state.settledDeposits, 0);
      expect(cubit.state.depositCheckFailed, isFalse);
      await cubit.close();
    });

    test('a confirmed deposit refreshes the balance and history once, and is reported', () async {
      backend.balance = 0;
      backend.settle = () => {'checked': 1, 'settled': 1};
      backend.onSettled = () {
        backend.balance = 50;
        backend.transactions = [
          {'id': 'x', 'transactionId': 'T1', 'type': 'top_up', 'amount': 50, 'currency': 'SLE', 'status': 'completed', 'createdAt': 1}
        ];
      };
      final cubit = WalletCubit(convexClient: client, settler: settler);
      await cubit.loadWallet(userId: 'u1');
      expect(cubit.state.availableBalance, 50);
      expect(cubit.state.transactions, hasLength(1));
      expect(cubit.state.settledDeposits, 1);
      expect(backend.count('payments:checkMyPendingDeposits'), 1); // the reload never triggers another check
      await cubit.close();
    });

    test('repeated opens inside the throttle window do not call the server again', () async {
      final cubit = WalletCubit(convexClient: client, settler: settler);
      await cubit.loadWallet(userId: 'u1');
      await cubit.loadWallet(userId: 'u1');
      await cubit.loadWallet(userId: 'u1');
      expect(backend.count('payments:checkMyPendingDeposits'), 1);
      expect(backend.count('wallet:getUserBalance'), 3); // the wallet itself still refreshes
      await cubit.close();
    });

    test('duplicate settlement: the server answering settled=0 the second time changes nothing', () async {
      var first = true;
      backend.settle = () {
        final r = first ? {'checked': 1, 'settled': 1} : {'checked': 0, 'settled': 0};
        first = false;
        return r;
      };
      backend.onSettled = () => backend.balance = 50;
      final cubit = WalletCubit(convexClient: client, settler: settler);
      await cubit.loadWallet(userId: 'u1');
      expect(cubit.state.availableBalance, 50);
      clock.advance(const Duration(minutes: 1));
      await cubit.loadWallet(userId: 'u1', force: true);
      expect(cubit.state.availableBalance, 50);
      expect(cubit.state.settledDeposits, 0);
      await cubit.close();
    });

    test('stale read: a slow first load can never overwrite the balance read after a confirmed deposit', () async {
      backend.balance = 0;
      backend.balanceDelays.add(const Duration(milliseconds: 400)); // first load is slow and stale
      backend.settleDelay = const Duration(milliseconds: 100); // the credit lands AFTER that read was taken
      backend.settle = () => {'checked': 1, 'settled': 1};
      backend.onSettled = () => backend.balance = 50; // credited while the first read is still in flight
      final cubit = WalletCubit(convexClient: client, settler: settler);
      await cubit.loadWallet(userId: 'u1');
      await Future<void>.delayed(const Duration(milliseconds: 500)); // let the stale response arrive
      expect(cubit.state.availableBalance, 50);
      expect(cubit.state.isLoading, isFalse);
      await cubit.close();
    });

    test('provider/network error: the wallet still loads; the check reports a soft failure', () async {
      backend.balance = 12;
      backend.settleHttpError = 'Upstream provider error';
      final cubit = WalletCubit(convexClient: client, settler: settler);
      await cubit.loadWallet(userId: 'u1');
      expect(cubit.state.availableBalance, 12);
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.depositCheckFailed, isTrue);
      expect(cubit.state.isCheckingDeposits, isFalse);
      await cubit.close();
    });

    test('expired session: no deposit-check banner state (sign-in problems are not reported as a failed check)', () async {
      backend.settleHttpError = 'Authentication required: session expired';
      final cubit = WalletCubit(convexClient: client, settler: settler);
      await cubit.loadWallet(userId: 'u1');
      expect(cubit.state.depositCheckFailed, isFalse);
      expect(cubit.state.settledDeposits, 0);
      await cubit.close();
    });

    test('the wallet is never blocked by a slow check: balance is shown before the check finishes', () async {
      backend.balance = 7;
      backend.settleDelay = const Duration(milliseconds: 200);
      final cubit = WalletCubit(convexClient: client, settler: settler);
      final done = cubit.loadWallet(userId: 'u1');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(cubit.state.availableBalance, 7);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.isCheckingDeposits, isTrue);
      await done;
      expect(cubit.state.isCheckingDeposits, isFalse);
      await cubit.close();
    });

    test('closing the screen mid-check does not throw or emit', () async {
      backend.settleDelay = const Duration(milliseconds: 100);
      backend.settle = () => {'checked': 1, 'settled': 1};
      final cubit = WalletCubit(convexClient: client, settler: settler);
      final done = cubit.loadWallet(userId: 'u1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await cubit.close();
      await done; // completes without a "emit after close" error
    });
  });

  group('TransactionHistoryScreen banner', () {
    Future<_TestCubit> pump(WidgetTester tester) async {
      final cubit = _TestCubit(client);
      addTearDown(cubit.close);
      await tester.pumpWidget(MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>(create: (_) => AuthBloc(repository: _NoRepo())),
            BlocProvider<WalletCubit>.value(value: cubit),
          ],
          child: TransactionHistoryScreen(convexClient: client),
        ),
      ));
      await tester.pump();
      return cubit;
    }

    testWidgets('shows checking, then confirmed, and a soft failure message', (tester) async {
      final cubit = await pump(tester);
      expect(find.byKey(const Key('deposit-check-running')), findsNothing);

      cubit.set(const WalletState(isCheckingDeposits: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('deposit-check-running')), findsOneWidget);

      cubit.set(const WalletState(settledDeposits: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('2 deposits confirmed. Your balance is updated.'), findsOneWidget);

      cubit.set(const WalletState(depositCheckFailed: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('deposit-check-failed')), findsOneWidget);
      expect(find.textContaining('Pull down or tap refresh'), findsOneWidget);
    });
  });
}

class _TestCubit extends WalletCubit {
  _TestCubit(ConvexClientWrapper c) : super(convexClient: c);
  void set(WalletState s) => emit(s);
}

class _NoRepo extends Fake implements AuthRepository {}
