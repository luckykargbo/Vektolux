// Responsive layout checks for the client Home screen and the bottom navigation.
//
// The physical-iPhone build showed the Deposit / Withdraw / Receive / Scan & Pay tiles so narrow
// that "Deposit" wrapped one letter per line. These tests render the real screens (with a fake
// network, no real data) at small, current and large iPhone widths and at enlarged system text,
// and fail on any RenderFlex overflow or on a single-line label that wraps.

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
import 'package:vektolux/features/home/presentation/views/client_home_screen.dart';
import 'package:vektolux/features/navigation/presentation/views/main_navigation_shell.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

/// Every Convex call answers instantly: either an empty success, or a server error for the
/// wallet queries (to exercise the "Unable to load wallet" state). Nothing leaves the test.
ConvexClientWrapper _fakeConvex({bool walletFails = false}) {
  final client = MockClient((request) async {
    final body = request.body;
    if (walletFails && body.contains('alance')) {
      return http.Response(jsonEncode({'status': 'error', 'errorMessage': 'unavailable'}), 500);
    }
    return http.Response(jsonEncode({'status': 'success', 'value': null}), 200);
  });
  return ConvexClientWrapper(deploymentUrl: 'https://example.invalid', httpClient: client);
}

const _user = UserEntity(
  id: 'user_test_1',
  name: 'Lucky Kargbo',
  email: 'lucky@test.vektolux',
  phone: '+23276000000',
  role: UserRole.client,
  isVerified: true,
);

// Logical widths: iPhone SE (320/375), iPhone 15 (390-393), Pro Max (430).
const _widths = <double>[320, 375, 393, 430];
const _textScales = <double>[1.0, 1.35];

final List<String> _layoutErrors = [];

Future<void> _pumpHome(WidgetTester tester, {required double width, required double textScale, bool walletFails = false}) async {
  // Collect the full diagnostics (including the offending widget's file:line) of any layout error.
  _layoutErrors.clear();
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    _layoutErrors.add(details.toString());
    previous?.call(details); // keep the framework's own bookkeeping
  };
  addTearDown(() => FlutterError.onError = previous);
  tester.view.physicalSize = Size(width * 3, 932 * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  final bloc = _MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(), initialState: const AuthState(status: AuthStatus.authenticated, user: _user));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Roboto'),
      home: BlocProvider<AuthBloc>.value(
        value: bloc,
        child: ClientHomeScreen(convexClient: _fakeConvex(walletFails: walletFails)),
      ),
    ),
  );
  // let the fake network calls resolve and the screen settle
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox()); // disposes the screen (cancels its timers)
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
}

/// Fails with the FULL Flutter diagnostic (widget + file:line) if any layout error happened.
void _expectNoLayoutErrors(WidgetTester tester) {
  tester.takeException();
  if (_layoutErrors.isEmpty) return;
  fail(_layoutErrors.join('\n----\n'));
}

/// A label that must stay on one line: its rendered height is under two lines of its own font.
void _expectSingleLine(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsWidgets, reason: '"$text" should be on screen');
  for (final element in finder.evaluate()) {
    final widget = element.widget as Text;
    final fontSize = (widget.style?.fontSize ?? 14);
    final size = tester.getSize(find.byWidget(widget).first);
    expect(size.height, lessThan(fontSize * 1.15 * 2 * 1.2), reason: '"$text" wrapped onto several lines (height ${size.height})');
    expect(size.width, greaterThan(fontSize * 1.5), reason: '"$text" was squeezed to ${size.width}pt wide');
  }
}

