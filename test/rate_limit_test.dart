import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/rate_limit.dart';

void main() {
  group('ledger payloads (issue #15 redux)', () {
    test('reset is a full fresh window stamped only with server time', () {
      final payload = ledgerResetPayload(serverTime: 'ST');
      expect(payload, {'count': 1, 'windowStart': 'ST', 'lastActionAt': 'ST'});
    });

    test('increment never carries windowStart — the no-clock guarantee', () {
      final payload = ledgerIncrementPayload(
        incrementByOne: 'INC',
        serverTime: 'ST',
      );
      expect(payload, {'count': 'INC', 'lastActionAt': 'ST'});
      expect(payload.containsKey('windowStart'), isFalse);
    });
  });

  group('retry decision', () {
    FirebaseException fb(String code) =>
        FirebaseException(plugin: 'cloud_firestore', code: code);

    test('rules denial and missing ledger doc both trigger the other shape',
        () {
      expect(shouldTryOtherShape(fb('permission-denied')), isTrue);
      expect(shouldTryOtherShape(fb('not-found')), isTrue);
    });

    test('transient or unrelated failures are not retried as the other shape',
        () {
      expect(shouldTryOtherShape(fb('unavailable')), isFalse);
      expect(shouldTryOtherShape(StateError('boom')), isFalse);
    });

    test('only permission-denied counts as a rules denial', () {
      expect(isRulesDenial(fb('permission-denied')), isTrue);
      expect(isRulesDenial(fb('not-found')), isFalse);
      expect(isRulesDenial(fb('unavailable')), isFalse);
      expect(isRulesDenial(ArgumentError('nope')), isFalse);
    });
  });

  test('constants match the firestore.rules enforcement (5 per 5 minutes)',
      () {
    expect(kMaxActionsPerWindow, 5);
    expect(kRateLimitWindow, const Duration(minutes: 5));
  });

  test('RateLimitedException explains itself with the UI message', () {
    expect(const RateLimitedException().toString(), kRateLimitMessage);
    expect(kRateLimitMessage, contains('5 actions per 5 minutes'));
  });
}
