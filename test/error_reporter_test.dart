import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/error_reporter.dart';

void main() {
  group('shouldReport', () {
    test('drops silent diagnostics-only errors', () {
      final details = FlutterErrorDetails(
        exception: Exception('boom'),
        silent: true,
      );
      expect(shouldReport(details), isFalse);
    });

    test('forwards visible errors', () {
      final details = FlutterErrorDetails(exception: Exception('boom'));
      expect(shouldReport(details), isTrue);
    });
  });
}
