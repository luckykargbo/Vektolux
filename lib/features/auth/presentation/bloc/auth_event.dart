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
  final String? businessName;
  final String? tinNumber;

  const RegisterSubmittedEvent({
    required this.name,
    required this.email,
    required this.phone,
    required this.password,
    required this.role,
    this.businessName,
    this.tinNumber,
  });

  @override
  List<Object?> get props => [name, email, phone, password, role, businessName, tinNumber];
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
