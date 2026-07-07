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

  group('cooldownRemaining', () {
    final now = DateTime(2026, 7, 7, 12, 0, 0);

    test('null when the user never acted', () {
      expect(
        cooldownRemaining(
          lastActionAt: null,
          now: now,
          cooldown: kVoteCooldown,
        ),
        isNull,
      );
    });

    test('remaining time while inside the cooldown', () {
      expect(
        cooldownRemaining(
          lastActionAt: now.subtract(const Duration(minutes: 2)),
          now: now,
          cooldown: kVoteCooldown,
        ),
        const Duration(minutes: 3),
      );
    });

    test('null once the cooldown has passed (boundary inclusive)', () {
      expect(
        cooldownRemaining(
          lastActionAt: now.subtract(kVoteCooldown),
          now: now,
          cooldown: kVoteCooldown,
        ),
        isNull,
      );
      expect(
        cooldownRemaining(
          lastActionAt: now.subtract(const Duration(hours: 1)),
          now: now,
          cooldown: kVoteCooldown,
        ),
        isNull,
      );
    });
  });

  group('cooldownMessage', () {
    test('vote wording with minutes rounded up', () {
      expect(
        cooldownMessage(
          const Duration(minutes: 3, seconds: 10),
          isVote: true,
        ),
        "You've voted on this site recently — try again in 4 minutes.",
      );
    });

    test('report wording under a minute', () {
      expect(
        cooldownMessage(const Duration(seconds: 40), isVote: false),
        "You've reported activity on this site recently — try again in "
        'about a minute.',
      );
    });
  });
}
