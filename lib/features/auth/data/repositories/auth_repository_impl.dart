// lib/features/auth/data/repositories/auth_repository_impl.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Auth Repository Implementation
// Direct Convex Cloud backend integration with SharedPreferences session persistence.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../../../core/utils/safe_parser.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final ConvexClientWrapper _convexClient;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  static const String _keySessionToken = 'vkt_session_token';
  static const String _keyUserId = 'vkt_user_id';
  static const String _keyUserData = 'vkt_user_data';

  AuthRepositoryImpl({
    required ConvexClientWrapper convexClient,
  }) : _convexClient = convexClient;

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
    String? address,
    String? region,
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
        if (address != null && address.isNotEmpty) 'address': address,
        if (region != null && region.isNotEmpty) 'region': region,
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
      address: data['address']?.toString() ?? address,
      region: data['region']?.toString() ?? region,
    );

    // Save session in SharedPreferences
    await _cacheUser(user);
    if (user.sessionToken != null) {
      _convexClient.setAuthToken(user.sessionToken!);
    }

    _log.i('User registered on Convex Cloud: ${user.email} as ${user.role.displayName}');
    return user;
  }

  @override
  Future<UserEntity> login({
    required String identifier,
    required String password,
  }) async {
    final sanitizedIdentifier = identifier.trim().contains('@')
        ? identifier.trim().toLowerCase()
        : identifier.trim();

    final result = await _convexClient.mutation(
      'auth:loginWithPhoneOrEmail',
      args: {
        'identifier': sanitizedIdentifier,
        'password': password,
      },
    );

    if (!result.success) {
      throw NetworkException(result.errorMessage ?? 'Connection error. Please check your internet connection.');
    }

    if (result.value == null || result.value is! Map<String, dynamic>) {
      throw const DataParseException('Malformed response received from server.');
    }

    final data = result.value as Map<String, dynamic>;
    if (data['success'] == false || data['userId'] == null || data['sessionToken'] == null) {
      final msg = data['errorMessage']?.toString() ?? result.errorMessage ?? 'No account found with that email or phone number.';
      throw AuthException(msg, isCredentialFailure: true);
    }

    UserEntity user;
    try {
      user = UserEntity(
        id: asString(data['userId']),
        name: asString(data['name']),
        email: asString(data['email'], identifier),
        phone: asString(data['phone'], identifier),
        role: UserRoleX.fromConvex(asString(data['role'], 'client')),
        isVerified: asBool(data['isVerified']),
        isVerifiedSeller: asBool(data['isVerifiedSeller'], false),
        avatarUrl: data['avatarUrl'] as String?,
        walletAddress: data['walletAddress'] as String?,
        sessionToken: data['sessionToken']?.toString(),
        activeMode: asString(data['active_mode'], 'passenger'),
        isDriverVerified: asBool(data['is_driver_verified'], data['role'] == 'driver'),
        driverStatus: asString(data['driver_status'], 'offline'),
        verificationStatus: asString(data['verificationStatus'], asBool(data['isVerified']) ? 'verified' : 'unverified'),
        businessName: data['businessName'] as String?,
        tinNumber: data['tinNumber'] as String?,
        documentUrl: data['documentUrl'] as String?,
        rejectionReason: data['rejectionReason'] as String?,
        verifiedAt: (data['verifiedAt'] as num?)?.toInt(),
        bio: data['bio'] as String?,
        kycStatus: data['kycStatus'] as String?,
        address: data['address'] as String?,
        region: data['region'] as String?,
      );
    } catch (e, stack) {
      _log.e('Failed to parse user document on login: $e', error: e, stackTrace: stack);
      throw DataParseException('Failed to parse user profile: $e');
    }

    await _cacheUser(user);
    if (user.sessionToken != null) {
      _convexClient.setAuthToken(user.sessionToken!);
    }

    _log.i('User logged in from Convex Cloud: ${user.email}');
    return user;
  }

  @override
  Future<UserEntity?> getActiveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString(_keySessionToken);
      final userId = prefs.getString(_keyUserId);

      if (sessionToken == null || userId == null) return null;

      final userDataStr = prefs.getString(_keyUserData);
      if (userDataStr != null) {
        try {
          final decoded = jsonDecode(userDataStr) as Map<String, dynamic>;
          final cachedUser = UserEntity(
            id: asString(decoded['id'], userId),
            name: asString(decoded['name']),
            email: asString(decoded['email']),
            phone: asString(decoded['phone']),
            role: UserRoleX.fromConvex(asString(decoded['role'], 'client')),
            isVerified: asBool(decoded['isVerified']),
            isVerifiedSeller: asBool(decoded['isVerifiedSeller'], false),
            avatarUrl: decoded['avatarUrl'] as String?,
            walletAddress: decoded['walletAddress'] as String?,
            sessionToken: sessionToken,
            activeMode: asString(decoded['activeMode'], 'passenger'),
            isDriverVerified: asBool(decoded['isDriverVerified']),
            driverStatus: asString(decoded['driverStatus'], 'offline'),
            verificationStatus: asString(decoded['verificationStatus']),
            businessName: decoded['businessName'] as String?,
            tinNumber: decoded['tinNumber'] as String?,
            documentUrl: decoded['documentUrl'] as String?,
            address: decoded['address'] as String?,
            region: decoded['region'] as String?,
            bio: decoded['bio'] as String?,
            kycStatus: decoded['kycStatus'] as String?,
          );
          _convexClient.setAuthToken(sessionToken);
          return cachedUser;
        } catch (_) {}
      }

      // If jsonDecode failed, validate directly with Convex Cloud
      return await validateSession(userId: userId, sessionToken: sessionToken);
    } catch (e) {
      _log.e('Failed to read active session: $e');
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
      if (result.value is! Map<String, dynamic>) return null;

      final data = result.value as Map<String, dynamic>;
      final user = UserEntity(
        id: asString(data['userId']),
        name: asString(data['name']),
        email: asString(data['email']),
        phone: asString(data['phone']),
        role: UserRoleX.fromConvex(asString(data['role'], 'client')),
        isVerified: asBool(data['isVerified']),
        isVerifiedSeller: asBool(data['isVerifiedSeller'], false),
        avatarUrl: data['avatarUrl'] as String?,
        walletAddress: data['walletAddress'] as String?,
        sessionToken: sessionToken,
        activeMode: asString(data['active_mode'], 'passenger'),
        isDriverVerified: asBool(data['is_driver_verified'], data['role'] == 'driver'),
        driverStatus: asString(data['driver_status'], 'offline'),
        verificationStatus: asString(data['verificationStatus'], asBool(data['isVerified']) ? 'verified' : 'unverified'),
        businessName: data['businessName'] as String?,
        tinNumber: data['tinNumber'] as String?,
        documentUrl: data['documentUrl'] as String?,
        rejectionReason: data['rejectionReason'] as String?,
        verifiedAt: (data['verifiedAt'] as num?)?.toInt(),
        bio: data['bio'] as String?,
        kycStatus: data['kycStatus'] as String?,
        address: data['address'] as String?,
        region: data['region'] as String?,
      );

      // Refresh stored session
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySessionToken);
      await prefs.remove(_keyUserId);
      await prefs.remove(_keyUserData);
    } catch (_) {}

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
    String? bio,
    String? address,
    String? region,
  }) async {
    final current = await getActiveSession();
    if (current == null) {
      throw Exception('No active session found.');
    }

    final result = await _convexClient.mutation(
      'users:updateUserProfile',
      args: {
        'userId': userId,
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (bio != null) 'bio': bio,
        if (address != null) 'address': address,
        if (region != null) 'region': region,
      },
    );

    if (!result.success) {
      throw Exception(result.errorMessage ?? 'Failed to update profile on Convex cloud');
    }
    if (result.value == false) {
      throw Exception('Profile update was rejected by Convex server');
    }

    final updated = current.copyWith(
      name: name ?? current.name,
      phone: phone ?? current.phone,
      avatarUrl: avatarUrl ?? current.avatarUrl,
      bio: bio ?? current.bio,
      address: address ?? current.address,
      region: region ?? current.region,
    );

    await _cacheUser(updated);
    _log.i('Profile updated directly on Convex Cloud: ${updated.name}');
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
    _log.i('User switched mode directly on Convex Cloud to $targetMode');
    return updated;
  }

  // ── Private Helpers ──────────────────────────────────────────────

  Future<void> _cacheUser(UserEntity user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (user.sessionToken != null) {
        await prefs.setString(_keySessionToken, user.sessionToken!);
      }
      await prefs.setString(_keyUserId, user.id);
      final jsonMap = {
        'id': user.id,
        'name': user.name,
        'email': user.email,
        'phone': user.phone,
        'role': user.role.convexValue,
        'isVerified': user.isVerified,
        'isVerifiedSeller': user.isVerifiedSeller,
        'avatarUrl': user.avatarUrl,
        'walletAddress': user.walletAddress,
        'activeMode': user.activeMode,
        'isDriverVerified': user.isDriverVerified,
        'driverStatus': user.driverStatus,
        'verificationStatus': user.verificationStatus,
        'businessName': user.businessName,
        'tinNumber': user.tinNumber,
        'documentUrl': user.documentUrl,
        'address': user.address,
        'region': user.region,
        'bio': user.bio,
        'kycStatus': user.kycStatus,
      };
      await prefs.setString(_keyUserData, jsonEncode(jsonMap));
    } catch (e) {
      _log.w('Could not persist session to SharedPreferences: $e');
    }
  }
}
