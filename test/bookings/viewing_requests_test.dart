// Free site visits are REQUESTS (client side). Against a fake backend shaped like convex/bookings.ts:
// the "Request a Viewing" sheet only claims success when the server accepted the request; My Viewings
// shows the server's status (Requested → Confirmed, or Declined with the agent's reason) and lets the
// client withdraw a request; a property OWNER (no agent workspace) gets the same Accept / Decline screen.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/agent/presentation/views/viewing_requests_entry.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/bookings/presentation/views/my_bookings_screen.dart';
import 'package:vektolux/features/bookings/presentation/widgets/booking_modals.dart';
import 'package:vektolux/features/real_estate/domain/entities/property_listing_entity.dart';

class _ServerError {
  final String message;
  const _ServerError(this.message);
}

typedef _Route = Object? Function(Map<String, dynamic> args);

const _aminata = UserEntity(
  id: 'buyer_1',
  name: 'Aminata Kamara',
  email: 'aminata@test.vektolux',
  phone: '+23276000111',
  role: UserRole.client,
  isVerified: true,
  sessionToken: 'sess_aminata_0123456789abcdef',
);

const _owner = UserEntity(
  id: 'owner_1',
  name: 'Mariama Sesay',
  email: 'mariama@test.vektolux',
  phone: '+23276000333',
  role: UserRole.client,
  isVerified: true,
  sessionToken: 'sess_mariama_0123456789abcdef',
);

final int _now = DateTime.now().millisecondsSinceEpoch;
const _day = 86400000;

class _Backend {
  final Map<String, _Route> routes;
  final List<(String, Map<String, dynamic>)> calls = [];
  _Backend(this.routes);

  late final ConvexClientWrapper client = ConvexClientWrapper(
    deploymentUrl: 'https://example.invalid',
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final path = body['path'] as String;
      final args = Map<String, dynamic>.from(body['args'] as Map);
      calls.add((path, args));
      final route = routes[path];
      final value = route == null ? null : route(args);
      if (value is _ServerError) {
        return http.Response(jsonEncode({'status': 'error', 'errorMessage': 'Uncaught Error: ${value.message}'}), 200);
      }
      return http.Response(jsonEncode({'status': 'success', 'value': value}), 200);
    }),
  );

  Map<String, dynamic> lastArgs(String path) => calls.lastWhere((c) => c.$1 == path).$2;
  int count(String path) => calls.where((c) => c.$1 == path).length;
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A phone-sized surface (the request sheet is tall) with [home] and the client logged in as [user].
Future<void> _pump(WidgetTester tester, _Backend backend, Widget home, {UserEntity? user = _aminata}) async {
  tester.view.physicalSize = const Size(1200, 2600); // 400 × 866 logical
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (user != null) backend.client.setAuthToken(user.sessionToken!);
  await tester.pumpWidget(MaterialApp(home: home));
  await _settle(tester);
}

// ─── Request a Viewing ────────────────────────────────────────────────────

PropertyListingEntity _listing() => PropertyListingEntity(
      id: 'p1',
      ownerId: 'owner_1',
      title: 'Modern 3 Bedroom House',
      description: 'A bright family home.',
      category: RealEstateCategory.fromString('sale'),
      price: 2850000,
      address: 'Aberdeen, Western Area Urban',
      city: 'Freetown',
      country: 'Sierra Leone',
      latitude: 8.484,
      longitude: -13.234,
      geohash: '',
      availabilityStatus: 'available',
      ownerName: 'Mariama Sesay',
      bedrooms: 3,
      bathrooms: 2,
      areaSqM: 180,
    );

