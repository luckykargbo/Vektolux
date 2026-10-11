// Account & Profile → "Email & Sign-in Methods": email verification and explicit Google/Apple
// linking. The status shown always comes from the backend; a code or a provider sign-in is only
// ever a request, never a local "verified" / "linked" flag.

import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/core/services/biometric_login_service.dart';
import 'package:vektolux/core/theme/app_theme.dart';
import 'package:vektolux/core/widgets/app_text_scale.dart';
import 'package:vektolux/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:vektolux/features/auth/data/services/social_credential_provider.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/domain/repositories/auth_repository.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/auth/presentation/views/verify_email_screen.dart';
import 'package:vektolux/features/profile/presentation/views/account_profile_screen.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _NoBiometrics implements BiometricLoginService {
  @override
  Future<List<BiometricMethod>> availableMethods() async => const [];
  @override
  Future<bool> isEnabled(String userId) async => false;
  @override
  Future<void> setEnabled(String userId, bool value) async {}
  @override
  Future<bool> authenticate(String reason) async => false;
}

class _FakeCredentials implements SocialCredentialProvider {
  final List<String> asked = [];
  SocialCredential? result;
  Object? error;
  _FakeCredentials({this.result});

  @override
  Future<SocialCredential?> obtain(String provider) async {
    asked.add(provider);
    if (error != null) throw error!;
    return result;
  }
}

const _user = UserEntity(
  id: 'user_1',
  name: 'Mariama Sesay',
  email: 'mariama@test.vektolux',
  phone: '+23276123456',
  role: UserRole.client,
  isVerified: false,
  sessionToken: 'sess_mariama_0123456789abcdef',
);

const _idToken = 'header.payload.signature-never-shown';

typedef _Route = Object? Function(Map<String, dynamic> args);

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

/// A backend whose account-security status is mutable, like the real one.
class _Account {
  bool emailVerified;
  bool hasPin;
  bool hasPassword;
  bool google;
  bool apple = false;
  _Account({this.emailVerified = false, this.hasPin = false, this.hasPassword = false, this.google = false});

  Map<String, dynamic> status() => {
        'email': 'mariama@test.vektolux',
        'emailVerified': emailVerified,
        'hasPin': hasPin,
        'hasPassword': hasPassword,
        'linked': {'google': google, 'apple': apple},
      };
}

_Backend _backend(_Account a, {Map<String, _Route> extra = const {}}) => _Backend({
      'users:getUserProfile': (_) => {
            '_id': 'user_1',
            'name': 'Mariama Sesay',
            'email': 'mariama@test.vektolux',
            'phone': '+23276123456',
            'memberSince': DateTime.utc(2025, 4, 12).millisecondsSinceEpoch,
          },
      'payments:getUserSecurityPinStatus': (_) => {'hasPin': a.hasPin, 'hasPassword': a.hasPassword},
      'users:getAccountSecurityStatus': (_) => a.status(),
      ...extra,
    });

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, _Backend backend, {_FakeCredentials? credentials}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  backend.client.setAuthToken(_user.sessionToken!);
  final bloc = _MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(),
      initialState: const AuthState(status: AuthStatus.authenticated, user: _user));
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ConvexClientWrapper>.value(value: backend.client),
        RepositoryProvider<AuthRepository>(create: (_) => AuthRepositoryImpl(convexClient: backend.client)),
      ],
      child: BlocProvider<AuthBloc>.value(
        value: bloc,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => AppTextScale(child: child ?? const SizedBox.shrink()),
          home: AccountProfileScreen(biometrics: _NoBiometrics(), credentials: credentials ?? _FakeCredentials()),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 250, scrollable: find.byType(Scrollable).first);
  await _settle(tester, 2);
  await tester.tap(f);
  await _settle(tester);
}

