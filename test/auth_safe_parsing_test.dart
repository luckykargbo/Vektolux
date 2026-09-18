import 'package:flutter_test/flutter_test.dart';
import 'package:vektolux/core/utils/safe_parser.dart';
import 'package:vektolux/features/auth/domain/repositories/auth_repository.dart';

void main() {
  group('Safe Numeric & Auth Serialization Parsing', () {
    test('asNullableInt correctly parses doubles, ints, strings, and null without throwing TypeError', () {
      final doubleTimestamp = 1789731599135.0;
      expect(asNullableInt(doubleTimestamp), equals(1789731599135));
      expect((doubleTimestamp as num?)?.toInt(), equals(1789731599135));

      final intTimestamp = 1789731599135;
      expect(asNullableInt(intTimestamp), equals(1789731599135));
      expect((intTimestamp as num?)?.toInt(), equals(1789731599135));

      expect(asNullableInt('12345'), equals(12345));
      expect(asNullableInt(null), isNull);
    });

    test('asDouble and asNullableDouble parse currency and balance fields safely', () {
      final intBalance = 500;
      expect(asDouble(intBalance), equals(500.0));
      expect((intBalance as num?)?.toDouble(), equals(500.0));

      final doubleBalance = 500.75;
      expect(asDouble(doubleBalance), equals(500.75));
      expect((doubleBalance as num?)?.toDouble(), equals(500.75));

      expect(asDouble(null, 0.0), equals(0.0));
    });

    test('AuthException distinguishes credential failure from other errors', () {
      const credError = AuthException('Invalid email or password', isCredentialFailure: true);
      const networkError = NetworkException('Connection timeout');
      const parseError = DataParseException('type double is not a subtype of int');

      expect(credError.isCredentialFailure, isTrue);
      expect(networkError, isA<NetworkException>());
      expect(parseError, isA<DataParseException>());
    });
  });
}
