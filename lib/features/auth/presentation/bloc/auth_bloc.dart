// lib/features/auth/presentation/bloc/auth_bloc.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Auth Master BLoC
// Manages splash health checks, registration, login, and session state.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';

import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repository;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  AuthBloc({required AuthRepository repository})
      : _repository = repository,
        super(const AuthState()) {
    on<SplashInitEvent>(_onSplashInit);
    on<RoleSelectedEvent>(_onRoleSelected);
    on<RegisterSubmittedEvent>(_onRegisterSubmitted);
    on<LoginSubmittedEvent>(_onLoginSubmitted);
    on<LogoutEvent>(_onLogout);
  }

  // ═══════════════════════════════════════════════════════════════════
  //                     SPLASH INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onSplashInit(
    SplashInitEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthStatus.splashChecking));

    final stopwatch = Stopwatch()..start();

    // 1. SQLite is ready
    emit(state.copyWith(isSqliteReady: true));

    // 2. Check Convex connectivity
    bool convexReachable = false;
    try {
      convexReachable = await _repository.checkConvexHealth();
    } catch (_) {
      convexReachable = false;
    }
    emit(state.copyWith(isConvexReachable: convexReachable));

    // 3. Check for existing cached session
    final cachedUser = await _repository.getActiveSession();

    if (cachedUser != null && cachedUser.sessionToken != null) {
      emit(state.copyWith(hasExistingSession: true));

      // Try to validate session with backend if online
      UserEntity? validatedUser;
      if (convexReachable) {
        validatedUser = await _repository.validateSession(
          userId: cachedUser.id,
          sessionToken: cachedUser.sessionToken!,
        );
      }

      final activeUser = validatedUser ?? cachedUser;

      // Ensure minimum 3.5s splash duration
      await _ensureMinDuration(stopwatch, const Duration(milliseconds: 3500));

      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: activeUser,
      ));
    } else {
      // No session — route to onboarding / registration
      await _ensureMinDuration(stopwatch, const Duration(milliseconds: 3500));

      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        hasExistingSession: false,
      ));
    }

    stopwatch.stop();
    _log.i('Splash completed in ${stopwatch.elapsedMilliseconds}ms');
  }

  // ═══════════════════════════════════════════════════════════════════
  //                       ROLE SELECTION
  // ═══════════════════════════════════════════════════════════════════

  void _onRoleSelected(
    RoleSelectedEvent event,
    Emitter<AuthState> emit,
  ) {
    emit(state.copyWith(selectedRole: event.role));
  }

  // ═══════════════════════════════════════════════════════════════════
  //                        REGISTRATION
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onRegisterSubmitted(
    RegisterSubmittedEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthStatus.registering));

    try {
      final user = await _repository.register(
        name: event.name,
        email: event.email,
        phone: event.phone,
        password: event.password,
        role: event.role,
        businessName: event.businessName,
        tinNumber: event.tinNumber,
      );

      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        successMessage: 'Welcome to Vektolux, ${user.name}!',
      ));
    } catch (e) {
      _log.e('Registration failed: $e');
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                           LOGIN
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onLoginSubmitted(
    LoginSubmittedEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(status: AuthStatus.loggingIn));

    try {
      final user = await _repository.login(
        identifier: event.identifier,
        password: event.password,
      );

      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        successMessage: 'Welcome back, ${user.name}!',
      ));
    } catch (e) {
      _log.e('Login failed: $e');
      emit(state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                          LOGOUT
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onLogout(
    LogoutEvent event,
    Emitter<AuthState> emit,
  ) async {
    await _repository.logout();
    emit(const AuthState(status: AuthStatus.unauthenticated));
    _log.i('User logged out');
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Ensure minimum splash duration for smooth UX.
  Future<void> _ensureMinDuration(
    Stopwatch stopwatch,
    Duration minDuration,
  ) async {
    final elapsed = stopwatch.elapsed;
    if (elapsed < minDuration) {
      await Future.delayed(minDuration - elapsed);
    }
  }
}
