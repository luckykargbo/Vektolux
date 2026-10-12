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
  ///
  /// Throws [MfaRequiredException] when the account has two-factor authentication enabled and no
  /// (valid) [totpCode] was supplied: no session exists until the second factor is verified.
  Future<UserEntity> login({
    required String identifier,
    required String password,
    String? totpCode,
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

  /// Social sign-in returning user + hasPhone flag.
  Future<({UserEntity user, bool hasPhone})> socialSignIn({
    required String email,
    String? name,
    String? avatarUrl,
    required String provider,
    required String providerId,
    String? nonce,
  });

  /// Social sign-in step 2 for an account with two-factor authentication: trades the single-use
  /// challenge from [MfaRequiredException.challengeToken] plus an authenticator / backup code for the
  /// session. Throws [MfaChallengeException] (with [MfaChallengeException.retryable]) when refused.
  Future<({UserEntity user, bool hasPhone})> completeSocialMfa({
    required String challengeToken,
    required String totpCode,
  });

  /// Burns a pending social MFA challenge (user backed out). Best effort; never throws.
  Future<void> cancelSocialMfa(String challengeToken);

  /// Apple sign-in step 1: a one-time server nonce. Give Apple only `nonceHash`; send the raw
  /// `nonce` back with the identity token.
  Future<({String nonce, String nonceHash})> createOAuthChallenge({required String provider});

  /// Proves ownership of the account's email with the code that was mailed to it.
  Future<void> verifyEmail({required String code});

  /// Sends a fresh email-verification code to the signed-in user's own address.
  Future<void> resendEmailVerification();

  /// Authoritative email-verification / linked-provider status from the backend.
  Future<AccountSecurityStatus> getAccountSecurityStatus();

  /// Links a Google/Apple identity to the signed-in account. [secret] is the Account PIN (or the
  /// account password when no PIN exists) whenever [AccountSecurityStatus.needsSecret] is true.
  /// Throws [AuthException] with the server's message when linking is refused.
  Future<void> linkSocialIdentity({
    required String provider,
    required String providerId,
    String? nonce,
    String? secret,
  });

  /// Link Sierra Leone phone number to complete profile setup, or change it.
  /// Changing an existing number requires [currentPin] when the account has a PIN.
  Future<UserEntity> linkPhoneNumber({
    required String userId,
    required String phoneNumber,
    String? currentPin,
  });
}

/// Authentication and credential failure exceptions (invalid password, account not found).
/// What the backend reports about the signed-in account's email proof and linked providers.
class AccountSecurityStatus {
  final String email;
  final bool emailVerified;
  final bool hasPin;
  final bool hasPassword;
  final bool googleLinked;
  final bool appleLinked;

  const AccountSecurityStatus({
    required this.email,
    required this.emailVerified,
    required this.hasPin,
    required this.hasPassword,
    required this.googleLinked,
    required this.appleLinked,
  });

  /// Linking re-authenticates with the PIN, or the password when there is no PIN.
  bool get needsSecret => hasPin || hasPassword;
  bool isLinked(String provider) => provider == 'apple' ? appleLinked : googleLinked;
}

/// The server accepted the credentials / provider identity but requires a second factor first.
/// [challengeToken] is set for Google/Apple sign-in (use completeSocialMfa); it is null for password
/// login (call login again with a totpCode).
class MfaRequiredException implements Exception {
  final String message;
  final String? challengeToken;
  final DateTime? expiresAt;
  const MfaRequiredException(this.message, {this.challengeToken, this.expiresAt});

  bool get isSocial => challengeToken != null;

  @override
  String toString() => message;
}

/// A social MFA code was refused. [retryable] is true when the same challenge may be tried again
/// (wrong code); false when it is spent (expired, locked, too many attempts) and sign-in must restart.
class MfaChallengeException implements Exception {
  final String message;
  final bool retryable;
  const MfaChallengeException(this.message, {required this.retryable});

  @override
  String toString() => message;
}

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
