import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class _Result {
  _Result({
    required this.exitCode,
    required this.output,
    required this.profile,
    required this.systemTemp,
    required this.leftInSystemTemp,
    required this.driverAlive,
    required this.driveArgs,
  });

  final int exitCode;
  final String output;

  /// Where the fake chromedriver made "Chrome's profile".
  final String profile;

  /// The TMPDIR the script itself ran with, and what was in it afterwards.
  final String systemTemp;
  final List<String> leftInSystemTemp;

  final bool driverAlive;
  final String driveArgs;
}

/// Runs the real scripts/verify_web.sh — a copy, in a throwaway repo root, so
/// the developer's own build/ is never touched — against a fake chromedriver
/// and a fake `flutter`.
///
/// The fake driver behaves like the real one where it matters for issue #56:
/// it makes a profile directory in whatever TMPDIR it was started with, never
/// removes it, and runs until it is killed.
_Result _runScript({int flutterExit = 0}) {
  final root = Directory.systemTemp.createTempSync('verify_web_test');
  try {
    final bin = Directory('${root.path}/bin')..createSync();
    final repo = Directory('${root.path}/repo/scripts')
      ..createSync(recursive: true);
    final systemTemp = Directory('${root.path}/systmp')..createSync();
    File('scripts/verify_web.sh').copySync('${repo.path}/verify_web.sh');

    void stub(String name, String body) {
      final file = File('${bin.path}/$name')
        ..writeAsStringSync('#!/usr/bin/env bash\n$body');
      Process.runSync('chmod', ['+x', file.path]);
    }

    stub('chromedriver', r'''
here="$(dirname "$0")"
profile="${TMPDIR:-/tmp}/org.chromium.Chromium.scoped_dir.$$"
mkdir -p "$profile/Default"
echo cookies > "$profile/Default/Cookies"
echo "$$" > "$here/driver.pid"
echo "$profile" > "$here/profile.path"
exec /bin/sleep 600
''');
    // Waits for the profile first: the script only gives the driver 2 s, and
    // cleaning up a profile that was never made would prove nothing.
    stub('flutter', '''
here="\$(dirname "\$0")"
for _ in \$(seq 1 200); do
  [ -f "\$here/profile.path" ] && break
  /bin/sleep 0.05
done
echo "\$*" > "\$here/drive.args"
mkdir -p build/integration_screenshots
touch build/integration_screenshots/home.png
exit $flutterExit
''');

    // The script's own "give the driver 2 s" — the fakes call /bin/sleep.
    stub('sleep', 'exit 0\n');

    final result = Process.runSync(
      'bash',
      ['${repo.path}/verify_web.sh'],
      includeParentEnvironment: false,
      environment: {
        'PATH':
            '${bin.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
        'HOME': root.path,
        'TMPDIR': systemTemp.path,
        'CHROMEWEBDRIVER': bin.path,
        'FLUTTER': '${bin.path}/flutter',
      },
    );

    String read(String name) {
      final file = File('${bin.path}/$name');
      return file.existsSync() ? file.readAsStringSync().trim() : '';
    }

    final pid = read('driver.pid');
    final driverAlive =
        pid.isNotEmpty && Process.runSync('kill', ['-0', pid]).exitCode == 0;
    if (driverAlive) Process.runSync('kill', [pid]);

    return _Result(
      exitCode: result.exitCode,
      output: '${result.stdout}${result.stderr}',
      profile: read('profile.path'),
      systemTemp: systemTemp.path,
      leftInSystemTemp: [
        for (final entry in systemTemp.listSync(recursive: true)) entry.path,
      ],
      driverAlive: driverAlive,
      driveArgs: read('drive.args'),
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// Issue #56: every run left Chrome's profile (45–143 MB) behind in /tmp —
/// chromedriver only removes it when the WebDriver session is deleted, which
/// `flutter drive` never does. On a tmpfs with a per-user quota a handful of
/// runs broke everything that writes there, shell output included.
void main() {
  test('the driver runs in a temp dir of its own, and a finished run leaves '
      'nothing of it behind', () {
    final run = _runScript();

    expect(run.exitCode, 0, reason: run.output);
    expect(run.profile, isNotEmpty, reason: 'the fake driver never started');
    // Not straight into the shared temp dir, where nobody would own it…
    expect(run.profile, startsWith('${run.systemTemp}/'));
    expect(File(run.profile).parent.path, isNot(run.systemTemp));
    // …and gone afterwards, private dir and all.
    expect(run.leftInSystemTemp, isEmpty);
    expect(run.driverAlive, isFalse);
  });

  test('a failing run cleans up just the same', () {
    final run = _runScript(flutterExit: 1);

    expect(run.exitCode, isNot(0));
    expect(run.profile, isNotEmpty, reason: 'the fake driver never started');
    expect(run.leftInSystemTemp, isEmpty);
    expect(run.driverAlive, isFalse);
  });

  test('it still drives the integration suite in headless Chrome', () {
    final run = _runScript();

    expect(run.driveArgs, startsWith('drive '));
    expect(run.driveArgs, contains('--target=integration_test/app_test.dart'));
    expect(run.driveArgs, contains('--browser-name=chrome'));
    expect(run.driveArgs, contains('--driver-port=4444'));
  });
}
