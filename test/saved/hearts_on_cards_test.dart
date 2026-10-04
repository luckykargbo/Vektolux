// The hearts on the Real Estate marketplace and on Explore are the account's SERVER-side saves — not
// local state that resets on restart: they start from what the server holds, a tap is a server call
// (vehicles as vehicles, properties as properties), a refusal is rolled back, and a guest is asked to log in.

import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/explore/presentation/views/explore_screen.dart';
import 'package:vektolux/features/real_estate/presentation/views/real_estate_marketplace_screen.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _ServerError {
  final String message;
  const _ServerError(this.message);
}

const _aminata = UserEntity(
  id: 'buyer_1',
  name: 'Aminata Kamara',
  email: 'aminata@test.vektolux',
  phone: '+23276000111',
  role: UserRole.client,
  isVerified: true,
  sessionToken: 'sess_aminata_0123456789abcdef',
);

final int _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> _property(String id, {String category = 'sale'}) => {
      '_id': id,
      'id': id,
      '_creationTime': _now,
      'ownerId': 'owner_1',
      'title': 'Modern 3 Bedroom House $id',
      'description': 'A bright family home.',
      'category': category,
      'price': 2850000,
      'currency': 'SLE',
      'publicLocation': 'Inside Freetown, Sierra Leone',
      'city': 'Freetown',
      'district': 'Western Area Urban',
      'bedrooms': 3,
      'bathrooms': 2,
      'areaSqM': 180,
      'amenities': <String>[],
      'imageUrls': <String>[],
      'availabilityStatus': 'available',
      'isPublished': true,
      'updatedAt': _now,
      'ownerName': 'Mariama Sesay',
      'isVerified': true,
      'type': 'property',
    };

Map<String, dynamic> _vehicle(String id) => {
      '_id': id,
      'id': id,
      'ownerId': 'owner_1',
      'title': '2019 Toyota Hilux $id',
      'category': 'car_sale',
      'price': 450000000,
      'pricingType': 'total_sale',
      'location': 'Inside Freetown, Sierra Leone',
      'publicLocation': 'Inside Freetown, Sierra Leone',
      'images': <String>[],
      'imageUrls': <String>[],
      'status': 'AVAILABLE',
      'make': 'Toyota',
      'model': 'Hilux',
      'year': 2019,
      'salePrice': 450000000,
      'currency': 'SLE',
      'listingIntent': 'sale',
      'vehicleType': 'car_sale',
      'type': 'vehicle',
      'isPublished': true,
      'ownerName': 'Mariama Sesay',
    };

class _Server {
  /// session token → saved ids
  final Map<String, Set<String>> saved = {};
  String? refuseNextToggle;
  final List<(String, Map<String, dynamic>)> calls = [];

  late final ConvexClientWrapper client = ConvexClientWrapper(
    deploymentUrl: 'https://example.invalid',
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final path = body['path'] as String;
      final args = Map<String, dynamic>.from(body['args'] as Map);
      calls.add((path, args));
      try {
        return http.Response(jsonEncode({'status': 'success', 'value': _handle(path, args)}), 200);
      } on _ServerError catch (e) {
        return http.Response(jsonEncode({'status': 'error', 'errorMessage': 'Uncaught Error: ${e.message}'}), 200);
      }
    }),
  );

  List<Map<String, dynamic>> toggles() => [for (final c in calls) if (c.$1 == 'savedListings:toggleSavedListing') c.$2];

  Object? _handle(String path, Map<String, dynamic> args) {
    final session = args['sessionToken'] as String?;
    switch (path) {
      case 'realEstate:listProperties':
        return [_property('prop_a'), _property('prop_b', category: 'long_term_rent')];
      case 'explore:getExploreFeed':
        return {
          'recommended': [_property('prop_a'), _vehicle('veh_a')],
          'propertiesNearYou': <Map<String, dynamic>>[],
          'vehiclesForSaleAndHire': <Map<String, dynamic>>[],
          'topAgentsAndDealers': <Map<String, dynamic>>[],
        };
      case 'savedListings:getMySavedListingIds':
        if (session == null) throw const _ServerError('Please log in.');
        return [for (final id in saved[session] ?? const <String>{}) {'listingType': id.startsWith('veh') ? 'vehicle' : 'property', 'listingId': id}];
      case 'savedListings:toggleSavedListing':
        if (session == null) throw const _ServerError('Please log in.');
        final refusal = refuseNextToggle;
        if (refusal != null) {
          refuseNextToggle = null;
          throw _ServerError(refusal);
        }
        final mine = saved.putIfAbsent(session, () => <String>{});
        final id = args['listingId'] as String;
        final wasSaved = mine.remove(id);
        if (!wasSaved) mine.add(id);
        return {'saved': !wasSaved};
      default:
        return null;
    }
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, _Server server, Widget Function(ConvexClientWrapper) screen, {UserEntity? user = _aminata}) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390 × 844 logical
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (user != null) server.client.setAuthToken(user.sessionToken!);
  final bloc = _MockAuthBloc();
  whenListen(
    bloc,
    const Stream<AuthState>.empty(),
    initialState: user == null
        ? const AuthState(status: AuthStatus.unauthenticated)
        : AuthState(status: AuthStatus.authenticated, user: user),
  );
  await tester.pumpWidget(RepositoryProvider<ConvexClientWrapper>.value(
    value: server.client,
    child: BlocProvider<AuthBloc>.value(value: bloc, child: MaterialApp(home: screen(server.client))),
  ));
  await _settle(tester);
}

