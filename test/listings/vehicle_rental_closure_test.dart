// Vehicle rental is no longer an in-app transaction: a rental listing offers "contact the dealer"
// (the existing conversation), never an in-app rental checkout / escrow. Vehicle SALES keep their
// inspection and purchase-escrow actions.

import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/auth/domain/entities/user_entity.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_event.dart';
import 'package:vektolux/features/auth/presentation/bloc/auth_state.dart';
import 'package:vektolux/features/listings/presentation/views/vehicle_detail_screen.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

ConvexClientWrapper _client(List<String> calls) => ConvexClientWrapper(
      deploymentUrl: 'https://example.invalid',
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        calls.add(body['path'] as String);
        return http.Response(jsonEncode({'status': 'success', 'value': <dynamic>[]}), 200);
      }),
    );

Future<void> _pump(WidgetTester tester, Widget screen, List<String> calls) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final bloc = _MockAuthBloc();
  whenListen(bloc, const Stream<AuthState>.empty(), initialState: const AuthState(status: AuthStatus.unauthenticated));
  await tester.pumpWidget(
    RepositoryProvider<ConvexClientWrapper>.value(
      value: _client(calls),
      child: BlocProvider<AuthBloc>.value(value: bloc, child: MaterialApp(home: screen)),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('a rental listing offers "contact the dealer", never an in-app rental checkout', (tester) async {
    final calls = <String>[];
    await _pump(
      tester,
      const VehicleDetailScreen(
        id: 'veh_rent',
        make: 'Toyota',
        model: 'Hilux',
        year: 2022,
        vehicleType: 'car_rental',
        listingIntent: 'rental',
        pricePerDay: 750,
        ownerId: 'owner_1',
      ),
      calls,
    );
    expect(find.text('Contact dealer to rent'), findsOneWidget);
    expect(find.text('Rent with Escrow'), findsNothing);
    expect(find.text('Buy with Escrow'), findsNothing);
    expect(calls.where((c) => c.startsWith('bookings:') || c.startsWith('escrow:initiate')), isEmpty);
  });

  testWidgets('a sale listing keeps pre-purchase inspection and purchase escrow', (tester) async {
    await _pump(
      tester,
      const VehicleDetailScreen(
        id: 'veh_sale',
        make: 'Toyota',
        model: 'Prado',
        year: 2022,
        vehicleType: 'car_sale',
        listingIntent: 'sale',
        salePrice: 900000,
        ownerId: 'owner_1',
      ),
      <String>[],
    );
    expect(find.text('Buy with Escrow'), findsOneWidget);
    expect(find.text('Inspect'), findsOneWidget);
    expect(find.text('Contact dealer to rent'), findsNothing);
    expect(find.text('Rent with Escrow'), findsNothing);
  });

  testWidgets('a per-trip haulage truck is hired through its owner, never bought with purchase escrow', (tester) async {
    final calls = <String>[];
    await _pump(
      tester,
      const VehicleDetailScreen(
        id: 'veh_truck',
        make: 'Mack',
        model: 'Granite',
        year: 2019,
        vehicleType: 'sand_dump_truck',
        listingIntent: 'rental',
        salePrice: 2500,
        ownerId: 'owner_1',
      ),
      calls,
    );
    expect(find.text('Contact owner to hire'), findsOneWidget);
    expect(find.text('Buy with Escrow'), findsNothing);
    expect(find.text('Inspect'), findsNothing);
    expect(calls.where((c) => c.startsWith('bookings:') || c.startsWith('escrow:initiate')), isEmpty);
  });

  testWidgets('a hire-only vehicle type never offers purchase escrow even if the intent is mislabelled as sale', (tester) async {
    await _pump(
      tester,
      const VehicleDetailScreen(
        id: 'veh_van',
        make: 'Toyota',
        model: 'HiAce',
        year: 2020,
        vehicleType: 'delivery_van',
        listingIntent: 'sale',
        salePrice: 500,
        ownerId: 'owner_1',
      ),
      <String>[],
    );
    expect(find.text('Buy with Escrow'), findsNothing);
    expect(find.text('Contact owner to hire'), findsOneWidget);
  });

  testWidgets('a sale listing without a price offers no invented price', (tester) async {
    await _pump(
      tester,
      const VehicleDetailScreen(
        id: 'veh_noprice',
        make: 'Toyota',
        model: 'Corolla',
        year: 2018,
        vehicleType: 'car_sale',
        listingIntent: 'sale',
        ownerId: 'owner_1',
      ),
      <String>[],
    );
    // the price label is shown in several places on this screen, never as an invented amount
    expect(find.text('Contact for Price'), findsWidgets);
    expect(find.textContaining('25,000'), findsNothing);
    expect(find.textContaining('25000'), findsNothing);
  });
}
