import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/rate_limit.dart';

void main() {
  group('isRateLimited', () {
    test('true for a permission-denied FirebaseException', () {
      final e = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      expect(isRateLimited(e), isTrue);
    });

    test('false for other Firebase errors and plain exceptions', () {
      expect(
        isRateLimited(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        isFalse,
      );
      expect(isRateLimited(Exception('boom')), isFalse);
    });
  });

  group('nextLedger', () {
    final now = DateTime(2026, 7, 7, 12, 0, 0);

    test('first ever action opens a window with count 1', () {
      expect(
        nextLedger(windowStart: null, count: 0, now: now),
        (resetWindow: true, count: 1),
      );
    });

    test('actions inside the window increment the count', () {
      final start = now.subtract(const Duration(minutes: 2));
      expect(
        nextLedger(windowStart: start, count: 1, now: now),
        (resetWindow: false, count: 2),
      );
      expect(
        nextLedger(windowStart: start, count: 4, now: now),
        (resetWindow: false, count: 5),
      );
    });

    test('an expired window resets to count 1', () {
      expect(
        nextLedger(
          windowStart: now.subtract(
            kActionWindow + const Duration(seconds: 1),
          ),
          count: 5,
          now: now,
        ),
        (resetWindow: true, count: 1),
      );
    });

    test('exactly at the window boundary still counts as inside', () {
      // Mirrors the rules: reset needs request.time > windowStart + 5m.
      expect(
        nextLedger(
          windowStart: now.subtract(kActionWindow),
          count: 2,
          now: now,
        ),
        (resetWindow: false, count: 3),
      );
    });
  });
}
