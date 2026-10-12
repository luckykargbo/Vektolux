import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/domain/repositories/auth_repository.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/auth/presentation/views/login_screen.dart';
import 'package:vektolux/features/auth/presentation/views/mfa_code_dialog.dart';

class _Transport extends http.BaseClient {
  _Transport(this.handler);
  final Map<String, dynamic> Function(Map<String, dynamic> body) handler;
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonDecode(request is http.Request ? request.body : '{}') as Map<String, dynamic>;
    bodies.add(body);
    final value = handler(body);
    final text = jsonEncode({'status': 'success', 'value': value});
    return http.StreamedResponse(Stream.value(utf8.encode(text)), 200,
        headers: {'content-type': 'application/json'}, request: request);
  }
}

const _challenge = 'c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00';
const _sessionToken = 'aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbccccccccccccccccdddddddddddddddd';

Map<String, dynamic> _mfaRequired() => {
      'blocked': true,
      'code': 'MFA_REQUIRED',
      'message': 'Two-factor authentication code required.',
      'mfaChallengeToken': _challenge,
      'mfaExpiresAt': DateTime.now().millisecondsSinceEpoch + 300000,
    };

Map<String, dynamic> _session({String role = 'admin'}) => {
      'userId': 'user_1',
      'hasPhone': true,
      'sessionToken': _sessionToken,
      'user': {'id': 'user_1', 'name': 'Boss', 'email': 'boss@test.vektolux', 'phone': '+23276000000', 'role': role, 'isVerified': true},
    };

Future<Map<String, String?>> _stored() async {
  final p = await SharedPreferences.getInstance();
  return {'token': p.getString('vkt_session_token'), 'userId': p.getString('vkt_user_id')};
}

