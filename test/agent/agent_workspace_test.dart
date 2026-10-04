// The Real Estate Agent workspace, rendered for real (MainNavigationShell → AgentShell) against
// a fake Convex backend that answers with responses shaped like the real functions. Nothing
// leaves the test. Covers: role routing (agent / buyer / owner / pending / rejected /
// suspended / unavailable), dashboard values, subscription & posting states, listing status
// and filters, client conversations, viewing requests, notifications, the profile, the
// Add Listing flow with real photo + video uploads (progress, failure, retry), and layout at
// several iPhone sizes.

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
import 'package:image_picker/image_picker.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/core/theme/app_theme.dart';
import 'package:vektolux/core/widgets/app_text_scale.dart';
import 'package:vektolux/features/agent/data/agent_api.dart';
import 'package:vektolux/features/agent/domain/agent_models.dart';
import 'package:vektolux/features/agent/presentation/bloc/agent_workspace_cubit.dart';
import 'package:vektolux/features/agent/presentation/views/agent_add_listing_screen.dart';
import 'package:vektolux/features/agent/presentation/views/agent_shell.dart';
import 'package:vektolux/features/agent/presentation/widgets/listing_media_editor.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/listings/presentation/views/property_detail_screen.dart';
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
  bool carDealer = false,
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
      'canPostVehicle': carDealer,
      'isCarDealer': carDealer,
      'professionalTitle': carDealer ? 'Real Estate Agent & Car Dealer' : 'Real Estate Agent',
      'canManageHotel': false,
      'applications': applications,
    };

Map<String, dynamic> _listing(
  String id,
  String title, {
  String category = 'sale',
  bool published = true,
  num price = 2850000,
  String? lifecycle,
  String? reason,
  int inquiries = 0,
}) =>
    {
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
      'saveCount': 0,
      'inquiryCount': inquiries,
      'viewingRequestCount': 0,
      // the server derives this; the app never decides that a listing is live
      'lifecycleStatus': lifecycle ?? (published ? 'active' : 'unpublished'),
      if (reason != null) 'moderationReason': reason,
      'updatedAt': _now,
    };

/// One client conversation (messaging:getMyConversations / getThread), with server-side state.
class _Chat {
  String status = 'pending';
  int unread = 1;
  final List<Map<String, dynamic>> messages = [
    {'id': 'req1:inquiry', 'fromMe': false, 'body': 'Hello, is this property still available?', 'createdAt': _now - 60000, 'readAt': null},
  ];

  Map<String, dynamic> conversation() => {
        'id': 'req1',
        'myRole': 'seller',
        'status': status,
        'counterpart': {'id': 'client_9', 'name': 'Aminata Kamara', 'avatarUrl': null, 'isVerified': true},
        'listingId': 'l1',
        'listingType': 'property',
        'listing': {
          'id': 'l1', 'type': 'property', 'title': 'Modern 3 Bedroom House', 'category': 'sale', 'price': 2850000,
          'currency': 'SLE', 'imageUrl': null, 'location': 'Aberdeen, Western Area Urban',
        },
        'lastMessage': messages.last['body'],
        'lastMessageAt': messages.last['createdAt'],
        'lastMessageFromMe': messages.last['fromMe'],
        'unread': unread,
        'createdAt': _now - 60000,
      };

  Map<String, dynamic> thread() =>
      {'conversation': conversation(), 'canSend': status != 'declined', 'truncated': false, 'messages': messages};
}

Map<String, dynamic> _visit(
  String id,
  String status, {
  int daysAhead = 1,
  String client = 'Ibrahim Koroma',
  String? phone,
  String? reason,
}) =>
    {
      'id': id,
      'listingId': 'l1',
      'listingTitle': 'Modern 3 Bedroom House',
      'listingImage': null,
      'publicLocation': 'Aberdeen, Western Area Urban',
      'representing': false,
      'clientName': client,
      'clientAvatarUrl': null,
      'clientPhone': status == 'confirmed' ? phone : null,
      'status': status,
      'startTime': _now + daysAhead * 86400000,
      'endTime': _now + daysAhead * 86400000 + 3600000,
      'notes': 'Can we meet at the gate?',
      'declineReason': status == 'declined' ? reason : null,
      'cancelReason': status == 'cancelled' ? reason : null,
      'requestedAt': _now - 3600000,
    };

/// Site-visit requests with server-side state: a request is answered once (like convex/bookings.ts).
class _Visits {
  final List<Map<String, dynamic>> rows;
  _Visits([List<Map<String, dynamic>>? initial])
      : rows = initial ??
            [
              _visit('b1', 'requested', daysAhead: 1, client: 'Ibrahim Koroma'),
              _visit('b2', 'confirmed', daysAhead: 3, client: 'Fatmata Conteh', phone: '+23276123456'),
            ];

  Object? respond(Map<String, dynamic> a) {
    final i = rows.indexWhere((r) => r['id'] == a['bookingId']);
    if (i < 0) return const _ServerError('Booking not found');
    final row = rows[i];
    if (row['status'] != 'requested') {
      return _ServerError(row['status'] == 'confirmed' ? 'This request was already accepted.' : 'This request was already declined.');
    }
    if (a['decision'] == 'accept') {
      rows[i] = {...row, 'status': 'confirmed', 'clientPhone': '+23276000999'};
      return {'status': 'confirmed'};
    }
    final reason = (a['reason'] as String? ?? '').trim();
    if (reason.length < 3) return const _ServerError('Please give a reason for declining.');
    rows[i] = {...row, 'status': 'declined', 'declineReason': reason};
    return {'status': 'declined'};
  }

  Object? cancel(Map<String, dynamic> a) {
    final i = rows.indexWhere((r) => r['id'] == a['bookingId']);
    if (i < 0) return const _ServerError('Booking not found');
    if (rows[i]['status'] == 'requested') return const _ServerError('Accept or decline this viewing request instead.');
    rows[i] = {...rows[i], 'status': 'cancelled', 'cancelReason': a['reason']};
    return {'success': true, 'refunded': 0};
  }
}

List<Map<String, dynamic>> _notifications() => [
      {
        'id': 'n1', 'targetType': 'single_user', 'title': 'Application approved',
        'body': 'You are approved as a Real Estate Agent.', 'read': false, 'createdAt': _now - 5000,
      },
      {
        'id': 'n2', 'targetType': 'all_users', 'title': 'Planned maintenance',
        'body': 'The app is unavailable on Saturday night.', 'read': true, 'createdAt': _now - 9000000,
      },
      {
        'id': 'n3', 'targetType': 'single_user', 'title': 'New inquiry from Aminata Kamara',
        'body': 'About "Modern 3 Bedroom House": Hello, is this property still available?', 'read': false,
        'createdAt': _now - 60000, 'deepLinkScreen': 'messages', 'deepLinkId': 'req1',
      },
      {
        'id': 'n4', 'targetType': 'single_user', 'title': 'Booking confirmed',
        'body': 'Ibrahim Koroma booked a site visit.', 'read': true, 'createdAt': _now - 7000000,
      },
    ];

