// Settings → Account & Profile: real account data, a read-only verified name, PIN-protected phone
// change, the existing hashed PIN, OS-only biometric login, and a 30-day deletion REQUEST.

import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/core/services/biometric_login_service.dart';
import 'package:vektolux/core/theme/app_theme.dart';
import 'package:vektolux/core/widgets/app_text_scale.dart';
import 'package:vektolux/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/domain/repositories/auth_repository.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/profile/presentation/views/account_profile_screen.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class _FakeBiometrics implements BiometricLoginService {
  List<BiometricMethod> methods;
  bool osResult;
  final Map<String, bool> enabled = {};
  final List<String> prompts = [];

  _FakeBiometrics({this.methods = const [], this.osResult = true});

  @override
  Future<List<BiometricMethod>> availableMethods() async => methods;
  @override
  Future<bool> isEnabled(String userId) async => enabled[userId] ?? false;
  @override
  Future<void> setEnabled(String userId, bool value) async => enabled[userId] = value;
  @override
  Future<bool> authenticate(String reason) async {
    prompts.add(reason);
    return osResult;
  }
}

typedef _Route = Object? Function(Map<String, dynamic> args);

const _agent = UserEntity(
  id: 'agent_1',
  name: 'Session Name',
  email: 'mariama@test.vektolux',
  phone: '+23276123456',
  role: UserRole.agent,
  isVerified: true,
  verificationStatus: 'approved',
  sessionToken: 'sess_mariama_0123456789abcdef',
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

Map<String, dynamic> _profile({
  String name = 'Mariama Sesay',
  bool verified = true,
  String email = 'mariama@test.vektolux',
  String phone = '+23276123456',
}) =>
    {
      '_id': 'agent_1',
      'name': name,
      'professionalTitle': 'Real Estate Agent',
      'identityVerified': verified,
      // 12 Apr 2025, 12:00 UTC
      'memberSince': DateTime.utc(2025, 4, 12, 12).millisecondsSinceEpoch,
      'email': email,
      'phone': phone,
    };

_Backend _backend({bool hasPin = false, Map<String, dynamic>? profile, Map<String, _Route> extra = const {}}) => _Backend({
      'users:getUserProfile': (_) => profile ?? _profile(),
      'payments:getUserSecurityPinStatus': (_) => {'hasPin': hasPin, 'hasPassword': true},
      ...extra,
    });

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_MockAuthBloc> _pump(
  WidgetTester tester,
  _Backend backend, {
  _FakeBiometrics? biometrics,
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  backend.client.setAuthToken(_agent.sessionToken!);
  final bloc = _MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(),
      initialState: const AuthState(status: AuthStatus.authenticated, user: _agent));
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
          home: AccountProfileScreen(biometrics: biometrics ?? _FakeBiometrics()),
        ),
      ),
    ),
  );
  await _settle(tester);
  return bloc;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _settle(tester, 2);
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  // The repository caches the signed-in user on the device after a server change.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('profile header', () {
    testWidgets('shows the server-verified name, identity, status and member-since — and no way to edit the name',
        (tester) async {
      await _pump(tester, _backend());
      expect(find.text('Mariama Sesay'), findsOneWidget); // server value, not the cached session name
      expect(find.text('Session Name'), findsNothing);
      expect(find.byKey(const Key('account-identity-verified')), findsOneWidget);
      expect(find.text('Verified Identity'), findsOneWidget);
      expect(find.text('Real Estate Agent'), findsOneWidget);
      expect(find.text('Member since 12 Apr 2025'), findsOneWidget);
      expect(find.text('Verified name · cannot be edited'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Edit name'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget); // only the phone "Change" action
    });

    testWidgets('an unverified identity is shown honestly', (tester) async {
      await _pump(tester, _backend(profile: _profile(verified: false)));
      expect(find.byKey(const Key('account-identity-unverified')), findsOneWidget);
      expect(find.text('Verified Identity'), findsNothing);
    });

    testWidgets('only Account & Profile sections are shown', (tester) async {
      // A tall viewport builds every section at once.
      await _pump(tester, _backend(), size: const Size(390, 2000));
      for (final title in ['Contact Details', 'Account PIN', 'Biometric Login', 'Delete Account']) {
        expect(find.text(title), findsWidgets);
      }
      for (final unrelated in ['Professional subscription', 'Browse as a client', 'Wallet', 'Support']) {
        expect(find.text(unrelated), findsNothing);
      }
    });
  });

  group('contact details', () {
    testWidgets('shows the real phone and email; hides an internal sign-in placeholder email', (tester) async {
      await _pump(tester, _backend());
      expect(find.text('+232 76 123 456'), findsOneWidget);
      expect(find.text('mariama@test.vektolux'), findsOneWidget);
    });

    testWidgets('a placeholder email from Apple/Google sign-in is not shown', (tester) async {
      await _pump(tester, _backend(profile: _profile(email: 'apple_123@users.vektolux.invalid')));
      expect(find.byKey(const Key('account-email-row')), findsNothing);
    });

    testWidgets('changing the phone goes to the server with the Account PIN, and shows its refusal', (tester) async {
      var attempts = 0;
      final backend = _backend(hasPin: true, extra: {
        'users:linkPhoneNumber': (args) {
          attempts++;
          return attempts == 1
              ? {'success': false, 'phoneNumber': '+23276123456', 'errorCode': 'INVALID', 'message': 'Incorrect PIN. 4 attempt(s) remaining.'}
              : {'success': true, 'phoneNumber': '+23277555444'};
        },
      });
      final bloc = await _pump(tester, backend);
      await _tap(tester, find.byKey(const Key('account-change-phone')));
      expect(find.byKey(const Key('account-phone-pin')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('account-phone-input')), '077 555 444');
      await tester.enterText(find.byKey(const Key('account-phone-pin')), '9999');
      await _tap(tester, find.byKey(const Key('account-phone-save')));
      expect(find.text('Incorrect PIN. 4 attempt(s) remaining.'), findsOneWidget);
      expect(backend.lastArgs('users:linkPhoneNumber'), {
        'userId': 'agent_1',
        'phoneNumber': '+23277555444',
        'currentPin': '9999',
        'sessionToken': _agent.sessionToken,
      });

      await tester.enterText(find.byKey(const Key('account-phone-pin')), '4821');
      await _tap(tester, find.byKey(const Key('account-phone-save')));
      expect(find.byKey(const Key('account-phone-input')), findsNothing);
      verify(() => bloc.add(const RefreshUserSessionEvent())).called(1);
      expect(backend.count('users:updateUserProfile'), 0);
    });

    testWidgets('an invalid number never reaches the server', (tester) async {
      final backend = _backend();
      await _pump(tester, backend);
      await _tap(tester, find.byKey(const Key('account-change-phone')));
      expect(find.byKey(const Key('account-phone-pin')), findsNothing); // no PIN set yet
      await tester.enterText(find.byKey(const Key('account-phone-input')), '12');
      await _tap(tester, find.byKey(const Key('account-phone-save')));
      expect(find.byKey(const Key('account-sheet-error')), findsOneWidget);
      expect(backend.count('users:linkPhoneNumber'), 0);
    });
  });

  group('account PIN', () {
    testWidgets('a new PIN is set through the existing hashed-PIN mutation and never displayed', (tester) async {
      final backend = _backend(extra: {'payments:setWalletPin': (_) => {'success': true}});
      await _pump(tester, backend);
      expect(find.text('Not set'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('account-pin-action')));
      expect(find.byKey(const Key('account-pin-current')), findsNothing);

      await tester.enterText(find.byKey(const Key('account-pin-new')), '4821');
      await tester.enterText(find.byKey(const Key('account-pin-confirm')), '4821');
      final field = tester.widget<TextField>(
          find.descendant(of: find.byKey(const Key('account-pin-new')), matching: find.byType(TextField)));
      expect(field.obscureText, isTrue);
      // The controller holds the digits; nothing on screen shows them.
      expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? w.textSpan?.toPlainText()) == '4821'), findsNothing);

      await _tap(tester, find.byKey(const Key('account-pin-save')));
      expect(backend.lastArgs('payments:setWalletPin'),
          {'userId': 'agent_1', 'pin': '4821', 'sessionToken': _agent.sessionToken});
      expect(find.text('Set'), findsOneWidget);
      expect(find.text('Change PIN'), findsOneWidget);
    });

    testWidgets('changing an existing PIN needs the current one; mismatches never reach the server', (tester) async {
      final backend = _backend(hasPin: true, extra: {'payments:setWalletPin': (_) => {'success': true}});
      await _pump(tester, backend);
      await _tap(tester, find.byKey(const Key('account-pin-action')));
      await tester.enterText(find.byKey(const Key('account-pin-current')), '1111');
      await tester.enterText(find.byKey(const Key('account-pin-new')), '2222');
      await tester.enterText(find.byKey(const Key('account-pin-confirm')), '3333');
      await _tap(tester, find.byKey(const Key('account-pin-save')));
      expect(find.text('The PINs do not match.'), findsOneWidget);
      expect(backend.count('payments:setWalletPin'), 0);

      await tester.enterText(find.byKey(const Key('account-pin-confirm')), '2222');
      await _tap(tester, find.byKey(const Key('account-pin-save')));
      expect(backend.lastArgs('payments:setWalletPin')['currentPin'], '1111');
    });
  });

  group('biometric login', () {
    testWidgets('no enrolled biometrics: nothing is offered as if it existed', (tester) async {
      await _pump(tester, _backend(), biometrics: _FakeBiometrics());
      expect(find.byKey(const Key('account-biometric-switch')), findsNothing);
      expect(find.byKey(const Key('account-biometric-unavailable')), findsOneWidget);
      expect(find.text('Face ID'), findsNothing);
      expect(find.text('Touch ID'), findsNothing);
    });

    testWidgets('Face ID turns on only after the OS confirms it', (tester) async {
      final bio = _FakeBiometrics(methods: [BiometricMethod.faceId], osResult: false);
      await _pump(tester, _backend(), biometrics: bio);
      expect(find.text('Face ID'), findsOneWidget);
      expect(find.text('Touch ID'), findsNothing);

      await _tap(tester, find.byKey(const Key('account-biometric-switch')));
      expect(bio.prompts, hasLength(1));
      expect(bio.enabled['agent_1'], isNot(true));

      bio.osResult = true;
      await _tap(tester, find.byKey(const Key('account-biometric-switch')));
      expect(bio.enabled['agent_1'], isTrue);
      expect(find.text('Enabled'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('account-biometric-switch')));
      expect(bio.enabled['agent_1'], isFalse);
    });

    testWidgets('a Touch ID device shows Touch ID', (tester) async {
      await _pump(tester, _backend(), biometrics: _FakeBiometrics(methods: [BiometricMethod.touchId]));
      expect(find.text('Touch ID'), findsOneWidget);
      expect(find.text('Face ID'), findsNothing);
    });
  });

  group('delete account', () {
    testWidgets('explains the 30-day window and only REQUESTS deletion after confirmation', (tester) async {
      final backend = _backend(hasPin: true, extra: {
        'users:requestAccountDeletion': (_) => {
              'success': false,
              'errorCode': 'FUNDS_REMAINING',
              'message': 'Withdraw your wallet balance and settle any escrow before deleting your account.',
            },
      });
      await _pump(tester, backend);
      await tester.scrollUntilVisible(find.byKey(const Key('account-delete-button')), 100,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('permanently deleted after 30 days'), findsOneWidget);

      await _tap(tester, find.byKey(const Key('account-delete-button')));
      final submit = find.byKey(const Key('account-delete-submit'));
      expect(tester.widget<FilledButton>(find.descendant(of: submit, matching: find.byType(FilledButton))).onPressed,
          isNull);

      await tester.enterText(find.byKey(const Key('account-delete-confirm-input')), 'delete');
      await tester.enterText(find.byKey(const Key('account-delete-pin')), '4821');
      await _settle(tester, 2);
      await _tap(tester, submit);

      expect(backend.lastArgs('users:requestAccountDeletion'),
          {'userId': 'agent_1', 'currentPin': '4821', 'sessionToken': _agent.sessionToken});
      expect(find.text('Withdraw your wallet balance and settle any escrow before deleting your account.'),
          findsOneWidget);
      expect(backend.count('users:deleteUserAccount'), 0);
    });
  });

  group('layout', () {
    for (final size in const [Size(320, 568), Size(390, 844), Size(430, 932), Size(820, 1180)]) {
      testWidgets('no overflow at ${size.width.toInt()}×${size.height.toInt()} with large text', (tester) async {
        await _pump(
          tester,
          _backend(profile: _profile(name: 'Mohamed Abdulai Bangura-Kamara Konteh')),
          biometrics: _FakeBiometrics(methods: [BiometricMethod.faceUnlock, BiometricMethod.fingerprint]),
          size: size,
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.byKey(const Key('account-delete-button')), 150,
            scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
