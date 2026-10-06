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
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/core/theme/app_theme.dart';
import 'package:vektolux/core/widgets/app_text_scale.dart';
import 'package:vektolux/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/domain/repositories/auth_repository.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/profile/presentation/views/account_profile_screen.dart';
import 'package:vektolux/features/profile/presentation/views/profile_screen.dart';
import 'package:vektolux/features/wallet_payments/presentation/bloc/wallet_cubit.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

typedef _Route = Object? Function(Map<String, dynamic> args);

/// A refusal from the server (the mutation threw).
class _ServerError {
  final String message;
  const _ServerError(this.message);
}

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

Future<_MockAuthBloc> _pump(WidgetTester tester, _Backend backend, UserEntity user) async {
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
  return bloc;
}

/// The signed-in session as the app stores it on the device (read by AuthRepositoryImpl).
void _seedSession(UserEntity u) => SharedPreferences.setMockInitialValues({
      'vkt_session_token': u.sessionToken!,
      'vkt_user_id': u.id,
      'vkt_user_data': jsonEncode({
        'id': u.id, 'name': u.name, 'email': u.email, 'phone': u.phone, 'role': u.role.convexValue,
        'isVerified': u.isVerified, 'verificationStatus': u.verificationStatus,
        'bio': u.bio, 'address': u.address, 'region': u.region,
      }),
    });

/// Routes the shared Account & Profile screen reads.
Map<String, _Route> _accountProfileRoutes(UserEntity u) => {
      'users:getUserProfile': (_) => {
            '_id': u.id, 'name': u.name, 'identityVerified': u.isVerified, 'email': u.email, 'phone': u.phone,
            'memberSince': DateTime.utc(2025, 4, 12, 12).millisecondsSinceEpoch,
          },
      'payments:getUserSecurityPinStatus': (_) => {'hasPin': false, 'hasPassword': true},
    };