Finder _text(String s) => find.text(s);
Finder _key(String k) => find.byKey(Key(k));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('email verification', () {
    testWidgets('shows the backend status: unverified offers Verify, verified offers nothing', (tester) async {
      await _pump(tester, _backend(_Account()));
      await tester.scrollUntilVisible(_key('account-email-verification-row'), 250, scrollable: find.byType(Scrollable).first);
      expect(_text('Not verified'), findsOneWidget);
      expect(_key('account-email-verify-action'), findsOneWidget);
    });

    testWidgets('a verified account shows Verified and no Verify action', (tester) async {
      await _pump(tester, _backend(_Account(emailVerified: true)));
      await tester.scrollUntilVisible(_key('account-email-verification-row'), 250, scrollable: find.byType(Scrollable).first);
      expect(_text('Verified'), findsOneWidget);
      expect(_key('account-email-verify-action'), findsNothing);
    });

    testWidgets('a correct code is verified by the server, and the status is re-read from it', (tester) async {
      final account = _Account();
      final backend = _backend(account, extra: {
        'auth:verifyEmail': (args) {
          account.emailVerified = args['code'] == '123456';
          return {'success': account.emailVerified, 'message': 'x'};
        },
      });
      await _pump(tester, backend);
      await _tap(tester, _key('account-email-verify-action'));
      expect(_key('email-verify-explainer'), findsOneWidget);
      expect(_key('email-verify-success'), findsNothing);

      await tester.enterText(_key('email-verify-code'), '123456');
      await _tap(tester, _key('email-verify-submit'));
      expect(backend.lastArgs('auth:verifyEmail'), {'code': '123456', 'sessionToken': _user.sessionToken});
      expect(_key('email-verify-success'), findsOneWidget);
      await _settle(tester, 15); // sheet closes itself
      expect(backend.count('users:getAccountSecurityStatus'), greaterThanOrEqualTo(2));
      await tester.scrollUntilVisible(_key('account-email-verification-row'), 250, scrollable: find.byType(Scrollable).first);
      expect(_text('Verified'), findsOneWidget);
    });

    testWidgets('an invalid / expired / reused code is refused, nothing is marked verified, and the user can retry',
        (tester) async {
      final account = _Account();
      var attempts = 0;
      final backend = _backend(account, extra: {
        'auth:verifyEmail': (args) {
          attempts++;
          if (attempts == 1) {
            return {'success': false, 'message': 'Invalid or expired verification code. Please request a new one.'};
          }
          account.emailVerified = true;
          return {'success': true, 'message': 'ok'};
        },
      });
      await _pump(tester, backend);
      await _tap(tester, _key('account-email-verify-action'));

      await tester.enterText(_key('email-verify-code'), '000000');
      await _tap(tester, _key('email-verify-submit'));
      expect(find.textContaining('Invalid or expired verification code'), findsOneWidget);
      expect(_key('email-verify-success'), findsNothing);
      expect(account.emailVerified, isFalse);

      // recovers in place, without restarting anything
      await tester.enterText(_key('email-verify-code'), '654321');
      await _tap(tester, _key('email-verify-submit'));
      expect(_key('email-verify-success'), findsOneWidget);
      expect(backend.count('auth:verifyEmail'), 2);
      await _settle(tester, 15); // let the sheet's auto-close elapse
    });

    testWidgets('a malformed code never reaches the server', (tester) async {
      final backend = _backend(_Account());
      await _pump(tester, backend);
      await _tap(tester, _key('account-email-verify-action'));
      await tester.enterText(_key('email-verify-code'), '123');
      await _tap(tester, _key('email-verify-submit'));
      expect(_key('email-verify-error'), findsOneWidget);
      expect(backend.count('auth:verifyEmail'), 0);
    });

    testWidgets('resend is throttled locally after a send, and the server limit is shown', (tester) async {
      var sends = 0;
      final backend = _backend(_Account(), extra: {
        'auth:resendEmailVerification': (_) {
          sends++;
          return sends == 1
              ? {'success': true, 'message': 'sent'}
              : {'success': false, 'message': 'Too many requests. Please wait 15 minutes and try again.'};
        },
      });
      await _pump(tester, backend);
      await _tap(tester, _key('account-email-verify-action'));

      await _tap(tester, _key('email-verify-resend'));
      expect(backend.count('auth:resendEmailVerification'), 1);
      expect(_key('email-verify-info'), findsOneWidget);
      expect(find.textContaining('Send a new code in'), findsOneWidget);
      // the button is disabled during the cooldown: tapping does nothing
      await tester.tap(_key('email-verify-resend'), warnIfMissed: false);
      await _settle(tester, 2);
      expect(backend.count('auth:resendEmailVerification'), 1);

      // after the cooldown the server's own limit is what the user sees
      await tester.pump(const Duration(seconds: 61));
      await _tap(tester, _key('email-verify-resend'));
      expect(find.textContaining('Too many requests'), findsOneWidget);
    });
  });

  group('linking Google / Apple', () {
    testWidgets('an account with no PIN and no password links with the session alone', (tester) async {
      final account = _Account();
      final creds = _FakeCredentials(result: const SocialCredential(idToken: _idToken));
      final backend = _backend(account, extra: {
        'users:linkSocialIdentity': (_) {
          account.google = true;
          return {'success': true};
        },
      });
      await _pump(tester, backend, credentials: creds);
      await _tap(tester, _key('account-link-google-action'));
      expect(_key('account-link-secret'), findsNothing);
      await _tap(tester, _key('account-link-submit'));

      expect(creds.asked, ['google']);
      expect(backend.lastArgs('users:linkSocialIdentity'), {
        'provider': 'google',
        'providerId': _idToken,
        'sessionToken': _user.sessionToken,
      });
      await tester.scrollUntilVisible(_key('account-link-google-row'), 250, scrollable: find.byType(Scrollable).first);
      expect(find.descendant(of: _key('account-link-google-row'), matching: _text('Linked')), findsOneWidget);
      expect(_key('account-link-google-action'), findsNothing);
      expect(_text(_idToken), findsNothing); // identity tokens are never displayed
    });

    testWidgets('a PIN-protected account must enter the PIN: empty is refused locally, wrong is refused by the server',
        (tester) async {
      final account = _Account(hasPin: true, hasPassword: true);
      final creds = _FakeCredentials(result: const SocialCredential(idToken: _idToken));
      final backend = _backend(account, extra: {
        'users:linkSocialIdentity': (args) {
          if (args['currentPin'] != '4821') {
            return {'success': false, 'errorCode': 'INVALID', 'message': 'Incorrect PIN. 4 attempt(s) remaining.'};
          }
          account.google = true;
          return {'success': true};
        },
      });
      await _pump(tester, backend, credentials: creds);
      await _tap(tester, _key('account-link-google-action'));
      expect(_key('account-link-secret'), findsOneWidget);

      // missing PIN: nothing is asked of Google and nothing is sent
      await _tap(tester, _key('account-link-submit'));
      expect(find.textContaining('Enter your Account PIN'), findsOneWidget);
      expect(creds.asked, isEmpty);
      expect(backend.count('users:linkSocialIdentity'), 0);

      // wrong PIN: server refuses, account unchanged
      await tester.enterText(_key('account-link-secret'), '9999');
      await _tap(tester, _key('account-link-submit'));
      expect(find.textContaining('Incorrect PIN'), findsOneWidget);
      expect(account.google, isFalse);

      // right PIN: linked
      await tester.enterText(_key('account-link-secret'), '4821');
      await _tap(tester, _key('account-link-submit'));
      expect(backend.lastArgs('users:linkSocialIdentity')['currentPin'], '4821');
      expect(account.google, isTrue);
    });

    testWidgets('a password account without a PIN re-authenticates with its password', (tester) async {
      final account = _Account(hasPassword: true);
      final creds = _FakeCredentials(result: const SocialCredential(idToken: _idToken));
      final backend = _backend(account, extra: {
        'users:linkSocialIdentity': (args) {
          account.google = args['currentPin'] == 'Correct-Horse-9';
          return {'success': account.google, 'message': 'Incorrect PIN. 4 attempt(s) remaining.'};
        },
      });
      await _pump(tester, backend, credentials: creds);
      await _tap(tester, _key('account-link-google-action'));
      expect(find.text('Account password'), findsOneWidget);
      await tester.enterText(_key('account-link-secret'), 'Correct-Horse-9');
      await _tap(tester, _key('account-link-submit'));
      expect(account.google, isTrue);
    });

    testWidgets('cancelling in the provider UI changes nothing and sends nothing', (tester) async {
      final account = _Account();
      final creds = _FakeCredentials(result: null);
      final backend = _backend(account);
      await _pump(tester, backend, credentials: creds);
      await _tap(tester, _key('account-link-google-action'));
      await _tap(tester, _key('account-link-submit'));
      expect(creds.asked, ['google']);
      expect(find.textContaining('cancelled'), findsOneWidget);
      expect(backend.count('users:linkSocialIdentity'), 0);
      expect(account.google, isFalse);
    });

    testWidgets('a provider SDK error is handled gracefully and sends nothing', (tester) async {
      final creds = _FakeCredentials()..error = Exception('PlatformException(sign_in_failed, 10)');
      final backend = _backend(_Account());
      await _pump(tester, backend, credentials: creds);
      await _tap(tester, _key('account-link-google-action'));
      await _tap(tester, _key('account-link-submit'));
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      expect(backend.count('users:linkSocialIdentity'), 0);
    });

    testWidgets('an identity already linked to another account is refused; status is unchanged', (tester) async {
      final account = _Account();
      final creds = _FakeCredentials(result: const SocialCredential(idToken: _idToken));
      final backend = _backend(account, extra: {
        'users:linkSocialIdentity': (_) => {
              'success': false,
              'errorCode': 'ALREADY_LINKED',
              'message': 'This Google account is already linked to a different Vektolux account.',
            },
      });
      await _pump(tester, backend, credentials: creds);
      await _tap(tester, _key('account-link-google-action'));
      await _tap(tester, _key('account-link-submit'));
      expect(find.textContaining('already linked to a different Vektolux account'), findsOneWidget);
      expect(account.google, isFalse);
    });

    testWidgets('Apple sends the one-time nonce with the identity token', (tester) async {
      final account = _Account();
      final creds = _FakeCredentials(result: SocialCredential(idToken: _idToken, nonce: 'ab' * 32));
      final backend = _backend(account, extra: {
        'users:linkSocialIdentity': (_) {
          account.apple = true;
          return {'success': true};
        },
      });
      await _pump(tester, backend, credentials: creds);
      await _tap(tester, _key('account-link-apple-action'));
      await _tap(tester, _key('account-link-submit'));
      expect(creds.asked, ['apple']);
      expect(backend.lastArgs('users:linkSocialIdentity')['nonce'], 'ab' * 32);
      expect(backend.lastArgs('users:linkSocialIdentity')['provider'], 'apple');
    });

    testWidgets('an already-linked provider shows Linked and cannot be linked again', (tester) async {
      await _pump(tester, _backend(_Account(google: true, emailVerified: true)));
      await tester.scrollUntilVisible(_key('account-link-google-row'), 250, scrollable: find.byType(Scrollable).first);
      expect(_key('account-link-google-action'), findsNothing);
      expect(_key('account-link-apple-action'), findsOneWidget);
    });
  });

  group('after registration', () {
    Future<void> pumpScreen(WidgetTester tester, _Backend backend, VoidCallback onContinue) async {
      await tester.pumpWidget(
        RepositoryProvider<AuthRepository>(
          create: (_) => AuthRepositoryImpl(convexClient: backend.client),
          child: MaterialApp(
            theme: AppTheme.light,
            home: VerifyEmailScreen(email: 'new@test.vektolux', onContinue: onContinue),
          ),
        ),
      );
      await _settle(tester, 2);
    }

    testWidgets('says the email is unverified, can be skipped, and never claims verification', (tester) async {
      var continued = 0;
      final backend = _backend(_Account());
      backend.client.setAuthToken(_user.sessionToken!);
      await pumpScreen(tester, backend, () => continued++);
      expect(find.textContaining('not verified yet'), findsOneWidget);
      expect(find.textContaining('new@test.vektolux'), findsWidgets);
      expect(_key('email-verify-success'), findsNothing);
      await tester.tap(_key('email-verify-skip'));
      expect(continued, 1);
      expect(backend.count('auth:verifyEmail'), 0);
    });

    testWidgets('offers Continue only after the server accepted the code', (tester) async {
      var continued = 0;
      final backend = _backend(_Account(), extra: {'auth:verifyEmail': (_) => {'success': true, 'message': 'ok'}});
      backend.client.setAuthToken(_user.sessionToken!);
      await pumpScreen(tester, backend, () => continued++);
      expect(_key('email-verify-continue'), findsNothing);
      await tester.enterText(_key('email-verify-code'), '123456');
      await tester.tap(_key('email-verify-submit'));
      await _settle(tester);
      expect(_key('email-verify-success'), findsOneWidget);
      await tester.tap(_key('email-verify-continue'));
      expect(continued, 1);
    });
  });
}
