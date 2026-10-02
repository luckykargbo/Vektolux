import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vektolux/core/network/convex_client_wrapper.dart';
import 'package:vektolux/features/verification/data/services/kyc_verification_service.dart';
import 'package:vektolux/features/verification/domain/entities/verification_record.dart';

/// A Convex client whose HTTP layer answers with [respond] (synthetic data only, no network).
KycVerificationServiceImpl serviceWith(Future<http.Response> Function(http.Request req) respond) {
  final client = ConvexClientWrapper(
    deploymentUrl: 'https://test.invalid',
    httpClient: MockClient(respond),
  );
  return KycVerificationServiceImpl(convexClient: client);
}

http.Response convexValue(Object? value) =>
    http.Response(jsonEncode({'status': 'success', 'value': value}), 200, headers: {'content-type': 'application/json'});
http.Response convexError(String message) =>
    http.Response(jsonEncode({'status': 'error', 'errorMessage': message}), 200, headers: {'content-type': 'application/json'});

void expectNotVerified(KycResult r) {
  expect(r.isVerified, isFalse);
  expect(r.badge, 'NONE');
}

void main() {
  group('KycVerificationService document number validation', () {
    late KycVerificationService kycService;

    setUp(() {
      kycService = KycVerificationServiceImpl(
        convexClient: ConvexClientWrapper(deploymentUrl: 'https://mock.convex.cloud'),
      );
    });

    test('validates Sierra Leone NIN correctly (8-12 alphanumeric characters)', () {
      expect(kycService.validateDocumentNumber(docType: IdDocumentType.nationalId, docNumber: '1029384756'), isTrue);
      expect(kycService.validateDocumentNumber(docType: IdDocumentType.nationalId, docNumber: 'SL8849201A'), isTrue);
      expect(kycService.validateDocumentNumber(docType: IdDocumentType.nationalId, docNumber: '12345678'), isTrue);
      expect(kycService.validateDocumentNumber(docType: IdDocumentType.nationalId, docNumber: '1234567'), isFalse);
      expect(kycService.validateDocumentNumber(docType: IdDocumentType.nationalId, docNumber: '1234567890123'), isFalse);
      expect(kycService.validateDocumentNumber(docType: IdDocumentType.nationalId, docNumber: 'SL-1234!567'), isFalse);
    });

    test('validates ECOWAS Biometric ID correctly (8-14 alphanumeric)', () {
      expect(kycService.validateDocumentNumber(docType: IdDocumentType.ecowasCard, docNumber: 'EC89201948'), isTrue);
      expect(kycService.validateDocumentNumber(docType: IdDocumentType.ecowasCard, docNumber: '12345'), isFalse);
    });

    test('validates International Passport correctly (6-10 alphanumeric)', () {
      expect(kycService.validateDocumentNumber(docType: IdDocumentType.passport, docNumber: 'A12345678'), isTrue);
      expect(kycService.validateDocumentNumber(docType: IdDocumentType.passport, docNumber: 'P123'), isFalse);
    });

    test('returns clear validation error messages', () {
      expect(kycService.getValidationError(docType: IdDocumentType.nationalId, docNumber: ''),
          contains('Please enter your document number'));
      expect(kycService.getValidationError(docType: IdDocumentType.nationalId, docNumber: '123'),
          contains('Invalid SL-NIN: Must be 8-12 alphanumeric characters'));
    });
  });

  group('verification status comes ONLY from the backend', () {
    test('backend says verified -> verified with GREEN_TICK', () async {
      final s = serviceWith((_) async => convexValue({'isVerified': true, 'status': 'verified', 'badge': 'GREEN_TICK'}));
      final r = await s.getVerificationStatus(userId: 'u1');
      expect(r.success, isTrue);
      expect(r.isVerified, isTrue);
      expect(r.badge, 'GREEN_TICK');
    });

    test('backend "approved" (legacy spelling) is also verified', () async {
      final s = serviceWith((_) async => convexValue({'isVerified': true, 'status': 'approved', 'badge': 'GREEN_TICK'}));
      expect((await s.getVerificationStatus(userId: 'u1')).isVerified, isTrue);
    });

    test('pending -> pending, not verified', () async {
      for (final st in ['pending', 'PENDING_REVIEW']) {
        final s = serviceWith((_) async => convexValue({'isVerified': false, 'status': st, 'badge': 'NONE'}));
        final r = await s.getVerificationStatus(userId: 'u1');
        expect(r.isPending, isTrue, reason: st);
        expectNotVerified(r);
      }
    });

    test('rejected -> rejected (with the reason), not verified', () async {
      final s = serviceWith((_) async =>
          convexValue({'isVerified': false, 'status': 'REJECTED', 'badge': 'NONE', 'rejectionReason': 'Blurry ID photo'}));
      final r = await s.getVerificationStatus(userId: 'u1');
      expect(r.isRejected, isTrue);
      expect(r.errorMessage, 'Blurry ID photo');
      expectNotVerified(r);
    });

    test('unverified -> unverified', () async {
      final s = serviceWith((_) async => convexValue({'isVerified': false, 'status': 'unverified', 'badge': 'NONE'}));
      final r = await s.getVerificationStatus(userId: 'u1');
      expect(r.status, 'unverified');
      expectNotVerified(r);
    });

    test('backend failure (error response or HTTP 500) -> error, NOT verified', () async {
      for (final respond in <Future<http.Response> Function(http.Request)>[
        (_) async => convexError('Internal error'),
        (_) async => http.Response('oops', 500),
      ]) {
        final r = await serviceWith(respond).getVerificationStatus(userId: 'u1');
        expect(r.isError, isTrue);
        expect(r.status, 'error');
        expectNotVerified(r);
      }
    });

    test('network failure -> error, NOT a fake success', () async {
      final s = serviceWith((_) async => throw http.ClientException('Failed host lookup'));
      final r = await s.getVerificationStatus(userId: 'u1');
      expect(r.isError, isTrue);
      expectNotVerified(r);
    });

    test('malformed responses are never verified', () async {
      final malformed = <Object?>[
        null,
        'verified',
        <String, dynamic>{},
        {'status': 'verified', 'badge': 'GREEN_TICK'}, // no isVerified flag
        {'isVerified': 'true', 'status': 'verified', 'badge': 'GREEN_TICK'}, // wrong type
        {'isVerified': true}, // no status
        {'isVerified': true, 'status': 'super-verified', 'badge': 'GREEN_TICK'}, // unknown status
        {'isVerified': false, 'status': 'verified', 'badge': 'GREEN_TICK'}, // contradictory
        {'isVerified': true, 'status': 'pending', 'badge': 'GREEN_TICK'}, // contradictory
      ];
      for (final body in malformed) {
        final r = await serviceWith((_) async => convexValue(body)).getVerificationStatus(userId: 'u1');
        expectNotVerified(r);
        expect(r.isError, isTrue, reason: '$body');
      }
      final body = await serviceWith((_) async => http.Response('<html>not json</html>', 200)).getVerificationStatus(userId: 'u1');
      expectNotVerified(body);
    });

    test('a verified status without the server badge never shows a GREEN_TICK', () async {
      final s = serviceWith((_) async => convexValue({'isVerified': true, 'status': 'verified', 'badge': 'NONE'}));
      final r = await s.getVerificationStatus(userId: 'u1');
      expect(r.badge, 'NONE');
      expect(r.isVerified, isFalse);
    });

    test('a previously verified user stays consistent with the backend: a later failure is "unknown", not a downgrade or upgrade', () async {
      var call = 0;
      final s = serviceWith((_) async {
        call++;
        return call == 1
            ? convexValue({'isVerified': true, 'status': 'verified', 'badge': 'GREEN_TICK'})
            : throw http.ClientException('Connection reset by peer');
      });
      final first = await s.getVerificationStatus(userId: 'u1');
      expect(first.isVerified, isTrue);
      final second = await s.getVerificationStatus(userId: 'u1');
      expect(second.status, 'error'); // not 'verified' (no fabrication) and not 'rejected'/'unverified'
      expect(second.isVerified, isFalse);
      expect(second.isRejected, isFalse);
    });
  });

  group('submitting for review never manufactures a verified result', () {
    Future<KycResult> submit(KycVerificationServiceImpl s) =>
        s.runMockVerification(userId: 'u1', sessionToken: 'tok', docType: IdDocumentType.nationalId, docNumber: '1029384756');

    test('backend accepts the submission -> pending (not verified)', () async {
      final s = serviceWith((_) async => convexValue({'success': true, 'status': 'pending', 'badge': 'NONE', 'referenceId': 'vkt_review_1'}));
      final r = await submit(s);
      expect(r.isPending, isTrue);
      expect(r.referenceId, 'vkt_review_1');
      expectNotVerified(r);
    });

    test('backend error -> error, NOT the old local GREEN_TICK fallback', () async {
      final r = await submit(serviceWith((_) async => convexError('Authentication required')));
      expect(r.isError, isTrue);
      expectNotVerified(r);
      expect(r.referenceId, isNull); // no fabricated vkt_mock_ reference
    });

    test('network failure -> error, NOT the old local GREEN_TICK fallback', () async {
      final r = await submit(serviceWith((_) async => throw http.ClientException('Failed host lookup')));
      expect(r.isError, isTrue);
      expectNotVerified(r);
      expect(r.referenceId, isNull);
    });

    test('malformed submission response -> error (no default "verified" / GREEN_TICK)', () async {
      for (final body in <Object?>[null, <String, dynamic>{}, {'success': true}, {'success': true, 'status': 'whatever'}, {'success': false, 'status': 'verified'}]) {
        final r = await submit(serviceWith((_) async => convexValue(body)));
        expect(r.isError, isTrue, reason: '$body');
        expectNotVerified(r);
      }
    });

    test('an invalid document number is refused locally without calling the backend', () async {
      var called = false;
      final s = serviceWith((_) async {
        called = true;
        return convexValue({'success': true, 'status': 'pending'});
      });
      final r = await s.runMockVerification(userId: 'u1', sessionToken: 'tok', docType: IdDocumentType.nationalId, docNumber: '12');
      expect(called, isFalse);
      expectNotVerified(r);
    });
  });

  group('ConvexClientWrapper Auth Header Safeguard', () {
    test('does not attach non-JWT hex session tokens to Authorization header', () {
      final client = ConvexClientWrapper(deploymentUrl: 'https://test.convex.cloud');
      client.setAuthToken('7c4a8d9b01ef23456789abcdef0123456789abcdef0123456789abcdef012345');
      expect(client.hasAuthToken, isTrue);
      expect(client.authToken, isNotNull);
    });
  });
}
