// The owner's "My Listings": every card shows the state the SERVER derived (never a hard-coded "Live"),
// the administrator's reason on a rejected / removed listing, and no edit or delete actions on a
// listing an administrator removed.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/listings/presentation/views/my_listings_screen.dart';

const _owner = UserEntity(
  id: 'owner_1',
  name: 'Mariama Sesay',
  email: 'mariama@test.vektolux',
  phone: '+23276000333',
  role: UserRole.agent,
  isVerified: true,
  isVerifiedSeller: true,
  verificationStatus: 'approved',
  sessionToken: 'sess_mariama_0123456789abcdef',
);

Map<String, dynamic> _property(
  String id, {
  String? lifecycle,
  String? reason,
  String category = 'sale',
  bool? isPublished,
}) =>
    {
      '_id': id,
      'title': 'Property $id',
      'description': 'A bright family home.',
      'category': category,
      'price': 2850000,
      'currency': 'SLE',
      'address': 'Aberdeen, Western Area Urban',
      'bedrooms': 3,
      'bathrooms': 2,
      'imageUrls': <String>[],
      if (lifecycle != null) 'lifecycleStatus': lifecycle,
      if (reason != null) 'moderationReason': reason,
      if (isPublished != null) 'isPublished': isPublished,
    };

Map<String, dynamic> _vehicle(String id, {bool? isPublished, String? status}) => {
      '_id': id,
      'make': 'Toyota',
      'model': 'Hilux $id',
      'year': 2020,
      'salePrice': 450000000,
      'currency': 'SLE',
      'listingIntent': 'sale',
      'imageUrls': <String>[],
      if (isPublished != null) 'isPublished': isPublished,
      if (status != null) 'status': status,
    };

final List<(String, Map<String, dynamic>)> _calls = [];

ConvexClientWrapper _client({List<Map<String, dynamic>> properties = const [], List<Map<String, dynamic>> vehicles = const []}) {
  _calls.clear();
  return ConvexClientWrapper(
    deploymentUrl: 'https://example.invalid',
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final path = body['path'] as String;
      _calls.add((path, Map<String, dynamic>.from(body['args'] as Map)));
      final value = switch (path) {
        'realEstate:getMyPropertyListings' => properties,
        'mobility:getMyVehicleListings' => vehicles,
        _ => null,
      };
      return http.Response(jsonEncode({'status': 'success', 'value': value}), 200);
    }),
  );
}

Future<void> _pump(WidgetTester tester, ConvexClientWrapper client) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390 × 844 logical
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: MyListingsScreen(convexClient: client, currentUser: _owner)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _in(String cardKey, Finder matching) => find.descendant(of: find.byKey(Key(cardKey)), matching: matching);

/// Widget tests measure text with a wide placeholder font; measure with Roboto so a layout failure
/// here would be a real one.
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

  testWidgets('each property shows the state the server derived — and the administrator\'s reason where there is one', (tester) async {
    final client = _client(properties: [
      _property('a1', lifecycle: 'active'),
      _property('p1', lifecycle: 'pending_review', category: 'long_term_rent'),
      _property('r1', lifecycle: 'rejected', reason: 'Photos do not show the property.'),
    ]);
    await _pump(tester, client);
    expect(_in('my-listing-status-a1', find.text('Active')), findsOneWidget);
    expect(_in('my-listing-status-p1', find.text('Pending review')), findsOneWidget);
    expect(_in('my-listing-status-r1', find.text('Rejected')), findsOneWidget);
    expect(find.byKey(const Key('my-listing-reason-r1')), findsOneWidget);
    expect(find.text('Reason: Photos do not show the property.'), findsOneWidget);
    expect(find.byKey(const Key('my-listing-reason-a1')), findsNothing, reason: 'an active listing has no reason');
    expect(find.byKey(const Key('my-listing-reason-p1')), findsNothing);
    expect(find.text('Live'), findsNothing, reason: 'nothing says "Live" unless the server says it is active');

    // the categories read like the rest of the app, not like database values
    expect(find.text('FOR SALE'), findsNWidgets(2));
    expect(find.text('FOR RENT'), findsOneWidget);
    expect(find.text('LONG_TERM_RENT'), findsNothing);

    // the query names this account and carries its session
    final args = _calls.firstWhere((c) => c.$1 == 'realEstate:getMyPropertyListings').$2;
    expect(args['ownerId'], _owner.id);
    expect(args['sessionToken'], _owner.sessionToken);
  });

  testWidgets('a listing an administrator removed keeps its reason and offers no edit or delete', (tester) async {
    final client = _client(properties: [
      _property('x1', lifecycle: 'removed', reason: 'Reported as a duplicate listing.'),
      _property('a1', lifecycle: 'active'),
    ]);
    await _pump(tester, client);
    expect(_in('my-listing-status-x1', find.text('Removed')), findsOneWidget);
    expect(find.text('Reason: Reported as a duplicate listing.'), findsOneWidget);
    expect(_in('my-listing-x1', find.text('Update Price')), findsNothing);
    expect(_in('my-listing-x1', find.text('Edit Details')), findsNothing);
    expect(_in('my-listing-x1', find.text('Sold? Delete')), findsNothing);
    // an ordinary listing keeps its actions
    expect(_in('my-listing-a1', find.text('Update Price')), findsOneWidget);
    expect(_in('my-listing-a1', find.text('Edit Details')), findsOneWidget);
    expect(_in('my-listing-a1', find.text('Sold? Delete')), findsOneWidget);
  });

  testWidgets('draft, unpublished and archived listings are labelled as such — never as live', (tester) async {
    final client = _client(properties: [
      _property('d1', lifecycle: 'draft', isPublished: false),
      _property('u1', lifecycle: 'unpublished', isPublished: false, category: 'hourly_guesthouse'),
      _property('z1', lifecycle: 'archived', isPublished: false),
    ]);
    await _pump(tester, client);
    expect(_in('my-listing-status-d1', find.text('Draft')), findsOneWidget);
    expect(_in('my-listing-status-u1', find.text('Unpublished')), findsOneWidget);
    expect(_in('my-listing-status-z1', find.text('Archived')), findsOneWidget);
    expect(find.text('Active'), findsNothing);
    expect(find.text('Live'), findsNothing);
    expect(find.text('SHORT STAY'), findsOneWidget);
  });

  testWidgets('a server that does not report a state yet: published → Active, not published → Unpublished (nothing else is assumed)', (tester) async {
    final client = _client(properties: [
      _property('o1', isPublished: true),
      _property('o2', isPublished: false),
    ]);
    await _pump(tester, client);
    expect(_in('my-listing-status-o1', find.text('Active')), findsOneWidget);
    expect(_in('my-listing-status-o2', find.text('Unpublished')), findsOneWidget);
  });

  testWidgets('vehicles show their real state too', (tester) async {
    final client = _client(
      properties: [_property('a1', lifecycle: 'active')],
      vehicles: [
        _vehicle('v1'),
        _vehicle('v2', isPublished: false),
        _vehicle('v3', status: 'TAKEN_DOWN'),
      ],
    );
    await _pump(tester, client);
    await tester.tap(find.textContaining('Vehicles ('));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_in('my-vehicle-status-v1', find.text('Active')), findsOneWidget);
    expect(_in('my-vehicle-status-v2', find.text('Unpublished')), findsOneWidget);
    expect(_in('my-vehicle-status-v3', find.text('Removed')), findsOneWidget);
    expect(find.text('Live'), findsNothing);
  });
}
