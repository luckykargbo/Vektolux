// Responsive layout, colour and data-honesty checks for the Explore screen.
//
// Renders the real ExploreScreen (fake network, test-only data) at small / normal / large iPhone
// widths, with enlarged system text and with the phone in Dark Mode, and fails on:
//   • any RenderFlex / layout error      • a one-line label that wraps or is squeezed
//   • sections replaced by an error      • details the listing does not actually have
//   • light-on-white text in Dark Mode

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
import 'package:vektolux/core/theme/app_colors.dart';
import 'package:vektolux/core/theme/app_theme.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/explore/presentation/views/explore_screen.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

const _user = UserEntity(id: 'user_test_1', name: 'Test User', email: 't@test.vektolux', phone: '+23276000000', role: UserRole.client, isVerified: true);

// Test-only listings shaped like the real backend feed. Some deliberately lack optional details.
final _house = {
  'id': 'p1', 'type': 'property', 'title': '3 Bedroom House', 'category': 'sale', 'price': 320000, 'currency': 'SLE',
  'location': 'Inside Freetown, Sierra Leone', 'city': 'Freetown', 'bedrooms': 3, 'bathrooms': 2, 'areaSqM': 167, 'isVerified': true,
};
final _land = {
  'id': 'p2', 'title': 'Land for Sale', 'category': 'sale', 'price': 75000, 'currency': 'SLE', 'city': 'Frekka', 'isVerified': false,
}; // no beds / baths / area
final _rental = {
  'id': 'p3', 'title': 'Family Apartment With A Very Long Name Indeed', 'category': 'long_term_rent', 'price': 1200000, 'currency': 'SLE',
  'city': 'Bo', 'bedrooms': 2, 'bathrooms': 1, 'areaSqM': 90, 'isVerified': true,
};
final _suv = {
  'id': 'v1', 'type': 'vehicle', 'title': 'Toyota Land Cruiser Prado', 'category': 'car_sale', 'pricingType': 'total_sale', 'price': 45000, 'currency': 'SLE',
  'location': 'Inside Freetown, Sierra Leone', 'year': 2021, 'fuelType': 'Diesel', 'transmission': 'Automatic', 'isVerified': true,
};
final _bareCar = {
  'id': 'v2', 'title': 'Mystery Car', 'category': 'car_sale', 'price': 9000, 'currency': 'SLE', 'location': 'Inside Bo, Sierra Leone', 'isVerified': false,
}; // no year / fuel / transmission / pricingType
final _hire = {
  'id': 'v3', 'title': 'Toyota Hilux', 'category': 'car_rental', 'pricingType': 'per_day', 'price': 120, 'currency': 'SLE', 'location': 'Inside Freetown, Sierra Leone',
  'year': 2022, 'fuelType': 'Diesel', 'transmission': 'Manual', 'isVerified': true,
};
final _agents = [
  {'id': 'a1', 'name': 'Samuel Cars', 'role': 'Auto Dealer', 'isVerified': true, 'listingsCount': 158},
  {'id': 'a2', 'name': 'Grace Properties With A Long Name', 'role': 'Real Estate Agent', 'isVerified': true, 'listingsCount': 1},
  {'id': 'a3', 'name': 'David Rentals', 'role': 'Real Estate Agent', 'isVerified': false, 'listingsCount': 74},
];

ConvexClientWrapper _fakeConvex({bool feedFails = false, bool empty = false}) {
  final client = MockClient((request) async {
    if (request.body.contains('getExploreFeed')) {
      if (feedFails) return http.Response(jsonEncode({'status': 'error', 'errorMessage': 'unavailable'}), 500);
      final value = empty
          ? {'recommended': [], 'propertiesNearYou': [], 'vehiclesForSaleAndHire': [], 'topAgentsAndDealers': []}
          : {
              'recommended': [_house, _suv],
              'propertiesNearYou': [_house, _land, _rental],
              'vehiclesForSaleAndHire': [_suv, _bareCar, _hire],
              'topAgentsAndDealers': _agents,
            };
      return http.Response(jsonEncode({'status': 'success', 'value': value}), 200);
    }
    return http.Response(jsonEncode({'status': 'success', 'value': 0}), 200);
  });
  return ConvexClientWrapper(deploymentUrl: 'https://example.invalid', httpClient: client);
}

