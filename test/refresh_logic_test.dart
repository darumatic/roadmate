import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/refresh_logic.dart';

void main() {
  group('shouldRestartOnRefresh', () {
    test('a healthy live stream is never restarted (re-bills every doc)', () {
      expect(shouldRestartOnRefresh(const AsyncData(<int>[1])), isFalse);
    });

    test('a stream still loading is left to finish', () {
      expect(shouldRestartOnRefresh(const AsyncLoading<int>()), isFalse);
    });

    test('an errored stream is restarted so pull-to-refresh retries', () {
      expect(
        shouldRestartOnRefresh(AsyncError<int>('offline', StackTrace.empty)),
        isTrue,
      );
    });
  });
}
