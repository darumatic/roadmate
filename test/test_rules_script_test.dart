import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Firestore rules harness launcher (scripts/test_rules.sh).
///
/// `flutter test` does not cover test/rules/, so firestore.rules is only ever
/// verified by that script — and firebase-tools refuses to start the emulator
/// on Java < 21. On the Mac that refusal is easy to hit with a modern JDK
/// installed: Homebrew keeps `openjdk` keg-only (never on PATH) while
/// /usr/bin/java is a stub that resolves to nothing. The script therefore
/// adopts a qualifying keg itself and fails loudly when none exists, so a
/// rules change is never left silently unverified.
void main() {
  final script = File('scripts/test_rules.sh');

  test('test_rules.sh finds a Java 21+ runtime before starting the emulator',
      () {
    expect(script.existsSync(), isTrue);
    final sh = script.readAsStringSync();

    // Homebrew's keg-only JDKs, Apple Silicon and Intel prefixes.
    expect(sh, contains('/opt/homebrew/opt/openjdk/bin/java'));
    expect(sh, contains('/usr/local/opt/openjdk/bin/java'));

    // The version gate itself — a candidate is only adopted at 21 or above.
    expect(sh, contains('java_major'));
    expect(sh, contains('-lt 21'));
    expect(sh, contains('-ge 21'));

    // No usable JDK must abort rather than let the emulator fail obscurely.
    expect(sh, contains('needs Java 21+'));
    expect(sh, contains('exit 1'));

    // And it still has to run the harness it exists for.
    expect(sh, contains('firebase emulators:exec'));
    expect(sh, contains('node test/rules/rules_test.mjs'));
  });

  test('the JDK probe runs before the emulator is invoked', () {
    final sh = script.readAsStringSync();
    expect(sh.indexOf('needs Java 21+'),
        lessThan(sh.indexOf('firebase emulators:exec')),
        reason: 'the guard is pointless after the emulator has been started');
  });
}