Finder _heart(String id, IconData icon) => find.descendant(of: find.byKey(Key('heart-$id')), matching: find.byIcon(icon));

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

  group('Real Estate marketplace cards', () {
    testWidgets('a card states only what the listing says: beds and baths, and no invented garage', (tester) async {
      final server = _Server();
      await _pump(tester, server, (c) => RealEstateMarketplaceScreen(convexClient: c));
      expect(find.text('3 Beds'), findsWidgets);
      expect(find.text('2 Baths'), findsWidgets);
      expect(find.textContaining('Garage'), findsNothing, reason: 'the listings declare no parking');
    });
  });

  group('Real Estate marketplace hearts', () {
    testWidgets('start from what the server holds for this account, not from local state', (tester) async {
      final server = _Server()..saved[_aminata.sessionToken!] = {'prop_a'};
      await _pump(tester, server, (c) => RealEstateMarketplaceScreen(convexClient: c));
      expect(_heart('prop_a', Icons.favorite_rounded), findsOneWidget);
      expect(_heart('prop_b', Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('a tap saves on the server as a property; tapping again un-saves', (tester) async {
      final server = _Server();
      await _pump(tester, server, (c) => RealEstateMarketplaceScreen(convexClient: c));
      await tester.tap(find.byKey(const Key('heart-prop_b')));
      await _settle(tester);
      expect(_heart('prop_b', Icons.favorite_rounded), findsOneWidget);
      expect(server.saved[_aminata.sessionToken], {'prop_b'});
      expect(server.toggles().single, {'listingType': 'property', 'listingId': 'prop_b', 'sessionToken': _aminata.sessionToken});

      await tester.tap(find.byKey(const Key('heart-prop_b')));
      await _settle(tester);
      expect(_heart('prop_b', Icons.favorite_border_rounded), findsOneWidget);
      expect(server.saved[_aminata.sessionToken], isEmpty);
    });

    testWidgets('a refused save is rolled back and the server\'s message is shown', (tester) async {
      final server = _Server()..refuseNextToggle = 'This listing is no longer available.';
      await _pump(tester, server, (c) => RealEstateMarketplaceScreen(convexClient: c));
      await tester.tap(find.byKey(const Key('heart-prop_a')));
      await _settle(tester);
      expect(_heart('prop_a', Icons.favorite_border_rounded), findsOneWidget);
      expect(find.text('This listing is no longer available.'), findsOneWidget);
    });

    testWidgets('a guest is asked to log in and nothing is saved', (tester) async {
      final server = _Server();
      await _pump(tester, server, (c) => RealEstateMarketplaceScreen(convexClient: c), user: null);
      await tester.tap(find.byKey(const Key('heart-prop_a')));
      await _settle(tester);
      expect(find.text('Log in to save properties.'), findsOneWidget);
      expect(server.toggles(), isEmpty);
      expect(_heart('prop_a', Icons.favorite_border_rounded), findsOneWidget);
    });
  });

  group('Explore hearts', () {
    testWidgets('a saved property and a vehicle each start from the server', (tester) async {
      final server = _Server()..saved[_aminata.sessionToken!] = {'veh_a'};
      await _pump(tester, server, (c) => ExploreScreen(convexClient: c));
      expect(_heart('veh_a', Icons.favorite_rounded), findsOneWidget);
      expect(_heart('prop_a', Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('a vehicle is saved as a vehicle and a property as a property', (tester) async {
      final server = _Server();
      await _pump(tester, server, (c) => ExploreScreen(convexClient: c));
      await tester.tap(find.byKey(const Key('heart-veh_a')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('heart-prop_a')));
      await _settle(tester);
      final toggles = server.toggles();
      expect(toggles.map((t) => t['listingType']).toList(), ['vehicle', 'property']);
      expect(toggles.map((t) => t['listingId']).toList(), ['veh_a', 'prop_a']);
      expect(toggles.every((t) => t['sessionToken'] == _aminata.sessionToken), isTrue);
      expect(server.saved[_aminata.sessionToken], {'veh_a', 'prop_a'});
      expect(_heart('veh_a', Icons.favorite_rounded), findsOneWidget);
      expect(_heart('prop_a', Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('a guest is asked to log in', (tester) async {
      final server = _Server();
      await _pump(tester, server, (c) => ExploreScreen(convexClient: c), user: null);
      await tester.tap(find.byKey(const Key('heart-prop_a')));
      await _settle(tester);
      expect(find.text('Log in to save properties.'), findsOneWidget);
      expect(server.toggles(), isEmpty);
    });
  });
}
