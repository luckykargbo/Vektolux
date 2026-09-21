// lib/main.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Application Entry Point
// Initializes core services and launches the MaterialApp with direct Convex Cloud connection.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'core/network/connectivity_monitor.dart';
import 'core/network/convex_client_wrapper.dart';
import 'core/constants/app_constants.dart';
import 'features/auth/auth.dart';
import 'features/mobility/presentation/bloc/mobility_bloc.dart';
import 'features/mobility/data/repositories/mobility_repository_impl.dart';
import 'core/services/notification_service.dart';
import 'core/services/payment_methods_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── Initialize Core Services ──────────────────────────────────────
  final convexClient = ConvexClientWrapper(
    deploymentUrl: ApiConstants.convexUrl,
  );
  // Optional connectivity monitor for connection status indicators
  ConnectivityMonitor();

  // ── Initialize Push Notification Service ──────────────────────────
  try {
    await NotificationService.instance.initialize(
      convexClient: convexClient,
    );
  } catch (e) {
    debugPrint('[Main] NotificationService initialization notice: $e');
  }

  // ── Initialize Payment Methods Service ────────────────────────────
  PaymentMethodsService.instance.initialize(
    convexClient: convexClient,
  );

  // ── Launch App ────────────────────────────────────────────────────
  runApp(VektoluxApp(
    convexClient: convexClient,
  ));
}

class VektoluxApp extends StatelessWidget {
  final ConvexClientWrapper convexClient;

  const VektoluxApp({
    super.key,
    required this.convexClient,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ConvexClientWrapper>.value(value: convexClient),
        RepositoryProvider<AuthRepository>(
          create: (ctx) => AuthRepositoryImpl(
            convexClient: convexClient,
          ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (context) => AuthBloc(
              repository: context.read<AuthRepository>(),
            ),
          ),
          BlocProvider<MobilityBloc>(
            create: (context) => MobilityBloc(
              repository: MobilityRepositoryImpl(
                convexClient: convexClient,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          title: 'Vektolux',
          debugShowCheckedModeBanner: false,

          // ── Theme ───────────────────────────────────────────────────
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,

          // ── Auth User Synchronization for Notifications ─────────────
          builder: (context, child) {
            return BlocListener<AuthBloc, AuthState>(
              listenWhen: (prev, curr) => prev.user?.id != curr.user?.id,
              listener: (context, state) {
                if (state.user != null) {
                  NotificationService.instance.updateUser(state.user!.id);
                } else {
                  NotificationService.instance.updateUser(null);
                }
              },
              child: child ?? const SizedBox.shrink(),
            );
          },

          // ── Initial Screen ──────────────────────────────────────────
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
