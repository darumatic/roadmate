import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/user_ban.dart';
import 'package:roadmate/services/ban_logic.dart';

final _now = DateTime(2026, 7, 29, 10, 0);

void main() {
  group('banExpiry', () {
    test('a one-day ban lifts 24 hours later', () {
      expect(banExpiry(BanDuration.oneDay, _now), DateTime(2026, 7, 30, 10, 0));
    });

    test('forever has no expiry at all', () {
      expect(banExpiry(BanDuration.forever, _now), isNull);
    });
  });

  group('banIsActive', () {
    test('a future expiry still bites', () {
      expect(
        banIsActive(until: _now.add(const Duration(hours: 1)), now: _now),
        isTrue,
      );
    });

    test('a past expiry does not', () {
      expect(
        banIsActive(
          until: _now.subtract(const Duration(minutes: 1)),
          now: _now,
        ),
        isFalse,
      );
    });

    test('the moment it expires, it stops', () {
      expect(banIsActive(until: _now, now: _now), isFalse);
    });

    // A permanent ban is stored as a doc with no `until`; a truncated or
    // half-written doc looks identical, so this must fail closed.
    test('a missing expiry means permanent, not unbanned', () {
      expect(banIsActive(until: null, now: _now), isTrue);
    });
  });

  group('banEditData', () {
    test('a one-day ban carries the expiry', () {
      final data = banEditData(duration: BanDuration.oneDay, now: _now);
      expect(data['until'], DateTime(2026, 7, 30, 10, 0));
      expect(data.containsKey('reason'), isFalse);
    });

    test('a permanent ban omits the expiry field entirely', () {
      final data = banEditData(duration: BanDuration.forever, now: _now);
      expect(data.containsKey('until'), isFalse);
    });

    test('the reason is trimmed, and a blank one is dropped', () {
      expect(
        banEditData(
          duration: BanDuration.oneDay,
          now: _now,
          reason: '  vote spam  ',
        )['reason'],
        'vote spam',
      );
      expect(
        banEditData(
          duration: BanDuration.oneDay,
          now: _now,
          reason: '   ',
        ).containsKey('reason'),
        isFalse,
      );
    });

    // The rules cap the reason at 200 chars and reject the whole write past
    // it — clipping here keeps a long paste from failing the ban outright.
    test('an over-long reason is clipped to the rules limit', () {
      final data = banEditData(
        duration: BanDuration.forever,
        now: _now,
        reason: 'x' * 500,
      );
      expect((data['reason']! as String).length, kBanReasonMaxLength);
    });

    // Every key must be one the rules' isValidBan allow-list accepts.
    test('writes no key outside the allowed shape', () {
      final data = banEditData(
        duration: BanDuration.oneDay,
        now: _now,
        reason: 'spam',
      );
      expect(data.keys, everyElement(isIn(const ['until', 'reason'])));
    });
  });

  group('banNoticeMessage', () {
    test('a timed ban names the moment it lifts', () {
      final message = banNoticeMessage(DateTime(2026, 7, 30, 14, 15));
      expect(message, contains('suspended until'));
      expect(message, contains('30 Jul 2026'));
    });

    test('a permanent ban does not pretend it will lift', () {
      final message = banNoticeMessage(null);
      expect(message, contains('suspended'));
      expect(message, isNot(contains('until')));
    });
  });

  group('BannedException', () {
    test('explains itself with the notice the user sees', () {
      const permanent = BannedException(null);
      expect(permanent.toString(), banNoticeMessage(null));
      expect(permanent.message, permanent.toString());

      final timed = BannedException(DateTime(2026, 7, 30));
      expect(timed.message, contains('30 Jul 2026'));
    });
  });

  group('UserBan', () {
    test('parses a timed ban from its document', () {
      final ban = UserBan.fromMap('spammer', {
        'until': '2026-07-30T10:00:00.000',
        'reason': 'vote spam',
        'createdAt': '2026-07-29T10:00:00.000',
        'createdBy': 'admin1',
      });
      expect(ban.uid, 'spammer');
      expect(ban.until, DateTime(2026, 7, 30, 10, 0));
      expect(ban.isPermanent, isFalse);
      expect(ban.isActiveAt(_now), isTrue);
      expect(ban.isActiveAt(DateTime(2026, 7, 31)), isFalse);
      expect(ban.reason, 'vote spam');
      expect(ban.createdBy, 'admin1');
    });

    test('a document with no expiry is a permanent ban', () {
      final ban = UserBan.fromMap('spammer', {
        'createdAt': '2026-07-29T10:00:00.000',
        'createdBy': 'admin1',
      });
      expect(ban.isPermanent, isTrue);
      expect(ban.isActiveAt(DateTime(2099, 1, 1)), isTrue);
    });

    test('round-trips through toMap', () {
      final ban = UserBan(
        uid: 'spammer',
        until: DateTime(2026, 7, 30, 10, 0),
        reason: 'spam',
        createdAt: _now,
        createdBy: 'admin1',
      );
      final restored = UserBan.fromMap('spammer', ban.toMap());
      expect(restored.until, ban.until);
      expect(restored.reason, ban.reason);
      expect(restored.createdAt, ban.createdAt);
      expect(restored.createdBy, ban.createdBy);
    });
  });
}
