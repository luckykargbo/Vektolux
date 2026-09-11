// lib/features/auth/presentation/bloc/auth_event.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Auth BLoC Events
// ═══════════════════════════════════════════════════════════════════════

import 'package:equatable/equatable.dart';
import '../../domain/entities/user_entity.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Triggered on splash screen init — checks SQLite, Convex, and session.
class SplashInitEvent extends AuthEvent {
  const SplashInitEvent();
}

/// User selected their role during registration.
class RoleSelectedEvent extends AuthEvent {
  final UserRole role;
  const RoleSelectedEvent(this.role);

  @override
  List<Object?> get props => [role];
}

/// Registration form submitted.
class RegisterSubmittedEvent extends AuthEvent {
  final String name;
  final String email;
  final String phone;
  final String password;
  final UserRole role;
  final String? avatarUrl;
  final String? businessName;
  final String? tinNumber;
  final String? documentStorageId;
  final String? documentUrl;

  const RegisterSubmittedEvent({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
    required this.role,
    this.avatarUrl,
    this.businessName,
    this.tinNumber,
    this.documentStorageId,
    this.documentUrl,
  });

  @override
  List<Object?> get props => [
        name,
        email,
        phone,
        password,
        role,
        avatarUrl,
        businessName,
        tinNumber,
        documentStorageId,
        documentUrl,
      ];
}

/// Login form submitted.
class LoginSubmittedEvent extends AuthEvent {
  final String identifier; // email or phone
  final String password;

  const LoginSubmittedEvent({
    required this.identifier,
    required this.password,
  });

  @override
  List<Object?> get props => [identifier, password];
}

/// User requests logout.
class LogoutEvent extends AuthEvent {
  const LogoutEvent();
}

/// User requests profile update (name, phone, avatarUrl).
class UpdateUserProfileEvent extends AuthEvent {
  final String? name;
  final String? phone;
  final String? avatarUrl;

  const UpdateUserProfileEvent({
    this.name,
    this.phone,
    this.avatarUrl,
  });

  @override
  List<Object?> get props => [name, phone, avatarUrl];
}

/// User upgraded or switched active role.
class UserRoleUpdatedEvent extends AuthEvent {
  final UserRole newRole;

  const UserRoleUpdatedEvent(this.newRole);

  @override
  List<Object?> get props => [newRole];
}

/// Refresh current user session and verification status from backend.
class RefreshUserSessionEvent extends AuthEvent {
  const RefreshUserSessionEvent();
}


/// User switches between passenger and driver mode.
class SwitchUserModeEvent extends AuthEvent {
  final String targetMode; // 'passenger' | 'driver'

  const SwitchUserModeEvent(this.targetMode);

  @override
  List<Object?> get props => [targetMode];
}

