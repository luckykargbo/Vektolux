import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/auth/data/repositories/auth_repository_impl.dart';

/// Test transport: records every request body and answers with [handler].
class RecordingClient extends http.BaseClient {
  RecordingClient(this.handler);

  final Future<http.Response> Function(int call, Map<String, dynamic> body) handler;
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final text = request is http.Request ? request.body : '{}';
    final body = jsonDecode(text) as Map<String, dynamic>;
    bodies.add(body);
    final r = await handler(bodies.length, body);
    return http.StreamedResponse(Stream.value(r.bodyBytes), r.statusCode, headers: r.headers, request: request);
  }
}

http.Response okJson(Object? value) =>
    http.Response(jsonEncode({'status': 'success', 'value': value}), 200, headers: {'content-type': 'application/json'});

const _token = 'aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbccccccccccccccccdddddddddddddddd';

Future<void> _seedSession() async {
  SharedPreferences.setMockInitialValues({
    'vkt_session_token': _token,
    'vkt_user_id': 'user_1',
    'vkt_user_data': jsonEncode({'id': 'user_1', 'name': 'Test', 'email': 't@test.vektolux'}),
  });
}

Future<Map<String, Object?>> _storedAuth() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'token': prefs.getString('vkt_session_token'),
    'userId': prefs.getString('vkt_user_id'),
    'userData': prefs.getString('vkt_user_data'),
  };
}

void main() {
  late ConvexClientWrapper convex;
  late AuthRepositoryImpl repo;

  AuthRepositoryImpl build(RecordingClient transport) {
    convex = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: transport);
    convex.setAuthToken(_token);
    return repo = AuthRepositoryImpl(convexClient: convex);
  }

  void expectLocallySignedOut(Map<String, Object?> stored) {
    expect(stored['token'], isNull);
    expect(stored['userId'], isNull);
    expect(stored['userData'], isNull);
    expect(convex.hasAuthToken, isFalse);
    expect(convex.authToken, isNull);
  }

  test('allow-list: auth:logout is sent with the session token argument', () async {
    await _seedSession();
    final transport = RecordingClient((_, __) async => okJson(true));
    await build(transport).logout();

    expect(transport.bodies, hasLength(1));
    expect(transport.bodies.single['path'], 'auth:logout');
    expect((transport.bodies.single['args'] as Map)['sessionToken'], _token);
  });

  test('successful logout revokes on the server BEFORE local credentials are cleared', () async {
    await _seedSession();
    Map<String, Object?>? storedWhenServerCalled;
    var tokenHeldByClientWhenCalled = false;
    final transport = RecordingClient((_, __) async {
      storedWhenServerCalled = await _storedAuth();
      tokenHeldByClientWhenCalled = convex.hasAuthToken;
      return okJson(true);
    });

    await build(transport).logout();

    expect(storedWhenServerCalled?['token'], _token, reason: 'server call must happen while the token is still stored');
    expect(tokenHeldByClientWhenCalled, isTrue);
    expect(transport.bodies, hasLength(1));
    expectLocallySignedOut(await _storedAuth());
  });

  test('server rejection (HTTP 500) still completes local logout', () async {
    await _seedSession();
    final transport = RecordingClient((_, __) async => http.Response('boom', 500));

    await build(transport).logout();

    expect(transport.bodies, isNotEmpty);
    expectLocallySignedOut(await _storedAuth());
  });

  test('server answering false (unknown/expired token) still completes local logout', () async {
    await _seedSession();
    final transport = RecordingClient((_, __) async => okJson(false));

    await build(transport).logout();

    expectLocallySignedOut(await _storedAuth());
  });

  test('offline / socket failure still completes local logout', () async {
    await _seedSession();
    final transport = RecordingClient((_, __) async => throw http.ClientException('Failed host lookup'));

    await build(transport).logout();

    // Exactly one attempt: no background retries, no HTTP-client reset after logout returns.
    expect(transport.bodies, hasLength(1));
    expectLocallySignedOut(await _storedAuth());
  });

  test('a server call that never answers cannot block logout (bounded wait)', () async {
    await _seedSession();
    final never = Completer<http.Response>();
    final transport = RecordingClient((_, __) => never.future);

    final watch = Stopwatch()..start();
    await build(transport).logout();
    watch.stop();

    expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
    expectLocallySignedOut(await _storedAuth());

    // Nothing keeps retrying in the background once logout has returned.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(transport.bodies, hasLength(1));
  });

  test('a rejected request (HTTP 500) is not retried', () async {
    await _seedSession();
    final transport = RecordingClient((_, __) async => http.Response('boom', 500));

    await build(transport).logout();

    expect(transport.bodies, hasLength(1));
  });

  test('logout without a stored session makes no server call and does not throw', () async {
    SharedPreferences.setMockInitialValues({});
    final transport = RecordingClient((_, __) async => okJson(true));
    convex = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: transport);
    repo = AuthRepositoryImpl(convexClient: convex);

    await repo.logout();

    expect(transport.bodies, isEmpty);
    expect(convex.hasAuthToken, isFalse);
  });

  test('token held only in memory is still revoked on the server', () async {
    SharedPreferences.setMockInitialValues({});
    final transport = RecordingClient((_, __) async => okJson(true));
    build(transport);

    await repo.logout();

    expect((transport.bodies.single['args'] as Map)['sessionToken'], _token);
    expect(convex.hasAuthToken, isFalse);
  });

  group('ConvexClientWrapper.mutation retry controls', () {
    test('maxAttempts: 1 makes a single attempt on a socket error', () async {
      final transport = RecordingClient((_, __) async => throw http.ClientException('Connection reset by peer'));
      final client = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: transport);

      final res = await client.mutation('anything:here', maxAttempts: 1);

      expect(res.success, isFalse);
      expect(transport.bodies, hasLength(1));
    });

    test('the default policy still retries socket errors 3 times', () async {
      final transport = RecordingClient((_, __) async => throw http.ClientException('Connection reset by peer'));
      final client = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: transport);

      final res = await client.mutation('anything:here');

      expect(res.success, isFalse);
      expect(transport.bodies, hasLength(3));
    });

    test('a short timeout with maxAttempts: 1 returns a timeout failure after one attempt', () async {
      final never = Completer<http.Response>();
      final transport = RecordingClient((_, __) => never.future);
      final client = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: transport);

      final res = await client.mutation('anything:here', maxAttempts: 1, timeout: const Duration(milliseconds: 200));

      expect(res.success, isFalse);
      expect(res.errorMessage, contains('timed out'));
      expect(transport.bodies, hasLength(1));
    });
  });
}
