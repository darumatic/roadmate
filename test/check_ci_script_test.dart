import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('check_ci.sh expands its sha argument to the full 40-char form', () {
    // GitHub's head_sha filter only matches the full sha; a short sha matches
    // no runs, so the script would poll "queued" until timeout. The script
    // must normalise its argument through git rev-parse.
    final script = File('scripts/check_ci.sh').readAsStringSync();
    expect(script, contains(r'sha="$(git rev-parse "${1:-HEAD}")"'));
  });
}
