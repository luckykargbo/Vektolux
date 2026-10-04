// Saved properties (the heart), against a fake backend that behaves like convex/savedListings.ts and
// convex/listingStats.ts: a save is a record of the SESSION's account (the app never names a user),
// so it follows the account across logout, reinstall and devices. Covers the state behind every
// heart, the Saved Properties list, and the heart + view counting on a property page.

import 'dart:async';
import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/listings/presentation/views/property_detail_screen.dart';
import 'package:vektolux/features/saved/data/saved_listings_api.dart';
import 'package:vektolux/features/saved/domain/saved_listing.dart';
import 'package:vektolux/features/saved/presentation/saved_hearts.dart';
import 'package:vektolux/features/saved/presentation/saved_properties_screen.dart';

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

const _ibrahim = UserEntity(
  id: 'buyer_2',
  name: 'Ibrahim Koroma',
  email: 'ibrahim@test.vektolux',
  phone: '+23276000222',
  role: UserRole.client,
  isVerified: true,
  sessionToken: 'sess_ibrahim_0123456789abcdef',
);

Map<String, dynamic> _card(
  String id, {
  String title = 'Modern 3 Bedroom House',
  String category = 'sale',
  num price = 2850000,
  String location = 'Aberdeen, Western Area Urban',
}) =>
    {
      'listingType': 'property',
      'listingId': id,
      'savedAt': 1700000000000,
      'available': true,
      'title': title,
      'category': category,
      'price': price,
      'hourlyRate': null,
      'currency': 'SLE',
      'location': location,
      'imageUrl': null,
      'bedrooms': 3,
      'bathrooms': 2,
      'areaSqM': 180,
      'ownerId': 'seller_1',
    };

/// A fake Convex deployment. Saved records are keyed by the SESSION token, exactly as the real
/// functions key them by the authenticated account.
class _Server {
  /// session token → saved property ids
  final Map<String, Set<String>> saved = {};

  /// listing id → what `getMySavedListings` returns while the listing is public
  final Map<String, Map<String, dynamic>> cards = {
    'p1': _card('p1'),
    'p2': _card('p2', title: '2 Bedroom Apartment', category: 'long_term_rent', price: 1200000, location: 'Hill Station, Western Area Urban'),
  };

  /// Rows added to the saved list that are not properties (a saved vehicle).
  final List<Map<String, dynamic>> extraRows = [];

  /// Make the next toggle fail with this server message.
  String? refuseNextToggle;
  String? idsError;
  String? listError;
  String? viewError;

  /// While set, a toggle is not answered until it completes.
  Completer<void>? gate;

  final List<(String, Map<String, dynamic>)> calls = [];

  late final ConvexClientWrapper client = ConvexClientWrapper(
    deploymentUrl: 'https://example.invalid',
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final path = body['path'] as String;
      final args = Map<String, dynamic>.from(body['args'] as Map);
      calls.add((path, args));
      try {
        return http.Response(jsonEncode({'status': 'success', 'value': await _handle(path, args)}), 200);
      } on _ServerError catch (e) {
        return http.Response(jsonEncode({'status': 'error', 'errorMessage': 'Uncaught Error: ${e.message}'}), 200);
      }
    }),
  );

  Map<String, dynamic> lastArgs(String path) => calls.lastWhere((c) => c.$1 == path).$2;
  int count(String path) => calls.where((c) => c.$1 == path).length;

  Future<Object?> _handle(String path, Map<String, dynamic> args) async {
    final session = args['sessionToken'] as String?;
    switch (path) {
      case 'savedListings:getMySavedListingIds':
        if (session == null) throw const _ServerError('Please log in.');
        if (idsError != null) throw _ServerError(idsError!);
        return [
          for (final id in saved[session] ?? const <String>{}) {'listingType': 'property', 'listingId': id},
        ];
      case 'savedListings:toggleSavedListing':
        if (session == null) throw const _ServerError('Please log in.');
        await gate?.future;
        final refusal = refuseNextToggle;
        if (refusal != null) {
          refuseNextToggle = null;
          throw _ServerError(refusal);
        }
        final mine = saved.putIfAbsent(session, () => <String>{});
        final wasSaved = mine.remove(args['listingId'] as String);
        if (!wasSaved) mine.add(args['listingId'] as String);
        return {'saved': !wasSaved};
      case 'savedListings:getMySavedListings':
        if (session == null) throw const _ServerError('Please log in.');
        if (listError != null) throw _ServerError(listError!);
        return [
          for (final id in saved[session] ?? const <String>{})
            // a listing that is no longer public comes back WITHOUT details, only so it can be removed
            cards[id] ?? {'listingType': 'property', 'listingId': id, 'savedAt': 1, 'available': false},
          ...extraRows,
        ];
      case 'realEstate:getPropertyById':
        final card = cards[args['listingId']];
        if (card == null) return null;
        return {
          '_id': card['listingId'],
          'title': card['title'],
          'description': 'A bright family home.',
          'category': card['category'],
          'price': card['price'],
          'publicLocation': card['location'],
          'ownerId': 'seller_1',
          'owner': {'name': 'Mariama Sesay'},
          'imageUrls': <String>[],
          'videoUrls': <String>[],
          'bedrooms': 3,
          'bathrooms': 2,
          'areaSqM': 180,
          'amenities': <String>[],
        };
      case 'listingStats:recordPropertyView':
        if (viewError != null) throw _ServerError(viewError!);
        return null;
      default:
        return null;
    }
  }
}

