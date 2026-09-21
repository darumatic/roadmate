import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Issue #54: the read meter only knows about reads that go through
/// `.metered(...)` (lib/services/metered_firestore.dart). A new listener or
/// get that skips it would be invisible — and nothing would ever say so,
/// because an uncounted read breaks nothing. So this does.
void main() {
  // A Firestore read, up to its closing parenthesis (one level of nesting is
  // all `snapshots(includeMetadataChanges: true)` and `tx.get(ref)` need).
  final read = RegExp(r'\.(snapshots|get)\((?:[^()]|\([^()]*\))*\)');
  final metered = RegExp(r'^\s*\.metered\(');

  /// Source with comments blanked out, so a `// …` between a read and its
  /// `.metered(` — or a mention in a doc comment — can't confuse the scan.
  String code(String source) => source
      .split('\n')
      .map((line) {
        final at = line.indexOf('//');
        return at == -1 ? line : line.substring(0, at);
      })
      .join('\n');

  test('every Firestore read in lib/ is metered', () {
    final unmetered = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final source = file.readAsStringSync();
      final stripped = code(source);
      for (final match in read.allMatches(stripped)) {
        if (metered.hasMatch(stripped.substring(match.end))) continue;
        final line = '\n'.allMatches(stripped.substring(0, match.start)).length;
        // The line as written, comments and all: `// unmetered: <why>`
        // is the way to say a `.get(` is not Firestore's.
        if (source.split('\n')[line].contains('// unmetered:')) continue;
        unmetered.add('${file.path}:${line + 1}  ${match.group(0)}');
      }
    }

    expect(
      unmetered,
      isEmpty,
      reason:
          'These reads are invisible to the read meter. Follow each with '
          '.metered(ReadSource.…) — or, if it is not a Firestore read, end '
          'its line with "// unmetered: <why>".',
    );
  });

  test('the scan sees a read that is not metered', () {
    const sample = '''
      final a = await ref.get();
      final b = await ref.get().metered(ReadSource.other);
      final c = query
          .snapshots(includeMetadataChanges: true)
          // a comment in between
          .metered(ReadSource.sites);
      final d = await tx.get(claimRef);
    ''';
    final stripped = code(sample);
    final missed = [
      for (final match in read.allMatches(stripped))
        if (!metered.hasMatch(stripped.substring(match.end))) match.group(0),
    ];
    expect(missed, ['.get()', '.get(claimRef)']);
  });
}
