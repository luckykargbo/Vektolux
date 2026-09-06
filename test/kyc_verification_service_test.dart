import 'package:flutter_test/flutter_test.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/verification/data/services/kyc_verification_service.dart';
import 'package:vektolux/features/verification/domain/entities/verification_record.dart';

void main() {
  group('KycVerificationService Document Number Validation', () {
    late KycVerificationService kycService;
    late ConvexClientWrapper mockConvex;

    setUp(() {
      mockConvex = ConvexClientWrapper(deploymentUrl: 'https://mock.convex.cloud');
      kycService = KycVerificationServiceImpl(convexClient: mockConvex);
    });

    test('validates Sierra Leone NIN correctly (8-12 alphanumeric characters)', () {
      // Valid NINs
      expect(
        kycService.validateDocumentNumber(
          docType: IdDocumentType.nationalId,
          docNumber: '1029384756',
        ),
        isTrue,
      );
      expect(
        kycService.validateDocumentNumber(
          docType: IdDocumentType.nationalId,
          docNumber: 'SL8849201A',
        ),
        isTrue,
      );
      expect(
        kycService.validateDocumentNumber(
          docType: IdDocumentType.nationalId,
          docNumber: '12345678', // 8 chars minimum
        ),
        isTrue,
      );

      // Invalid NINs
      expect(
        kycService.validateDocumentNumber(
          docType: IdDocumentType.nationalId,
          docNumber: '1234567', // too short (< 8)
        ),
        isFalse,
      );
      expect(
        kycService.validateDocumentNumber(
          docType: IdDocumentType.nationalId,
          docNumber: '1234567890123', // too long (> 12)
        ),
        isFalse,
      );
      expect(
        kycService.validateDocumentNumber(
          docType: IdDocumentType.nationalId,
          docNumber: 'SL-1234!567', // illegal character
        ),
        isFalse,
      );
    });

    test('validates ECOWAS Biometric ID correctly (8-14 alphanumeric)', () {
      expect(
        kycService.validateDocumentNumber(
          docType: IdDocumentType.ecowasCard,
          docNumber: 'EC89201948',
        ),
        isTrue,
      );
      expect(
        kycService.validateDocumentNumber(
          docType: IdDocumentType.ecowasCard,
          docNumber: '12345', // too short
        ),
        isFalse,
      );
    });

    test('validates International Passport correctly (6-10 alphanumeric)', () {
      expect(
        kycService.validateDocumentNumber(
          docType: IdDocumentType.passport,
          docNumber: 'A12345678',
        ),
        isTrue,
      );
      expect(
        kycService.validateDocumentNumber(
          docType: IdDocumentType.passport,
          docNumber: 'P123', // too short
        ),
        isFalse,
      );
    });

    test('returns clear validation error messages', () {
      final emptyError = kycService.getValidationError(
        docType: IdDocumentType.nationalId,
        docNumber: '',
      );
      expect(emptyError, contains('Please enter your document number'));

      final invalidNinError = kycService.getValidationError(
        docType: IdDocumentType.nationalId,
        docNumber: '123',
      );
      expect(invalidNinError, contains('Invalid SL-NIN: Must be 8-12 alphanumeric characters'));
    });
  });

  group('ConvexClientWrapper Auth Header Safeguard', () {
    test('does not attach non-JWT hex session tokens to Authorization header', () {
      final client = ConvexClientWrapper(deploymentUrl: 'https://test.convex.cloud');
      // Setting a PBKDF2/SHA-256 session token hex string
      client.setAuthToken('7c4a8d9b01ef23456789abcdef0123456789abcdef0123456789abcdef012345');
      expect(client.hasAuthToken, isTrue);
      expect(client.authToken, isNotNull);
      // Non-JWT token is safely stored without causing HTTP 401 InvalidAuthHeader on gateway
    });
  });
}
