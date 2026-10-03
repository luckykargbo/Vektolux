// The Real Estate Agent workspace, rendered for real (MainNavigationShell → AgentShell) against
// a fake Convex backend that answers with responses shaped like the real functions. Nothing
// leaves the test. Covers: role routing (agent / buyer / owner / pending / rejected /
// suspended / unavailable), dashboard values, subscription & posting states, listing status
// and filters, messages, notifications, navigation, and layout at several iPhone sizes.

import 'dart:async';
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
import 'package:vektolux/features/navigation/presentation/views/main_navigation_shell.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _ServerError {
  final String message;
  const _ServerError(this.message);
}

typedef _Route = Object? Function(Map<String, dynamic> args);

/// A fake Convex deployment: answers by function path, records every call.
class _Backend {
  final Map<String, _Route> routes;
  final List<(String, Map<String, dynamic>)> calls = [];
  final Map<String, Completer<void>> holds = {};

  _Backend(this.routes);

  ConvexClientWrapper client() => ConvexClientWrapper(
        deploymentUrl: 'https://example.invalid',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final path = body['path'] as String;
          final args = Map<String, dynamic>.from(body['args'] as Map);
          calls.add((path, args));
          final hold = holds[path];
          if (hold != null) await hold.future;
          final route = routes[path];
          final value = route == null ? null : route(args);
          if (value is _ServerError) {
            return http.Response(jsonEncode({'status': 'error', 'errorMessage': 'Uncaught Error: ${value.message}'}), 200);
          }
          return http.Response(jsonEncode({'status': 'success', 'value': value}), 200);
        }),
      );

  bool called(String path) => calls.any((c) => c.$1 == path);
  Map<String, dynamic> lastArgs(String path) => calls.lastWhere((c) => c.$1 == path).$2;
}

// ─── Fixtures (shaped like the real Convex responses) ───────────────────

const _agentUser = UserEntity(
  id: 'agent_1',
  name: 'Mariama Sesay',
  email: 'mariama@test.vektolux',
  phone: '+23276111222',
  role: UserRole.agent,
  isVerified: true,
  sessionToken: 'sess_agent_1_0123456789abcdef',
);

const _clientUser = UserEntity(
  id: 'client_1',
  name: 'Lucky Kargbo',
  email: 'lucky@test.vektolux',
  phone: '+23276000000',
  role: UserRole.client,
  isVerified: true,
  sessionToken: 'sess_client_1_0123456789abcdef',
);

final int _future = DateTime(2030).millisecondsSinceEpoch;
final int _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> _status({
  String role = 'real_estate_agent',
  bool approved = true,
  bool subscribed = true,
  List<Map<String, dynamic>> applications = const [],
}) =>
    {
      'role': role,
      'roleApproved': approved,
      'verifiedAgent': approved && subscribed && role == 'real_estate_agent',
      'verifiedHotel': false,
      'agentExpiresAt': subscribed ? _future : null,
      'hotelExpiresAt': null,
      'hasActiveSubscription': subscribed,
      'isInGracePeriod': false,
      'gracePeriodEndsAt': null,
      'legacyGraceEndedAt': null,
      'subscriptionPolicyConfigured': false,
      'canPostProperty': approved && (subscribed || role == 'real_estate_owner'),
      'canPostVehicle': false,
      'canManageHotel': false,
      'applications': applications,
    };

Map<String, dynamic> _listing(String id, String title, {String category = 'sale', bool published = true, num price = 2850000}) => {
      '_id': id,
      '_creationTime': _now - 1000 * id.hashCode.abs() % 100000,
      'ownerId': 'agent_1',
      'title': title,
      'description': 'A well kept property',
      'category': category,
      'price': price,
      'currency': 'SLE',
      'address': '17 Hidden Close', // private — must never be shown
      'latitude': 8.4012,
      'longitude': -13.2123,
      'privateContactPhone': '+23277555999', // private — must never be shown
      'city': 'Aberdeen',
      'district': 'Western Area Urban',
      'country': 'Sierra Leone',
      'bedrooms': 3,
      'bathrooms': 2,
      'areaSqM': 167,
      'imageUrls': <String>[],
      'availabilityStatus': 'available',
      'isFeatured': false,
      'isPublished': published,
      'viewCount': 0,
      'updatedAt': _now,
    };

Map<String, dynamic> _inquiry(String status) => {
      'id': 'q1',
      'buyerName': 'Aminata Kamara',
      'buyerAvatarUrl': null,
      'buyerIsVerified': true,
      'listingId': 'l1',
      'listingType': 'property',
      'message': 'Hello, is this property still available?',
      'status': status,
      'createdAt': _now - 60000,
      if (status != 'pending') 'respondedAt': _now,
    };

