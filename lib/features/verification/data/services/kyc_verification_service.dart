// lib/features/verification/data/services/kyc_verification_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Identity verification (KYC) client service.
//
// The Convex backend is the ONLY authority on identity verification. This client never manufactures
// a verified state: a result is "verified" only when the backend explicitly reports it. A failed
// request, an unreachable network, a backend error or a malformed response is reported as an ERROR
// (state unknown) — never as verified, and never as a fabricated rejection.
//
// (Client-side calls to identity providers were removed: a result computed on the device — or with
// provider API keys shipped in the app — can be forged and must never decide verification.)
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:logger/logger.dart';

import '../../../../core/network/convex_client_wrapper.dart';
import '../../domain/entities/verification_record.dart';

/// Result of a verification request or status lookup.
class KycResult {
  /// The request reached the backend and its answer was understood.
  final bool success;

  /// 'verified' | 'pending' | 'rejected' | 'unverified' | 'error' (state unknown: request failed).
  final String status;

  /// 'GREEN_TICK' only when the backend confirmed verification; otherwise 'NONE'.
  final String badge;
  final String? referenceId;
  final String? errorMessage;
  final Map<String, dynamic>? rawData;

  const KycResult({
    required this.success,
    required this.status,
    this.badge = 'NONE',
    this.referenceId,
    this.errorMessage,
    this.rawData,
  });

  /// A failure whose outcome is unknown. It must not be shown as verified OR as rejected.
  const KycResult.error(String message)
      : success = false,
        status = 'error',
        badge = 'NONE',
        referenceId = null,
        errorMessage = message,
        rawData = null;

  bool get isVerified => success && status == 'verified' && badge == 'GREEN_TICK';
  bool get isPending => success && status == 'pending';
  bool get isRejected => success && status == 'rejected';
  bool get isError => !success;
}

/// Maps the backend's status vocabulary (schema `verificationStatusEnum`) to client states.
/// Anything unrecognised returns null and is treated as a malformed response.
String? normalizeServerVerificationStatus(Object? raw) {
  if (raw is! String) return null;
  switch (raw.trim().toLowerCase()) {
    case 'verified':
    case 'approved':
      return 'verified';
    case 'pending':
    case 'pending_review':
      return 'pending';
    case 'rejected':
      return 'rejected';
    case 'unverified':
      return 'unverified';
    default:
      return null;
  }
}

/// Abstract contract for identity-verification operations.
abstract class KycVerificationService {
  /// Validate the format of a Sierra Leone NIN or other document number.
  bool validateDocumentNumber({
    required IdDocumentType docType,
    required String docNumber,
  });

  /// Format validation error message.
  String? getValidationError({
    required IdDocumentType docType,
    required String docNumber,
  });

  /// Submits the document for MANUAL review by Vektolux (the backend records it as pending).
  /// Never returns verified on its own.
  Future<KycResult> runMockVerification({
    required String userId,
    required String sessionToken,
    required IdDocumentType docType,
    required String docNumber,
  });

  /// Current verification state, as reported by the backend.
  Future<KycResult> getVerificationStatus({required String userId});
}

class KycVerificationServiceImpl implements KycVerificationService {
  final ConvexClientWrapper _convexClient;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));

  KycVerificationServiceImpl({required ConvexClientWrapper convexClient}) : _convexClient = convexClient;

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
      IdDocumentType.voterId =>
        // Sierra Leone Voter ID Card: 7 to 12 alphanumeric characters
        RegExp(r'^[A-Za-z0-9]{7,12}$').hasMatch(cleaned),
      IdDocumentType.driverLicense =>
        // SLRSA Driver License: 6 to 12 alphanumeric characters
        RegExp(r'^[A-Za-z0-9]{6,12}$').hasMatch(cleaned),
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
        IdDocumentType.voterId =>
          'Invalid Voter ID: Must be 7-12 alphanumeric characters.',
        IdDocumentType.driverLicense =>
          'Invalid Driver License: Must be 6-12 alphanumeric characters.',
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
      return KycResult(success: false, status: 'unverified', errorMessage: validationErr);
    }

    try {
      final result = await _convexClient.mutation(
        'verification:mockCompleteVerification',
        args: {
          'userId': userId,
          'sessionToken': sessionToken,
          'documentType': docType.convexKey,
          'idNumber': docNumber.trim(),
        },
      );
      if (!result.success) {
        return KycResult.error(result.errorMessage ?? 'Verification could not be submitted. Please try again.');
      }
      final data = result.value;
      if (data is! Map || data['success'] != true) {
        return const KycResult.error('Unexpected response from the server. Please try again.');
      }
      return _fromServer(Map<String, dynamic>.from(data), serverSaysVerified: null);
    } catch (e) {
      _log.w('Verification submission failed: ${e.runtimeType}');
      return const KycResult.error('Network problem. Your verification was not submitted. Please try again.');
    }
  }

  @override
  Future<KycResult> getVerificationStatus({required String userId}) async {
    try {
      final res = await _convexClient.query('verification:getVerificationStatus', args: {'userId': userId});
      if (!res.success) {
        return KycResult.error(res.errorMessage ?? 'Could not load your verification status.');
      }
      final data = res.value;
      if (data is! Map) {
        return const KycResult.error('Unexpected response from the server.');
      }
      final map = Map<String, dynamic>.from(data);
      final isVerified = map['isVerified'];
      if (isVerified is! bool) {
        return const KycResult.error('Unexpected response from the server.');
      }
      return _fromServer(map, serverSaysVerified: isVerified);
    } catch (e) {
      _log.w('Verification status lookup failed: ${e.runtimeType}');
      return const KycResult.error('Network problem. Could not load your verification status.');
    }
  }

  /// Builds a result strictly from the backend's answer. "verified" requires the backend's status to
  /// say so AND (when the backend sends it) its isVerified flag to agree. Unknown statuses are errors.
  KycResult _fromServer(Map<String, dynamic> data, {required bool? serverSaysVerified}) {
    final status = normalizeServerVerificationStatus(data['status']);
    if (status == null) {
      return const KycResult.error('Unexpected verification status from the server.');
    }
    if (status == 'verified' && serverSaysVerified == false) {
      return const KycResult.error('Inconsistent verification status from the server.');
    }
    if (status != 'verified' && serverSaysVerified == true) {
      return const KycResult.error('Inconsistent verification status from the server.');
    }
    final verified = status == 'verified';
    return KycResult(
      success: true,
      status: status,
      badge: verified && data['badge'] == 'GREEN_TICK' ? 'GREEN_TICK' : 'NONE',
      referenceId: (data['referenceId'] ?? data['recentCheckId'])?.toString(),
      errorMessage: status == 'rejected' ? data['rejectionReason']?.toString() : null,
      rawData: data,
    );
  }
}
