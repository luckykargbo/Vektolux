// lib/features/verification/data/services/kyc_verification_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — eIDV & KYC Verification Service
// Unified provider interface supporting Local Dev Mock, Smile ID, and Prembly.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import '../../../../core/database/daos/cached_users_dao.dart';
import '../../../../core/network/convex_client_wrapper.dart';
import '../../domain/entities/verification_record.dart';

/// Result of an eIDV verification attempt.
class KycResult {
  final bool success;
  final String status; // 'verified', 'pending', 'rejected', 'unverified'
  final String? badge; // 'GREEN_TICK', 'NONE'
  final String? referenceId;
  final String? errorMessage;
  final Map<String, dynamic>? rawData;

  const KycResult({
    required this.success,
    required this.status,
    this.badge,
    this.referenceId,
    this.errorMessage,
    this.rawData,
  });

  bool get isVerified => success && status == 'verified';
}

/// Abstract contract for eIDV & KYC operations.
abstract class KycVerificationService {
  /// Validate format of Sierra Leone NIN or passport number.
  bool validateDocumentNumber({
    required IdDocumentType docType,
    required String docNumber,
  });

  /// Format validation error message.
  String? getValidationError({
    required IdDocumentType docType,
    required String docNumber,
  });

  /// Run simulated instant verification for development and testing.
  Future<KycResult> runMockVerification({
    required String userId,
    required String sessionToken,
    required IdDocumentType docType,
    required String docNumber,
  });

  /// Production check via Prembly Sierra Leone NIN verification API.
  Future<KycResult> verifyNinWithPrembly({
    required String nin,
    required String apiKey,
    required String appId,
  });

  /// Production biometric check via Smile ID.
  Future<KycResult> verifyBiometricsWithSmileId({
    required String userId,
    required String referenceId,
    required String selfieBase64,
    required String documentBase64,
    required String partnerId,
    required String apiKey,
  });

  /// Check live status from Convex backend.
  Future<KycResult> getVerificationStatus({required String userId});
}

/// Production implementation of KycVerificationService.
class KycVerificationServiceImpl implements KycVerificationService {
  final ConvexClientWrapper _convexClient;
  final CachedUsersDao? _usersDao;
  final http.Client _httpClient;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  KycVerificationServiceImpl({
    required ConvexClientWrapper convexClient,
    CachedUsersDao? usersDao,
    http.Client? httpClient,
  })  : _convexClient = convexClient,
        _usersDao = usersDao,
        _httpClient = httpClient ?? http.Client();

  @override
  bool validateDocumentNumber({
    required IdDocumentType docType,
    required String docNumber,
  }) {
    final cleaned = docNumber.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.isEmpty) return false;

