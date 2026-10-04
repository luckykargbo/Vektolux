import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

  group('the session token is attached only to server functions that declare it', () {
    Future<Map<String, dynamic>> sentArgs(String path, {String? token, Map<String, dynamic> args = const {}}) async {
      late Map<String, dynamic> sent;
      final transport = TrackingClient((_, request) async {
        sent = Map<String, dynamic>.from((jsonDecode((request as http.Request).body) as Map)['args'] as Map);
        return ok(null);
      });
      final client = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: transport);
      if (token != null) client.setAuthToken(token);
      await client.mutation(path, args: args);
      return sent;
    }

    test('saved properties, view counting, viewing requests and the agent\'s listing actions carry the session', () async {
      for (final path in [
        'savedListings:toggleSavedListing',
        'savedListings:getMySavedListingIds',
        'savedListings:getMySavedListings',
        'listingStats:recordPropertyView',
        'bookings:createBooking',
        'bookings:getMyViewingRequests',
        'bookings:respondToViewingRequest',
        'bookings:cancelBooking',
        'realEstate:archivePropertyListing',
        'realEstate:restorePropertyListing',
        'realEstate:updatePropertyListing',
      ]) {
        expect((await sentArgs(path, token: 'sess_abc'))['sessionToken'], 'sess_abc', reason: path);
      }
    });

    test('logged out: no session is sent', () async {
      expect((await sentArgs('savedListings:toggleSavedListing')).containsKey('sessionToken'), isFalse);
    });

    test('a public function never receives one (Convex rejects arguments a function does not declare)', () async {
      expect((await sentArgs('realEstate:listProperties', token: 'sess_abc')).containsKey('sessionToken'), isFalse);
      expect((await sentArgs('realEstate:getPropertyById', token: 'sess_abc', args: {'listingId': 'p1'})), {'listingId': 'p1'});
    });

    test('a session the caller already put in the arguments is kept as given', () async {
      final sent = await sentArgs('savedListings:toggleSavedListing', token: 'sess_abc', args: {'sessionToken': 'sess_other'});
      expect(sent['sessionToken'], 'sess_other');
    });

    // Convex rejects an argument a function does not declare, so a function listed here that does not
    // declare `sessionToken` would fail for every logged-in user. Checked against the server source.
    test('every function in the allowlist exists on the server and declares sessionToken', () {
      final wrapper = File('lib/core/network/convex_client_wrapper.dart').readAsStringSync();
      final block = RegExp(r'_sessionTokenFunctions\s*=\s*\{(.*?)\n  \};', dotAll: true).firstMatch(wrapper)!.group(1)!;
      final entries = RegExp(r"'([A-Za-z0-9_]+:[A-Za-z0-9_]+)'")
          .allMatches(block.replaceAll(RegExp(r'//[^\n]*'), ''))
          .map((m) => m.group(1)!)
          .toList();
      expect(entries.length, greaterThan(100), reason: 'the allowlist was found');

      final problems = <String>[];
      for (final entry in entries) {
        final parts = entry.split(':');
        final file = File('convex/${parts[0]}.ts');
        if (!file.existsSync()) {
          problems.add('$entry: there is no convex/${parts[0]}.ts');
          continue;
        }
        final ts = file.readAsStringSync();
        final declaration = RegExp('export const ${RegExp.escape(parts[1])}\\s*=\\s*\\w+\\(').firstMatch(ts);
        if (declaration == null) {
          problems.add('$entry: not exported by the server');
          continue;
        }
        final stops = [ts.indexOf('handler:', declaration.end), ts.indexOf('export const', declaration.end)].where((i) => i != -1);
        final end = stops.isEmpty ? ts.length : stops.reduce(math.min);
        if (!ts.substring(declaration.end, end).contains('sessionToken')) problems.add('$entry: does not declare sessionToken');
      }
      expect(problems, isEmpty);
    });
  });
}