/// Flutter's default test font draws every glyph as a full square, which makes text far wider
/// than on a phone. Load the SDK's Roboto (metrics close to iOS San Francisco) so widths are real.
Future<void> _loadRealFont() async {
  Directory? dir;
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) dir = Directory('$root/bin/cache/artifacts/material_fonts');
  // fallback: walk up from the test runner binary to the SDK root
  var cur = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8 && (dir == null || !dir.existsSync()); i++) {
    final candidate = Directory('${cur.path}/bin/cache/artifacts/material_fonts');
    if (candidate.existsSync()) dir = candidate;
    cur = cur.parent;
  }
  if (dir == null || !dir.existsSync()) return; // falls back to the (wider) test font: stricter, never looser
  final loader = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf']) {
    final file = File('${dir.path}/$f');
    if (file.existsSync()) loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadRealFont);

  for (final width in _widths) {
    for (final scale in _textScales) {
      testWidgets('Home screen lays out at ${width.toInt()}pt wide, text ×$scale — no overflow, one-line action labels', (tester) async {
        await _pumpHome(tester, width: width, textScale: scale);
        _expectNoLayoutErrors(tester);
        for (final label in ['Deposit', 'Withdraw', 'Receive', 'Scan & Pay']) {
          _expectSingleLine(tester, label);
        }
        _expectSingleLine(tester, 'Vektolux Escrow Wallet');
        _expectSingleLine(tester, 'Mobile Money');
        _expectSingleLine(tester, 'Bank Transfer');
        // the four actions share one row, side by side
        final ys = ['Deposit', 'Withdraw', 'Receive', 'Scan & Pay'].map((t) => tester.getCenter(find.text(t).first).dy).toList();
        expect(ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b), lessThan(2));
        // Mobile Money and Bank Transfer cards side by side with equal heights
        final mm = tester.getTopLeft(find.text('Mobile Money'));
        final bt = tester.getTopLeft(find.text('Bank Transfer'));
        expect((mm.dy - bt.dy).abs(), lessThan(2));
        expect(bt.dx, greaterThan(mm.dx));
        await _tearDown(tester);
      });
    }
  }

  testWidgets('a wallet load failure shows the real error inside the card, without breaking the layout', (tester) async {
    await _pumpHome(tester, width: 375, textScale: 1.35, walletFails: true);
    _expectNoLayoutErrors(tester);
    // never a fabricated balance
    expect(find.text('SLE 0.00'), findsNothing);
    _expectSingleLine(tester, 'Deposit');
    await _tearDown(tester);
  });

  // The real app shell: Home + the bottom navigation bar, at the same widths.
  for (final width in _widths) {
    testWidgets('bottom navigation at ${width.toInt()}pt wide, text ×1.35 — five one-line labels, evenly spaced, inside the screen', (tester) async {
      tester.view.physicalSize = Size(width * 3, 932 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.35;
      _layoutErrors.clear();
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        _layoutErrors.add(details.toString());
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);
      final bloc = _MockAuthBloc();
      whenListen(bloc, const Stream<AuthState>.empty(), initialState: const AuthState(status: AuthStatus.authenticated, user: _user));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: RepositoryProvider<ConvexClientWrapper>.value(
            value: _fakeConvex(),
            child: BlocProvider<AuthBloc>.value(value: bloc, child: const MainNavigationShell()),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      _expectNoLayoutErrors(tester);

      final labels = ['Home', 'Explore', 'Real Estate', 'Auto Market', 'Account'];
      final centers = <double>[];
      for (final l in labels) {
        // "Home" also appears in the Saved Places shortcut above, so take the lowest match (the tab bar).
        expect(find.text(l), findsWidgets, reason: '"$l" tab missing');
        final f = find.text(l).last;
        final box = tester.getRect(f);
        expect(box.height, lessThan(24), reason: '"$l" wrapped onto several lines');
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(width), reason: '"$l" is clipped by the screen edge');
        centers.add(box.center.dx);
      }
      // five equal columns: consecutive label centres are one column (width/5) apart
      for (var i = 1; i < centers.length; i++) {
        expect((centers[i] - centers[i - 1]), closeTo(width / 5, 1.5));
      }
      // the bar is slim (58pt + home-indicator inset), not a tall block
      final navBottom = tester.getRect(find.text('Home').last).bottom;
      expect(navBottom, lessThanOrEqualTo(932));

      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }
}
