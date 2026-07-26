import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Firestore backup tool is the project's only disaster-recovery path:
/// `firestore.rules` forbids client-side re-seeding, so a wiped database can
/// only be rebuilt from a snapshot. Its logic is tested by a stdlib Python
/// suite (`scripts/backup_firestore_test.py`); this test runs that suite as
/// part of `flutter test` so the release cycle covers it too.
void main() {
  test('backup_firestore.py self-test suite passes', () {
    final result = Process.runSync('python3', [
      'scripts/backup_firestore_test.py',
    ], workingDirectory: Directory.current.path);
    expect(
      result.exitCode,
      0,
      reason:
          'scripts/backup_firestore_test.py failed:\n'
          '${result.stdout}\n${result.stderr}',
    );
  });

  test('restore requires an explicit --confirm and never deletes', () {
    // A restore runs as the Admin SA and bypasses security rules, so an
    // accidental invocation must not be able to write. Guard the dry-run
    // default and the absence of any delete write at the source level.
    final script = File('scripts/backup_firestore.py').readAsStringSync();
    expect(script, contains("'--confirm', action='store_true'"));
    expect(script, contains('if not args.confirm:'));
    expect(script, isNot(contains("'delete':")));
  });

  test('snapshots are written atomically', () {
    // An interrupted run must not leave a truncated file that looks like a
    // usable backup: write to .partial, then rename into place.
    final script = File('scripts/backup_firestore.py').readAsStringSync();
    expect(script, contains(".partial'"));
    expect(script, contains('os.replace(tmp, target)'));
  });
}
