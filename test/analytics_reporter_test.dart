import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/analytics_reporter.dart';

void main() {
  group('shouldCollectAnalytics', () {
    test('disabled in debug builds', () {
      expect(shouldCollectAnalytics(isDebug: true), isFalse);
    });

    test('enabled in release builds', () {
      expect(shouldCollectAnalytics(isDebug: false), isTrue);
    });
  });

  group('AnalyticsReporter', () {
    test('setCollectionEnabled is a safe no-op before Firebase init', () {
      // Tests run on the dart:io branch with no Firebase app configured; the
      // reporter must not throw (startup may reach it after a timed-out init).
      expect(
        () => const AnalyticsReporter().setCollectionEnabled(true),
        returnsNormally,
      );
    });
  });
}