/// Everything an approved, subscribed agent with two listings sees.
Map<String, _Route> _agentRoutes({
  Map<String, dynamic>? status,
  List<Map<String, dynamic>>? listings,
  List<Map<String, dynamic>> authorizations = const [],
  Map<String, Map<String, dynamic>> publicProperties = const {},
  _Chat? chat,
  bool noConversations = false,
  _Visits? visits,
  int unread = 3,
}) {
  final c = chat ?? _Chat();
  final v = visits ?? _Visits();
  return {
    'subscriptions:getMyProfessionalStatus': (_) => status ?? _status(),
    'subscriptions:getUserActiveSubscription': (_) => (status ?? _status())['hasActiveSubscription'] == true
        ? {'planName': 'Agent Pro', 'tierCode': 'agent_pro', 'status': 'active', 'expiryDate': _future}
        : null,
    'realEstate:getMyPropertyListings': (_) =>
        listings ??
        [
          _listing('l1', 'Modern 3 Bedroom House', inquiries: 1), // the one conversation below is about l1
          _listing('l2', '2 Bedroom Apartment', category: 'long_term_rent', published: false, price: 1200000),
        ],
    'listingAgents:getMyAgentAuthorizations': (_) => authorizations,
    'realEstate:getPropertyById': (a) => publicProperties[a['listingId']],
    'messaging:getMyConversations': (_) => noConversations ? <Map<String, dynamic>>[] : [c.conversation()],
    'messaging:getThread': (a) => a['requestId'] == 'req1' ? c.thread() : const _ServerError('Conversation not found.'),
    'messaging:sendMessage': (a) {
      c.messages.add({'id': 'm${c.messages.length + 1}', 'fromMe': true, 'body': a['body'], 'createdAt': _now + 1000, 'readAt': null});
      return null;
    },
    'messaging:markThreadRead': (_) {
      c.unread = 0;
      return null;
    },
    'adminPortal:respondToContactRequest': (a) {
      c.status = a['action'] == 'accepted' ? 'accepted' : 'declined';
      return {'status': c.status.toUpperCase()};
    },
    'bookings:getMyViewingRequests': (_) => v.rows,
    'bookings:respondToViewingRequest': v.respond,
    'bookings:cancelBooking': v.cancel,
    'notifications:getUnreadNotificationCount': (_) => unread,
    'notifications:getUserNotifications': (_) => _notifications(),
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
    'users:updateBio': (_) => {'success': true},
    'listingAgents:respondToListingAgentInvitation': (_) => {'status': 'active'},
    'realEstate:updatePropertyListing': (_) => {'success': true, 'message': 'Listing updated successfully'},
    'files:generateUploadUrl': (_) => 'https://upload.example.invalid/api/storage/upload?token=t',
    'locations:getSierraLeoneLocations': (_) => [
          {'region': 'Western Area', 'district': 'Western Area Urban', 'towns': ['Aberdeen', 'Lumley']},
        ],
  };
}

// ─── Harness ─────────────────────────────────────────────────────────────

final List<String> _layoutErrors = [];

void _captureErrors(WidgetTester tester, {required double width, required double height, required double textScale}) {
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
}

Future<void> _pump(
  WidgetTester tester, {
  required UserEntity user,
  required _Backend backend,
  double width = 393,
  double height = 852,
  double textScale = 1.0,
  bool settle = true,
}) async {
  _captureErrors(tester, width: width, height: height, textScale: textScale);
  final bloc = _MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(), initialState: AuthState(status: AuthStatus.authenticated, user: user));
  await tester.pumpWidget(
    RepositoryProvider<ConvexClientWrapper>.value(
      value: backend.client(),
      child: BlocProvider<AuthBloc>.value(
        value: bloc,
        // The app's real theme and text-scale cap (as in main.dart), so theme-level layout rules are tested too.
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => AppTextScale(child: child ?? const SizedBox.shrink()),
          home: const MainNavigationShell(),
        ),
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

/// The page's own (vertical) scrollable — not a horizontal chip row above it.
Finder get _page => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

/// Back to the top of the page.
Future<void> _scrollTop(WidgetTester tester) async {
  await tester.drag(_page, const Offset(0, 4000));
  await _settle(tester, 4);
}

/// A lazy list builds only what is near the viewport, in whichever direction the page was last scrolled.
/// To get [finder] built: go back to the top first (it may be above), then scroll down until it appears.
Future<void> _build(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) return;
  await _scrollTop(tester);
  if (finder.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(finder, 250, scrollable: _page);
}

/// Scrolls [finder] into view (building it first if a lazy list has not built it yet), then taps it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await _build(tester, finder);
  await tester.ensureVisible(finder);
  await _settle(tester, 3);
  await tester.tap(finder);
}

/// Scrolls the current page until [finder] is built and visible.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await _build(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pump();
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
  // The theme names Poppins / Inter (not bundled: phones use their system font); measure with Roboto.
  for (final family in ['Roboto', 'Inter', 'Poppins']) {
    final loader = FontLoader(family);
    for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
      final file = File('${dir.path}/$f');
      if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    }
    await loader.load();
  }
}

// ─── Add Listing harness: the real screen, a fake device picker and a fake upload transport ──

/// A valid 1×1 transparent PNG (the picker hands the screen real image bytes).
final Uint8List _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, //
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

/// Distinct, still valid PNGs (a text chunk of [extra] bytes before IEND), so each upload has its own size.
Uint8List _pngVariant(int extra) {
  if (extra == 0) return _png;
  final type = [0x74, 0x45, 0x58, 0x74]; // tEXt
  final data = [0x63, 0x00, ...List.filled(extra, 0x78)]; // "c\0xxx…"
  final chunk = [..._u32(data.length), ...type, ...data, ..._u32(_crc32([...type, ...data]))];
  final iend = _png.length - 12;
  return Uint8List.fromList([..._png.sublist(0, iend), ...chunk, ..._png.sublist(iend)]);
}

// (On phones an XFile's name comes from its path.)
XFile _photo(String name, {int variant = 0}) =>
    XFile.fromData(_pngVariant(variant), name: name, path: name, mimeType: 'image/png');

XFile _video(String name, {int bytes = 200000, int? reportedLength}) =>
    XFile.fromData(Uint8List(bytes), name: name, path: name, mimeType: 'video/mp4', length: reportedLength);

class _FakePicker implements ListingMediaSource {
  final List<List<XFile>> photoBatches;
  final List<XFile?> videos;
  int _p = 0;
  int _v = 0;

  _FakePicker({this.photoBatches = const [], this.videos = const []});

  @override
  Future<List<XFile>> pickPhotos(BuildContext context, {required int max}) async =>
      _p < photoBatches.length ? photoBatches[_p++] : const [];

  @override
  Future<XFile?> pickVideo(BuildContext context) async => _v < videos.length ? videos[_v++] : null;
}

/// Stands in for Convex storage's upload endpoint: the storage id names the type and size of
/// the bytes it received, so a test can see exactly which uploads were attached.
class _Storage {
  final List<(String, int)> received = [];
  int failNext = 0;

  late final MockClient client = MockClient((req) async {
    final type = req.headers['content-type'] ?? req.headers['Content-Type'] ?? '';
    received.add((type, req.bodyBytes.length));
    if (failNext > 0) {
      failNext--;
      return http.Response('storage unavailable', 503);
    }
    final kind = type.startsWith('video/') ? 'vid' : 'img';
    return http.Response(jsonEncode({'storageId': '${kind}_${req.bodyBytes.length}'}), 200);
  });
}

Future<AgentWorkspaceCubit> _pumpAddListing(
  WidgetTester tester, {
  required _Backend backend,
  required ListingMediaSource picker,
  required _Storage storage,
  Map<String, dynamic>? status,
  double width = 393,
  double height = 932,
  double textScale = 1.0,
}) async {
  _captureErrors(tester, width: width, height: height, textScale: textScale);
  final client = backend.client();
  final cubit = AgentWorkspaceCubit(
    api: AgentApi(client: client, userId: _agentUser.id, sessionToken: _agentUser.sessionToken),
    status: ProfessionalStatus.fromMap(status ?? _status()),
  );
  addTearDown(cubit.close);
  // As in main.dart: the client is provided at the root (the location picker reads it).
  await tester.pumpWidget(RepositoryProvider<ConvexClientWrapper>.value(
    value: client,
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => AppTextScale(child: child ?? const SizedBox.shrink()),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open-add-listing'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AgentShellScope(
                  user: _agentUser,
                  convexClient: client,
                  openTab: (_) {},
                  openClientView: () {},
                  child: BlocProvider.value(
                    value: cubit,
                    child: AgentAddListingScreen(mediaSource: picker, uploadClient: storage.client),
                  ),
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const Key('open-add-listing')));
  await _settle(tester);
  return cubit;
}

