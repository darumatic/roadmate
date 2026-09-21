import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/read_meter.dart';

/// Issue #54: the read meter lives in three languages — the app counts
/// (Dart), the rules bound what it may write, and an hourly cron reads the
/// day's document and alerts (Python). These hold them to one another, and run
/// the cron's own suite as part of `flutter test`.
void main() {
  test('read_meter.py self-test suite passes', () {
    final result = Process.runSync('python3', [
      'scripts/read_meter_test.py',
    ], workingDirectory: Directory.current.path);
    expect(
      result.exitCode,
      0,
      reason:
          'scripts/read_meter_test.py failed:\n'
          '${result.stdout}\n${result.stderr}',
    );
  });

  // The app files a flush under the quota day it works out by hand (Dart has
  // no zone database); the cron looks under the one the real zone database
  // gives. If they ever disagreed, the cron would read an empty document
  // while the reads piled up next door — and never alert.
  test('the app and the cron agree on the quota day — every hour around '
      'both daylight-time changes, for years', () {
    final moments = <DateTime>[
      for (final year in [2026, 2027, 2030, 2035])
        for (final (month, firstDay) in [(3, 7), (3, 12), (11, 1), (11, 5)])
          for (var hour = 0; hour < 24 * 4; hour++)
            DateTime.utc(year, month, firstDay, hour),
      for (var month = 1; month <= 12; month++) ...[
        DateTime.utc(2026, month, 1, 6, 59),
        DateTime.utc(2026, month, 1, 7),
        DateTime.utc(2026, month, 1, 7, 59),
        DateTime.utc(2026, month, 1, 8),
      ],
    ];

    final result = Process.runSync('python3', [
      '-c',
      'import sys, datetime as dt\n'
          'sys.path.insert(0, "scripts")\n'
          'import read_meter\n'
          'for iso in sys.argv[1:]:\n'
          '    print(read_meter.quota_day(dt.datetime.fromisoformat(iso)))\n',
      for (final moment in moments)
        moment.toIso8601String().replaceFirst('Z', '+00:00'),
    ], workingDirectory: Directory.current.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final fromPython = (result.stdout as String).trim().split('\n');
    expect(fromPython, hasLength(moments.length));
    for (final (i, moment) in moments.indexed) {
      expect(quotaDayOf(moment), fromPython[i], reason: 'at $moment');
    }
  });

  test('all three name the same collection and the same counters', () {
    final rules = File('firestore.rules').readAsStringSync();
    final script = File('scripts/read_meter.py').readAsStringSync();

    expect(rules, contains('match /$readMeterCollection/{day}'));
    expect(script, contains("COLLECTION = '$readMeterCollection'"));

    // Every counter a build can write is one the rules accept…
    final accepted = RegExp(
      r"function isUsageCount\(d, old\) \{[\s\S]*?hasOnly\(\[([\s\S]*?)\]\)",
    ).firstMatch(rules);
    expect(accepted, isNotNull);
    final names = RegExp(
      r"'([a-z_A-Z]+)'",
    ).allMatches(accepted!.group(1)!).map((m) => m.group(1)!).toSet();
    final written = {
      for (final source in ReadSource.values)
        for (final platform in ['web', 'android', 'ios'])
          readCounterField(source, platform),
    };
    // …and the rules accept nothing else from them but the timestamp: the
    // backup's counter is listed only to be frozen.
    expect(names, {...written, 'backup_server', 'updatedAt'});
    for (final counter in written) {
      expect(rules, contains("usageStep(d, old, '$counter')"));
    }
    expect(script, contains("BACKUP_FIELD = 'backup_server'"));
    expect(
      rules,
      contains("d.get('backup_server', 0) == old.get('backup_server', 0)"),
    );
  });

  test('a flush is clamped to the step the rules accept', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(
      rules,
      contains('d.get(field, 0) - old.get(field, 0) <= $readMeterMaxStep'),
    );
  });

  test('metering a read may never cost a read: no lookup on the write '
      'path, and nothing but admins reads the counters', () {
    final rules = File('firestore.rules').readAsStringSync();
    final block = RegExp(
      r'match /usage/\{day\} \{([\s\S]*?)\n    \}',
    ).firstMatch(rules);
    expect(block, isNotNull);
    final writes = block!
        .group(1)!
        .split('\n')
        .where((line) => !line.contains('allow read'))
        .join('\n');
    for (final lookup in ['get(', 'exists(', 'isBanned', 'isAdmin']) {
      expect(writes, isNot(contains(lookup)), reason: lookup);
    }
    expect(block.group(1), contains('allow read: if isAdmin();'));
  });
}