    return switch (docType) {
      IdDocumentType.nationalId =>
        // Sierra Leone National Identification Number (NIN): 8 to 12 alphanumeric characters
        RegExp(r'^[A-Za-z0-9]{8,12}$').hasMatch(cleaned),
      IdDocumentType.ecowasCard =>
        // ECOWAS Biometric Card: 8 to 14 alphanumeric characters
        RegExp(r'^[A-Za-z0-9]{8,14}$').hasMatch(cleaned),
      IdDocumentType.passport =>
        // International ICAO Passport: 6 to 10 alphanumeric characters
        RegExp(r'^[A-Za-z0-9]{6,10}$').hasMatch(cleaned),
    };
  }

  @override
  String? getValidationError({
    required IdDocumentType docType,
    required String docNumber,
  }) {
    final cleaned = docNumber.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.isEmpty) {
      return 'Please enter your document number.';
    }

    if (!validateDocumentNumber(docType: docType, docNumber: docNumber)) {
      return switch (docType) {
        IdDocumentType.nationalId =>
          'Invalid SL-NIN: Must be 8-12 alphanumeric characters (e.g. 1029384756 or SL8849201).',
        IdDocumentType.ecowasCard =>
          'Invalid ECOWAS ID: Must be 8-14 alphanumeric characters.',
        IdDocumentType.passport =>
          'Invalid Passport No: Must be 6-10 alphanumeric characters (e.g. A12345678).',
      };
    }
    return null;
  }

  @override
  Future<KycResult> runMockVerification({
    required String userId,
    required String sessionToken,
    required IdDocumentType docType,
    required String docNumber,
  }) async {
    final validationErr = getValidationError(docType: docType, docNumber: docNumber);
    if (validationErr != null) {
      return KycResult(
        success: false,
        status: 'unverified',
        errorMessage: validationErr,
      );
    }

    try {
      _log.i('Running simulated verification for user $userId (doc: ${docType.name})');

      final result = await _convexClient.mutation(
        'verification:mockCompleteVerification',
        args: {
          'userId': userId,
          'sessionToken': sessionToken,
          'documentType': docType.convexKey,
          'idNumber': docNumber.trim(),
        },
      );

      if (result.success && result.value != null) {
        final data = result.value is Map<String, dynamic>
            ? result.value as Map<String, dynamic>
            : <String, dynamic>{};

        if (_usersDao != null) {
          await _usersDao.updateVerificationStatus(
            userId: userId,
            isVerified: true,
          );
        }

        _log.i('Simulated verification successful for user $userId');
        return KycResult(
          success: true,
          status: data['status']?.toString() ?? 'verified',
          badge: data['badge']?.toString() ?? 'GREEN_TICK',
          referenceId: data['referenceId']?.toString(),
          rawData: data,
        );
      }

      // If Convex backend returned an error or is unreachable during mock mode,
      // gracefully complete mock verification locally so the developer/tester is never blocked.
      _log.w('Convex mock mutation returned: ${result.errorMessage}. Gracefully completing mock verification locally.');
      if (_usersDao != null) {
        await _usersDao.updateVerificationStatus(
          userId: userId,
          isVerified: true,
        );
      }

      return KycResult(
        success: true,
        status: 'verified',
        badge: 'GREEN_TICK',
        referenceId: 'vkt_mock_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      _log.w('Mock verification caught exception: $e. Gracefully completing mock verification locally.');
      if (_usersDao != null) {
        await _usersDao.updateVerificationStatus(
          userId: userId,
          isVerified: true,
        );
      }

      return KycResult(
        success: true,
        status: 'verified',
        badge: 'GREEN_TICK',
        referenceId: 'vkt_mock_${DateTime.now().millisecondsSinceEpoch}',
      );
    }
  }

  @override
  Future<KycResult> verifyNinWithPrembly({
    required String nin,
    required String apiKey,
    required String appId,
  }) async {
    const url = 'https://api.prembly.com/identitypass/verification/sl/nin';
    try {
      final response = await _httpClient.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'app-id': appId,
        },
        body: jsonEncode({'number': nin.trim()}),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final status = body['status'] == true || body['verification_status'] == 'VERIFIED';
        return KycResult(
          success: status,
          status: status ? 'verified' : 'rejected',
          badge: status ? 'GREEN_TICK' : 'NONE',
          rawData: body,
          errorMessage: status ? null : (body['message']?.toString() ?? 'NIN verification failed'),
        );
      } else {
        return KycResult(
          success: false,
          status: 'rejected',
          errorMessage: 'Prembly returned HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      return KycResult(
        success: false,
        status: 'unverified',
        errorMessage: 'Prembly connection error: $e',
      );
    }
  }

  @override
  Future<KycResult> verifyBiometricsWithSmileId({
    required String userId,
    required String referenceId,
    required String selfieBase64,
    required String documentBase64,
    required String partnerId,
    required String apiKey,
  }) async {
    const url = 'https://api.smileidentity.com/v1/upload';
    try {
      final payload = {
        'source_sdk': 'flutter',
        'partner_id': partnerId,
        'user_id': userId,
        'job_id': referenceId,
        'job_type': 1, // Biometric KYC
        'country': 'SL',
        'images': [
          {'image_type_id': 2, 'image': selfieBase64},
          {'image_type_id': 1, 'image': documentBase64},
        ],
      };

      final response = await _httpClient.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final isSuccess = body['success'] == true || body['result_code'] == '0810';
        return KycResult(
          success: isSuccess,
          status: isSuccess ? 'verified' : 'pending',
          badge: isSuccess ? 'GREEN_TICK' : 'NONE',
          referenceId: referenceId,
          rawData: body,
          errorMessage: isSuccess ? null : body['result_text']?.toString(),
        );
      } else {
        return KycResult(
          success: false,
          status: 'rejected',
          errorMessage: 'Smile ID returned HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      return KycResult(
        success: false,
        status: 'unverified',
        errorMessage: 'Smile ID connection error: $e',
      );
    }
  }

  @override
  Future<KycResult> getVerificationStatus({required String userId}) async {
    try {
      final res = await _convexClient.query(
        'verification:getVerificationStatus',
        args: {'userId': userId},
      );

      if (res.success && res.value != null) {
        final data = res.value as Map<String, dynamic>;
        final isVerified = data['isVerified'] as bool? ?? false;
        final status = data['status']?.toString() ?? (isVerified ? 'verified' : 'unverified');
        final badge = data['badge']?.toString() ?? (isVerified ? 'GREEN_TICK' : 'NONE');

        return KycResult(
          success: true,
          status: status,
          badge: badge,
          referenceId: data['recentCheckId']?.toString(),
          errorMessage: data['rejectionReason']?.toString(),
          rawData: data,
        );
      } else {
        return KycResult(
          success: false,
          status: 'unverified',
          errorMessage: res.errorMessage ?? 'Failed to retrieve verification status',
        );
      }
    } catch (e) {
      return KycResult(
        success: false,
        status: 'unverified',
        errorMessage: 'Status query failed: $e',
      );
    }
  }
}
