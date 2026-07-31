import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `scripts/asc_submit.py` is the last gate before App Store metadata reaches
/// Apple, and guideline 2.3.10 (no Google Play / Play Store / Android in App
/// Store metadata) already cost the project one rejection at 0.1.38. Its pure
/// helpers have a stdlib self-test; run it as part of `flutter test` so the
/// release cycle covers the guard, not just `scripts/release_ios.sh`.
void main() {
  test('asc_submit.py self-test passes', () {
    final result = Process.runSync('python3', [
      'scripts/asc_submit.py',
      '--self-test',
    ], workingDirectory: Directory.current.path);
    expect(
      result.exitCode,
      0,
      reason:
          'scripts/asc_submit.py --self-test failed:\n'
          '${result.stdout}\n${result.stderr}',
    );
  });

  test('the 2.3.10 guard covers every field Apple shows', () {
    // 0.1.55 shipped with only the What's New text guarded; the description,
    // promotional text and keywords went to Apple unchecked. Keep all three
    // in the read-back check.
    final script = File('scripts/asc_submit.py').readAsStringSync();
    expect(script, contains('UNWRITTEN_LOCALIZATION_FIELDS'));
    for (final field in ['description', 'promotionalText', 'keywords']) {
      expect(
        script,
        contains('"$field"'),
        reason: '$field must stay in the 2.3.10 read-back check',
      );
    }
    expect(script, contains('def check_metadata('));
  });

  test('the metadata check runs before the version is submitted', () {
    // A violation must stop the run while the version is still editable —
    // catching it after "Submit for review" would be too late.
    final script = File('scripts/asc_submit.py').readAsStringSync();
    final check = script.indexOf('check_metadata(version_id)');
    final submit = script.indexOf('==> Submit for review');
    expect(check, greaterThan(-1));
    expect(submit, greaterThan(-1));
    expect(
      check,
      lessThan(submit),
      reason: 'the 2.3.10 check must run before the review submission',
    );
  });

  test('the release notes on disk are 2.3.10 clean', () {
    // The file the script uploads verbatim. Guarding it here means a bad edit
    // fails at `flutter test`, not an hour into an iOS release.
    final notes = File('store/apple_whats_new.txt').readAsStringSync();
    final lower = notes.toLowerCase();
    for (final banned in ['google play', 'play store', 'android']) {
      expect(
        lower,
        isNot(contains(banned)),
        reason:
            'store/apple_whats_new.txt must not mention "$banned" '
            '(App Store guideline 2.3.10)',
      );
    }
  });
}