/// Everything an approved, subscribed agent with two listings sees.
Map<String, _Route> _agentRoutes({
  Map<String, dynamic>? status,
  List<Map<String, dynamic>>? listings,
  List<Map<String, dynamic>> authorizations = const [],
  Map<String, Map<String, dynamic>> publicProperties = const {},
  List<Map<String, dynamic>>? inquiries,
  int unread = 3,
}) {
  final inquiryState = inquiries ?? [_inquiry('pending')];
  return {
    'subscriptions:getMyProfessionalStatus': (_) => status ?? _status(),
    'subscriptions:getUserActiveSubscription': (_) => (status ?? _status())['hasActiveSubscription'] == true
        ? {'planName': 'Agent Pro', 'tierCode': 'agent_pro', 'status': 'active', 'expiryDate': _future}
        : null,
    'realEstate:getMyPropertyListings': (_) =>
        listings ??
        [
          _listing('l1', 'Modern 3 Bedroom House'),
          _listing('l2', '2 Bedroom Apartment', category: 'long_term_rent', published: false, price: 1200000),
        ],
    'listingAgents:getMyAgentAuthorizations': (_) => authorizations,
    'realEstate:getPropertyById': (a) => publicProperties[a['listingId']],
    'adminPortal:getSellerContactRequests': (_) => inquiryState,
    'adminPortal:respondToContactRequest': (a) {
      final accepted = a['action'] == 'accepted';
      inquiryState[0] = _inquiry(accepted ? 'accepted' : 'declined');
      return {
        'status': accepted ? 'ACCEPTED' : 'DECLINED',
        'sellerPhone': accepted ? '+23276111222' : null,
        'message': accepted ? 'Contact request accepted. The buyer can now see your phone number.' : 'Contact request declined.',
      };
    },
    'notifications:getUnreadNotificationCount': (_) => unread,
    'notifications:getUserNotifications': (_) => [
          {
            'id': 'n1', 'targetType': 'single_user', 'title': 'Application approved',
            'body': 'You are approved as a Real Estate Agent.', 'read': false, 'createdAt': _now - 5000,
          },
          {
            'id': 'n2', 'targetType': 'all_users', 'title': 'Planned maintenance',
            'body': 'The app is unavailable on Saturday night.', 'read': true, 'createdAt': _now - 9000000,
          },
        ],
    'notifications:markAsRead': (_) => true,
    'realEstateEscrow:getMyRealEstateEscrows': (_) => {
          'contracts': [
            {'_id': 'c1', 'contractCode': 'VX-DEAL-1', 'currentState': 'FUNDS_LOCKED', 'isOwner': true, 'propertyTitle': 'Modern 3 Bedroom House', 'netBeneficiaryExpected': 2400000, 'releasedBeneficiaryAmount': 0, 'platformFeeAmount': 142500},
            {'_id': 'c2', 'contractCode': 'VX-DEAL-2', 'currentState': 'FULLY_SETTLED', 'isOwner': true, 'propertyTitle': 'Old flat'},
            {'_id': 'c3', 'contractCode': 'VX-DEAL-3', 'currentState': 'FUNDS_LOCKED', 'isOwner': false, 'propertyTitle': 'Bought as client'},
          ],
          'inspectionPasses': [],
        },
    'walletCore:getEarningsSummary': (_) => {'totalEarned': 1250.5, 'currency': 'SLE', 'count': 2, 'truncated': false},
    'users:getUserProfile': (_) => {'_id': 'agent_1', 'name': 'Mariama Sesay', 'followersCount': 7, 'followingCount': 2},
    'listingAgents:respondToListingAgentInvitation': (_) => {'status': 'active'},
    'realEstate:updatePropertyListing': (_) => {'success': true, 'message': 'Listing updated successfully'},
  };
}

// ─── Harness ─────────────────────────────────────────────────────────────

final List<String> _layoutErrors = [];

Future<void> _pump(
  WidgetTester tester, {
  required UserEntity user,
  required _Backend backend,
  double width = 393,
  double height = 852,
  double textScale = 1.0,
  bool settle = true,
}) async {
  _layoutErrors.clear();
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    _layoutErrors.add(details.toString());
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  final bloc = _MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(), initialState: AuthState(status: AuthStatus.authenticated, user: user));
  await tester.pumpWidget(
    RepositoryProvider<ConvexClientWrapper>.value(
      value: backend.client(),
      child: BlocProvider<AuthBloc>.value(
        value: bloc,
        child: MaterialApp(theme: ThemeData(fontFamily: 'Roboto'), home: const MainNavigationShell()),
      ),
    ),
  );
  if (settle) await _settle(tester);
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

void _expectNoLayoutErrors(WidgetTester tester) {
  tester.takeException();
  if (_layoutErrors.isEmpty) return;
  fail(_layoutErrors.join('\n----\n'));
}

Finder _nav(int index) => find.byKey(Key('agent-nav-$index'));

