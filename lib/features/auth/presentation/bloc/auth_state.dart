// lib/features/auth/presentation/bloc/auth_state.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Auth BLoC State
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import '../../domain/entities/user_entity.dart';

enum AuthStatus {
  initial,
  splashChecking,
  unauthenticated,
  authenticated,
  needsPhoneSetup,
  registering,
  loggingIn,
  linkingPhone,
  error,
}

class AuthState extends Equatable {
  final AuthStatus status;
  final UserEntity? user;
  final UserRole? selectedRole;
  final String? errorMessage;
  final String? successMessage;

  // Splash health check indicators
  final bool isSqliteReady;
  final bool isConvexReachable;
  final bool hasExistingSession;
  final bool hasPhone;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.selectedRole,
    this.errorMessage,
    this.successMessage,
    this.isSqliteReady = false,
    this.isConvexReachable = false,
    this.hasExistingSession = false,
    this.hasPhone = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserEntity? user,
    bool clearUser = false,
    UserRole? selectedRole,
    bool clearSelectedRole = false,
    String? errorMessage,
    String? successMessage,
    bool? isSqliteReady,
    bool? isConvexReachable,
    bool? hasExistingSession,
    bool? hasPhone,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      selectedRole: clearSelectedRole ? null : (selectedRole ?? this.selectedRole),
      errorMessage: errorMessage,
      successMessage: successMessage,
      isSqliteReady: isSqliteReady ?? this.isSqliteReady,
      isConvexReachable: isConvexReachable ?? this.isConvexReachable,
      hasExistingSession: hasExistingSession ?? this.hasExistingSession,
      hasPhone: hasPhone ?? this.hasPhone,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;
  bool get isLoading =>
      status == AuthStatus.splashChecking ||
      status == AuthStatus.registering ||
      status == AuthStatus.loggingIn ||
      status == AuthStatus.linkingPhone;

  @override
  List<Object?> get props => [
        status,
        user,
        selectedRole,
        errorMessage,
        successMessage,
        isSqliteReady,
        isConvexReachable,
        hasExistingSession,
        hasPhone,
      ];
}

