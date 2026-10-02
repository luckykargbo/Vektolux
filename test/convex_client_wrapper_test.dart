import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vektolux/core/network/convex_client_wrapper.dart';

/// Test transport: answers with [handler], counts every request, and records close().
/// If the wrapper ever swapped it for a real client, the counts below would not add up.
class TrackingClient extends http.BaseClient {
  TrackingClient(this.handler);

  final Future<http.Response> Function(int call, http.BaseRequest request) handler;
  final List<Uri> requests = [];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) throw StateError('used after close');
    requests.add(request.url);
    final r = await handler(requests.length, request);
    return http.StreamedResponse(Stream.value(r.bodyBytes), r.statusCode, headers: r.headers, request: request);
  }

  @override
  void close() => closed = true;
}

http.Response ok(Object? value) =>
    http.Response(jsonEncode({'status': 'success', 'value': value}), 200, headers: {'content-type': 'application/json'});

void main() {
  group('an injected HTTP client is never replaced by the retry logic', () {
    test('a transient socket error is retried through the SAME injected client', () async {
      final transport = TrackingClient((call, _) async {
        if (call == 1) throw http.ClientException('Connection reset by peer');
        return ok({'answer': 42});
      });
      final client = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: transport);

      final res = await client.query('anything:here');

      expect(res.success, isTrue);
      expect((res.value as Map)['answer'], 42);
      expect(transport.requests, hasLength(2)); // the retry reached the injected client
      expect(transport.closed, isFalse);
    });

    test('persistent socket errors exhaust every retry on the injected client (no real network)', () async {
      final transport = TrackingClient((_, __) async => throw http.ClientException('Failed host lookup'));
      final client = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: transport);

      final res = await client.mutation('anything:here');

      expect(res.success, isFalse);
      expect(transport.requests, hasLength(3)); // all 3 attempts went to the injected client
      expect(transport.requests.every((u) => u.host == 'test.invalid'), isTrue);
      expect(transport.closed, isFalse);
    });

    test('later calls after a failure still use the injected client', () async {
      var fail = true;
      final transport = TrackingClient((_, __) async {
        if (fail) throw http.ClientException('Connection reset by peer');
        return ok('fine');
      });
      final client = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: transport);

      expect((await client.query('a:b')).success, isFalse);
      final before = transport.requests.length;
      fail = false;
      final res = await client.query('a:b');
      expect(res.success, isTrue);
      expect(res.value, 'fine');
      expect(transport.requests.length, before + 1);
    });

    test('dispose() does not close a client the wrapper does not own', () {
      final transport = TrackingClient((_, __) async => ok(null));
      ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: transport).dispose();
      expect(transport.closed, isFalse);
    });
  });
}
