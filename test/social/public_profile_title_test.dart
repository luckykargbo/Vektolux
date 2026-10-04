// A public profile shows the professional identity the SERVER derives from the approved roles: an
// agent who is also an approved Car Dealer is "Real Estate Agent & Car Dealer"; a plain agent is
// "Real Estate Agent"; a profile without approved business role stays a client. The app never
// combines roles itself.

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
import 'package:vektolux/features/social/presentation/views/public_profile_screen.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

const _viewer = UserEntity(
  id: 'buyer_1',
  name: 'Aminata Kamara',
  email: 'aminata@test.vektolux',
  phone: '+23276000111',
  role: UserRole.client,
  isVerified: true,
  sessionToken: 'sess_aminata_0123456789abcdef',
);

Map<String, dynamic> _profile({String? professionalTitle, String role = 'agent', bool seller = true}) => {
      '_id': 'owner_1',
      'name': 'Mariama Sesay',
      if (professionalTitle != null) 'professionalTitle': professionalTitle,
      'bio': 'Helping families find homes in Freetown.',
      'role': role,
      'verificationBadge': seller ? 'GREEN_TICK' : 'NONE',
      'followersCount': 12,
      'followingCount': 3,
      'isVerified': true,
      'isVerifiedSeller': seller,
      'canPublishListings': seller,
    };

ConvexClientWrapper _client(Map<String, dynamic> profile) => ConvexClientWrapper(
      deploymentUrl: 'https://example.invalid',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final value = switch (body['path']) {
          'users:getUserProfile' => profile,
          'users:getUserPosts' => <Map<String, dynamic>>[],
          'social:getFollowStatus' => {'isFollowing': false},
          _ => null,
        };
        return http.Response(jsonEncode({'status': 'success', 'value': value}), 200);
      }),
    );

Future<void> _pump(WidgetTester tester, Map<String, dynamic> profile) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = _client(profile);
  final bloc = _MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(), initialState: const AuthState(status: AuthStatus.authenticated, user: _viewer));
  await tester.pumpWidget(RepositoryProvider<ConvexClientWrapper>.value(
    value: client,
    child: BlocProvider<AuthBloc>.value(
      value: bloc,
      child: MaterialApp(home: PublicProfileScreen(userId: 'owner_1', convexClient: client)),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

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

  testWidgets('an agent who is also an approved Car Dealer is shown as "Real Estate Agent & Car Dealer"', (tester) async {
    await _pump(tester, _profile(professionalTitle: 'Real Estate Agent & Car Dealer'));
    expect(find.text('Mariama Sesay'), findsWidgets);
    expect(find.text('Real Estate Agent & Car Dealer'), findsOneWidget);
    expect(find.text('Property Agent'), findsNothing);
  });

  testWidgets('a plain agent is "Real Estate Agent"', (tester) async {
    await _pump(tester, _profile(professionalTitle: 'Real Estate Agent'));
    expect(find.text('Real Estate Agent'), findsOneWidget);
    expect(find.textContaining('Car Dealer'), findsNothing);
  });

  testWidgets('a server that does not send a title yet: the role name is used (nothing is combined by the app)', (tester) async {
    await _pump(tester, _profile());
    expect(find.text('Property Agent'), findsOneWidget);
    expect(find.textContaining('Car Dealer'), findsNothing);
  });

  testWidgets('a profile without an approved business role stays a client — no professional title', (tester) async {
    await _pump(tester, _profile(professionalTitle: 'Client', role: 'client', seller: false));
    expect(find.text('Verified Client & Buyer'), findsOneWidget);
    expect(find.textContaining('Real Estate'), findsNothing);
    expect(find.textContaining('Dealer'), findsNothing);
  });
}
