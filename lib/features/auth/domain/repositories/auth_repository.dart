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

  /// Update user profile (name, phone, avatarUrl) and refresh cache.
  Future<UserEntity> updateUserProfile({
    required String userId,
    String? name,
    String? phone,
    String? avatarUrl,
  });
}
