import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/read_meter.dart';

/// A clock the test moves by hand.
class _Clock {
  DateTime now = DateTime.utc(2026, 9, 21, 3);

  DateTime call() => now;
  void pass(Duration time) => now = now.add(time);
}

const _minute = Duration(minutes: 1);

/// Issue #54: with no billing account the 50,000 reads/day quota is a cliff —
/// past it Firestore refuses reads — and Google won't report usage without
/// billing either. So the app counts what it is delivered, by Firestore's own
/// billing rules; these pin those rules.
void main() {
  group('quotaDayOf — the day Firestore counts in (midnight Pacific)', () {
    test('winter: the day turns over at 08:00 UTC (PST)', () {
      expect(quotaDayOf(DateTime.utc(2026, 1, 15, 7, 59)), '2026-01-14');
      expect(quotaDayOf(DateTime.utc(2026, 1, 15, 8)), '2026-01-15');
    });

    test('summer: at 07:00 UTC (PDT)', () {
      expect(quotaDayOf(DateTime.utc(2026, 7, 1, 6, 59)), '2026-06-30');
      expect(quotaDayOf(DateTime.utc(2026, 7, 1, 7)), '2026-07-01');
    });

    test('daylight time starts on the second Sunday of March: that day '
        'begins in PST, the next one in PDT', () {
      expect(quotaDayOf(DateTime.utc(2026, 3, 8, 7, 59)), '2026-03-07');
      expect(quotaDayOf(DateTime.utc(2026, 3, 8, 8)), '2026-03-08');
      expect(quotaDayOf(DateTime.utc(2026, 3, 9, 6, 59)), '2026-03-08');
      expect(quotaDayOf(DateTime.utc(2026, 3, 9, 7)), '2026-03-09');
    });

    test('and ends on the first Sunday of November: that day begins in PDT, '
        'the next one in PST', () {
      expect(quotaDayOf(DateTime.utc(2026, 11, 1, 6, 59)), '2026-10-31');
      expect(quotaDayOf(DateTime.utc(2026, 11, 1, 7)), '2026-11-01');
      expect(quotaDayOf(DateTime.utc(2026, 11, 2, 7, 59)), '2026-11-01');
      expect(quotaDayOf(DateTime.utc(2026, 11, 2, 8)), '2026-11-02');
    });

    test('an Australian driving day is ONE quota day until the reset around '
        '5 pm AEST — which a UTC day would have cut in two at 10 am', () {
      final dawn = DateTime.utc(2026, 9, 20, 20); // 6 am AEST on the 21st
      final beforeReset = DateTime.utc(2026, 9, 21, 6, 59); // 4:59 pm AEST
      final afterReset = DateTime.utc(2026, 9, 21, 7); // 5 pm AEST
      expect(quotaDayOf(dawn), '2026-09-20');
      expect(quotaDayOf(beforeReset), '2026-09-20');
      expect(quotaDayOf(afterReset), '2026-09-21');
    });

    test("whatever zone the device's clock is in", () {
      final moment = DateTime.utc(2026, 9, 21, 6, 59);
      expect(quotaDayOf(moment.toLocal()), quotaDayOf(moment));
    });
  });

  group('ReadMeter', () {
    test('adds up by source until it is taken, then starts from nothing', () {
      final meter = ReadMeter();
      expect(meter.isEmpty, isTrue);

      meter.add(ReadSource.sites, 89);
      meter.add(ReadSource.reports, 14);
      meter.add(ReadSource.sites, 2);
      expect(meter.isEmpty, isFalse);
      expect(meter.take(), {ReadSource.sites: 91, ReadSource.reports: 14});

      expect(meter.isEmpty, isTrue);
      expect(meter.take(), isEmpty);
    });

    test('a snapshot that cost nothing leaves no trace', () {
      final meter = ReadMeter()
        ..add(ReadSource.other, 0)
        ..add(ReadSource.other, -3);
      expect(meter.isEmpty, isTrue);
    });
  });

  group('ListenerBill — what Firestore bills a listener for', () {
    late _Clock clock;
    ListenerBill bill({DateTime? lastSyncedAt}) =>
        ListenerBill(now: clock.call, lastSyncedAt: lastSyncedAt);

    setUp(() => clock = _Clock());

    test('a new listener pays for its whole first result', () {
      expect(bill().onSnapshot(isFromCache: false, size: 89, changed: 89), 89);
    });

    test('and for one read when that result is empty', () {
      expect(bill().onSnapshot(isFromCache: false, size: 0, changed: 0), 1);
    });

    test('after that, only for what the server added or changed — a '
        'metadata-only event costs nothing', () {
      final sites = bill()
        ..onSnapshot(isFromCache: false, size: 89, changed: 89);

      expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 2), 2);
      expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 0), 0);
      expect(sites.onSnapshot(isFromCache: false, size: 90, changed: 1), 1);
    });

    test('nothing served from the cache is a read', () {
      final sites = bill();
      expect(sites.onSnapshot(isFromCache: true, size: 89, changed: 89), 0);
      expect(sites.onSnapshot(isFromCache: true, size: 89, changed: 1), 0);
    });

    group('a restarted app with a persisted cache (phones)', () {
      test('resumes cheaply when its last sync is younger than 30 minutes: '
          'the server bills only what changed', () {
        final sites = bill(
          lastSyncedAt: clock.now.subtract(const Duration(minutes: 29)),
        )..onSnapshot(isFromCache: true, size: 89, changed: 89);

        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 3), 3);
      });

      test('pays in full once that sync is 30 minutes old', () {
        final sites = bill(
          lastSyncedAt: clock.now.subtract(const Duration(minutes: 30)),
        )..onSnapshot(isFromCache: true, size: 89, changed: 89);

        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 0), 89);
      });

      test('and when nobody remembers a sync at all', () {
        final sites = bill()
          ..onSnapshot(isFromCache: true, size: 89, changed: 89);

        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 0), 89);
      });

      test('a young sync is no discount without a cache to resume from — '
          'the web starts every listener from nothing', () {
        final sites = bill(lastSyncedAt: clock.now.subtract(_minute));

        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 89), 89);
      });
    });

    group('cut off for more than 30 minutes, a listener is billed again in '
        'full', () {
      test('offline that long: the snapshots were from-cache meanwhile', () {
        final sites = bill()
          ..onSnapshot(isFromCache: false, size: 89, changed: 89)
          ..onSnapshot(isFromCache: true, size: 89, changed: 0);
        clock.pass(const Duration(minutes: 30));

        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 1), 89);
        // Once: the next change is a change again.
        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 1), 1);
      });

      test('offline for less, the resume token still holds: only what '
          'changed', () {
        final sites = bill()
          ..onSnapshot(isFromCache: false, size: 89, changed: 89)
          ..onSnapshot(isFromCache: true, size: 89, changed: 0);
        clock.pass(const Duration(minutes: 29));

        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 1), 1);
      });

      test('frozen that long — a gap between checks — the next answer from '
          'the server is the whole result, whatever it says changed', () {
        final sites = bill()
          ..onSnapshot(isFromCache: false, size: 89, changed: 89);
        for (var i = 0; i < 5; i++) {
          clock.pass(_minute);
          expect(sites.onCheck(), 0);
        }

        clock.pass(const Duration(minutes: 31));
        expect(sites.onCheck(), 0);
        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 1), 89);
        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 1), 1);
      });

      test('a freeze of less than 31 minutes could still have resumed for '
          'free', () {
        final sites = bill()
          ..onSnapshot(isFromCache: false, size: 89, changed: 89);

        clock.pass(const Duration(minutes: 30, seconds: 59));
        expect(sites.onCheck(), 0);
        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 1), 1);
      });

      test('a re-run that changed nothing raises no snapshot at all, so it '
          'is billed on trust — at the follow-up check, never the one that '
          'noticed it, and once', () {
        final sites = bill()
          ..onSnapshot(isFromCache: false, size: 89, changed: 89);

        clock.pass(const Duration(minutes: 45));
        expect(sites.onCheck(), 0); // the app came back…
        clock.pass(const Duration(milliseconds: 5));
        expect(sites.onCheck(), 0); // …and the overdue tick fired with it

        clock.pass(listenerCheckFollowUp);
        expect(sites.onCheck(), 89);
        clock.pass(_minute);
        expect(sites.onCheck(), 0);
        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 1), 1);
      });

      test('a glance too short to reach the follow-up check re-ran the query '
          'all the same: it is billed when the next freeze is noticed, not '
          'written off by it', () {
        final sites = bill()
          ..onSnapshot(isFromCache: false, size: 89, changed: 89);

        clock.pass(const Duration(minutes: 45));
        expect(sites.onCheck(), 0);
        clock.pass(const Duration(seconds: 5)); // and away again

        clock.pass(const Duration(minutes: 40));
        expect(sites.onCheck(), 89); // the first glance
        clock.pass(listenerCheckFollowUp);
        expect(sites.onCheck(), 89); // and this one
      });

      test('unless the listener was offline for that glance — then nothing '
          'was re-run', () {
        final sites = bill()
          ..onSnapshot(isFromCache: false, size: 89, changed: 89);

        clock.pass(const Duration(minutes: 45));
        sites.onCheck();
        sites.onSnapshot(isFromCache: true, size: 89, changed: 0);

        clock.pass(const Duration(minutes: 40));
        expect(sites.onCheck(), 0);
      });

      test('but not while the listener says it is offline: nothing has been '
          're-run yet', () {
        final sites = bill()
          ..onSnapshot(isFromCache: false, size: 89, changed: 89);

        clock.pass(const Duration(minutes: 45));
        sites.onCheck();
        sites.onSnapshot(isFromCache: true, size: 89, changed: 0);
        clock.pass(_minute);
        expect(sites.onCheck(), 0);

        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 0), 89);
      });

      test('a freeze before the first answer owes nothing extra: the first '
          'answer is the whole result anyway', () {
        final sites = bill();

        clock.pass(const Duration(minutes: 45));
        expect(sites.onCheck(), 0);
        clock.pass(_minute);
        expect(sites.onCheck(), 0);
        expect(sites.onSnapshot(isFromCache: false, size: 89, changed: 89), 89);
      });
    });

    test('lastSyncedAt is when the listener was last CONNECTED, not when a '
        'document last changed: the SDK keeps its resume token fresh through '
        'a quiet morning, so the restart after it is still a cheap one', () {
      final morning = bill()
        ..onSnapshot(isFromCache: false, size: 89, changed: 89);
      for (var minute = 0; minute < 120; minute++) {
        clock.pass(_minute);
        expect(morning.onCheck(), 0);
      }
      expect(morning.lastSyncedAt, clock.now);

      // Ten minutes after the app was put away, it is started again.
      clock.pass(const Duration(minutes: 10));
      final restarted = bill(lastSyncedAt: morning.lastSyncedAt)
        ..onSnapshot(isFromCache: true, size: 89, changed: 89);
      expect(restarted.onSnapshot(isFromCache: false, size: 89, changed: 0), 0);
    });

    test('but it stops moving while the listener is offline', () {
      final sites = bill()
        ..onSnapshot(isFromCache: false, size: 89, changed: 89);
      final synced = clock.now;
      sites.onSnapshot(isFromCache: true, size: 89, changed: 0);

      clock.pass(_minute);
      sites.onCheck();
      expect(sites.lastSyncedAt, synced);
    });

    test('lastSyncedAt follows every answer from the server, for whoever '
        'keeps it across restarts', () {
      final sites = bill();
      expect(sites.lastSyncedAt, isNull);

      sites.onSnapshot(isFromCache: true, size: 89, changed: 89);
      expect(sites.lastSyncedAt, isNull);

      sites.onSnapshot(isFromCache: false, size: 89, changed: 0);
      expect(sites.lastSyncedAt, clock.now);

      clock.pass(const Duration(minutes: 7));
      sites.onSnapshot(isFromCache: false, size: 89, changed: 1);
      expect(sites.lastSyncedAt, clock.now);
    });
  });

  group('readMeterFlush — what goes into the day\'s counter document', () {
    final at = DateTime.utc(2026, 9, 21, 3);
    ({String day, Map<String, Object> data})? flush(
      Map<ReadSource, int> counts, {
      String platform = 'web',
    }) => readMeterFlush(
      counts,
      platform: platform,
      at: at,
      plus: (reads) => '+$reads',
      serverTime: 'ST',
    );

    test('one increment per source, named for the platform, filed under the '
        'quota day', () {
      final write = flush({ReadSource.sites: 89, ReadSource.reports: 14});

      expect(write!.day, quotaDayOf(at));
      expect(write.data, {
        'sites_web': '+89',
        'reports_web': '+14',
        'updatedAt': 'ST',
      });
      expect(
        flush({ReadSource.other: 6}, platform: 'android')!.data.keys,
        containsAll(['other_android']),
      );
    });

    test('nothing counted, nothing written — not even a timestamp', () {
      expect(flush({}), isNull);
      expect(flush({ReadSource.sites: 0}), isNull);
    });

    test('a count beyond what the rules accept in one step is clamped, not '
        'refused whole', () {
      final write = flush({ReadSource.other: readMeterMaxStep + 1});
      expect(write!.data['other_web'], '+$readMeterMaxStep');
    });
  });
}