String _stepTitle(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('agent-add-step-title'))).data ?? '';

Future<void> _next(WidgetTester tester, String expectedStep) async {
  await tester.tap(find.byKey(const Key('agent-add-next')));
  await _settle(tester, 4);
  final error = find.byKey(const Key('agent-add-error'));
  expect(_stepTitle(tester), expectedStep,
      reason: error.evaluate().isEmpty ? null : 'validation: ${tester.widget<Text>(error).data}');
  _expectNoLayoutErrors(tester);
}

Future<void> _fillBasics(WidgetTester tester, {String category = 'long_term_rent'}) async {
  await tester.tap(find.byKey(Key('agent-add-category-$category')));
  await tester.enterText(find.byKey(const Key('agent-add-title')), 'Family Home in Aberdeen');
  await tester.enterText(find.byKey(const Key('agent-add-description')), 'Three bedrooms, tiled floors, running water and a fenced compound.');
}

Future<void> _fillPriceAndLocation(WidgetTester tester, {String price = '1500000', String address = '12 Private Street'}) async {
  await tester.enterText(find.byKey(const Key('agent-add-price')), price);
  await _settle(tester, 3); // let the caret scroll animation finish (scrolling content ignores taps)
  expect(find.text('District (required)'), findsOneWidget);
  // Tap the fields themselves (with large text the floating label sits outside the field's box).
  final dropdowns = find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>);
  await _tapVisible(tester, dropdowns.first);
  await _settle(tester, 4);
  await tester.tap(find.text('Western Area Urban — Western Area').last);
  await _settle(tester, 4);
  await _tapVisible(tester, dropdowns.at(1));
  await _settle(tester, 4);
  await tester.tap(find.text('Aberdeen').last);
  await _settle(tester, 4);
  await tester.enterText(find.byKey(const Key('agent-add-address')), address);
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
      expect(find.textContaining('Car'), findsNothing, reason: 'no car dealing in the agent workspace');
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

    testWidgets('a vehicle dealer keeps the standard app (car dealing stays separate)', (tester) async {
      final backend = _Backend({'subscriptions:getMyProfessionalStatus': (_) => _status(role: 'vehicle_dealer')});
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
      expect(backend.called('messaging:getMyConversations'), isFalse);

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
      expect(find.descendant(of: find.byKey(const Key('agent-kpi-active')), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-kpi-review')), matching: find.text('0')), findsOneWidget,
          reason: 'nothing waits for an administrator');
      expect(find.descendant(of: find.byKey(const Key('agent-kpi-messages')), matching: find.text('1')), findsOneWidget,
          reason: 'unread client messages from the server counter');
      expect(find.descendant(of: find.byKey(const Key('agent-kpi-followers')), matching: find.text('7')), findsOneWidget);
      expect(find.text('SLE 1,250.50'), findsOneWidget);
      expect(find.text('2 payouts'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-home-notifications')), matching: find.text('3')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-viewing-pending')), matching: find.text('1 Pending')), findsOneWidget,
          reason: 'the real count of requests waiting for an answer');
      expect(find.byKey(const Key('agent-next-viewing')), findsOneWidget, reason: 'the soonest CONFIRMED visit (not the pending request)');
      expect(find.descendant(of: find.byKey(const Key('agent-next-viewing')), matching: find.textContaining('Fatmata Conteh')), findsOneWidget);
      await _reveal(tester, find.byKey(const Key('agent-recent-inquiries')));
      expect(find.descendant(of: find.byKey(const Key('agent-recent-inquiries')), matching: find.text('Aminata Kamara')), findsOneWidget);
      expect(find.byKey(const Key('agent-auto-add')), findsNothing, reason: 'no car tools without a separately approved Car Dealer');
      expect(find.text('Modern 3 Bedroom House'), findsWidgets);
      await _reveal(tester, find.byKey(const Key('agent-quick-Add Property')));
      for (final action in ['Add Property', 'My Listings', 'Messages', 'Viewings', 'Notifications']) {
        expect(find.byKey(Key('agent-quick-$action')), findsOneWidget, reason: action);
      }
      expect(find.textContaining('Post Car'), findsNothing);
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
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Add Property')));
      await _settle(tester);
      expect(find.text('Posting is not available'), findsOneWidget);
      expect(find.textContaining('subscription is not active'), findsWidgets);
      expect(find.byKey(const Key('agent-add-step-title')), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('with posting allowed, Add Property opens the 5-step flow and validates each step', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes()));
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Add Property')));
      await _settle(tester);
      expect(find.text('Type & title'), findsOneWidget);
      expect(find.text('1/5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agent-add-next')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('agent-add-error')), findsOneWidget);
      expect(find.text('1/5'), findsOneWidget);
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
      expect(find.text('2 Bedroom Apartment'), findsNothing);
      backend.holds['realEstate:getMyPropertyListings']!.complete();
      await _settle(tester);
      expect(find.text('2 Bedroom Apartment'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a backend error is shown with Retry — no placeholder listings', (tester) async {
      var down = true;
      final routes = _agentRoutes();
      final real = routes['realEstate:getMyPropertyListings']!;
      routes['realEstate:getMyPropertyListings'] = (a) => down ? const _ServerError('Listings are unavailable') : real(a);
      await _pump(tester, user: _agentUser, backend: _Backend(routes));
      expect(find.text('Listings are unavailable'), findsOneWidget);
      expect(find.text('2 Bedroom Apartment'), findsNothing);
      down = false;
      await tester.tap(find.text('Retry').first);
      await _settle(tester);
      expect(find.text('2 Bedroom Apartment'), findsOneWidget);
      await _tearDown(tester);
    });
  });

  group('My Listings', () {
    testWidgets('filters, counts, real status badges and real inquiry counts', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes()));
      await _openTab(tester, 1);
      expect(find.text('My Listings'), findsOneWidget);
      expect(find.text('All (2)'), findsOneWidget);
      expect(find.text('For Sale (1)'), findsOneWidget);
      expect(find.text('For Rent (1)'), findsOneWidget);
      expect(find.text('Unpublished (1)'), findsOneWidget);
      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Archived (0)'), findsNothing, reason: 'only filters that apply to some listings');
      expect(find.text('Rejected (0)'), findsNothing);
      expect(find.byKey(const Key('agent-listing-l1')), findsOneWidget);
      // statistics come from the server's counters on each listing (views, saves, inquiries, viewing requests)
      final l1Stats = find.byKey(const Key('agent-listing-stats-l1'));
      expect(l1Stats, findsOneWidget);
      expect(find.descendant(of: l1Stats, matching: find.text('1')), findsOneWidget, reason: 'one real inquiry about l1');
      expect(find.descendant(of: l1Stats, matching: find.text('0')), findsNWidgets(3));
      expect(find.descendant(of: find.byKey(const Key('agent-listing-stats-l2')), matching: find.text('1')), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('agent-listing-l2')), matching: find.text('Unpublished')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-listing-l2')), matching: find.text('SLE 1,200,000 / year')), findsOneWidget);

      await _tapVisible(tester, find.byKey(const Key('agent-filter-unpublished')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('agent-listing-l1')), findsNothing);
      expect(find.byKey(const Key('agent-listing-l2')), findsOneWidget);

      await _tapVisible(tester, find.byKey(const Key('agent-filter-sale')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('agent-listing-l1')), findsOneWidget);
      expect(find.byKey(const Key('agent-listing-l2')), findsNothing);
      expect(find.textContaining('Hidden Close'), findsNothing);
      expect(find.textContaining('555999'), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('opening a listing shows the buyer-facing detail page with public data only', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes()));
      await _openTab(tester, 1);
      await tester.tap(find.byKey(const Key('agent-listing-l1')));
      await _settle(tester);
      expect(find.byType(PropertyDetailScreen), findsOneWidget);
      expect(find.textContaining('Hidden Close'), findsNothing);
      expect(find.textContaining('555999'), findsNothing);
      expect(find.textContaining('Starlink'), findsNothing, reason: 'no invented amenities');
      _expectNoLayoutErrors(tester);
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

    testWidgets('an authorised listing the server no longer shows is left out — never an empty "Untitled listing"', (tester) async {
      final backend = _Backend(_agentRoutes(
        authorizations: [
          {'id': 'auth1', 'listingType': 'property', 'listingId': 'p9', 'status': 'active', 'invitedAt': _now - 10000, 'acceptedAt': _now - 9000},
          {'id': 'auth3', 'listingType': 'property', 'listingId': 'gone', 'status': 'active', 'invitedAt': _now - 10000, 'acceptedAt': _now - 9000},
        ],
        publicProperties: {
          'p9': {'_id': 'p9', 'title': 'Owner Villa', 'category': 'sale', 'price': 5500000, 'currency': 'SLE', 'publicLocation': 'Inside Lumley, Sierra Leone', 'imageUrls': [], 'isPublished': true, 'availabilityStatus': 'available'},
        },
      ));
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 1);
      expect(find.text('Owner Villa'), findsOneWidget);
      expect(find.text('Untitled listing'), findsNothing, reason: 'getPropertyById returned null for it');
      expect(find.text('All (3)'), findsOneWidget, reason: 'two own listings and the one represented listing that exists');
      await _tearDown(tester);
    });
  });

  group('messages (real conversations)', () {
    testWidgets('inbox shows the client, the property they are interested in, the last message and unread', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes()));
      await _openTab(tester, 2);
      expect(find.text('Aminata Kamara'), findsOneWidget);
      expect(find.text('Interested in: Modern 3 Bedroom House'), findsOneWidget);
      expect(find.text('Hello, is this property still available?'), findsOneWidget);
      expect(find.text('1 unread'), findsOneWidget);
      // search narrows by name / property / text
      await tester.enterText(find.byKey(const Key('agent-messages-search')), 'villa');
      await _settle(tester, 2);
      expect(find.text('No matches'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('agent-messages-search')), 'aminata');
      await _settle(tester, 2);
      expect(find.byKey(const Key('conversation-req1')), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('opening a conversation marks it read; a reply goes to the server and is re-read', (tester) async {
      final chat = _Chat();
      final backend = _Backend(_agentRoutes(chat: chat));
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 2);
      await tester.tap(find.byKey(const Key('conversation-req1')));
      await _settle(tester);
      expect(find.byKey(const Key('chat-msg-req1:inquiry')), findsOneWidget);
      expect(find.byKey(const Key('chat-listing')), findsOneWidget, reason: 'the property the client is asking about');
      expect(backend.lastArgs('messaging:markThreadRead')['requestId'], 'req1');
      expect(backend.lastArgs('messaging:markThreadRead')['sessionToken'], _agentUser.sessionToken);

      await tester.enterText(find.byKey(const Key('chat-input')), 'Yes, it is available. When would you like to view it?');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat-send')));
      await _settle(tester);
      final sent = backend.lastArgs('messaging:sendMessage');
      expect(sent['requestId'], 'req1');
      expect(sent['body'], 'Yes, it is available. When would you like to view it?');
      expect(find.byKey(const Key('chat-msg-m2')), findsOneWidget, reason: 'shown once the server has it');
      _expectNoLayoutErrors(tester);

      // closing declines the inquiry on the server; the composer goes away
      await tester.tap(find.byKey(const Key('chat-menu')));
      await _settle(tester, 3);
      await tester.tap(find.text('Close conversation'));
      await _settle(tester, 3);
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await _settle(tester);
      expect(backend.lastArgs('adminPortal:respondToContactRequest')['action'], 'declined');
      expect(find.byKey(const Key('chat-closed')), findsOneWidget);
      expect(find.byKey(const Key('chat-input')), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('no conversations → empty state, never sample conversations', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes(noConversations: true)));
      await _openTab(tester, 2);
      expect(find.text('No messages yet'), findsOneWidget);
      expect(find.text('Aminata Kamara'), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('a server without messaging yet says so instead of showing an empty inbox', (tester) async {
      final routes = _agentRoutes();
      routes['messaging:getMyConversations'] =
          (_) => const _ServerError("Could not find public function for 'messaging:getMyConversations'.");
      await _pump(tester, user: _agentUser, backend: _Backend(routes));
      await _openTab(tester, 2);
      expect(find.textContaining('after the next Vektolux server update'), findsOneWidget);
      await _tearDown(tester);
    });
  });

  group('viewing requests (accept / decline)', () {
    testWidgets('requests open on Pending with Accept / Decline; confirmed, declined and cancelled have their own tabs', (tester) async {
      final backend = _Backend(_agentRoutes(visits: _Visits([
        _visit('b1', 'requested', daysAhead: 1, client: 'Ibrahim Koroma'),
        _visit('b2', 'confirmed', daysAhead: 3, client: 'Fatmata Conteh', phone: '+23276123456'),
        _visit('b3', 'declined', daysAhead: 4, client: 'Sorie Bangura', reason: 'House being repainted'),
        _visit('b4', 'cancelled', daysAhead: 5, client: 'Kadiatu Jalloh', reason: 'Owner travelling'),
      ])));
      await _pump(tester, user: _agentUser, backend: backend);
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Viewings')));
      await _settle(tester);
      for (final label in ['Pending (1)', 'Confirmed (1)', 'Declined (1)', 'Cancelled (1)']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // opens on Pending: the request has Accept and Decline — and is NOT shown as confirmed
      expect(find.byKey(const Key('viewing-b1')), findsOneWidget);
      expect(find.byKey(const Key('viewing-accept-b1')), findsOneWidget);
      expect(find.byKey(const Key('viewing-decline-b1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('viewing-status-b1')), matching: find.text('Pending')), findsOneWidget);
      expect(find.text('Can we meet at the gate?'), findsOneWidget, reason: 'the client\'s note');
      expect(find.byKey(const Key('viewing-b2')), findsNothing);

      await _tapVisible(tester, find.byKey(const Key('viewings-tab-confirmed')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('viewing-b2')), findsOneWidget);
      expect(find.byKey(const Key('viewing-accept-b2')), findsNothing);
      expect(find.byKey(const Key('viewing-cancel-b2')), findsOneWidget, reason: 'a confirmed visit can be cancelled, not accepted again');
      expect(find.byKey(const Key('viewing-call-b2')), findsOneWidget, reason: 'the server shared the phone after confirmation');

      await _tapVisible(tester, find.byKey(const Key('viewings-tab-declined')));
      await _settle(tester, 3);
      expect(find.text('Reason: House being repainted'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('viewings-tab-cancelled')));
      await _settle(tester, 3);
      expect(find.text('Reason: Owner travelling'), findsOneWidget);
      _expectNoLayoutErrors(tester);
      await _tearDown(tester);
    });

    testWidgets('Accept goes to the server, the request becomes Confirmed and the pending count drops', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _agentUser, backend: backend);
      expect(find.text('1 Pending'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Viewings')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('viewing-accept-b1')));
      await _settle(tester);
      final args = backend.lastArgs('bookings:respondToViewingRequest');
      expect(args['bookingId'], 'b1');
      expect(args['decision'], 'accept');
      expect(args['sessionToken'], _agentUser.sessionToken);
      expect(find.byKey(const Key('viewing-b1')), findsNothing, reason: 'it left the Pending tab (the screen stays on Pending)');
      expect(find.text('No pending requests'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('viewings-tab-confirmed')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('viewing-b1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('viewing-status-b1')), matching: find.text('Confirmed')), findsOneWidget);
      await tester.pageBack();
      await _settle(tester, 4);
      await _scrollTop(tester);
      expect(find.text('0 Pending'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('Decline needs a reason; it is sent to the server and shown in the Declined tab', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _agentUser, backend: backend);
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Viewings')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('viewing-decline-b1')));
      await _settle(tester, 4);
      var confirm = tester.widget<ElevatedButton>(find.byKey(const Key('agent-reason-confirm')));
      expect(confirm.onPressed, isNull, reason: 'no reason, no decline');
      await tester.enterText(find.byKey(const Key('agent-reason-input')), 'Booked out that day');
      await tester.pump();
      confirm = tester.widget<ElevatedButton>(find.byKey(const Key('agent-reason-confirm')));
      expect(confirm.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('agent-reason-confirm')));
      await _settle(tester);
      final args = backend.lastArgs('bookings:respondToViewingRequest');
      expect(args['decision'], 'decline');
      expect(args['reason'], 'Booked out that day');
      await _tapVisible(tester, find.byKey(const Key('viewings-tab-declined')));
      await _settle(tester, 3);
      expect(find.text('Reason: Booked out that day'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a request someone else already answered shows the server\'s message and stays unchanged', (tester) async {
      final visits = _Visits();
      final backend = _Backend(_agentRoutes(visits: visits));
      await _pump(tester, user: _agentUser, backend: backend);
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Viewings')));
      await _settle(tester);
      // the owner accepted it from their own phone a moment ago
      visits.rows[0] = {...visits.rows[0], 'status': 'confirmed'};
      await tester.tap(find.byKey(const Key('viewing-accept-b1')));
      await _settle(tester);
      expect(find.text('This request was already accepted.'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a confirmed visit is cancelled with a reason through the existing booking rules', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _agentUser, backend: backend);
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Viewings')));
      await _settle(tester);
      await _tapVisible(tester, find.byKey(const Key('viewings-tab-confirmed')));
      await _settle(tester, 3);
      await tester.tap(find.byKey(const Key('viewing-cancel-b2')));
      await _settle(tester, 4);
      await tester.enterText(find.byKey(const Key('agent-reason-input')), 'Owner is travelling');
      await tester.pump();
      await tester.tap(find.byKey(const Key('agent-reason-confirm')));
      await _settle(tester);
      final args = backend.lastArgs('bookings:cancelBooking');
      expect(args['bookingId'], 'b2');
      expect(args['reason'], 'Owner is travelling');
      expect(args['userId'], 'agent_1');
      await _tearDown(tester);
    });

    testWidgets('an empty list is an honest empty state; an error offers Retry', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes(visits: _Visits([]))));
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Viewings')));
      await _settle(tester);
      expect(find.text('No pending requests'), findsOneWidget);
      expect(find.text('0 Pending'), findsNothing);
      await tester.pageBack();
      await _settle(tester, 4);
      await _scrollTop(tester);
      expect(find.text('0 Pending'), findsOneWidget);
      await _tearDown(tester);

      var down = true;
      final routes = _agentRoutes();
      final real = routes['bookings:getMyViewingRequests']!;
      routes['bookings:getMyViewingRequests'] = (a) => down ? const _ServerError('Viewings are unavailable') : real(a);
      await _pump(tester, user: _agentUser, backend: _Backend(routes));
      await _tapVisible(tester, find.byKey(const Key('agent-quick-Viewings')));
      await _settle(tester);
      expect(find.text('Viewings are unavailable'), findsWidgets);
      down = false;
      await tester.tap(find.text('Retry').first);
      await _settle(tester);
      expect(find.byKey(const Key('viewing-b1')), findsOneWidget);
      await _tearDown(tester);
    });
  });

  group('notifications', () {
    testWidgets('four tabs from real rows: Messages = conversations, Admin = broadcasts, System = the rest', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 3);
      for (final t in ['all', 'messages', 'system', 'admin']) {
        expect(find.byKey(Key('agent-notif-tab-$t')), findsOneWidget, reason: t);
      }
      expect(find.byKey(const Key('agent-notif-tab-viewings')), findsNothing);
      expect(find.text('Application approved'), findsOneWidget);
      expect(find.text('Planned maintenance'), findsOneWidget);
      expect(find.text('New inquiry from Aminata Kamara'), findsOneWidget);

      await _tapVisible(tester, find.byKey(const Key('agent-notif-tab-admin')));
      await _settle(tester, 3);
      expect(find.text('Planned maintenance'), findsOneWidget);
      expect(find.text('Application approved'), findsNothing);

      await _tapVisible(tester, find.byKey(const Key('agent-notif-tab-system')));
      await _settle(tester, 3);
      expect(find.text('Application approved'), findsOneWidget);
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(find.text('Planned maintenance'), findsNothing);
      expect(find.text('New inquiry from Aminata Kamara'), findsNothing);

      await _tapVisible(tester, find.byKey(const Key('agent-notif-tab-messages')));
      await _settle(tester, 3);
      expect(find.text('Application approved'), findsNothing);
      await tester.tap(find.text('New inquiry from Aminata Kamara'));
      await _settle(tester);
      expect(backend.lastArgs('notifications:markAsRead')['notificationId'], 'n3');
      expect(find.byKey(const Key('chat-input')), findsOneWidget, reason: 'the deep link opened conversation req1');
      await _tearDown(tester);
    });

    testWidgets('a viewing notification opens the viewing requests; a moderation notice opens My Listings', (tester) async {
      final routes = _agentRoutes();
      routes['notifications:getUserNotifications'] = (_) => [
            {
              'id': 'v1', 'targetType': 'single_user', 'title': 'New viewing request', 'body': 'Ibrahim Koroma wants to view "Villa".',
              'read': false, 'createdAt': _now - 1000, 'deepLinkScreen': 'viewings', 'deepLinkId': 'b1',
            },
            {
              'id': 'm1', 'targetType': 'single_user', 'title': 'Listing not approved', 'body': '"Villa" was not approved: photos missing.',
              'read': false, 'createdAt': _now - 2000, 'deepLinkScreen': 'listings', 'deepLinkId': 'l2',
            },
          ];
      final backend = _Backend(routes);
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 3);
      await tester.tap(find.byKey(const Key('agent-notification-v1')));
      await _settle(tester);
      expect(find.text('Viewing Requests'), findsWidgets);
      expect(find.byKey(const Key('viewing-accept-b1')), findsOneWidget);
      await tester.pageBack();
      await _settle(tester, 4);
      await tester.tap(find.byKey(const Key('agent-notification-m1')));
      await _settle(tester);
      expect(find.byKey(const Key('agent-listing-l1')), findsOneWidget, reason: 'the Listings tab');
      await _tearDown(tester);
    });
  });

  group('listing lifecycle (administrator review) and Auto tools', () {
    List<Map<String, dynamic>> lifecycleListings() => [
          _listing('a1', 'Active Villa'),
          _listing('p1', 'Waiting Villa', lifecycle: 'pending_review'),
          _listing('r1', 'Rejected Villa', lifecycle: 'rejected', reason: 'Photos do not show the property.'),
          _listing('x1', 'Removed Villa', lifecycle: 'removed', reason: 'Reported as a duplicate listing.'),
          _listing('d1', 'Draft Villa', published: false, lifecycle: 'draft'),
          _listing('z1', 'Archived Villa', lifecycle: 'archived'),
        ];

    testWidgets('every listing shows its real status; rejected and removed ones show the administrator\'s reason', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes(listings: lifecycleListings())));
      await _openTab(tester, 1);
      for (final (key, label) in const [
        ('agent-status-active', 'Active'),
        ('agent-status-pendingReview', 'Pending review'),
        ('agent-status-rejected', 'Rejected'),
        ('agent-status-removed', 'Removed'),
        ('agent-status-draft', 'Draft'),
        ('agent-status-archived', 'Archived'),
      ]) {
        await _reveal(tester, find.byKey(Key(key)));
        expect(find.descendant(of: find.byKey(Key(key)), matching: find.text(label)), findsOneWidget, reason: label);
      }
      // the administrator's reason is shown on the rejected and on the removed listing (a lazy list: reveal each)
      await _reveal(tester, find.byKey(const Key('agent-listing-reason-r1')));
      expect(find.text('Photos do not show the property.'), findsOneWidget);
      await _reveal(tester, find.byKey(const Key('agent-listing-reason-x1')));
      expect(find.text('Reported as a duplicate listing.'), findsOneWidget);
      // an active listing carries no reason; its real statistics come from the server record (all zero here)
      await _scrollTop(tester);
      expect(find.byKey(const Key('agent-listing-a1')), findsOneWidget);
      expect(find.byKey(const Key('agent-listing-reason-a1')), findsNothing);
      expect(find.byKey(const Key('agent-listing-stats-a1')), findsOneWidget);
      _expectNoLayoutErrors(tester);
      await _tearDown(tester);
    });

    testWidgets('filters appear only for statuses that exist, with their counts', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes(listings: lifecycleListings())));
      await _openTab(tester, 1);
      for (final f in ['all', 'active', 'pendingReview', 'rejected', 'unpublished', 'archived', 'removed']) {
        expect(find.byKey(Key('agent-filter-$f')), findsOneWidget, reason: f);
      }
      expect(find.byKey(const Key('agent-filter-offMarket')), findsNothing, reason: 'nothing is off-market');
      expect(find.byKey(const Key('agent-filter-sale')), findsNothing, reason: 'every listing is for sale: no redundant chip');
      expect(find.byKey(const Key('agent-filter-rent')), findsNothing);
      await _tapVisible(tester, find.byKey(const Key('agent-filter-pendingReview')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('agent-listing-p1')), findsOneWidget);
      expect(find.byKey(const Key('agent-listing-a1')), findsNothing);
      await _tapVisible(tester, find.byKey(const Key('agent-filter-rejected')));
      await _settle(tester, 3);
      expect(find.byKey(const Key('agent-listing-r1')), findsOneWidget);
      expect(find.byKey(const Key('agent-listing-p1')), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('the actions follow the status: draft → submit for review; pending → withdraw; rejected → resubmit; removed → no delete', (tester) async {
      final backend = _Backend(_agentRoutes(listings: lifecycleListings()));
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 1);

      Future<void> openMenu(String id) async {
        await _reveal(tester, find.byKey(Key('agent-listing-menu-$id')));
        await tester.tap(find.byKey(Key('agent-listing-menu-$id')));
        await _settle(tester, 3);
      }

      Future<void> closeMenu() async {
        await tester.tapAt(const Offset(5, 5));
        await _settle(tester, 3);
      }

      await openMenu('d1');
      expect(find.text('Submit for review'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await closeMenu();

      await openMenu('p1');
      expect(find.text('Withdraw from review'), findsOneWidget);
      expect(find.text('Submit for review'), findsNothing);
      await closeMenu();

      await openMenu('r1');
      expect(find.text('Resubmit for review'), findsOneWidget);
      await closeMenu();

      await openMenu('x1');
      expect(find.text('Delete'), findsNothing, reason: 'a removed listing stays on record');
      expect(find.text('Edit details'), findsNothing);
      expect(find.text('Submit for review'), findsNothing);
      await closeMenu();

      await openMenu('z1');
      expect(find.text('Restore as draft'), findsOneWidget);
      await tester.tap(find.text('Restore as draft'));
      await _settle(tester);
      expect(backend.lastArgs('realEstate:restorePropertyListing')['listingId'], 'z1');
      await _tearDown(tester);
    });

    testWidgets('submitting a draft asks the server to put it in review (the app never publishes)', (tester) async {
      final backend = _Backend(_agentRoutes(listings: lifecycleListings()));
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 1);
      await _reveal(tester, find.byKey(const Key('agent-listing-menu-d1')));
      await tester.tap(find.byKey(const Key('agent-listing-menu-d1')));
      await _settle(tester, 3);
      await tester.tap(find.text('Submit for review'));
      await _settle(tester, 3);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await _settle(tester);
      final args = backend.lastArgs('realEstate:updatePropertyListing');
      expect(args['listingId'], 'd1');
      expect(args['isPublished'], true);
      expect(args['sessionToken'], _agentUser.sessionToken);
      expect(args.keys.where((k) => k.toLowerCase().contains('moderation') || k.toLowerCase().contains('approv')), isEmpty,
          reason: 'the client cannot choose a moderation status');
      await _tearDown(tester);
    });

    testWidgets('Auto tools exist only for a separately approved Car Dealer (same account, same workspace)', (tester) async {
      // a plain agent: nothing about cars, anywhere
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes()));
      expect(find.text('Real Estate Agent'), findsOneWidget);
      expect(find.byKey(const Key('agent-auto-add')), findsNothing);
      await _openTab(tester, 4);
      await _reveal(tester, find.byKey(const Key('agent-logout')));
      expect(find.byKey(const Key('agent-auto-menu')), findsNothing);
      expect(find.textContaining('Vehicle'), findsNothing);
      await _tearDown(tester);

      // the same kind of account, approved as a Car Dealer by the server
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes(status: _status(carDealer: true))));
      expect(_showsAgentNav(), isTrue, reason: 'the real estate workspace is kept');
      expect(find.text('Real Estate Agent & Car Dealer'), findsOneWidget);
      await _reveal(tester, find.byKey(const Key('agent-auto-add')));
      expect(find.byKey(const Key('agent-auto-add')), findsOneWidget);
      expect(find.byKey(const Key('agent-auto-list')), findsOneWidget);
      expect(find.byKey(const Key('agent-quick-Add Property')), findsOneWidget, reason: 'property tools unchanged');
      await _openTab(tester, 4);
      await _reveal(tester, find.byKey(const Key('agent-auto-menu')));
      expect(find.byKey(const Key('agent-auto-menu')), findsOneWidget);
      await _tearDown(tester);
    });
  });

  group('profile and navigation', () {
    testWidgets('the five destinations, the dashboard shortcuts and the profile links', (tester) async {
      await _pump(tester, user: _agentUser, backend: _Backend(_agentRoutes()));
      await _openTab(tester, 1);
      expect(find.text('My Listings'), findsOneWidget);
      await _openTab(tester, 2);
      expect(find.byKey(const Key('agent-messages-search')), findsOneWidget);
      await _openTab(tester, 3);
      expect(find.text('Notifications'), findsWidgets);
      await _openTab(tester, 4);
      for (final link in ['My Listings', 'Messages', 'Viewing Requests', 'Followers', 'Following', 'Earnings & Payouts', 'Public Profile', 'Support', 'Settings']) {
        expect(find.byKey(Key('agent-menu-$link')), findsOneWidget, reason: link);
      }
      expect(find.descendant(of: find.byKey(const Key('agent-stat-Followers')), matching: find.text('7')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-stat-Following')), matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-stat-Active Deals')), matching: find.text('1')), findsOneWidget);
      expect(find.byKey(const Key('agent-subscription-card')), findsOneWidget);
      await _reveal(tester, find.byKey(const Key('agent-logout')));
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

    testWidgets('the bio is edited through the existing account function and re-read', (tester) async {
      final backend = _Backend(_agentRoutes());
      await _pump(tester, user: _agentUser, backend: backend);
      await _openTab(tester, 4);
      expect(find.text('Add a short professional bio'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agent-bio')));
      await _settle(tester, 4);
      await tester.enterText(find.byKey(const Key('agent-bio-input')), 'Residential sales and rentals in the Western Area.');
      await tester.tap(find.byKey(const Key('agent-bio-save')));
      await _settle(tester);
      final args = backend.lastArgs('users:updateBio');
      expect(args['bio'], 'Residential sales and rentals in the Western Area.');
      expect(args['userId'], 'agent_1');
      expect(args['sessionToken'], _agentUser.sessionToken);
      expect(backend.calls.where((c) => c.$1 == 'users:getUserProfile').length, greaterThanOrEqualTo(2), reason: 're-read after saving');
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

  group('Add Listing with photos and video', () {
    testWidgets('photos + video upload with real progress; only confirmed uploads are submitted, cover first', (tester) async {
      final listings = [_listing('l1', 'Modern 3 Bedroom House')];
      Map<String, dynamic>? created;
      final routes = _agentRoutes(listings: listings);
      routes['realEstate:createPropertyListing'] = (a) {
        created = a;
        // like the server: an agent's submission waits for an administrator; a draft stays private
        listings.add(_listing('new1', a['title'] as String,
            category: a['category'] as String,
            published: a['isPublished'] == true,
            price: a['price'] as num,
            lifecycle: a['isPublished'] == true ? 'pending_review' : 'draft'));
        return 'new1';
      };
      final backend = _Backend(routes);
      final storage = _Storage();
      final picker = _FakePicker(
        photoBatches: [
          [_photo('front.png'), _photo('kitchen.png', variant: 10)],
        ],
        videos: [_video('tour.mp4')],
      );
      await _pumpAddListing(tester, backend: backend, picker: picker, storage: storage);

      // 1 Type & title
      await _fillBasics(tester);
      await _next(tester, 'Photos & video');

      // 2 Media is required: no photo → stays on the step
      await tester.tap(find.byKey(const Key('agent-add-next')));
      await _settle(tester, 3);
      expect(find.text('Add at least one photo.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('media-add-photos')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('media-add-video')));
      await _settle(tester);
      expect(storage.received.map((r) => r.$1).toSet(), {'image/png', 'video/mp4'}, reason: 'uploaded with their real types');
      expect(find.byKey(const Key('media-photo-1')), findsOneWidget);
      expect(find.byKey(const Key('media-photo-2')), findsOneWidget);
      expect(find.byKey(const Key('media-cover-badge')), findsOneWidget);
      expect(find.textContaining('Uploaded ·'), findsOneWidget, reason: 'the video row shows the confirmed upload');
      expect(backend.calls.where((c) => c.$1 == 'files:generateUploadUrl').length, 3);
      _expectNoLayoutErrors(tester);

      // make the kitchen photo the cover (tap → preview → Make cover)
      await tester.tap(find.byKey(const Key('media-photo-2')));
      await _settle(tester, 3);
      await tester.tap(find.text('Make cover'));
      await _settle(tester, 3);

      await _next(tester, 'Details');
      await tester.enterText(find.byKey(const Key('agent-add-beds')), '3');
      await tester.tap(find.byKey(const Key('agent-add-amenity-Parking')));
      await _settle(tester, 2);
      await _next(tester, 'Price & location');
      expect(find.byKey(const Key('agent-add-public-location')), findsOneWidget);
      expect(find.byKey(const Key('agent-add-private-details')), findsOneWidget);
      expect(find.text('Buyers see this'), findsOneWidget);
      expect(find.text('Never published'), findsOneWidget);
      await _fillPriceAndLocation(tester);
      await _next(tester, 'Review');

      expect(find.descendant(of: find.byKey(const Key('agent-add-preview')), matching: find.text('SLE 1,500,000 / year')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-add-preview')), matching: find.text('Aberdeen, Western Area Urban')),
          findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('agent-add-preview')), matching: find.textContaining('12 Private Street')),
          findsNothing, reason: 'the private address is never part of the public preview');
      await _tapVisible(tester, find.byKey(const Key('agent-add-submit')));
      await _settle(tester);

      expect(created, isNotNull);
      final photoA = 'img_${_png.length}';
      final photoB = 'img_${_pngVariant(10).length}';
      expect(created!['imageStorageIds'], [photoB, photoA], reason: 'only Convex storage ids, cover first');
      expect(created!['videoStorageIds'], ['vid_200000']);
      expect(created!['category'], 'long_term_rent');
      expect(created!['price'], 1500000);
      expect(created!['bedrooms'], 3);
      expect(created!['amenities'], ['Parking']);
      expect(created!['address'], '12 Private Street', reason: 'the private verification address, stored privately');
      expect(created!['city'], 'Aberdeen', reason: 'the public location is the chosen town, never the address');
      expect(created!['district'], 'Western Area Urban');
      expect(created!['privateContactPhone'], '+23276111222');
      expect(created!['isPublished'], true);
      expect(created!['sessionToken'], _agentUser.sessionToken);
      expect(created!.keys.where((k) => k.toLowerCase().contains('verif') || k.toLowerCase().contains('approv')), isEmpty,
          reason: 'the app never asks for its own listing to be verified or approved');
      expect(find.byKey(const Key('agent-add-result-title')), findsOneWidget);
      expect(find.text('Submitted for review'), findsOneWidget, reason: 'the status read back from the server: waiting for an administrator');
      expect(find.text('Your listing is live'), findsNothing, reason: 'an agent\'s listing is never live before it is approved');
      expect(find.byKey(const Key('agent-status-pendingReview')), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('Save as draft keeps the listing private: isPublished false, result "Draft saved"', (tester) async {
      Map<String, dynamic>? created;
      final listings = <Map<String, dynamic>>[];
      final routes = _agentRoutes(listings: listings);
      routes['realEstate:createPropertyListing'] = (a) {
        created = a;
        listings.add(_listing('new1', a['title'] as String,
            published: a['isPublished'] == true, lifecycle: a['isPublished'] == true ? 'pending_review' : 'draft'));
        return 'new1';
      };
      await _pumpAddListing(tester,
          backend: _Backend(routes), picker: _FakePicker(photoBatches: [[_photo('front.png')]]), storage: _Storage());
      await _fillBasics(tester, category: 'sale');
      await _next(tester, 'Photos & video');
      await tester.tap(find.byKey(const Key('media-add-photos')));
      await _settle(tester);
      await _next(tester, 'Details');
      await _next(tester, 'Price & location');
      await _fillPriceAndLocation(tester, price: '900000');
      await _next(tester, 'Review');
      // the default is to submit for review; the agent picks "Save as draft"
      expect(find.widgetWithText(ElevatedButton, 'Submit for review'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('agent-add-mode-draft')));
      await _settle(tester, 2);
      expect(find.widgetWithText(ElevatedButton, 'Save as draft'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const Key('agent-add-submit')));
      await _settle(tester);
      expect(created!['isPublished'], false);
      expect(find.text('Draft saved'), findsOneWidget);
      expect(find.byKey(const Key('agent-status-draft')), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a failed upload shows its error, is never attached, and can be retried or removed', (tester) async {
      Map<String, dynamic>? created;
      final routes = _agentRoutes();
      routes['realEstate:createPropertyListing'] = (a) {
        created = a;
        return 'new1';
      };
      final backend = _Backend(routes);
      final storage = _Storage()..failNext = 1;
      final picker = _FakePicker(
        photoBatches: [
          [_photo('front.png')],
        ],
        videos: [_video('huge.mp4', bytes: 10, reportedLength: 60 * 1024 * 1024), _video('tour.mp4')],
      );
      await _pumpAddListing(tester, backend: backend, picker: picker, storage: storage);
      await _fillBasics(tester);
      await _next(tester, 'Photos & video');

      await tester.tap(find.byKey(const Key('media-add-photos')));
      await _settle(tester);
      expect(find.text('Failed · Retry'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agent-add-next')));
      await _settle(tester, 3);
      expect(find.textContaining('No photo uploaded yet'), findsOneWidget, reason: 'a failed photo does not count');

      await tester.tap(find.byKey(const Key('media-retry-photo-1')));
      await _settle(tester);
      expect(find.text('Failed · Retry'), findsNothing);

      // a video over the limit is refused before uploading
      await tester.tap(find.byKey(const Key('media-add-video')));
      await _settle(tester, 4);
      expect(find.textContaining('at most 50 MB'), findsOneWidget);
      expect(storage.received.where((r) => r.$1.startsWith('video/')), isEmpty);

      // a video whose upload fails blocks submitting until it is retried or removed
      storage.failNext = 1;
      await tester.tap(find.byKey(const Key('media-add-video')));
      await _settle(tester);
      expect(find.byKey(const Key('media-retry-video-2')), findsOneWidget);

      await _next(tester, 'Details');
      await _next(tester, 'Price & location');
      await _fillPriceAndLocation(tester);
      await _next(tester, 'Review');
      await _tapVisible(tester, find.byKey(const Key('agent-add-submit')));
      await _settle(tester);
      expect(created, isNull);
      expect(find.text('Retry or remove the media that failed to upload.'), findsOneWidget);
      // back to the media step and remove the failed video
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Back'));
        await _settle(tester, 3);
      }
      await tester.tap(find.byKey(const Key('media-remove-video-2')));
      await _settle(tester, 2);
      for (final step in ['Details', 'Price & location', 'Review']) {
        await _next(tester, step);
      }
      await _tapVisible(tester, find.byKey(const Key('agent-add-submit')));
      await _settle(tester);
      expect(created, isNotNull);
      expect(created!['imageStorageIds'], ['img_${_png.length}']);
      expect(created!.containsKey('videoStorageIds'), isFalse, reason: 'the failed video was never attached');
      await _tearDown(tester);
    });

    testWidgets('a server refusal is shown as returned, and nothing is marked as created', (tester) async {
      final routes = _agentRoutes();
      routes['realEstate:createPropertyListing'] =
          (_) => const _ServerError('Your Real Estate Agent subscription is not active. Subscribe to post listings.');
      final storage = _Storage();
      await _pumpAddListing(tester,
          backend: _Backend(routes), picker: _FakePicker(photoBatches: [[_photo('front.png')]]), storage: storage);
      await _fillBasics(tester, category: 'sale');
      await _next(tester, 'Photos & video');
      await tester.tap(find.byKey(const Key('media-add-photos')));
      await _settle(tester);
      await _next(tester, 'Details');
      await _next(tester, 'Price & location');
      await _fillPriceAndLocation(tester, price: '750000', address: '3 Hidden Lane');
      await _next(tester, 'Review');
      await _tapVisible(tester, find.byKey(const Key('agent-add-submit')));
      await _settle(tester);
      expect(find.byKey(const Key('agent-add-submit-error')), findsOneWidget);
      expect(find.textContaining('subscription is not active'), findsOneWidget);
      expect(find.byKey(const Key('agent-add-result-title')), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('without posting permission the submit button stays disabled and the reason is shown', (tester) async {
      final storage = _Storage();
      await _pumpAddListing(tester,
          backend: _Backend(_agentRoutes()),
          picker: _FakePicker(photoBatches: [[_photo('front.png')]]),
          storage: storage,
          status: _status(subscribed: false));
      await _fillBasics(tester);
      await _next(tester, 'Photos & video');
      await tester.tap(find.byKey(const Key('media-add-photos')));
      await _settle(tester);
      await _next(tester, 'Details');
      await _next(tester, 'Price & location');
      await _fillPriceAndLocation(tester);
      await _next(tester, 'Review');
      expect(find.byKey(const Key('agent-add-blocked')), findsOneWidget);
      final submit = tester.widget<ElevatedButton>(find.byKey(const Key('agent-add-submit')));
      expect(submit.onPressed, isNull);
      await _tearDown(tester);
    });

    for (final (width, scale) in const [(320.0, 1.35), (430.0, 1.0)]) {
      testWidgets('the media step and the location step fit ${width.toInt()}pt at text ×$scale', (tester) async {
        final storage = _Storage();
        await _pumpAddListing(tester,
            backend: _Backend(_agentRoutes()),
            picker: _FakePicker(
              photoBatches: [
                [_photo('a.png'), _photo('b.png', variant: 1), _photo('c.png', variant: 2), _photo('d.png', variant: 3)],
              ],
              videos: [_video('a-very-long-video-file-name-from-the-phone-gallery-2026-10-04.mp4')],
            ),
            storage: storage,
            width: width,
            height: 700,
            textScale: scale);
        await _fillBasics(tester);
        _expectNoLayoutErrors(tester);
        await _next(tester, 'Photos & video');
        await tester.tap(find.byKey(const Key('media-add-photos')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('media-add-video')));
        await _settle(tester);
        _expectNoLayoutErrors(tester);
        await _next(tester, 'Details');
        await _next(tester, 'Price & location');
        await _fillPriceAndLocation(tester);
        _expectNoLayoutErrors(tester);
        await _next(tester, 'Review');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
        await _settle(tester, 3);
        _expectNoLayoutErrors(tester);
        await _tearDown(tester);
      });
    }
  });

  group('layout of pushed agent pages on small and large phones', () {
    for (final (width, scale) in const [(320.0, 1.35), (430.0, 1.0)]) {
      testWidgets('${width.toInt()}pt, text ×$scale: settings, viewings, earnings, followers, conversation, bio', (tester) async {
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

        await visit(() => _tapVisible(tester, find.byTooltip('Settings').first));
        await visit(() => _tapVisible(tester, find.byKey(const Key('agent-quick-Viewings'))));
        await _openTab(tester, 4);
        await visit(() => _tapVisible(tester, find.byKey(const Key('agent-menu-Earnings & Payouts'))));
        await visit(() => _tapVisible(tester, find.byKey(const Key('agent-menu-Followers'))));
        await _openTab(tester, 2);
        await visit(() => tester.tap(find.byKey(const Key('conversation-req1'))));
        await _openTab(tester, 4);
        await tester.tap(find.byKey(const Key('agent-bio')));
        await _settle(tester, 4);
        _expectNoLayoutErrors(tester);
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