Future<void> _openEditProfile(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Edit Profile').first);
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

  group('Account — Edit Profile and the shared Account & Profile screen', () {
    setUp(() => _seedSession(_buyer));

    testWidgets('name and phone are read-only; only area, address and bio are inputs', (tester) async {
      await _pump(tester, _backend(), _buyer);
      await _openEditProfile(tester);
      final name = find.byKey(const Key('edit-profile-name'));
      final phone = find.byKey(const Key('edit-profile-phone'));
      expect(find.descendant(of: name, matching: find.text('Aminata Kamara')), findsOneWidget);
      expect(find.descendant(of: name, matching: find.textContaining('managed by Vektolux')), findsOneWidget);
      expect(find.descendant(of: name, matching: find.byType(EditableText)), findsNothing);
      expect(find.descendant(of: phone, matching: find.text('+23276000111')), findsOneWidget);
      expect(find.descendant(of: phone, matching: find.byType(EditableText)), findsNothing);
      expect(find.byType(EditableText), findsNWidgets(2), reason: 'street address and bio only');
    });

    testWidgets('Account & Profile opens from the Account tab (the same screen agents use)', (tester) async {
      await _pump(tester, _backend()..routes.addAll(_accountProfileRoutes(_buyer)), _buyer);
      await _openTile(tester, 'profile-account-profile');
      expect(find.byType(AccountProfileScreen), findsOneWidget);
      expect(find.byKey(const Key('account-verified-name')), findsOneWidget);
    });

    testWidgets('the fake biometric switch is gone; Biometric login opens the shared screen\'s real setting', (tester) async {
      final backend = _backend()..routes.addAll(_accountProfileRoutes(_buyer));
      await _pump(tester, backend, _buyer);
      expect(find.text('Biometric / FaceID Authorization'), findsNothing);
      expect(find.textContaining('authorize escrow transactions'), findsNothing);
      expect(find.byKey(const Key('profile-biometric-login')), findsOneWidget);
      await _openTile(tester, 'profile-biometric-login');
      expect(find.byType(AccountProfileScreen), findsOneWidget);
      // No biometric hardware in the test: the real setting says so instead of offering a switch.
      expect(find.byKey(const Key('account-biometric-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('account-biometric-switch')), findsNothing);
    });

    testWidgets('the old PIN sheet is gone; the Account PIN row opens the shared screen', (tester) async {
      final backend = _backend()..routes.addAll(_accountProfileRoutes(_buyer));
      await _pump(tester, backend, _buyer);
      expect(find.text('Escrow Security PIN'), findsNothing);
      await _openTile(tester, 'profile-account-pin');
      expect(find.byType(AccountProfileScreen), findsOneWidget);
      expect(find.byKey(const Key('account-pin-row')), findsOneWidget);
    });

    testWidgets('Delete Account goes through the shared 30-day request, never the old immediate delete', (tester) async {
      final backend = _backend()
        ..routes.addAll(_accountProfileRoutes(_buyer))
        ..routes['users:requestAccountDeletion'] = (_) => {
              'success': false,
              'errorCode': 'FUNDS_REMAINING',
              'message': 'Withdraw your wallet balance and settle any escrow before deleting your account.',
            };
      await _pump(tester, backend, _buyer);
      expect(find.text('Delete Account & Erase Personal Data'), findsNothing);
      expect(find.textContaining('scheduled for deletion after 30 days'), findsOneWidget);
      await _openTile(tester, 'profile-delete-account');
      expect(find.byType(AccountProfileScreen), findsOneWidget);

      await tester.scrollUntilVisible(find.byKey(const Key('account-delete-button')), 150,
          scrollable: find.byType(Scrollable).first);
      await _openTile(tester, 'account-delete-button');
      await tester.enterText(find.byKey(const Key('account-delete-confirm-input')), 'DELETE');
      await _settle(tester, 2);
      await tester.ensureVisible(find.byKey(const Key('account-delete-submit')));
      await tester.tap(find.byKey(const Key('account-delete-submit')));
      await _settle(tester);

      expect(backend.count('users:requestAccountDeletion'), 1);
      expect(find.textContaining('Withdraw your wallet balance'), findsOneWidget);
      expect(backend.count('users:deleteUserAccount'), 0);
    });

    testWidgets('"Change phone number" opens the shared phone-change flow', (tester) async {
      final backend = _backend()..routes.addAll(_accountProfileRoutes(_buyer));
      await _pump(tester, backend, _buyer);
      await _openEditProfile(tester);
      await tester.ensureVisible(find.byKey(const Key('edit-profile-change-phone')));
      await tester.tap(find.byKey(const Key('edit-profile-change-phone')));
      await _settle(tester, 12);
      expect(find.byType(AccountProfileScreen), findsOneWidget);
      expect(find.byKey(const Key('account-phone-input')), findsOneWidget, reason: 'its phone sheet opens directly');
      expect(backend.count('users:updateUserProfile'), 0);
    });

    testWidgets('bio and address still save; success only after the server accepts', (tester) async {
      final backend = _backend()..routes['users:updateUserProfile'] = (_) => true;
      final bloc = await _pump(tester, backend, _buyer);
      await _openEditProfile(tester);
      clearInteractions(bloc); // the Account tab refreshes the session once when it opens
      await tester.enterText(find.byType(EditableText).at(0), '9 Wilkinson Road, Freetown');
      await tester.enterText(find.byType(EditableText).at(1), 'Looking for a family home.');
      await tester.ensureVisible(find.byKey(const Key('edit-profile-save')));
      await tester.tap(find.byKey(const Key('edit-profile-save')));
      await _settle(tester);
      expect(backend.lastArgs('users:updateUserProfile'), {
        'userId': 'buyer_1',
        'address': '9 Wilkinson Road, Freetown',
        'bio': 'Looking for a family home.',
        'sessionToken': _buyer.sessionToken,
      }, reason: 'name and phone are never sent from this sheet');
      expect(find.text('Profile information updated successfully.'), findsOneWidget);
      expect(find.byKey(const Key('edit-profile-save')), findsNothing, reason: 'the sheet closed');
      verify(() => bloc.add(const RefreshUserSessionEvent())).called(1);
    });

    testWidgets('a rejected save shows the server reason and never claims success', (tester) async {
      final backend = _backend()
        ..routes['users:updateUserProfile'] = (_) => const _ServerError('Bio contains a phone number.');
      final bloc = await _pump(tester, backend, _buyer);
      await _openEditProfile(tester);
      clearInteractions(bloc); // the Account tab refreshes the session once when it opens
      await tester.enterText(find.byType(EditableText).at(1), 'Call me on 076 000 111');
      await tester.ensureVisible(find.byKey(const Key('edit-profile-save')));
      await tester.tap(find.byKey(const Key('edit-profile-save')));
      await _settle(tester);
      expect(find.text('Profile information updated successfully.'), findsNothing);
      expect(find.byKey(const Key('edit-profile-error')), findsOneWidget);
      expect(find.text('Bio contains a phone number.'), findsOneWidget);
      expect(find.byKey(const Key('edit-profile-save')), findsOneWidget, reason: 'the sheet stays open');
      verifyNever(() => bloc.add(const RefreshUserSessionEvent()));
    });

    testWidgets('a network failure is explained plainly and is not reported as success', (tester) async {
      final backend = _backend()..routes['users:updateUserProfile'] = (_) => const _ServerError('HTTP 503: upstream');
      await _pump(tester, backend, _buyer);
      await _openEditProfile(tester);
      await tester.enterText(find.byType(EditableText).at(1), 'New bio');
      await tester.ensureVisible(find.byKey(const Key('edit-profile-save')));
      await tester.tap(find.byKey(const Key('edit-profile-save')));
      await _settle(tester);
      expect(find.text('Profile information updated successfully.'), findsNothing);
      expect(find.textContaining('could not be saved'), findsOneWidget);
    });
  });

  group('Account — only real data', () {
    testWidgets('the fake "Saved addresses" are gone', (tester) async {
      await _pump(tester, _backend(), _buyer);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Account & Profile')), findsOneWidget);
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
