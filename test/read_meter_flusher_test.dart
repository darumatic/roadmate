import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/read_meter.dart';
import 'package:roadmate/services/read_meter_flusher.dart';

/// Issue #54: the meter is flushed about once when the app is put away and
/// once per half hour while it stays open — never per action, because writes
/// have a daily quota of their own. (testWidgets for its fake clock.)
void main() {
  late ReadMeter meter;
  late List<(String day, Map<String, Object> data)> writes;
  late bool signedIn;

  ReadMeterFlusher flusher({Future<void> Function()? failing}) =>
      ReadMeterFlusher(
        meter: meter,
        platform: 'web',
        ready: () => signedIn,
        plus: (reads) => '+$reads',
        serverTime: 'ST',
        write: (day, data) {
          writes.add((day, data));
          return failing?.call() ?? Future.value();
        },
      );

  setUp(() {
    meter = ReadMeter();
    writes = [];
    signedIn = true;
  });

  testWidgets('writes what was counted, once, under the quota day', (
    tester,
  ) async {
    final subject = flusher();
    meter
      ..add(ReadSource.sites, 89)
      ..add(ReadSource.reports, 14);

    subject.flush();

    expect(writes, hasLength(1));
    expect(writes.single.$1, matches(r'^\d{4}-\d{2}-\d{2}$'));
    expect(writes.single.$2, {
      'sites_web': '+89',
      'reports_web': '+14',
      'updatedAt': 'ST',
    });
    expect(meter.isEmpty, isTrue);
  });

  testWidgets('nothing counted, nothing written', (tester) async {
    flusher().flush();
    expect(writes, isEmpty);
  });

  testWidgets('waits for the sign-in: the counts stay until a write can go '
      'out', (tester) async {
    final subject = flusher();
    signedIn = false;
    meter.add(ReadSource.sites, 89);

    subject.flush();
    expect(writes, isEmpty);
    expect(meter.isEmpty, isFalse);

    signedIn = true;
    subject.flush();
    expect(writes.single.$2['sites_web'], '+89');
  });

  testWidgets('a fresh start flushes early: a browser tab closed within the '
      'half hour would otherwise flush only while unloading, and that write '
      'dies with the page', (tester) async {
    final subject = flusher()..start();
    addTearDown(subject.dispose);
    meter.add(ReadSource.sites, 89);

    await tester.pump(const Duration(seconds: 29));
    expect(writes, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(writes.single.$2['sites_web'], '+89');

    // Once: from here on it is the half-hour cadence alone.
    meter.add(ReadSource.reports, 2);
    await tester.pump(const Duration(minutes: 5));
    expect(writes, hasLength(1));
    subject.dispose();
  });

  testWidgets('that first flush is tried again until one goes out — the '
      'sign-in may not be there yet', (tester) async {
    final subject = flusher()..start();
    addTearDown(subject.dispose);
    signedIn = false;
    meter.add(ReadSource.sites, 89);

    await tester.pump(const Duration(seconds: 70));
    expect(writes, isEmpty);

    signedIn = true;
    await tester.pump(const Duration(seconds: 20));
    expect(writes.single.$2['sites_web'], '+89');
    subject.dispose();
  });

  testWidgets('and given up after ten tries, leaving the half-hour cadence', (
    tester,
  ) async {
    final subject = flusher()..start();
    addTearDown(subject.dispose);

    await tester.pump(const Duration(minutes: 5)); // nothing was ever counted
    meter.add(ReadSource.sites, 89);
    await tester.pump(const Duration(minutes: 5));
    expect(writes, isEmpty);

    await tester.pump(const Duration(minutes: 20));
    expect(writes, hasLength(1));
    subject.dispose();
  });

  testWidgets('every half hour while the app stays open — and a quiet half '
      'hour costs no write at all', (tester) async {
    final subject = flusher()..start();
    addTearDown(subject.dispose);
    meter.add(ReadSource.sites, 89);
    await tester.pump(const Duration(seconds: 30)); // the early one
    expect(writes, hasLength(1));

    meter.add(ReadSource.reports, 2);
    await tester.pump(const Duration(minutes: 29));
    expect(writes, hasLength(1));
    await tester.pump(const Duration(seconds: 30));
    expect(writes, hasLength(2));

    await tester.pump(const Duration(minutes: 30));
    expect(writes, hasLength(2));

    meter.add(ReadSource.reports, 1);
    await tester.pump(const Duration(minutes: 30));
    expect(writes, hasLength(3));
    subject.dispose();
  });

  testWidgets('putting the app away flushes — once, however many steps the '
      'platform reports it in, and not again within a minute', (tester) async {
    final subject = flusher();
    meter.add(ReadSource.sites, 89);

    subject
      ..onBackground() // hidden
      ..onBackground() // paused
      ..onBackground(); // detached
    expect(writes, hasLength(1));

    // Flipping between tabs with reports trickling in.
    meter.add(ReadSource.reports, 1);
    await tester.pump(const Duration(seconds: 59));
    subject.onBackground();
    expect(writes, hasLength(1));

    await tester.pump(const Duration(seconds: 1));
    subject.onBackground();
    expect(writes, hasLength(2));
    expect(writes.last.$2['reports_web'], '+1');
  });

  testWidgets('a refused write is dropped, not put back: a count that kept '
      'growing would outgrow the step the rules accept', (tester) async {
    final subject = flusher(
      failing: () => Future.error(StateError('permission-denied')),
    );
    meter.add(ReadSource.sites, 89);

    subject.flush();
    await tester.pump();

    expect(writes, hasLength(1));
    expect(meter.isEmpty, isTrue);
  });

  test('builds are filed under web, android or ios — a desktop build is a '
      "developer's and is not metered", () {
    expect(readMeterPlatform(isWeb: true), 'web');
    expect(
      readMeterPlatform(isWeb: false, platform: TargetPlatform.android),
      'android',
    );
    expect(
      readMeterPlatform(isWeb: false, platform: TargetPlatform.iOS),
      'ios',
    );
    for (final desktop in [
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      expect(readMeterPlatform(isWeb: false, platform: desktop), isNull);
    }
  });
}
