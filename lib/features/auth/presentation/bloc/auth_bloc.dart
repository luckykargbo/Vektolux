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
    on<UpdateUserProfileEvent>(_onUpdateUserProfile);
    on<UserRoleUpdatedEvent>(_onUserRoleUpdated);
    on<SwitchUserModeEvent>(_onSwitchUserMode);
    on<RefreshUserSessionEvent>(_onRefreshUserSession);
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

      // Smooth splash transition (400ms)
      await _ensureMinDuration(stopwatch, const Duration(milliseconds: 400));

      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: activeUser,
      ));
    } else {
      // No session — route to onboarding / registration
      await _ensureMinDuration(stopwatch, const Duration(milliseconds: 400));

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
        avatarUrl: event.avatarUrl,
        businessName: event.businessName,
        tinNumber: event.tinNumber,
        documentStorageId: event.documentStorageId,
        documentUrl: event.documentUrl,
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

  // ═══════════════════════════════════════════════════════════════════
  //                      UPDATE USER PROFILE
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onUpdateUserProfile(
    UpdateUserProfileEvent event,
    Emitter<AuthState> emit,
  ) async {
    if (state.user == null) return;

    try {
      final updatedUser = await _repository.updateUserProfile(
        userId: state.user!.id,
        name: event.name,
        phone: event.phone,
        avatarUrl: event.avatarUrl,
      );

      emit(state.copyWith(
        user: updatedUser,
        successMessage: 'Profile updated successfully!',
      ));
    } catch (e) {
      _log.e('Failed to update profile: $e');
      emit(state.copyWith(
        errorMessage: 'Failed to update profile: $e',
      ));
    }
  }

  void _onUserRoleUpdated(
    UserRoleUpdatedEvent event,
    Emitter<AuthState> emit,
  ) {
    if (state.user != null) {
      final updatedUser = state.user!.copyWith(
        role: event.newRole,
        isVerified: true,
        verificationStatus: 'verified',
      );
      emit(state.copyWith(user: updatedUser));
      _log.i('User role updated in state: ${event.newRole.displayName}');
    }
  }

  Future<void> _onSwitchUserMode(
    SwitchUserModeEvent event,
    Emitter<AuthState> emit,
  ) async {
    final currentUser = state.user;
    if (currentUser == null) return;

    try {
      final updatedUser = await _repository.switchUserMode(
        userId: currentUser.id,
        targetMode: event.targetMode,
      );

      final modeLabel = event.targetMode == 'driver' ? 'Driver Workspace' : 'Passenger Mode';
      emit(state.copyWith(
        user: updatedUser,
        successMessage: 'Switched to $modeLabel',
      ));
      _log.i('User mode switched to ${event.targetMode}');
    } catch (e) {
      _log.e('Failed to switch mode: $e');
      emit(state.copyWith(
        errorMessage: 'Failed to switch mode: $e',
      ));
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //                    REFRESH USER SESSION
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _onRefreshUserSession(
    RefreshUserSessionEvent event,
    Emitter<AuthState> emit,
  ) async {
    final currentUser = state.user;
    if (currentUser == null || currentUser.sessionToken == null) return;

    try {
      final updatedUser = await _repository.validateSession(
        userId: currentUser.id,
        sessionToken: currentUser.sessionToken!,
      );

      if (updatedUser != null) {
        emit(state.copyWith(user: updatedUser));
        _log.i('Refreshed user session. Status: ${updatedUser.verificationStatus}');
      }
    } catch (e) {
      _log.w('Could not refresh user session: $e');
    }
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