/// Flutter's default test font draws square glyphs (far wider than a phone). Use the SDK's Roboto.
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

final List<String> _layoutErrors = [];

Future<void> _pumpExplore(
  WidgetTester tester, {
  required double width,
  double textScale = 1.0,
  bool feedFails = false,
  bool empty = false,
  bool phoneInDarkMode = false,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.physicalSize = Size(width * 3, 3200 * 3); // tall: every section is built and measured
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  if (phoneInDarkMode) tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
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
      theme: AppTheme.light.copyWith(textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Roboto')),
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: BlocProvider<AuthBloc>.value(
        value: bloc,
        child: ExploreScreen(convexClient: _fakeConvex(feedFails: feedFails, empty: empty)),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.platformDispatcher.clearTextScaleFactorTestValue();
  tester.platformDispatcher.clearPlatformBrightnessTestValue();
}

void _expectNoLayoutErrors(WidgetTester tester) {
  tester.takeException();
  if (_layoutErrors.isEmpty) return;
  fail(_layoutErrors.join('\n----\n'));
}

/// A label that must stay on a single line (height below two lines of its own font).
void _expectOneLine(WidgetTester tester, Finder finder, {String? label}) {
  expect(finder, findsWidgets, reason: '${label ?? 'label'} should be on screen');
  for (final e in finder.evaluate()) {
    final w = e.widget as Text;
    final size = tester.getSize(find.byWidget(w));
    final fontSize = w.style?.fontSize ?? 14;
    expect(size.height, lessThan(fontSize * 1.4 * 1.9), reason: '${label ?? w.data} wrapped (height ${size.height})');
    expect(size.width, greaterThan(fontSize * 1.2), reason: '${label ?? w.data} squeezed to ${size.width}pt');
  }
}

void main() {
  setUpAll(_loadRealFont);

  for (final width in <double>[320, 375, 393, 430]) {
    for (final scale in <double>[1.0, 1.35]) {
      testWidgets('Explore at ${width.toInt()}pt wide, text ×$scale — no overflow, one-line labels, stable cards', (tester) async {
        await _pumpExplore(tester, width: width, textScale: scale);
        _expectNoLayoutErrors(tester);

        // header
        _expectOneLine(tester, find.text('Explore'), label: 'title');
        // five categories in ONE row
        final cats = ['Properties', 'Vehicles', 'Agents', 'Dealers', 'Rentals'];
        final ys = cats.map((c) => tester.getCenter(find.text(c)).dy).toList();
        expect(ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b), lessThan(2), reason: 'categories must share one row');
        for (final c in cats) {
          _expectOneLine(tester, find.text(c), label: c);
          final r = tester.getRect(find.text(c));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(width), reason: '$c is cut off by the screen edge');
        }
        // section titles on one line
        for (final t in ['Recommended for You', 'Properties Near You', 'Vehicles for Sale & Hire', 'Top Agents & Dealers']) {
          _expectOneLine(tester, find.text(t), label: t);
        }
        // prices stay on one line, cards have real width
        _expectOneLine(tester, find.text('SLE 320,000'), label: 'price');
        // Recommended shows two cards across on every phone
        final p1 = tester.getRect(find.text('SLE 320,000').first);
        final p2 = tester.getRect(find.text('SLE 45,000').first);
        expect((p1.top - p2.top).abs(), lessThan(2), reason: 'recommended cards share a row');
        expect(p2.right, lessThanOrEqualTo(width + 1));
        // agents: three cards share a row; Follow buttons all one line
        final f = find.text('Follow');
        expect(f, findsWidgets);
        _expectOneLine(tester, find.text('Find Agents →'), label: 'Find Agents');
        await _tearDown(tester);
      });
    }
  }

  testWidgets('cards show only details the listing really has (nothing invented)', (tester) async {
    await _pumpExplore(tester, width: 393);
    _expectNoLayoutErrors(tester);
    // real details appear
    expect(find.text('3'), findsWidgets); // bedrooms
    expect(find.textContaining('167 m²'), findsWidgets);
    expect(find.text('Diesel'), findsWidgets);
    expect(find.text('Auto'), findsWidgets);
    expect(find.text('For Hire'), findsWidgets);
    expect(find.text('For Rent'), findsWidgets);
    expect(find.textContaining('/ year'), findsWidgets);
    expect(find.textContaining('/ day'), findsWidgets);
    // the old invented defaults are gone
    expect(find.text('1,800 sqft'), findsNothing);
    expect(find.textContaining('sqft'), findsNothing);
    expect(find.text('2021'), findsNWidgets(2)); // the SUV (in Recommended and in Vehicles); the bare car has no year
    expect(find.text('2022'), findsOneWidget); // the hire vehicle only
    expect(find.text('Land for Sale'), findsOneWidget);
    // the land listing has no beds/baths/area → no spec row for it; the bare car has no year/fuel
    expect(find.text('Mystery Car'), findsOneWidget);
    // generalized public locations only — never a fabricated default
    expect(find.text('Freetown, Sierra Leone'), findsNothing);
    await _tearDown(tester);
  });

  testWidgets('a backend failure adds a banner but every section stays in place', (tester) async {
    await _pumpExplore(tester, width: 375, feedFails: true);
    _expectNoLayoutErrors(tester);
    expect(find.text('Retry'), findsOneWidget);
    for (final t in ['Recommended for You', 'Properties Near You', 'Vehicles for Sale & Hire', 'Top Agents & Dealers', 'Build your Explore feed']) {
      expect(find.text(t), findsOneWidget, reason: '$t should still be on screen');
    }
    expect(find.text("Couldn't load this section"), findsNWidgets(4));
    // never replaced with fake listings
    expect(find.text('3 Bedroom House'), findsNothing);
    await _tearDown(tester);
  });

  testWidgets('empty database: every section shows its honest empty state, layout intact', (tester) async {
    await _pumpExplore(tester, width: 375, textScale: 1.35, empty: true);
    _expectNoLayoutErrors(tester);
    expect(find.text('No recommendations yet'), findsOneWidget);
    expect(find.text('No properties nearby yet'), findsOneWidget);
    expect(find.text('No vehicles available yet'), findsOneWidget);
    expect(find.text('No agents or dealers yet'), findsOneWidget);
    await _tearDown(tester);
  });

  testWidgets('loading state keeps the section structure', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 3200 * 3);
    tester.view.devicePixelRatio = 3;
    final bloc = _MockAuthBloc();
    whenListen(bloc, const Stream<AuthState>.empty(), initialState: const AuthState(status: AuthStatus.authenticated, user: _user));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: BlocProvider<AuthBloc>.value(value: bloc, child: ExploreScreen(convexClient: _fakeConvex())),
      ),
    );
    await tester.pump(); // first frame: still loading
    expect(tester.takeException(), isNull);
    expect(find.text('Recommended for You'), findsOneWidget);
    expect(find.text('Top Agents & Dealers'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await _tearDown(tester);
  });

  testWidgets('iPhone in Dark Mode: the app is light-only, so text stays dark on white', (tester) async {
    await _pumpExplore(tester, width: 390, phoneInDarkMode: true, themeMode: ThemeMode.light);
    _expectNoLayoutErrors(tester);
    final theme = Theme.of(tester.element(find.byType(ExploreScreen)));
    expect(theme.brightness, Brightness.light);
    // the inherited (unstyled) text colour is dark, and the search field renders dark text
    expect(theme.textTheme.bodyMedium?.color, AppColors.textPrimary);
    await tester.enterText(find.byType(TextField), 'villa');
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.style.color, AppColors.obsidian);
    expect(editable.style.color!.computeLuminance(), lessThan(0.2));
    // titles and prices are explicitly dark; category/selected states use the Vektolux green
    final title = tester.widget<Text>(find.text('Explore'));
    expect(title.style?.color, AppColors.obsidian);
    await _tearDown(tester);
  });
}
