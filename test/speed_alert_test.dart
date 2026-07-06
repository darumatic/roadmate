import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/speed_alert.dart';

final _now = DateTime(2026, 7, 4, 9, 0, 0);

void main() {
  group('shouldAlert', () {
    test('no alert when no limit is set', () {
      expect(shouldAlert(speedKmh: 120, limitKmh: null, now: _now), isFalse);
      expect(shouldAlert(speedKmh: 120, limitKmh: 0, now: _now), isFalse);
    });

    test('no alert within tolerance of the limit', () {
      // limit 100, tolerance 2 -> 101 is fine, 103 is over.
      expect(shouldAlert(speedKmh: 101, limitKmh: 100, now: _now), isFalse);
      expect(shouldAlert(speedKmh: 103, limitKmh: 100, now: _now), isTrue);
    });

    test('fires on the first reading over the limit (rising edge)', () {
      expect(
        shouldAlert(speedKmh: 110, limitKmh: 100, now: _now, lastAlertAt: null),
        isTrue,
      );
    });

    test('repeats every second while still over the limit (issue #6)', () {
      final justAlerted = _now.subtract(const Duration(milliseconds: 500));
      expect(
        shouldAlert(
          speedKmh: 110,
          limitKmh: 100,
          now: _now,
          lastAlertAt: justAlerted,
        ),
        isFalse,
      );

      final longAgo = _now.subtract(const Duration(milliseconds: 1100));
      expect(
        shouldAlert(
          speedKmh: 110,
          limitKmh: 100,
          now: _now,
          lastAlertAt: longAgo,
        ),
        isTrue,
      );
    });
  });

  group('isOverLimit', () {
    test('respects the limit and tolerance', () {
      expect(isOverLimit(101, 100), isFalse);
      expect(isOverLimit(103, 100), isTrue);
      expect(isOverLimit(200, null), isFalse);
    });
  });

  group('pad3', () {
    test('zero-pads to three digits', () {
      expect(pad3(0), '000');
      expect(pad3(89), '089');
      expect(pad3(89.6), '090'); // rounds
      expect(pad3(110), '110');
    });

    test('clamps out-of-range values', () {
      expect(pad3(-5), '000');
      expect(pad3(1500), '999');
      expect(pad3(double.nan), '000');
    });
  });
}