SavedHearts _hearts(_Server server, UserEntity user) =>
    SavedHearts(SavedListingsApi(client: server.client, sessionToken: user.sessionToken));

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [user] is also "logged in" on the HTTP client, as the app does after login (that is what attaches the
/// session to the calls that do not add it themselves).
Future<void> _pumpApp(WidgetTester tester, Widget home, _Server server, {UserEntity? user = _aminata}) async {
  final bloc = _MockAuthBloc();
  whenListen(
    bloc,
    const Stream<AuthState>.empty(),
    initialState: user == null
        ? const AuthState(status: AuthStatus.unauthenticated)
        : AuthState(status: AuthStatus.authenticated, user: user),
  );
  if (user != null) server.client.setAuthToken(user.sessionToken!);
  await tester.pumpWidget(RepositoryProvider<ConvexClientWrapper>.value(
    value: server.client,
    child: BlocProvider<AuthBloc>.value(value: bloc, child: MaterialApp(home: home)),
  ));
  await _settle(tester);
}

SavedPropertiesScreen _savedScreen(_Server server, {UserEntity user = _aminata}) => SavedPropertiesScreen(
      api: SavedListingsApi(client: server.client, sessionToken: user.sessionToken),
      client: server.client,
    );

PropertyDetailScreen _property({String id = 'p1', String ownerId = 'seller_1'}) => PropertyDetailScreen(
      id: id,
      title: 'Modern 3 Bedroom House',
      description: 'A bright family home.',
      category: 'sale',
      price: 2850000,
      address: 'Aberdeen, Western Area Urban',
      latitude: 8.484,
      longitude: -13.234,
      ownerId: ownerId,
      ownerName: 'Mariama Sesay',
    );

Finder _heartIcon(IconData icon) => find.descendant(of: find.byKey(const Key('property-heart')), matching: find.byIcon(icon));

void main() {
  group('SavedHearts — the state behind every heart', () {
    test('signed out: a heart asks the user to log in and nothing is sent', () async {
      final hearts = SavedHearts(null);
      expect(hearts.signedIn, isFalse);
      expect(await hearts.toggle('p1'), 'Log in to save properties.');
      expect(hearts.isSaved('p1'), isFalse);
      await hearts.load(); // nothing to load
      expect(hearts.isSaved('p1'), isFalse);
    });

    test('load() reads what the ACCOUNT has saved, by session (the app never sends a user id)', () async {
      final server = _Server()..saved[_aminata.sessionToken!] = {'p1', 'p2'};
      final hearts = _hearts(server, _aminata);
      await hearts.load();
      expect(hearts.isSaved('p1'), isTrue);
      expect(hearts.isSaved('p2'), isTrue);
      expect(hearts.isSaved('p3'), isFalse);
      expect(server.lastArgs('savedListings:getMySavedListingIds'), {'sessionToken': _aminata.sessionToken});
    });

    test('a tap fills the heart at once; the server holds the record and its answer is what stays', () async {
      final server = _Server()..gate = Completer<void>();
      final hearts = _hearts(server, _aminata);
      var notified = 0;
      hearts.addListener(() => notified++);

      final pending = hearts.toggle('p1');
      expect(hearts.isSaved('p1'), isTrue, reason: 'optimistic: the heart is full before the server answers');
      expect(notified, 1);
      server.gate!.complete();
      expect(await pending, isNull);

      expect(hearts.isSaved('p1'), isTrue);
      expect(server.saved[_aminata.sessionToken], {'p1'}, reason: 'the SERVER has the save, not just the app');
      expect(server.lastArgs('savedListings:toggleSavedListing'),
          {'listingType': 'property', 'listingId': 'p1', 'sessionToken': _aminata.sessionToken});
    });

    test('tapping a saved heart un-saves it on the server', () async {
      final server = _Server()..saved[_aminata.sessionToken!] = {'p1'};
      final hearts = _hearts(server, _aminata);
      await hearts.load();
      expect(await hearts.toggle('p1'), isNull);
      expect(hearts.isSaved('p1'), isFalse);
      expect(server.saved[_aminata.sessionToken], isEmpty);
    });

    test('the server\'s answer wins over the app\'s guess (it was already saved on another device)', () async {
      final server = _Server()..saved[_aminata.sessionToken!] = {'p1'};
      final hearts = _hearts(server, _aminata); // never loaded: the app believes it is not saved
      expect(await hearts.toggle('p1'), isNull);
      expect(hearts.isSaved('p1'), isFalse, reason: 'the server un-saved it, so the heart is empty');
    });

    test('a refused save is rolled back and the server\'s own message is reported', () async {
      final server = _Server()..refuseNextToggle = 'This listing is no longer available.';
      final hearts = _hearts(server, _aminata);
      expect(await hearts.toggle('p1'), 'This listing is no longer available.');
      expect(hearts.isSaved('p1'), isFalse);
      expect(server.saved[_aminata.sessionToken] ?? <String>{}, isEmpty);
    });

    test('a refused un-save keeps the heart full', () async {
      final server = _Server()..saved[_aminata.sessionToken!] = {'p1'};
      final hearts = _hearts(server, _aminata);
      await hearts.load();
      server.refuseNextToggle = 'Something went wrong on our side.';
      expect(await hearts.toggle('p1'), 'Something went wrong on our side.');
      expect(hearts.isSaved('p1'), isTrue);
    });

    test('a second tap while the first is still being answered does nothing (no double toggle)', () async {
      final server = _Server()..gate = Completer<void>();
      final hearts = _hearts(server, _aminata);
      final first = hearts.toggle('p1');
      expect(await hearts.toggle('p1'), isNull);
      server.gate!.complete();
      await first;
      expect(server.count('savedListings:toggleSavedListing'), 1);
      expect(hearts.isSaved('p1'), isTrue);
    });

    test('a failed load leaves every heart empty — nothing is invented', () async {
      final server = _Server()
        ..saved[_aminata.sessionToken!] = {'p1'}
        ..idsError = 'Please try again later.';
      final hearts = _hearts(server, _aminata);
      await hearts.load();
      expect(hearts.isSaved('p1'), isFalse);
    });

    test('a save belongs to the account: another account sees none, the same account sees it again after a fresh start', () async {
      final server = _Server();
      final first = _hearts(server, _aminata);
      expect(await first.toggle('p1'), isNull);
      first.dispose(); // logout / app closed

      final someoneElse = _hearts(server, _ibrahim);
      await someoneElse.load();
      expect(someoneElse.isSaved('p1'), isFalse, reason: 'another account never sees it');

      final again = _hearts(server, _aminata); // a new app start, or another device
      await again.load();
      expect(again.isSaved('p1'), isTrue, reason: 'the save follows the account');
    });
  });

  group('SavedListing — read from the server only', () {
    test('prices read the way the marketplace shows them; an unavailable one carries no details', () {
      expect(SavedListing.fromMap(_card('a')).priceLabel, 'SLE 2,850,000');
      expect(SavedListing.fromMap(_card('a')).tag, 'For Sale');
      expect(SavedListing.fromMap(_card('b', category: 'long_term_rent', price: 1200000)).priceLabel, 'SLE 1,200,000 / year');
      expect(SavedListing.fromMap(_card('b', category: 'long_term_rent')).tag, 'For Rent');
      expect(SavedListing.fromMap({..._card('c', category: 'hourly_guesthouse'), 'hourlyRate': 15000}).priceLabel, 'SLE 15,000 / hr');
      expect(SavedListing.fromMap(_card('d', price: 0)).priceLabel, 'Price on request');

      final gone = SavedListing.fromMap({'listingType': 'property', 'listingId': 'x', 'savedAt': 1, 'available': false});
      expect(gone.available, isFalse);
      expect(gone.title, 'Listing');
      expect(gone.imageUrl, isNull);
    });
  });

  group('Saved Properties screen', () {
    testWidgets('nothing saved yet → the honest empty state', (tester) async {
      final server = _Server();
      await _pumpApp(tester, _savedScreen(server), server);
      expect(find.byKey(const Key('saved-empty')), findsOneWidget);
      expect(find.text('No saved properties yet'), findsOneWidget);
      expect(find.text('Tap the heart on a property to save it.'), findsOneWidget);
      expect(server.lastArgs('savedListings:getMySavedListings'), {'sessionToken': _aminata.sessionToken});
    });

    testWidgets('lists exactly what this account saved; a saved vehicle is not a property; a property that is gone is marked', (tester) async {
      final server = _Server()
        ..saved[_aminata.sessionToken!] = {'p1', 'p2', 'gone'}
        ..saved[_ibrahim.sessionToken!] = {'p1'}
        ..extraRows.add({'listingType': 'vehicle', 'listingId': 'v1', 'savedAt': 1, 'available': true, 'title': '2019 Toyota Hilux'});
      await _pumpApp(tester, _savedScreen(server), server);

      expect(find.byKey(const Key('saved-p1')), findsOneWidget);
      expect(find.text('Modern 3 Bedroom House'), findsOneWidget);
      expect(find.text('SLE 2,850,000'), findsOneWidget);
      expect(find.text('Aberdeen, Western Area Urban'), findsOneWidget);
      expect(find.text('For Sale'), findsOneWidget);
      expect(find.byKey(const Key('saved-p2')), findsOneWidget);
      expect(find.text('SLE 1,200,000 / year'), findsOneWidget);
      expect(find.text('For Rent'), findsOneWidget);

      expect(find.byKey(const Key('saved-gone')), findsOneWidget);
      expect(find.text('No longer available'), findsOneWidget, reason: 'kept so it can be removed, without any details');
      expect(find.byKey(const Key('saved-v1')), findsNothing, reason: 'this list is for properties');
      expect(find.text('2019 Toyota Hilux'), findsNothing);
      expect(find.byKey(const Key('saved-empty')), findsNothing);
    });

    testWidgets('removing a property is a server action: the card goes and the record is deleted', (tester) async {
      final server = _Server()..saved[_aminata.sessionToken!] = {'p1', 'p2'};
      await _pumpApp(tester, _savedScreen(server), server);
      await tester.tap(find.byKey(const Key('saved-remove-p1')));
      await _settle(tester);
      expect(find.byKey(const Key('saved-p1')), findsNothing);
      expect(find.byKey(const Key('saved-p2')), findsOneWidget);
      expect(server.saved[_aminata.sessionToken], {'p2'});
      expect(server.lastArgs('savedListings:toggleSavedListing'),
          {'listingType': 'property', 'listingId': 'p1', 'sessionToken': _aminata.sessionToken});
    });

    testWidgets('a refused removal puts the card back and shows the server\'s message', (tester) async {
      final server = _Server()..saved[_aminata.sessionToken!] = {'p1'};
      await _pumpApp(tester, _savedScreen(server), server);
      server.refuseNextToggle = 'Something went wrong on our side.';
      await tester.tap(find.byKey(const Key('saved-remove-p1')));
      await _settle(tester);
      expect(find.byKey(const Key('saved-p1')), findsOneWidget);
      expect(find.text('Something went wrong on our side.'), findsOneWidget);
      expect(server.saved[_aminata.sessionToken], {'p1'});
    });

    testWidgets('a server error is shown with a working Retry', (tester) async {
      final server = _Server()
        ..saved[_aminata.sessionToken!] = {'p1'}
        ..listError = 'Saved properties are unavailable right now.';
      await _pumpApp(tester, _savedScreen(server), server);
      expect(find.text('Saved properties are unavailable right now.'), findsOneWidget);
      expect(find.byKey(const Key('saved-p1')), findsNothing);
      server.listError = null;
      await tester.tap(find.text('Retry'));
      await _settle(tester);
      expect(find.byKey(const Key('saved-p1')), findsOneWidget);
    });

    testWidgets('a server that does not have saves yet is explained, not shown as a crash', (tester) async {
      final server = _Server()..listError = "Could not find public function for 'savedListings:getMySavedListings'.";
      await _pumpApp(tester, _savedScreen(server), server);
      expect(find.text('Saved properties become available after the next Vektolux server update.'), findsOneWidget);
    });

    testWidgets('opening a card shows the public property page; one that was withdrawn says so', (tester) async {
      final server = _Server()..saved[_aminata.sessionToken!] = {'p1', 'p2'};
      await _pumpApp(tester, _savedScreen(server), server);
      await tester.tap(find.byKey(const Key('saved-p1')));
      await _settle(tester, 10);
      expect(server.lastArgs('realEstate:getPropertyById'), {'listingId': 'p1'});
      expect(find.byType(PropertyDetailScreen), findsOneWidget);
      expect(find.text('Western Area, Sierra Leone'), findsWidgets, reason: 'the page shows the generalized public location');
      await tester.pageBack();
      await _settle(tester, 6);

      // p2 is withdrawn while the list is open: the server no longer returns it
      server.cards.remove('p2');
      await tester.tap(find.byKey(const Key('saved-p2')));
      await _settle(tester, 6);
      expect(find.text('This property is no longer available.'), findsOneWidget);
      expect(find.byType(PropertyDetailScreen), findsNothing);
    });
  });

  group('the heart and the view count on a property page', () {
    testWidgets('a property the account saved shows a full heart; tapping it un-saves on the server', (tester) async {
      final server = _Server()..saved[_aminata.sessionToken!] = {'p1'};
      await _pumpApp(tester, _property(), server);
      expect(_heartIcon(Icons.favorite_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('property-heart')));
      await _settle(tester);
      expect(_heartIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(server.saved[_aminata.sessionToken], isEmpty);
    });

    testWidgets('an empty heart saves it: filled at once, stored for the account, and still full after reopening the page', (tester) async {
      final server = _Server();
      await _pumpApp(tester, _property(), server);
      expect(_heartIcon(Icons.favorite_border_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('property-heart')));
      await _settle(tester);
      expect(_heartIcon(Icons.favorite_rounded), findsOneWidget);
      expect(server.saved[_aminata.sessionToken], {'p1'});

      // leave and come back (a new page, new state): the heart comes from the server
      await tester.pumpWidget(const SizedBox());
      await _pumpApp(tester, _property(), server);
      expect(_heartIcon(Icons.favorite_rounded), findsOneWidget);
    });

    testWidgets('a refused save leaves the heart empty and shows the server\'s message', (tester) async {
      final server = _Server()..refuseNextToggle = 'This listing is no longer available.';
      await _pumpApp(tester, _property(), server);
      await tester.tap(find.byKey(const Key('property-heart')));
      await _settle(tester);
      expect(_heartIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.text('This listing is no longer available.'), findsOneWidget);
    });

    testWidgets('signed out: the heart asks to log in and the server is not called at all', (tester) async {
      final server = _Server();
      await _pumpApp(tester, _property(), server, user: null);
      await tester.tap(find.byKey(const Key('property-heart')));
      await _settle(tester);
      expect(find.text('Log in to save properties.'), findsOneWidget);
      expect(server.calls, isEmpty, reason: 'no saves, and a guest\'s visit is not counted');
    });

    testWidgets('the owner cannot save their own listing (no heart) and their own visit is not counted', (tester) async {
      final server = _Server();
      await _pumpApp(tester, _property(ownerId: _aminata.id), server);
      expect(find.byKey(const Key('property-heart')), findsNothing);
      expect(server.count('listingStats:recordPropertyView'), 0);
    });

    testWidgets('a signed-in visitor\'s open is reported once, with their session, naming only the listing', (tester) async {
      final server = _Server();
      await _pumpApp(tester, _property(), server);
      expect(server.count('listingStats:recordPropertyView'), 1);
      expect(server.lastArgs('listingStats:recordPropertyView'), {'listingId': 'p1', 'sessionToken': _aminata.sessionToken},
          reason: 'the server decides who looked; the app sends no count and no user id');
      // tapping the heart does not count as another view
      await tester.tap(find.byKey(const Key('property-heart')));
      await _settle(tester);
      expect(server.count('listingStats:recordPropertyView'), 1);
    });

    testWidgets('a failing view report never gets in the way of reading the listing', (tester) async {
      final server = _Server()..viewError = 'Something went wrong on our side.';
      await _pumpApp(tester, _property(), server);
      expect(server.count('listingStats:recordPropertyView'), 1);
      expect(find.text('Something went wrong on our side.'), findsNothing, reason: 'the visitor is not told about a statistic');
      expect(find.text('Modern 3 Bedroom House'), findsWidgets);
      expect(find.byKey(const Key('property-request-viewing')), findsOneWidget);
      expect(find.text('Request a Viewing'), findsOneWidget, reason: 'a free visit is a request, not a booking');
    });
  });
}