Future<void> _social(AuthRepositoryImpl repo) => repo.socialSignIn(
      email: 'boss@test.vektolux',
      provider: 'google',
      providerId: 'idtoken',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late ConvexClientWrapper convex;
  AuthRepositoryImpl build(_Transport t) {
    convex = ConvexClientWrapper(deploymentUrl: 'https://test.invalid', httpClient: t);
    return AuthRepositoryImpl(convexClient: convex);
  }

  group('repository: social sign-in', () {
    test('MFA_REQUIRED yields a typed challenge and creates NO session', () async {
      final repo = build(_Transport((_) => _mfaRequired()));
      Object? caught;
      try {
        await _social(repo);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<MfaRequiredException>());
      final e = caught as MfaRequiredException;
      expect(e.challengeToken, _challenge);
      expect(e.isSocial, isTrue);
      expect((await _stored())['token'], isNull);
      expect(convex.hasAuthToken, isFalse);
    });

    test('ordinary customer sign-in (no MFA) still creates the session', () async {
      final repo = build(_Transport((_) => _session(role: 'client')));
      final r = await repo.socialSignIn(email: 'c@test.vektolux', provider: 'google', providerId: 'idtoken');
      expect(r.user.sessionToken, _sessionToken);
      expect((await _stored())['token'], _sessionToken);
      expect(convex.hasAuthToken, isTrue);
    });

    test('the not-linked refusal stays a plain AuthException', () async {
      final repo = build(_Transport((_) => {'blocked': true, 'code': 'ACCOUNT_LINK_REQUIRED', 'message': 'Link first'}));
      expect(() => _social(repo), throwsA(isA<AuthException>()));
    });
  });

  group('repository: completeSocialMfa', () {
    test('a valid code activates the session', () async {
      final t = _Transport((_) => _session());
      final repo = build(t);
      final r = await repo.completeSocialMfa(challengeToken: _challenge, totpCode: ' 123456 ');
      expect(r.user.sessionToken, _sessionToken);
      expect(t.bodies.single['path'], 'users:completeSocialMfa');
      expect((t.bodies.single['args'] as Map)['totpCode'], '123456');
      expect((t.bodies.single['args'] as Map).containsKey('sessionToken'), isFalse);
      expect((await _stored())['token'], _sessionToken);
    });

    test('wrong code is retryable and creates no session', () async {
      final repo = build(_Transport((_) => {'blocked': true, 'code': 'MFA_INVALID', 'message': 'Invalid two-factor authentication code.'}));
      try {
        await repo.completeSocialMfa(challengeToken: _challenge, totpCode: '000000');
        fail('should throw');
      } on MfaChallengeException catch (e) {
        expect(e.retryable, isTrue);
      }
      expect((await _stored())['token'], isNull);
      expect(convex.hasAuthToken, isFalse);
    });

    test('expired, locked and spent challenges are NOT retryable', () async {
      for (final code in ['MFA_CHALLENGE_INVALID', 'MFA_LOCKED']) {
        final repo = build(_Transport((_) => {'blocked': true, 'code': code, 'message': 'nope'}));
        try {
          await repo.completeSocialMfa(challengeToken: _challenge, totpCode: '000000');
          fail('should throw');
        } on MfaChallengeException catch (e) {
          expect(e.retryable, isFalse, reason: code);
        }
      }
    });

    test('a malformed success payload is refused rather than half-signing-in', () async {
      final repo = build(_Transport((_) => {'userId': 'x'}));
      expect(
        () => repo.completeSocialMfa(challengeToken: _challenge, totpCode: '123456'),
        throwsA(isA<MfaChallengeException>()),
      );
      expect((await _stored())['token'], isNull);
    });

    test('cancel sends the challenge and swallows failures', () async {
      final t = _Transport((_) => {'success': true});
      await build(t).cancelSocialMfa(_challenge);
      expect(t.bodies.single['path'], 'users:cancelSocialMfa');
      expect((t.bodies.single['args'] as Map)['challengeToken'], _challenge);
    });
  });

  group('repository: password login with 2FA', () {
    test('mfaRequired response -> MfaRequiredException (no session); code is sent on the retry', () async {
      var call = 0;
      final t = _Transport((body) {
        call++;
        if ((body['args'] as Map).containsKey('totpCode')) {
          return {
            'success': true, 'userId': 'user_1', 'sessionToken': _sessionToken, 'name': 'Boss',
            'email': 'boss@test.vektolux', 'phone': '+23276000000', 'role': 'admin',
          };
        }
        return {'success': false, 'mfaRequired': true, 'errorMessage': 'Two-factor authentication code required.'};
      });
      final repo = build(t);
      await expectLater(
        repo.login(identifier: 'boss@test.vektolux', password: 'pw-pw-pw-pw'),
        throwsA(isA<MfaRequiredException>().having((e) => e.isSocial, 'isSocial', isFalse)),
      );
      expect((await _stored())['token'], isNull);
      final user = await repo.login(identifier: 'boss@test.vektolux', password: 'pw-pw-pw-pw', totpCode: '123456');
      expect(user.sessionToken, _sessionToken);
      expect(call, 2);
      expect((t.bodies.last['args'] as Map)['totpCode'], '123456');
    });
  });

  group('bloc', () {
    test('MFA_REQUIRED -> mfaRequired state with the challenge; code -> authenticated', () async {
      final repo = _FakeRepo()
        ..socialResult = (() => throw const MfaRequiredException('code', challengeToken: _challenge))
        ..mfaResult = ({required String t, required String c}) async => _user();
      final bloc = AuthBloc(repository: repo);
      bloc.add(const SocialAuthEvent(provider: 'google', token: 'tok', email: 'boss@test.vektolux'));
      await _until(bloc, (s) => s.status == AuthStatus.mfaRequired);
      expect(bloc.state.mfaChallengeToken, _challenge);
      expect(bloc.state.user, isNull); // no session / user before the second factor

      bloc.add(const SocialMfaSubmittedEvent('123456'));
      await _until(bloc, (s) => s.status == AuthStatus.authenticated);
      expect(bloc.state.user, isNotNull);
      expect(bloc.state.mfaChallengeToken, isNull);
      expect(repo.completed, [(_challenge, '123456')]);
      await bloc.close();
    });

    test('wrong code keeps the challenge and shows the message; a spent challenge ends the flow', () async {
      final repo = _FakeRepo()
        ..socialResult = (() => throw const MfaRequiredException('code', challengeToken: _challenge));
      final bloc = AuthBloc(repository: repo);
      bloc.add(const SocialAuthEvent(provider: 'google', token: 'tok', email: 'e@test.vektolux'));
      await _until(bloc, (s) => s.status == AuthStatus.mfaRequired);

      repo.mfaResult = ({required String t, required String c}) async =>
          throw const MfaChallengeException('Invalid two-factor authentication code.', retryable: true);
      bloc.add(const SocialMfaSubmittedEvent('000000'));
      await _until(bloc, (s) => s.status == AuthStatus.mfaRequired && s.errorMessage != null);
      expect(bloc.state.mfaChallengeToken, _challenge);
      expect(bloc.state.user, isNull);

      repo.mfaResult = ({required String t, required String c}) async =>
          throw const MfaChallengeException('This sign-in has expired. Please start again.', retryable: false);
      bloc.add(const SocialMfaSubmittedEvent('000000'));
      await _until(bloc, (s) => s.status == AuthStatus.error);
      expect(bloc.state.mfaChallengeToken, isNull);
      expect(bloc.state.user, isNull);
      await bloc.close();
    });

    test('cancel burns the challenge on the server and signs nothing in', () async {
      final repo = _FakeRepo()
        ..socialResult = (() => throw const MfaRequiredException('code', challengeToken: _challenge));
      final bloc = AuthBloc(repository: repo);
      bloc.add(const SocialAuthEvent(provider: 'apple', token: 'tok', email: 'e@test.vektolux', nonce: 'n'));
      await _until(bloc, (s) => s.status == AuthStatus.mfaRequired);
      bloc.add(const SocialMfaCancelledEvent());
      await _until(bloc, (s) => s.status == AuthStatus.unauthenticated);
      await Future<void>.delayed(Duration.zero);
      expect(repo.cancelled, [_challenge]);
      expect(bloc.state.mfaChallengeToken, isNull);
      // a late submit with no pending challenge is ignored
      bloc.add(const SocialMfaSubmittedEvent('123456'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.completed, isEmpty);
      await bloc.close();
    });

    test('password login: MfaRequired -> mfaRequired (no challenge token), retry with code signs in', () async {
      final repo = _FakeRepo()..loginResult = (code) async {
            if (code == null) throw const MfaRequiredException('code');
            return _user();
          };
      final bloc = AuthBloc(repository: repo);
      bloc.add(const LoginSubmittedEvent(identifier: 'a@b.c', password: 'pw'));
      await _until(bloc, (s) => s.status == AuthStatus.mfaRequired);
      expect(bloc.state.mfaChallengeToken, isNull);
      bloc.add(const LoginSubmittedEvent(identifier: 'a@b.c', password: 'pw', totpCode: '123456'));
      await _until(bloc, (s) => s.status == AuthStatus.authenticated);
      await bloc.close();
    });
  });

  group('LoginScreen integration', () {
    Future<(AuthBloc, _FakeRepo)> pumpLogin(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeRepo()
        ..socialResult = (() => throw const MfaRequiredException('code', challengeToken: _challenge));
      final bloc = AuthBloc(repository: repo);
      addTearDown(bloc.close);
      await tester.pumpWidget(MaterialApp(
        home: BlocProvider<AuthBloc>.value(value: bloc, child: const LoginScreen()),
      ));
      return (bloc, repo);
    }

    testWidgets('a pending social MFA challenge opens the code dialog; a spent challenge closes it and shows why', (tester) async {
      final (bloc, repo) = await pumpLogin(tester);
      repo.mfaResult = ({required String t, required String c}) async =>
          throw const MfaChallengeException('This sign-in has expired. Please start again.', retryable: false);
      bloc.add(const SocialAuthEvent(provider: 'google', token: 'tok', email: 'boss@test.vektolux'));
      await tester.pumpAndSettle();
      expect(find.byType(MfaCodeDialog), findsOneWidget);
      expect(bloc.state.user, isNull); // dialog is up, nothing is signed in

      await tester.enterText(find.byKey(const Key('mfa-code-field')), '123456');
      await tester.tap(find.byKey(const Key('mfa-submit')));
      await tester.pumpAndSettle();
      expect(repo.completed, [(_challenge, '123456')]);
      expect(find.byType(MfaCodeDialog), findsNothing);
      expect(find.text('This sign-in has expired. Please start again.'), findsOneWidget); // snackbar
      expect(bloc.state.user, isNull);
    });

    testWidgets('cancel closes the dialog, burns the challenge and signs nothing in', (tester) async {
      final (bloc, repo) = await pumpLogin(tester);
      bloc.add(const SocialAuthEvent(provider: 'google', token: 'tok', email: 'boss@test.vektolux'));
      await tester.pumpAndSettle();
      expect(find.byType(MfaCodeDialog), findsOneWidget);

      await tester.tap(find.byKey(const Key('mfa-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(MfaCodeDialog), findsNothing);
      expect(repo.cancelled, [_challenge]);
      expect(bloc.state.user, isNull);
      expect(bloc.state.status, AuthStatus.unauthenticated);
    });

    testWidgets('a wrong code keeps the dialog open with the message', (tester) async {
      final (bloc, repo) = await pumpLogin(tester);
      repo.mfaResult = ({required String t, required String c}) async =>
          throw const MfaChallengeException('Invalid two-factor authentication code.', retryable: true);
      bloc.add(const SocialAuthEvent(provider: 'google', token: 'tok', email: 'boss@test.vektolux'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('mfa-code-field')), '000000');
      await tester.tap(find.byKey(const Key('mfa-submit')));
      await tester.pumpAndSettle();
      expect(find.byType(MfaCodeDialog), findsOneWidget);
      expect(find.byKey(const Key('mfa-error')), findsOneWidget);
      expect(bloc.state.user, isNull);
    });
  });

  group('MfaCodeDialog', () {
    Future<void> pump(WidgetTester tester, {String? error, bool verifying = false, void Function(String)? onSubmit, VoidCallback? onCancel}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => MfaCodeDialog(
              errorMessage: error,
              verifying: verifying,
              onSubmit: onSubmit ?? (_) {},
              onCancel: onCancel ?? () {},
            ),
          ),
        ),
      ));
    }

    testWidgets('submits the trimmed code and shows server errors', (tester) async {
      String? got;
      await pump(tester, error: 'Invalid two-factor authentication code.', onSubmit: (c) => got = c);
      expect(find.byKey(const Key('mfa-error')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('mfa-code-field')), ' 123456 ');
      await tester.tap(find.byKey(const Key('mfa-submit')));
      expect(got, '123456');
    });

    testWidgets('empty code is not submitted; verifying disables both actions', (tester) async {
      var submits = 0;
      await pump(tester, onSubmit: (_) => submits++);
      await tester.tap(find.byKey(const Key('mfa-submit')));
      expect(submits, 0);
      await pump(tester, verifying: true, onSubmit: (_) => submits++);
      await tester.enterText(find.byKey(const Key('mfa-code-field')), '123456');
      await tester.tap(find.byKey(const Key('mfa-submit')), warnIfMissed: false);
      expect(submits, 0);
      expect(tester.widget<TextButton>(find.byKey(const Key('mfa-cancel'))).onPressed, isNull);
    });

    testWidgets('cancel calls back', (tester) async {
      var cancelled = false;
      await pump(tester, onCancel: () => cancelled = true);
      await tester.tap(find.byKey(const Key('mfa-cancel')));
      expect(cancelled, isTrue);
    });

    testWidgets('fits a 320pt phone at large text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.35)),
        child: MaterialApp(home: Scaffold(body: MfaCodeDialog(onSubmit: (_) {}, onCancel: () {}, errorMessage: 'Invalid two-factor authentication code.'))),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _until(AuthBloc bloc, bool Function(AuthState) test) async {
  if (test(bloc.state)) return;
  await bloc.stream.firstWhere(test).timeout(const Duration(seconds: 5));
}

UserEntity _user() => const UserEntity(
      id: 'user_1', name: 'Boss', email: 'boss@test.vektolux', phone: '+23276000000',
      role: UserRole.admin, sessionToken: _sessionToken,
    );

class _FakeRepo extends Fake implements AuthRepository {
  Never Function()? socialResult;
  Future<UserEntity> Function({required String t, required String c})? mfaResult;
  Future<UserEntity> Function(String? code)? loginResult;
  final List<(String, String)> completed = [];
  final List<String> cancelled = [];

  @override
  Future<({UserEntity user, bool hasPhone})> socialSignIn({
    required String email,
    String? name,
    String? avatarUrl,
    required String provider,
    required String providerId,
    String? nonce,
  }) async {
    socialResult!.call();
  }

  @override
  Future<({UserEntity user, bool hasPhone})> completeSocialMfa({required String challengeToken, required String totpCode}) async {
    completed.add((challengeToken, totpCode));
    final u = await mfaResult!(t: challengeToken, c: totpCode);
    return (user: u, hasPhone: true);
  }

  @override
  Future<void> cancelSocialMfa(String challengeToken) async => cancelled.add(challengeToken);

  @override
  Future<UserEntity> login({required String identifier, required String password, String? totpCode}) =>
      loginResult!(totpCode);
}
