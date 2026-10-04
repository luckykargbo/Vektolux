// The Account screen (the buyer / seller profile): only real data — the fake "Saved addresses" are
// gone, an address shows only when the account has one — and the activity entries it offers
// (Messages, Saved Properties, My Viewings, and Viewing Requests for an owner) open the real screens.

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
import 'package:vektolux/core/theme/app_theme.dart';
import 'package:vektolux/core/widgets/app_text_scale.dart';
import 'package:vektolux/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/domain/repositories/auth_repository.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/profile/presentation/views/profile_screen.dart';
import 'package:vektolux/features/wallet_payments/presentation/bloc/wallet_cubit.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

typedef _Route = Object? Function(Map<String, dynamic> args);

const _buyer = UserEntity(
  id: 'buyer_1',
  name: 'Aminata Kamara',
  email: 'aminata@test.vektolux',
  phone: '+23276000111',
  role: UserRole.client,
  isVerified: true,
  verificationStatus: 'approved',
  sessionToken: 'sess_aminata_0123456789abcdef',
);

const _buyerWithAddress = UserEntity(
  id: 'buyer_1',
  name: 'Aminata Kamara',
  email: 'aminata@test.vektolux',
  phone: '+23276000111',
  role: UserRole.client,
  isVerified: true,
  verificationStatus: 'approved',
  sessionToken: 'sess_aminata_0123456789abcdef',
  address: '14 Hill Station Road, Freetown',
  region: 'Western Area Urban',
);

const _seller = UserEntity(
  id: 'owner_1',
  name: 'Mariama Sesay',
  email: 'mariama@test.vektolux',
  phone: '+23276000333',
  role: UserRole.agent,
  isVerified: true,
  isVerifiedSeller: true,
  verificationStatus: 'approved',
  sessionToken: 'sess_mariama_0123456789abcdef',
  businessName: 'Sesay Properties Ltd',
  tinNumber: 'TIN-SL-0049781234',
);

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
      return http.Response(jsonEncode({'status': 'success', 'value': route == null ? null : route(args)}), 200);
    }),
  );

  Map<String, dynamic> lastArgs(String path) => calls.lastWhere((c) => c.$1 == path).$2;
  int count(String path) => calls.where((c) => c.$1 == path).length;
}

_Backend _backend({int listings = 2}) => _Backend({
      'users:getWalletProfile': (_) => {
            'userId': 'buyer_1', 'walletBalance': 1000.0, 'lockedEscrowBalance': 0, 'currency': 'SLE', 'activeEscrowDeals': 0,
          },
      'realEstate:getMyPropertyListings': (_) => [for (var i = 0; i < listings; i++) {'_id': 'p$i', 'title': 'Listing $i'}],
      'payments:getUserPaymentAccounts': (_) => [],
      'savedListings:getMySavedListings': (_) => [],
      'bookings:getUserBookings': (_) => [],
      'bookings:getMyViewingRequests': (_) => [],
      'messaging:getMyConversations': (_) => [],
    });

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, _Backend backend, UserEntity user) async {
  tester.view.physicalSize = const Size(1170, 2532); // 390 × 844 logical (iPhone 15)
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  backend.client.setAuthToken(user.sessionToken!);
  final bloc = _MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(), initialState: AuthState(status: AuthStatus.authenticated, user: user));
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ConvexClientWrapper>.value(value: backend.client),
        RepositoryProvider<AuthRepository>(create: (_) => AuthRepositoryImpl(convexClient: backend.client)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: bloc),
          BlocProvider<WalletCubit>(create: (_) => WalletCubit(convexClient: backend.client)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => AppTextScale(child: child ?? const SizedBox.shrink()),
          home: ProfileScreen(currentUserId: user.id, showBackButton: false),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _openTile(WidgetTester tester, String key) async {
  final tile = find.byKey(Key(key));
  await tester.ensureVisible(tile);
  await _settle(tester, 3);
  await tester.tap(tile);
  await _settle(tester, 10);
}

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

  group('Account — only real data', () {
    testWidgets('the fake "Saved addresses" are gone', (tester) async {
      await _pump(tester, _backend(), _buyer);
      expect(find.text('Account & Profile'), findsOneWidget);
      expect(find.text('SAVED ADDRESSES'), findsNothing);
      expect(find.textContaining('Saved address'), findsNothing);
      expect(find.text('Work / Office'), findsNothing);
      expect(find.text('Central Business District, Freetown'), findsNothing);
    });

    testWidgets('an account with no address shows none; one with an address shows exactly that', (tester) async {
      await _pump(tester, _backend(), _buyer);
      expect(find.textContaining('Hill Station Road'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      await _pump(tester, _backend(), _buyerWithAddress);
      expect(find.textContaining('14 Hill Station Road, Freetown'), findsOneWidget);
    });

    testWidgets('the listing count is read for THIS account (ownerId), with the session', (tester) async {
      final backend = _backend(listings: 3);
      await _pump(tester, backend, _seller);
      final args = backend.lastArgs('realEstate:getMyPropertyListings');
      expect(args['ownerId'], _seller.id);
      expect(args['sessionToken'], _seller.sessionToken);
    });
  });

  group('Account — my activity', () {
    testWidgets('a buyer sees Messages, Saved Properties and My Viewings — and not the owner-only entries', (tester) async {
      await _pump(tester, _backend(), _buyer);
      expect(find.text('MY ACTIVITY'), findsOneWidget);
      expect(find.byKey(const Key('profile-messages')), findsOneWidget);
      expect(find.byKey(const Key('profile-saved')), findsOneWidget);
      expect(find.byKey(const Key('profile-viewings')), findsOneWidget);
      expect(find.byKey(const Key('profile-viewing-requests')), findsNothing, reason: 'a buyer owns no listings to answer requests for');
    });

    testWidgets('Saved Properties opens the saved list (empty state when nothing is saved)', (tester) async {
      final backend = _backend();
      await _pump(tester, backend, _buyer);
      await _openTile(tester, 'profile-saved');
      expect(find.text('No saved properties yet'), findsOneWidget);
      expect(find.text('Tap the heart on a property to save it.'), findsOneWidget);
      expect(backend.lastArgs('savedListings:getMySavedListings')['sessionToken'], _buyer.sessionToken);
    });

    testWidgets('My Viewings opens the viewing requests the client sent', (tester) async {
      final backend = _backend();
      await _pump(tester, backend, _buyer);
      await _openTile(tester, 'profile-viewings');
      expect(find.text('My Viewings'), findsOneWidget);
      expect(find.text('No viewing requests yet.'), findsOneWidget);
      expect(backend.count('bookings:getUserBookings'), 1);
    });

    testWidgets('Messages opens the inbox', (tester) async {
      final backend = _backend();
      await _pump(tester, backend, _buyer);
      await _openTile(tester, 'profile-messages');
      expect(backend.count('messaging:getMyConversations'), 1);
      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('a verified owner also gets Viewing Requests (to accept or decline visits to their properties)', (tester) async {
      final backend = _backend();
      await _pump(tester, backend, _seller);
      expect(find.byKey(const Key('profile-viewing-requests')), findsOneWidget);
      await _openTile(tester, 'profile-viewing-requests');
      expect(find.text('Viewing Requests'), findsWidgets);
      expect(backend.lastArgs('bookings:getMyViewingRequests')['sessionToken'], _seller.sessionToken);
    });
  });
}
