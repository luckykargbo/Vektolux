// lib/features/auth/data/repositories/auth_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Auth Repository Implementation
// Combines Convex backend calls with local SQLite session caching.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'package:logger/logger.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/cached_users_dao.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final ConvexClientWrapper _convexClient;
  final CachedUsersDao _usersDao;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  AuthRepositoryImpl({
    required ConvexClientWrapper convexClient,
    required CachedUsersDao usersDao,
  })  : _convexClient = convexClient,
        _usersDao = usersDao;

  @override
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
  }) async {
    final result = await _convexClient.mutation(
      'auth:registerUser',
      args: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role.convexValue,
        if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
        if (businessName != null && businessName.isNotEmpty) 'businessName': businessName,
        if (tinNumber != null && tinNumber.isNotEmpty) 'tinNumber': tinNumber,
        if (documentStorageId != null && documentStorageId.isNotEmpty) 'documentStorageId': documentStorageId,
        if (documentUrl != null && documentUrl.isNotEmpty) 'documentUrl': documentUrl,
      },
    );

    if (!result.success || result.value == null) {
      throw Exception(result.errorMessage ?? 'Registration failed');
    }

    if (result.value is! Map<String, dynamic>) {
      throw Exception(result.errorMessage ?? 'Invalid server response');
    }

    final data = result.value as Map<String, dynamic>;
    if (data['success'] == false || data['userId'] == null || data['sessionToken'] == null) {
      throw Exception(data['errorMessage']?.toString() ?? result.errorMessage ?? 'Registration failed: Missing credentials');
    }

    final isRestrictedRole = role == UserRole.agent || role == UserRole.merchant;
    final user = UserEntity(
      id: data['userId']?.toString() ?? '',
      name: data['name']?.toString() ?? name,
      email: data['email']?.toString() ?? email,
      phone: data['phone']?.toString() ?? phone,
      role: UserRoleX.fromConvex(data['role']?.toString() ?? role.convexValue),
      avatarUrl: data['avatarUrl']?.toString() ?? avatarUrl,
      sessionToken: data['sessionToken']?.toString(),
      verificationStatus: isRestrictedRole ? 'pending' : 'unverified',
      businessName: businessName,
      tinNumber: tinNumber,
      documentUrl: documentUrl,
    );

    // Cache session locally
    await _cacheUser(user);
    if (user.sessionToken != null) {
      _convexClient.setAuthToken(user.sessionToken!);
    }

    _log.i('User registered: ${user.email} as ${user.role.displayName}');
    return user;
  }

  @override
  Future<UserEntity> login({
    required String identifier,
    required String password,
  }) async {
    final result = await _convexClient.mutation(
      'auth:loginWithPhoneOrEmail',
      args: {
        'identifier': identifier,
        'password': password,
      },
    );

    if (!result.success || result.value == null) {
      throw Exception(result.errorMessage ?? 'Login failed');
    }

    if (result.value is! Map<String, dynamic>) {
      throw Exception(result.errorMessage ?? 'Invalid server response');
    }

    final data = result.value as Map<String, dynamic>;
    if (data['success'] == false || data['userId'] == null || data['sessionToken'] == null) {
      throw Exception(data['errorMessage']?.toString() ?? result.errorMessage ?? 'Login failed: Invalid credentials');
    }

    final user = UserEntity(
      id: data['userId']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      email: data['email']?.toString() ?? identifier,
      phone: data['phone']?.toString() ?? identifier,
      role: UserRoleX.fromConvex(data['role']?.toString() ?? 'client'),
      isVerified: data['isVerified'] as bool? ?? false,
      avatarUrl: data['avatarUrl'] as String?,
      walletAddress: data['walletAddress'] as String?,
      sessionToken: data['sessionToken']?.toString(),
      activeMode: data['active_mode']?.toString() ?? 'passenger',
      isDriverVerified: data['is_driver_verified'] as bool? ?? (data['role'] == 'driver'),
      driverStatus: data['driver_status']?.toString() ?? 'offline',
      verificationStatus: data['verificationStatus']?.toString() ?? (data['isVerified'] == true ? 'verified' : 'unverified'),
      businessName: data['businessName'] as String?,
      tinNumber: data['tinNumber'] as String?,
      documentUrl: data['documentUrl'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      verifiedAt: data['verifiedAt'] as int?,
    );

    await _cacheUser(user);
    if (user.sessionToken != null) {
      _convexClient.setAuthToken(user.sessionToken!);
    }

    _log.i('User logged in: ${user.email}');
    return user;
  }

  @override
  Future<UserEntity?> getActiveSession() async {
    try {
      final cached = await _usersDao.getActiveSession();
      if (cached == null) return null;

      return UserEntity(
        id: cached.id,
        name: cached.name,
        email: cached.email,
        phone: cached.phone,
        role: UserRoleX.fromConvex(cached.role),
        isVerified: cached.isVerified,
        avatarUrl: cached.avatarUrl,
        walletAddress: cached.walletAddress,
        sessionToken: cached.sessionToken,
        activeMode: cached.role == 'driver' ? 'driver' : 'passenger',
        isDriverVerified: cached.role == 'driver',
        driverStatus: cached.role == 'driver' ? 'online' : 'offline',
      );
    } catch (e) {
      _log.e('Failed to read cached session: $e');
      return null;
    }
  }

  @override
  Future<UserEntity?> validateSession({
    required String userId,
    required String sessionToken,
  }) async {
    try {
      final result = await _convexClient.query(
        'auth:getUserSession',
        args: {
          'userId': userId,
          'sessionToken': sessionToken,
        },
      );

      if (!result.success || result.value == null) return null;

      final data = result.value as Map<String, dynamic>;
      final user = UserEntity(
        id: data['userId'] as String,
        name: data['name'] as String,
        email: data['email'] as String,
        phone: data['phone'] as String,
        role: UserRoleX.fromConvex(data['role'] as String),
        isVerified: data['isVerified'] as bool? ?? false,
        avatarUrl: data['avatarUrl'] as String?,
        walletAddress: data['walletAddress'] as String?,
        sessionToken: sessionToken,
        activeMode: data['active_mode']?.toString() ?? 'passenger',
        isDriverVerified: data['is_driver_verified'] as bool? ?? (data['role'] == 'driver'),
        driverStatus: data['driver_status']?.toString() ?? 'offline',
        verificationStatus: data['verificationStatus']?.toString() ?? (data['isVerified'] == true ? 'verified' : 'unverified'),
        businessName: data['businessName'] as String?,
        tinNumber: data['tinNumber'] as String?,
        documentUrl: data['documentUrl'] as String?,
        rejectionReason: data['rejectionReason'] as String?,
        verifiedAt: data['verifiedAt'] as int?,
      );

      // Refresh local cache with latest data
      await _cacheUser(user);
      _convexClient.setAuthToken(sessionToken);

      return user;
    } catch (e) {
      _log.w('Session validation failed (offline?): $e');
      return null;
    }
  }

  @override
  Future<void> logout() async {
    await _usersDao.clearSession();
    _convexClient.clearAuth();
    _log.i('User session cleared');
  }

  @override
  Future<bool> checkConvexHealth() async {
    try {
      final result = await _convexClient.query(
        'users:getUserById',
        args: {'userId': 'health_check_ping'},
      );
      return result.success || result.errorMessage == null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<UserEntity> updateUserProfile({
    required String userId,
    String? name,
    String? phone,
    String? avatarUrl,
  }) async {
    final current = await getActiveSession();
    if (current == null) {
      throw Exception('No active session found.');
    }

    try {
      await _convexClient.mutation(
        'users:updateUserProfile',
        args: {
          'userId': userId,
          if (name != null) 'name': name,
          if (phone != null) 'phone': phone,
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
        },
      );
    } catch (e) {
      _log.w('Could not sync profile update to Convex (offline mode?): $e');
    }

    final updated = current.copyWith(
      name: name ?? current.name,
      phone: phone ?? current.phone,
      avatarUrl: avatarUrl ?? current.avatarUrl,
    );

    await _cacheUser(updated);
    _log.i('Profile updated and cached: ${updated.name}');
    return updated;
  }

  @override
  Future<UserEntity> switchUserMode({
    required String userId,
    required String targetMode,
  }) async {
    final result = await _convexClient.mutation(
      'users:switchUserMode',
      args: {
        'userId': userId,
        'targetMode': targetMode,
      },
    );

    if (!result.success || result.value == null) {
      throw Exception(result.errorMessage ?? 'Failed to switch mode');
    }

    final data = result.value as Map<String, dynamic>;
    if (data['success'] == false) {
      throw Exception(data['message']?.toString() ?? 'Mode switch rejected');
    }

    final current = await getActiveSession();
    final updated = (current ??
            UserEntity(
              id: userId,
              name: '',
              email: '',
              phone: '',
              role: targetMode == 'driver' ? UserRole.driver : UserRole.client,
            ))
        .copyWith(
      activeMode: targetMode,
      role: targetMode == 'driver' ? UserRole.driver : UserRole.client,
      driverStatus: targetMode == 'driver' ? 'online' : 'offline',
    );

    await _cacheUser(updated);
    _log.i('User switched mode to $targetMode');
    return updated;
  }

  // ── Private Helpers ──────────────────────────────────────────────

  Future<void> _cacheUser(UserEntity user) async {
    await _usersDao.saveUserSession(
      CachedUsersTableCompanion.insert(
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role.convexValue,
        isVerified: Value(user.isVerified),
        avatarUrl: Value(user.avatarUrl),
        walletAddress: Value(user.walletAddress),
        sessionToken: Value(user.sessionToken),
        isActiveSession: const Value(true),
        cachedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