Future<void> _openTab(WidgetTester tester, int index) async {
  await tester.tap(_nav(index));
  await _settle(tester, 5);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

bool _showsAgentNav() => _nav(0).evaluate().isNotEmpty;
bool _showsBuyerNav() => find.text('Auto Market').evaluate().isNotEmpty && find.text('Explore').evaluate().isNotEmpty;

Future<void> _loadRealFont() async {
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
  final loader = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
    final file = File('${dir.path}/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadRealFont);

  group('role-specific routing (server-authoritative)', () {
    testWidgets('an approved Real Estate Agent gets the agent workspace, not the buyer shell', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _agentUser, backend: backend);
      expect(_showsAgentNav(), isTrue);
      final labels = ['Home', 'Listings', 'Messages', 'Notifications', 'Profile'];
      for (var i = 0; i < labels.length; i++) {
        expect(find.descendant(of: _nav(i), matching: find.text(labels[i])), findsOneWidget, reason: labels[i]);
      }
      expect(find.text('Auto Market'), findsNothing);
      expect(find.byKey(const Key('agent-header-name')), findsOneWidget);
      expect(find.text('Mariama Sesay'), findsOneWidget);
      expect(backend.lastArgs('subscriptions:getMyProfessionalStatus')['sessionToken'], _agentUser.sessionToken);
      await _tearDown(tester);
    });

    testWidgets('a client keeps the buyer interface', (tester) async {
      final backend = _Backend({'subscriptions:getMyProfessionalStatus': (_) => _status(role: 'client', approved: false, subscribed: false)});
      await _pump(tester, user: _clientUser, backend: backend);
      expect(_showsBuyerNav(), isTrue);
      expect(_showsAgentNav(), isFalse);
      await _tearDown(tester);
    });

    testWidgets('a Real Estate Owner keeps the owner/standard interface (not the agent dashboard)', (tester) async {
      final backend = _Backend({'subscriptions:getMyProfessionalStatus': (_) => _status(role: 'real_estate_owner', subscribed: false)});
      // The app maps owner accounts to UserRole.agent locally — only the server can tell them apart.
      await _pump(tester, user: _agentUser, backend: backend);
      expect(_showsBuyerNav(), isTrue);
      expect(_showsAgentNav(), isFalse);
      await _tearDown(tester);
    });

    testWidgets('the server decides: a stale local "client" role still opens an approved agent\'s workspace', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _clientUser, backend: backend);
      expect(_showsAgentNav(), isTrue);
      await _tearDown(tester);
    });

    testWidgets('a pending agent sees the approval state and can browse as a client', (tester) async {
      final backend = _Backend({
        'subscriptions:getMyProfessionalStatus': (_) => _status(approved: false, subscribed: false, applications: [
              {'id': 'a1', 'targetRole': 'agent', 'status': 'pending', 'reviewNotes': null},
            ]),
      });
      await _pump(tester, user: _agentUser, backend: backend);
      expect(find.text('Your agent application is under review'), findsOneWidget);
      expect(_showsAgentNav(), isFalse);
      expect(backend.called('realEstate:getMyPropertyListings'), isFalse, reason: 'no agent data is loaded before approval');

      await _tapVisible(tester, find.byKey(const Key('agent-pending-browse')));
      await _settle(tester);
      expect(_showsBuyerNav(), isTrue);
      expect(find.text('Your agent application'), findsOneWidget, reason: 'a bar leads back to the status');
      await _tearDown(tester);
    });

    testWidgets('a client whose agent application is pending sees the approval state', (tester) async {
      final backend = _Backend({
        'subscriptions:getMyProfessionalStatus': (_) => _status(role: 'client', approved: false, subscribed: false, applications: [
              {'id': 'a1', 'targetRole': 'agent', 'status': 'pending'},
            ]),
      });
      await _pump(tester, user: _clientUser, backend: backend);
      expect(find.byKey(const Key('agent-pending-title')), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a rejected agent sees the decision and the reviewer note, without agent tools', (tester) async {
      final backend = _Backend({
        'subscriptions:getMyProfessionalStatus': (_) => _status(approved: false, subscribed: false, applications: [
              {'id': 'a1', 'targetRole': 'agent', 'status': 'rejected', 'reviewNotes': 'Licence number could not be verified'},
            ]),
      });
      await _pump(tester, user: _agentUser, backend: backend);
      expect(find.text('Your agent application was not approved'), findsOneWidget);
      expect(find.textContaining('Licence number could not be verified'), findsOneWidget);
      expect(_showsAgentNav(), isFalse);
      await _tearDown(tester);
    });

    testWidgets('a suspended agent (client again) keeps only the standard app', (tester) async {
      final backend = _Backend({
        'subscriptions:getMyProfessionalStatus': (_) => _status(role: 'client', approved: false, subscribed: false, applications: [
              {'id': 'a1', 'targetRole': 'agent', 'status': 'suspended', 'reviewNotes': 'Complaints'},
            ]),
      });
      await _pump(tester, user: _agentUser, backend: backend);
      expect(_showsBuyerNav(), isTrue);
      expect(_showsAgentNav(), isFalse);
      await _tearDown(tester);
    });

    testWidgets('if the status cannot be read, an agent-like account gets a recoverable error (never the workspace)', (tester) async {
      var unavailable = true;
      final backend = _Backend({
        'subscriptions:getMyProfessionalStatus': (_) => unavailable ? const _ServerError('Service unavailable') : _status(),
        ..._agentRoutes()..remove('subscriptions:getMyProfessionalStatus'),
      });
      await _pump(tester, user: _agentUser, backend: backend);
      expect(find.byKey(const Key('agent-access-error')), findsOneWidget);
      expect(_showsAgentNav(), isFalse);
      unavailable = false;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(_showsAgentNav(), isTrue);
      await _tearDown(tester);
    });

    testWidgets('a backend that does not have the status function yet (not deployed) keeps the standard app', (tester) async {
      final backend = _Backend({
        'subscriptions:getMyProfessionalStatus': (_) => const _ServerError(
            "Could not find public function for 'subscriptions:getMyProfessionalStatus'. Did you forget to run `npx convex dev`?"),
      });
      await _pump(tester, user: _agentUser, backend: backend);
      expect(_showsBuyerNav(), isTrue);
      expect(_showsAgentNav(), isFalse);
      expect(find.byKey(const Key('agent-access-error')), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('while the status is read, an agent-like account sees a neutral loading view', (tester) async {
      final backend = _Backend(_agentRoutes());
      backend.holds['subscriptions:getMyProfessionalStatus'] = Completer<void>();
      await _pump(tester, user: _agentUser, backend: backend, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('agent-access-checking')), findsOneWidget);
      expect(_showsAgentNav(), isFalse);
      expect(_showsBuyerNav(), isFalse);
      backend.holds['subscriptions:getMyProfessionalStatus']!.complete();
      await _settle(tester);
      expect(_showsAgentNav(), isTrue);
      await _tearDown(tester);
    });

    testWidgets('an approved agent can switch to the client view and back', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _agentUser, backend: backend);
      await tester.tap(find.byTooltip('Settings').first);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('agent-settings-client-view')));
      await _settle(tester);
      expect(_showsBuyerNav(), isTrue);
      expect(find.text('Viewing Vektolux as a client'), findsOneWidget);
      await tester.tap(find.byKey(const Key('return-to-agent-workspace')));
      await _settle(tester);
      expect(_showsAgentNav(), isTrue);
      await _tearDown(tester);
    });
  });

  group('agent dashboard', () {
    testWidgets('shows the real server values and nothing invented', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes()));
      expect(find.byKey(const Key('agent-verified-badge')), findsOneWidget);
      expect(find.text('Agent Pro'), findsOneWidget, reason: 'subscription label from the active plan');
      expect(find.text('Real Estate Agent'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-total-listings')), matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-active-deals')), matching: find.text('1')), findsOneWidget);
      expect(find.text('SLE 1,250.50'), findsOneWidget);
      expect(find.text('2 completed payouts to your wallet'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-home-notifications')), matching: find.text('3')), findsOneWidget);
      expect(find.text('Modern 3 Bedroom House'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
      // no invented monthly figure / trend, and no private data
      expect(find.textContaining('This Month'), findsNothing);
      expect(find.textContaining('vs last month'), findsNothing);
      expect(find.textContaining('Hidden Close'), findsNothing);
      expect(find.textContaining('555999'), findsNothing);
      expect(find.textContaining('Aberdeen, Western Area Urban'), findsWidgets);
      _expectNoLayoutErrors(tester);
      await _tearDown(tester);
    });

    testWidgets('without an active subscription: no badge or label, posting is blocked and explained', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes(status: _status(subscribed: false))));
      expect(find.byKey(const Key('agent-verified-badge')), findsNothing);
      expect(find.byKey(const Key('agent-subscription-label')), findsNothing);
      expect(find.byKey(const Key('agent-posting-blocked')), findsOneWidget);
      expect(find.textContaining('subscription is not active'), findsWidgets);
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Add Listing')));
      await _settle(tester);
      expect(find.text('Posting is not available'), findsOneWidget);
      expect(find.text('Step 1 of 7'), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('with posting allowed, Add Listing opens the 7-step flow', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes()));
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Add Listing')));
      await _settle(tester);
      expect(find.text('Step 1 of 7'), findsOneWidget);
      expect(find.text('Basic information'), findsOneWidget);
      // validation keeps the agent on the step until it is complete
      await tester.tap(find.byKey(const Key('agent-add-next')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('agent-add-error')), findsOneWidget);
      expect(find.text('Step 1 of 7'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('empty state offers Add Listing when posting is allowed', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes(listings: const [])));
      expect(find.text('No listings yet'), findsOneWidget);
      expect(find.ancestor(of: find.text('Add Listing'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-total-listings')), matching: find.text('0')), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('loading state, then the real listings', (tester) async {
      final backend = _Backend(_agentRoutes());
      backend.holds['realEstate:getMyPropertyListings'] = Completer<void>();
      await _pump(tester, user: _agentUser, backend: backend);
      expect(find.text('Loading your listings…'), findsOneWidget);
      expect(find.text('Modern 3 Bedroom House'), findsNothing);
      backend.holds['realEstate:getMyPropertyListings']!.complete();
      await _settle(tester);
      expect(find.text('Modern 3 Bedroom House'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a backend error is shown with Retry — no placeholder listings', (tester) async {
      var down = true;
      final routes = _agentRoutes();
      final real = routes['realEstate:getMyPropertyListings']!;
      routes['realEstate:getMyPropertyListings'] = (a) => down ? const _ServerError('Listings are unavailable') : real(a);
      await _pump(tester, user: _agentUser, backend: _Backend(routes));
      expect(find.text('Listings are unavailable'), findsOneWidget);
      expect(find.text('Modern 3 Bedroom House'), findsNothing);
      down = false;
      await tester.tap(find.text('Retry').first);
      await _settle(tester);
      expect(find.text('Modern 3 Bedroom House'), findsOneWidget);
      await _tearDown(tester);
    });
  });

  group('My Listings', () {
    testWidgets('filters, counts and real status badges', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes()));
      await _openTab(tester, 1);
      expect(find.text('My Listings'), findsOneWidget);
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('For Sale (1)'), findsOneWidget);
      expect(find.text('For Rent (1)'), findsOneWidget);
      expect(find.text('Unpublished (1)'), findsOneWidget);
      expect(find.byKey(const Key('agent-listing-l1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-listing-l2')), matching: find.text('Unpublished')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-listing-l2')), matching: find.text('SLE 1,200,000 / year')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent-filter-unpublished')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('agent-listing-l1')), findsNothing);
      expect(find.byKey(const Key('agent-listing-l2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent-filter-sale')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('agent-listing-l1')), findsOneWidget);
      expect(find.byKey(const Key('agent-listing-l2')), findsNothing);
      expect(find.textContaining('Hidden Close'), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('unpublishing goes through the server and the list is re-read', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 1);
      await tester.tap(find.byKey(const Key('agent-listing-menu-l1')));
      await _settle(tester, 3);
      await tester.tap(find.text('Unpublish').last);
      await _settle(tester, 3);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Unpublish'));
      await _settle(tester);
      final args = backend.lastArgs('realEstate:updatePropertyListing');
      expect(args['listingId'], 'l1');
      expect(args['isPublished'], false);
      expect(args['sessionToken'], _agentUser.sessionToken);
      expect(backend.calls.where((c) => c.$1 == 'realEstate:getMyPropertyListings').length, greaterThanOrEqualTo(2));
      await _tearDown(tester);
    });

    testWidgets('owner-authorised listings are marked and read-only; invitations can be answered', (tester) async {
      final backend = _Backend(_agentRoutes(
        authorizations: [
          {'id': 'auth1', 'listingType': 'property', 'listingId': 'p9', 'status': 'active', 'invitedAt': _now - 10000, 'acceptedAt': _now - 9000},
          {'id': 'auth2', 'listingType': 'property', 'listingId': 'p10', 'status': 'pending', 'invitedAt': _now - 5000},
        ],
        publicProperties: {
          'p9': {'_id': 'p9', 'title': 'Owner Villa', 'category': 'sale', 'price': 5500000, 'currency': 'SLE', 'publicLocation': 'Inside Lumley, Sierra Leone', 'imageUrls': [], 'isPublished': true, 'availabilityStatus': 'available'},
          'p10': {'_id': 'p10', 'title': 'Land for Sale', 'category': 'sale', 'price': 750000, 'currency': 'SLE', 'publicLocation': 'Inside Waterloo, Sierra Leone', 'imageUrls': [], 'isPublished': true, 'availabilityStatus': 'available'},
        },
      ));
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 1);
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Representing the owner'), findsOneWidget);
      expect(find.text('Invitations from owners'), findsOneWidget);
      expect(find.text('Land for Sale'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent-listing-menu-p9')));
      await _settle(tester, 3);
      expect(find.text('Stop representing'), findsOneWidget);
      expect(find.text('Delete'), findsNothing, reason: 'the owner keeps control of a represented listing');
      expect(find.text('Edit details'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await _settle(tester, 3);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Accept'));
      await _settle(tester);
      final args = backend.lastArgs('listingAgents:respondToListingAgentInvitation');
      expect(args['authorizationId'], 'auth2');
      expect(args['accept'], true);
      await _tearDown(tester);
    });
  });

  group('messages and notifications', () {
    testWidgets('inbox shows real inquiries; the conversation offers only what the server supports', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 2);
      expect(find.text('Aminata Kamara'), findsOneWidget);
      expect(find.text('Hello, is this property still available?'), findsOneWidget);
      expect(find.textContaining('Re: Modern 3 Bedroom House'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent-inquiry-q1')));
      await _settle(tester);
      expect(find.byKey(const Key('agent-conversation-message')), findsOneWidget);
      expect(find.byKey(const Key('agent-conversation-no-reply')), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'no fake reply box: the backend has no reply API');

      await tester.tap(find.byKey(const Key('agent-inquiry-accept')));
      await _settle(tester, 3);
      expect(find.textContaining('share your phone number'), findsOneWidget, reason: 'the privacy effect is stated before accepting');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Accept').last);
      await _settle(tester);
      expect(backend.lastArgs('adminPortal:respondToContactRequest')['action'], 'accepted');
      expect(find.textContaining('You accepted this inquiry on'), findsOneWidget);
      expect(find.byKey(const Key('agent-inquiry-accept')), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('no inquiries → empty state, never sample conversations', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes(inquiries: [])));
      await _openTab(tester, 2);
      expect(find.text('No messages yet'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('notification tabs: admin = broadcasts, system = account events, messages = inquiries', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 3);
      expect(find.text('Application approved'), findsOneWidget);
      expect(find.text('Planned maintenance'), findsOneWidget);
      expect(find.text('New message from Aminata Kamara'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent-notif-tab-admin')));
      await _settle(tester, 3);
      expect(find.text('Planned maintenance'), findsOneWidget);
      expect(find.text('Application approved'), findsNothing);

      await tester.tap(find.byKey(const Key('agent-notif-tab-system')));
      await _settle(tester, 3);
      expect(find.text('Application approved'), findsOneWidget);
      expect(find.text('Planned maintenance'), findsNothing);
      expect(find.text('New message from Aminata Kamara'), findsNothing);

      await tester.tap(find.byKey(const Key('agent-notif-tab-messages')));
      await _settle(tester, 3);
      expect(find.text('New message from Aminata Kamara'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent-notif-tab-system')));
      await _settle(tester, 3);
      await tester.tap(find.text('Application approved'));
      await _settle(tester);
      expect(backend.lastArgs('notifications:markAsRead')['notificationId'], 'n1');
      await _tearDown(tester);
    });
  });

  group('navigation', () {
    testWidgets('the five destinations, the dashboard shortcuts and the profile links', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes()));
      await _openTab(tester, 1);
      expect(find.text('My Listings'), findsOneWidget);
      await _openTab(tester, 2);
      expect(find.byKey(const Key('agent-messages-search')), findsOneWidget);
      await _openTab(tester, 3);
      expect(find.text('Notifications'), findsWidgets);
      await _openTab(tester, 4);
      expect(find.byKey(const Key('agent-menu-Earnings & Payouts')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-stat-Followers')), matching: find.text('7')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-stat-Active Deals')), matching: find.text('1')), findsOneWidget);
      expect(find.byKey(const Key('agent-logout')), findsOneWidget);

      await _openTab(tester, 0);
      await tester.tap(find.byKey(const Key('agent-home-notifications')));
      await _settle(tester, 4);
      expect(find.byKey(const Key('agent-notif-tab-all')), findsOneWidget);

      await _openTab(tester, 0);
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Messages')));
      await _settle(tester, 4);
      expect(find.byKey(const Key('agent-messages-search')), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('Earnings & Payouts shows server figures only', (tester) async {
      final routes = _agentRoutes();
      routes['wallet:getUserBalance'] =
          (_) => {'availableBalance': 300.0, 'pendingBalance': 0.0, 'escrowBalance': 50.0, 'currency': 'SLE'};
      routes['withdrawals:getMyWithdrawals'] = (_) => [
            {'id': 'w1', 'amount': 100, 'currency': 'SLE', 'method': 'mobile_money', 'provider': 'orange', 'destination': '****9876', 'status': 'completed', 'createdAt': _now - 86400000},
          ];
      await _pump(tester, user: _agentUser, backend: _Backend(routes));
      await _openTab(tester, 4);
      await tester.tap(find.byKey(const Key('agent-menu-Earnings & Payouts')));
      await _settle(tester);
      expect(find.byKey(const Key('agent-earnings-screen-total')), findsOneWidget);
      expect(find.text('SLE 1,250.50'), findsWidgets);
      expect(find.byKey(const Key('agent-wallet-available')), findsOneWidget);
      expect(find.text('SLE 300.00'), findsOneWidget);
      expect(find.text('SLE 50.00'), findsOneWidget, reason: 'held in escrow, as reported by the server');
      await tester.scrollUntilVisible(find.text('VX-DEAL-1'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('VX-DEAL-1'), findsOneWidget);
      expect(find.text('VX-DEAL-3'), findsNothing, reason: 'a deal where the agent is the buyer is not their earning');
      await tester.scrollUntilVisible(find.text('SLE 100.00'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.textContaining('****9876'), findsOneWidget, reason: 'destination exactly as masked by the server');
      _expectNoLayoutErrors(tester);
      await _tearDown(tester);
    });
  });

  group('Add Listing flow', () {
    testWidgets('7 steps → the existing create mutation; the result shows the server status (never "verified")', (tester) async {
      final listings = [_listing('l1', 'Modern 3 Bedroom House')];
      Map<String, dynamic>? created;
      final routes = _agentRoutes(listings: listings);
      routes['locations:getSierraLeoneLocations'] = (_) => [
            {'region': 'Western Area', 'district': 'Western Area Urban', 'towns': ['Aberdeen', 'Lumley']},
          ];
      routes['realEstate:createPropertyListing'] = (a) {
        created = a;
        listings.add(_listing('new1', a['title'] as String,
            category: a['category'] as String, published: a['isPublished'] == true, price: a['price'] as num));
        return 'new1';
      };
      final backend = _Backend(routes);
      await _pump(tester, user: _agentUser, backend: backend, height: 932);
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Add Listing')));
      await _settle(tester);

      Future<void> next(String expectedTitle) async {
        await tester.tap(find.byKey(const Key('agent-add-next')));
        await _settle(tester, 4);
        expect(find.text(expectedTitle), findsOneWidget);
        _expectNoLayoutErrors(tester);
      }

      // 1 Basic information
      await tester.tap(find.byKey(const Key('agent-add-category-long_term_rent')));
      await tester.enterText(find.byKey(const Key('agent-add-title')), 'Family Home in Aberdeen');
      await tester.enterText(find.byKey(const Key('agent-add-description')), 'Three bedrooms, tiled floors, running water and a fenced compound.');
      await next('Property details');
      // 2 Details (optional) → 3 Photos (optional; video is explained as unsupported)
      await next('Photos');
      expect(find.textContaining('Video highlights are not supported'), findsOneWidget);
      // 4 Price & terms
      await next('Price & terms');
      expect(find.text('Rent per year (SLE)'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('agent-add-price')), '1500000');
      // 5 Public location
      await next('Public location');
      await tester.tap(find.text('District (required)'));
      await _settle(tester, 4);
      await tester.tap(find.text('Western Area Urban — Western Area').last);
      await _settle(tester, 4);
      await tester.tap(find.text('Town / City (optional)'));
      await _settle(tester, 4);
      await tester.tap(find.text('Aberdeen').last);
      await _settle(tester, 4);
      await tester.enterText(find.byKey(const Key('agent-add-address')), '12 Private Street');
      // 6 Amenities
      await next('Amenities & features');
      await tester.tap(find.text('Parking'));
      await _settle(tester, 2);
      // 7 Review & submit
      await next('Review & submit');
      expect(find.text('SLE 1,500,000 / year'), findsOneWidget);
      expect(find.text('Aberdeen, Western Area Urban'), findsOneWidget);
      expect(find.text('12 Private Street'), findsNothing, reason: 'the private address is not part of the public summary');
      await _tapVisible(tester, find.byKey(const Key('agent-add-publish-toggle')));
      await _settle(tester, 2);
      expect(find.text('Save unpublished'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agent-add-submit')));
      await _settle(tester);

      expect(created, isNotNull);
      expect(created!['category'], 'long_term_rent');
      expect(created!['price'], 1500000);
      expect(created!['address'], '12 Private Street');
      expect(created!['city'], 'Aberdeen');
      expect(created!['district'], 'Western Area Urban');
      expect(created!['amenities'], ['Parking']);
      expect(created!['isPublished'], false);
      expect(created!['sessionToken'], _agentUser.sessionToken);
      expect(created!.keys.where((k) => k.toLowerCase().contains('verif') || k.toLowerCase().contains('approv')), isEmpty,
          reason: 'the app never asks for its own listing to be verified or approved');

      expect(find.byKey(const Key('agent-add-result-title')), findsOneWidget);
      expect(find.text('Saved, not published'), findsOneWidget);
      expect(find.text('Unpublished'), findsOneWidget);
      expect(find.text('A submitted listing is not marked as verified or approved.'), findsOneWidget);

      await tester.tap(find.text('Back to My Listings'));
      await _settle(tester);
      expect(_showsAgentNav(), isTrue);
      expect(find.descendant(of: find.byKey(const Key('agent-total-listings')), matching: find.text('2')), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a server refusal is shown as returned, and nothing is marked as created', (tester) async {
      final routes = _agentRoutes();
      routes['locations:getSierraLeoneLocations'] = (_) => [
            {'region': 'Western Area', 'district': 'Western Area Urban', 'towns': ['Aberdeen']},
          ];
      routes['realEstate:createPropertyListing'] =
          (_) => const _ServerError('Your Real Estate Agent subscription is not active. Subscribe to post listings.');
      await _pump(tester, user: _agentUser, backend: _Backend(routes), height: 932);
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Add Listing')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('agent-add-title')), 'Plot of land');
      await tester.enterText(find.byKey(const Key('agent-add-description')), 'Half town lot with documents, near the main road.');
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('agent-add-next')));
        await _settle(tester, 3);
      }
      await tester.enterText(find.byKey(const Key('agent-add-price')), '750000');
      await tester.tap(find.byKey(const Key('agent-add-next')));
      await _settle(tester, 4);
      await tester.tap(find.text('District (required)'));
      await _settle(tester, 4);
      await tester.tap(find.text('Western Area Urban — Western Area').last);
      await _settle(tester, 4);
      await tester.enterText(find.byKey(const Key('agent-add-address')), '3 Hidden Lane');
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('agent-add-next')));
        await _settle(tester, 3);
      }
      await tester.tap(find.byKey(const Key('agent-add-submit')));
      await _settle(tester);
      expect(find.byKey(const Key('agent-add-submit-error')), findsOneWidget);
      expect(find.textContaining('subscription is not active'), findsOneWidget);
      expect(find.byKey(const Key('agent-add-result-title')), findsNothing);
      await _tearDown(tester);
    });
  });

  group('layout of pushed agent pages on small and large phones', () {
    for (final (width, scale) in const [(320.0, 1.35), (430.0, 1.0)]) {
      testWidgets('${width.toInt()}pt, text ×$scale: analytics, settings, earnings, followers, conversation', (tester) async {
        final routes = _agentRoutes();
        routes['social:getFollowersList'] = (_) => [
              {'_id': 'u2', 'name': 'Fatmata Conteh-Williams', 'avatarUrl': null, 'verificationBadge': 'VERIFIED CITIZEN ID • ESCROW ENABLED'},
              {'_id': 'u3', 'name': 'Ibrahim Koroma', 'avatarUrl': null},
            ];
        routes['wallet:getUserBalance'] =
            (_) => {'availableBalance': 1234567.89, 'pendingBalance': 0.0, 'escrowBalance': 987654.32, 'currency': 'SLE'};
        await _pump(tester, user: _agentUser, backend: _Backend(routes), width: width, textScale: scale);

        Future<void> visit(Future<void> Function() open) async {
          await open();
          await _settle(tester);
          _expectNoLayoutErrors(tester);
          await tester.pageBack();
          await _settle(tester, 4);
        }

        await visit(() => _tapVisible(tester, find.byKey(const Key('agent-quick-Analytics'))));
        await visit(() => _tapVisible(tester, find.byTooltip('Settings').first));
        await _openTab(tester, 4);
        await visit(() => _tapVisible(tester, find.byKey(const Key('agent-menu-Earnings & Payouts'))));
        await visit(() => _tapVisible(tester, find.byKey(const Key('agent-menu-Followers'))));
        await _openTab(tester, 2);
        await visit(() => tester.tap(find.byKey(const Key('agent-inquiry-q1'))));
        await _tearDown(tester);
      });
    }

    testWidgets('the pending-approval screen fits a 320pt phone with large text', (tester) async {
      final backend = _Backend({
        'subscriptions:getMyProfessionalStatus': (_) => _status(approved: false, subscribed: false, applications: [
              {'id': 'a1', 'targetRole': 'agent', 'status': 'rejected', 'reviewNotes': 'Your licence document was unreadable; please upload a clearer scan.'},
            ]),
      });
      await _pump(tester, user: _agentUser, backend: backend, width: 320, textScale: 1.35);
      expect(find.byKey(const Key('agent-pending-title')), findsOneWidget);
      _expectNoLayoutErrors(tester);
      await _tearDown(tester);
    });
  });

  group('layout at iPhone sizes (no overflow on any agent tab)', () {
    for (final width in const [320.0, 375.0, 430.0]) {
      for (final scale in const [1.0, 1.35]) {
        testWidgets('${width.toInt()}pt wide, text ×$scale', (tester) async {
          final routes = _agentRoutes(listings: [
            _listing('l1', 'Spacious Family House With Ocean View And Large Garden In Hill Station'),
            _listing('l2', '2 Bedroom Apartment', category: 'long_term_rent', published: false, price: 1200000),
            _listing('l3', 'Guest House Rooms', category: 'hourly_guesthouse', price: 950000),
          ]);
          const longName = UserEntity(
            id: 'agent_1',
            name: 'Mohamed Abdulai Bangura-Kamara',
            email: 'm@test.vektolux',
            phone: '+23276111222',
            role: UserRole.agent,
            isVerified: true,
            sessionToken: 'sess_agent_1_0123456789abcdef',
          );
          await _pump(tester, user: longName, backend: _Backend(routes), width: width, textScale: scale);
          _expectNoLayoutErrors(tester);
          for (final tab in [1, 2, 3, 4, 0]) {
            await _openTab(tester, tab);
            _expectNoLayoutErrors(tester);
          }
          await _tearDown(tester);
        });
      }
    }
  });
}
