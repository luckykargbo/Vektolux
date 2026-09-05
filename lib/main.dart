// lib/main.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Application Entry Point
// Initializes core services and launches the MaterialApp.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'core/database/app_database.dart';
import 'core/network/connectivity_monitor.dart';
import 'core/network/convex_client_wrapper.dart';
import 'core/sync/offline_sync_engine.dart';
import 'core/constants/app_constants.dart';
import 'features/auth/auth.dart';
import 'features/mobility/presentation/bloc/mobility_bloc.dart';
import 'features/mobility/data/repositories/mobility_repository_impl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── Initialize Core Services ──────────────────────────────────────
  final database = AppDatabase();
  final convexClient = ConvexClientWrapper(
    deploymentUrl: ApiConstants.convexUrl,
  );
  final connectivityMonitor = ConnectivityMonitor();

  final syncEngine = OfflineSyncEngine(
    database: database,
    convexClient: convexClient,
    connectivityMonitor: connectivityMonitor,
  );

  await syncEngine.initialize();

  // ── Launch App ────────────────────────────────────────────────────
  runApp(VektoluxApp(
    syncEngine: syncEngine,
    database: database,
    convexClient: convexClient,
  ));
}

class VektoluxApp extends StatelessWidget {
  final OfflineSyncEngine syncEngine;
  final AppDatabase database;
  final ConvexClientWrapper convexClient;

  const VektoluxApp({
    super.key,
    required this.syncEngine,
    required this.database,
    required this.convexClient,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: database),
        RepositoryProvider<ConvexClientWrapper>.value(value: convexClient),
        RepositoryProvider<OfflineSyncEngine>.value(value: syncEngine),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              repository: AuthRepositoryImpl(
                convexClient: convexClient,
                usersDao: database.cachedUsersDao,
              ),
            ),
          ),
          BlocProvider<MobilityBloc>(
            create: (context) => MobilityBloc(
              repository: MobilityRepositoryImpl(
                ridesDao: database.cachedRidesDao,
                convexClient: convexClient,
                syncEngine: syncEngine,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          title: 'Vektolux',
          debugShowCheckedModeBanner: false,

          // ── Theme ───────────────────────────────────────────────────
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,

          // ── Initial Screen ──────────────────────────────────────────
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
