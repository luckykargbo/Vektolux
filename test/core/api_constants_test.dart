import 'package:flutter_test/flutter_test.dart';
import 'package:vektolux/core/constants/app_constants.dart';

void main() {
  group('ApiConstants.validateConvexUrl', () {
    test('rejects an empty URL (what an un-configured release build compiles to)', () {
      expect(ApiConstants.validateConvexUrl(''), isNotNull);
      expect(ApiConstants.validateConvexUrl('   '), isNotNull);
    });

    test('rejects non-https, wrong host and non-origin URLs', () {
      expect(ApiConstants.validateConvexUrl('http://ideal-poodle-813.convex.cloud'), isNotNull);
      expect(ApiConstants.validateConvexUrl('https://example.com'), isNotNull);
      expect(ApiConstants.validateConvexUrl('https://evil.com/.convex.cloud'), isNotNull);
      expect(ApiConstants.validateConvexUrl('https://x.convex.cloud.evil.com'), isNotNull);
      expect(ApiConstants.validateConvexUrl('https://x.convex.cloud/api'), isNotNull);
      expect(ApiConstants.validateConvexUrl('https://x.convex.cloud?a=b'), isNotNull);
      expect(ApiConstants.validateConvexUrl('not a url'), isNotNull);
    });

    test('accepts a bare https <deployment>.convex.cloud origin', () {
      expect(ApiConstants.validateConvexUrl('https://ideal-poodle-813.convex.cloud'), isNull);
      expect(ApiConstants.validateConvexUrl('https://happy-animal-123.convex.cloud/'), isNull);
    });
  });

  group('ApiConstants.assertConvexUrlConfigured', () {
    test('throws for a missing/invalid URL and passes for a valid one', () {
      expect(() => ApiConstants.assertConvexUrlConfigured(url: ''), throwsStateError);
      expect(() => ApiConstants.assertConvexUrlConfigured(url: 'https://example.com'), throwsStateError);
      expect(() => ApiConstants.assertConvexUrlConfigured(url: 'https://a-b-1.convex.cloud'), returnsNormally);
    });
  });

  test('the unverified vektolux-prod fallback is gone', () {
    expect(ApiConstants.convexUrl, isNot(contains('vektolux-prod')));
    expect(ApiConstants.defaultDevConvexUrl, 'https://ideal-poodle-813.convex.cloud');
  });

  test('debug/test builds still resolve to a valid default', () {
    // Tests are not `dart.vm.product`, so the dev default applies when CONVEX_URL is not defined.
    expect(ApiConstants.validateConvexUrl(ApiConstants.convexUrl), isNull);
  });
}