Widget _sheetOpener(_Backend backend) => Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const Key('open-sheet'),
            onPressed: () => PropertyInspectionModal.show(
              context,
              property: _listing(),
              currentUser: _aminata,
              convexClient: backend.client,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

Map<String, _Route> _bookingRoutes({String? refuse}) => {
      'bookings:createBooking': (a) => refuse != null
          ? _ServerError(refuse)
          : {
              'bookingId': 'b_new',
              'txRef': 'VX-1',
              'totalAmount': 0,
              'subtotal': 0,
              'serviceFee': 0,
              'status': 'requested',
              'paymentStatus': 'not_required',
              'vendorId': 'owner_1',
            },
    };

Map<String, dynamic> _row(
  String id,
  String status, {
  String type = 'property_inspection',
  String title = 'Modern 3 Bedroom House',
  int daysAhead = 1,
  String? declineReason,
  String? cancelReason,
}) =>
    {
      '_id': id,
      'listingId': 'p1',
      'listingTitle': title,
      'listingType': 'property',
      'buyerId': 'buyer_1',
      'vendorId': 'owner_1',
      'bookingType': type,
      'status': status,
      'startTime': _now + daysAhead * _day,
      'endTime': _now + daysAhead * _day + 3600000,
      'subtotal': type == 'property_inspection' ? 0 : 1500000,
      'serviceFee': 0,
      'totalAmount': type == 'property_inspection' ? 0 : 1575000,
      'currency': 'SLE',
      'paymentStatus': type == 'property_inspection' ? 'not_required' : 'completed',
      if (declineReason != null) 'declineReason': declineReason,
      if (cancelReason != null) 'cancelReason': cancelReason,
      'updatedAt': _now,
    };

/// Widget tests measure text with a wide placeholder font; measure with Roboto (close to the phone's
/// system font) so a layout failure here would be a real one.
Future<void> _loadFonts() async {
  Directory? dir;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) dir = Directory('$root/bin/cache/artifacts/material_fonts');
  var cur = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8 && (dir == null || !dir.existsSync()); i++) {
    final candidate = Directory('${cur.path}/bin/cache/artifacts/material_fonts');
    if (candidate.existsSync()) dir = candidate;
    cur = cur.parent;
  }
  if (dir == null || !dir.existsSync()) return;
  for (final family in ['Roboto', 'Inter', 'Poppins']) {
    final loader = FontLoader(family);
    for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
      final file = File('${dir.path}/$f');
      if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  group('Request a Viewing (the sheet)', () {
    testWidgets('a request the server accepted is announced as a REQUEST waiting for the agent — never as a confirmed booking', (tester) async {
      final backend = _Backend(_bookingRoutes());
      await _pump(tester, backend, _sheetOpener(backend));
      await tester.tap(find.byKey(const Key('open-sheet')));
      await _settle(tester);
      expect(find.text('Request a Viewing'), findsOneWidget);
      expect(find.text('Send Viewing Request'), findsOneWidget);

      await tester.tap(find.text('Send Viewing Request'));
      await _settle(tester);

      final sent = backend.lastArgs('bookings:createBooking');
      expect(sent['bookingType'], 'property_inspection');
      expect(sent['listingType'], 'property');
      expect(sent['listingId'], 'p1');
      expect(sent['sessionToken'], _aminata.sessionToken, reason: 'the server learns who is asking from the session');
      expect((sent['endTime'] as int) - (sent['startTime'] as int), 3600000);
      expect(sent['startTime'] as int, greaterThan(_now), reason: 'a future time');
      for (final forbidden in ['status', 'paymentStatus', 'totalAmount', 'subtotal', 'serviceFee', 'rate']) {
        expect(sent.containsKey(forbidden), isFalse, reason: 'the client cannot decide $forbidden');
      }

      expect(find.textContaining('Viewing request sent'), findsOneWidget);
      expect(find.textContaining('Waiting for the agent to confirm'), findsOneWidget);
      expect(find.textContaining('confirmed'), findsNothing, reason: 'it is not confirmed until the agent accepts');
      expect(find.text('Send Viewing Request'), findsNothing, reason: 'the sheet closed');
    });

    testWidgets('the chosen time and the note are sent as picked', (tester) async {
      final backend = _Backend(_bookingRoutes());
      await _pump(tester, backend, _sheetOpener(backend));
      await tester.tap(find.byKey(const Key('open-sheet')));
      await _settle(tester);
      await tester.tap(find.text('03:00 PM'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Can we meet at the gate?');
      await tester.pump();
      await tester.tap(find.text('Send Viewing Request'));
      await _settle(tester);
      final sent = backend.lastArgs('bookings:createBooking');
      expect(DateTime.fromMillisecondsSinceEpoch(sent['startTime'] as int).hour, 15);
      expect(sent['notes'], 'Can we meet at the gate?');
    });

    testWidgets('a request the server REFUSED is reported with the server\'s reason and is not shown as sent', (tester) async {
      final backend = _Backend(_bookingRoutes(refuse: 'That time slot is no longer available.'));
      await _pump(tester, backend, _sheetOpener(backend));
      await tester.tap(find.byKey(const Key('open-sheet')));
      await _settle(tester);
      await tester.tap(find.text('Send Viewing Request'));
      await _settle(tester);
      expect(find.text('Request not sent: That time slot is no longer available.'), findsOneWidget);
      expect(find.textContaining('Viewing request sent'), findsNothing);
      expect(find.text('Send Viewing Request'), findsOneWidget, reason: 'the sheet stays open so the client can pick another time');
    });
  });

  group('My Viewings (the client\'s requests and the agent\'s answers)', () {
    Map<String, _Route> routes(List<Map<String, dynamic>> rows) => {
          'bookings:getUserBookings': (_) => rows,
          'bookings:cancelBooking': (a) {
            final i = rows.indexWhere((r) => r['_id'] == a['bookingId']);
            if (i < 0) return const _ServerError('Booking not found');
            rows[i] = {...rows[i], 'status': 'cancelled', 'cancelReason': a['reason']};
            return {'success': true, 'refunded': 0};
          },
        };

    MyBookingsScreen screen(_Backend b, {bool viewingsOnly = true}) =>
        MyBookingsScreen(convexClient: b.client, currentUser: _aminata, viewingsOnly: viewingsOnly);

    testWidgets('a request is shown as REQUESTED and free; a paid stay is not part of My Viewings', (tester) async {
      final backend = _Backend(routes([
        _row('b1', 'requested'),
        _row('b2', 'confirmed', daysAhead: 3),
        _row('h1', 'confirmed', type: 'hourly_guesthouse', title: 'Guest House Aberdeen'),
      ]));
      await _pump(tester, backend, screen(backend));
      expect(find.text('My Viewings'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Past'), findsOneWidget);
      expect(find.text('REQUESTED'), findsOneWidget);
      expect(find.text('Viewing request sent. Waiting for the agent to confirm.'), findsOneWidget);
      expect(find.text('CONFIRMED'), findsOneWidget);
      expect(find.text('FREE'), findsNWidgets(2), reason: 'both visits are free');
      expect(find.text('Guest House Aberdeen'), findsNothing, reason: 'paid stays live in My Bookings');
      expect(find.text('Withdraw'), findsOneWidget, reason: 'only a pending request is withdrawn');
      expect(find.text('Cancel'), findsOneWidget, reason: 'a confirmed visit is cancelled');
    });

    testWidgets('a declined request moves to Past and shows the agent\'s reason, with nothing left to withdraw', (tester) async {
      final backend = _Backend(routes([
        _row('b3', 'declined', declineReason: 'House being repainted that week'),
        _row('b4', 'cancelled', cancelReason: 'Owner travelling'),
      ]));
      await _pump(tester, backend, screen(backend));
      expect(find.text('No viewing requests yet.'), findsOneWidget, reason: 'nothing is upcoming');
      await tester.tap(find.text('Past'));
      await _settle(tester);
      expect(find.text('DECLINED'), findsOneWidget);
      expect(find.text('Declined: House being repainted that week'), findsOneWidget);
      expect(find.text('CANCELLED'), findsOneWidget);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('withdrawing a pending request asks first, tells the server, and moves it to Past', (tester) async {
      final rows = [_row('b1', 'requested')];
      final backend = _Backend(routes(rows));
      await _pump(tester, backend, screen(backend));
      await tester.tap(find.text('Withdraw'));
      await _settle(tester, 3);
      expect(find.text('Withdraw Request?'), findsOneWidget);
      expect(backend.count('bookings:cancelBooking'), 0, reason: 'nothing is sent before the client confirms');

      await tester.tap(find.text('Yes, Withdraw'));
      await _settle(tester);
      final sent = backend.lastArgs('bookings:cancelBooking');
      expect(sent['bookingId'], 'b1');
      expect(sent['sessionToken'], _aminata.sessionToken);
      expect(find.text('Viewing request withdrawn.'), findsOneWidget);
      expect(backend.count('bookings:getUserBookings'), 2, reason: 're-read from the server after the change');
      expect(find.text('REQUESTED'), findsNothing);
    });

    testWidgets('keeping the request sends nothing', (tester) async {
      final backend = _Backend(routes([_row('b1', 'requested')]));
      await _pump(tester, backend, screen(backend));
      await tester.tap(find.text('Withdraw'));
      await _settle(tester, 3);
      await tester.tap(find.text('Keep Request'));
      await _settle(tester, 3);
      expect(backend.count('bookings:cancelBooking'), 0);
      expect(find.text('REQUESTED'), findsOneWidget);
    });

    testWidgets('the full My Bookings screen still lists paid stays next to the visits', (tester) async {
      final backend = _Backend(routes([
        _row('b1', 'requested'),
        _row('h1', 'confirmed', type: 'hourly_guesthouse', title: 'Guest House Aberdeen'),
      ]));
      await _pump(tester, backend, screen(backend, viewingsOnly: false));
      expect(find.text('My Bookings & Trips'), findsOneWidget);
      expect(find.text('Guest House Aberdeen'), findsOneWidget);
      expect(find.text('Modern 3 Bedroom House'), findsOneWidget);
    });
  });

  group('Viewing Requests for a property owner (no agent workspace)', () {
    Map<String, dynamic> request(String id, String status, {String client = 'Aminata Kamara', String? phone, String? reason}) => {
          'id': id,
          'listingId': 'p1',
          'listingTitle': 'Modern 3 Bedroom House',
          'listingImage': null,
          'publicLocation': 'Aberdeen, Western Area Urban',
          'representing': false,
          'clientName': client,
          'clientAvatarUrl': null,
          'clientPhone': status == 'confirmed' ? phone : null,
          'status': status,
          'startTime': _now + _day,
          'endTime': _now + _day + 3600000,
          'notes': 'Can we meet at the gate?',
          'declineReason': status == 'declined' ? reason : null,
          'cancelReason': null,
          'requestedAt': _now - 3600000,
        };

    Widget opener(_Backend b) => Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('open-requests'),
                onPressed: () => openViewingRequests(context, client: b.client, user: _owner),
                child: const Text('Open'),
              ),
            ),
          ),
        );

    testWidgets('the owner sees the pending request and accepting it is a server action that confirms it', (tester) async {
      final rows = [request('b1', 'requested')];
      final backend = _Backend({
        'bookings:getMyViewingRequests': (_) => rows,
        'bookings:respondToViewingRequest': (a) {
          final i = rows.indexWhere((r) => r['id'] == a['bookingId']);
          if (i < 0) return const _ServerError('Booking not found');
          rows[i] = {...rows[i], 'status': 'confirmed', 'clientPhone': '+23276000111'};
          return {'status': 'confirmed'};
        },
      });
      await _pump(tester, backend, opener(backend), user: _owner);
      await tester.tap(find.byKey(const Key('open-requests')));
      await _settle(tester, 10);

      expect(backend.lastArgs('bookings:getMyViewingRequests'), {'sessionToken': _owner.sessionToken});
      expect(find.byKey(const Key('viewing-b1')), findsOneWidget);
      expect(find.text('Aminata Kamara'), findsOneWidget);
      expect(find.byKey(const Key('viewing-call-b1')), findsNothing, reason: 'the client\'s phone is shared only after the owner accepts');

      await tester.tap(find.byKey(const Key('viewing-accept-b1')));
      await _settle(tester, 8);
      expect(backend.lastArgs('bookings:respondToViewingRequest'),
          {'bookingId': 'b1', 'decision': 'accept', 'sessionToken': _owner.sessionToken});
      expect(find.byKey(const Key('viewing-b1')), findsNothing, reason: 'it left the Pending tab');
    });

    testWidgets('declining needs a reason and sends it', (tester) async {
      final rows = [request('b1', 'requested')];
      final backend = _Backend({
        'bookings:getMyViewingRequests': (_) => rows,
        'bookings:respondToViewingRequest': (a) {
          rows[0] = {...rows[0], 'status': 'declined', 'declineReason': a['reason']};
          return {'status': 'declined'};
        },
      });
      await _pump(tester, backend, opener(backend), user: _owner);
      await tester.tap(find.byKey(const Key('open-requests')));
      await _settle(tester, 10);

      await tester.tap(find.byKey(const Key('viewing-decline-b1')));
      await _settle(tester, 4);
      await tester.tap(find.byKey(const Key('agent-reason-confirm')));
      await _settle(tester, 3);
      expect(backend.count('bookings:respondToViewingRequest'), 0, reason: 'a decline without a reason is not sent');

      await tester.enterText(find.byKey(const Key('agent-reason-input')), 'Away that day');
      await tester.pump();
      await tester.tap(find.byKey(const Key('agent-reason-confirm')));
      await _settle(tester, 8);
      expect(backend.lastArgs('bookings:respondToViewingRequest'),
          {'bookingId': 'b1', 'decision': 'decline', 'reason': 'Away that day', 'sessionToken': _owner.sessionToken});
    });

    testWidgets('a server refusal (someone else answered first) is shown and nothing is faked', (tester) async {
      final backend = _Backend({
        'bookings:getMyViewingRequests': (_) => [request('b1', 'requested')],
        'bookings:respondToViewingRequest': (_) => const _ServerError('This request was already answered.'),
      });
      await _pump(tester, backend, opener(backend), user: _owner);
      await tester.tap(find.byKey(const Key('open-requests')));
      await _settle(tester, 10);
      await tester.tap(find.byKey(const Key('viewing-accept-b1')));
      await _settle(tester, 8);
      expect(find.text('This request was already answered.'), findsOneWidget);
    });
  });
}
