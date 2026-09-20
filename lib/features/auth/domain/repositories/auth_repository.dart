// lib/features/auth/domain/repositories/auth_repository.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Auth Repository Interface
// ═══════════════════════════════════════════════════════════════════════

import '../entities/user_entity.dart';

/// Abstract authentication repository.
/// Implementations handle Convex backend + SQLite local caching.
abstract class AuthRepository {
  /// Register a new user.
  Future<UserEntity> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
    String? avatarUrl,
    String? businessName,
    String? tinNumber,
    String? documentStorageId,
    String? documentUrl,
    String? address,
    String? region,
  });

  /// Login with email or phone + password.
  Future<UserEntity> login({
    required String identifier,
    required String password,
  });

  /// Get the locally cached active session.
  Future<UserEntity?> getActiveSession();

  /// Validate the cached session against Convex backend.
  Future<UserEntity?> validateSession({
    required String userId,
    required String sessionToken,
  });

  /// Logout — clear local session.
  Future<void> logout();

  /// Check if Convex backend is reachable.
  Future<bool> checkConvexHealth();

  /// Update user profile (name, phone, avatarUrl, bio, address, region) and refresh cache.
  Future<UserEntity> updateUserProfile({
    required String userId,
    String? name,
    String? phone,
    String? avatarUrl,
    String? bio,
    String? address,
    String? region,
  });

  /// Switch user active mode ('passenger' vs 'driver') and update backend & cache.
  Future<UserEntity> switchUserMode({
    required String userId,
    required String targetMode,
  });
}

/// Authentication and credential failure exceptions (invalid password, account not found).
class AuthException implements Exception {
  final String message;
  final bool isCredentialFailure;
  const AuthException(this.message, {this.isCredentialFailure = false});

  @override
  String toString() => message;
}

/// Network and server connectivity exceptions (timeout, offline, Convex down).
class NetworkException implements Exception {
  final String message;
  const NetworkException(this.message);

  @override
  String toString() => message;
}

/// Data parsing / schema mismatch exceptions (type casting, missing required payload).
class DataParseException implements Exception {
  final String message;
  const DataParseException(this.message);

  @override
  String toString() => message;
}
