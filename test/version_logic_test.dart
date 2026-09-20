import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/version_logic.dart';
import 'package:roadmate/version.dart';
import 'package:roadmate/widgets/app_version_label.dart';

void main() {
  // A release normally bumps the patch; `release.sh --minor|--major` is how a
  // version like 1.1.0 is cut without hand-editing pubspec.yaml and the
  // generated lib/version.dart.
  group('bumpVersion', () {
    test('a minor bump resets the patch: 1.0.27 -> 1.1.0', () {
      expect(bumpVersion('1.0.27+103', part: VersionPart.minor), '1.1.0+104');
    });

    test('a major bump resets minor and patch', () {
      expect(bumpVersion('1.4.2+9', part: VersionPart.major), '2.0.0+10');
    });

    test('the build number only ever climbs — both stores refuse an upload '
        'whose build number is not higher than the last', () {
      for (final part in VersionPart.values) {
        expect(bumpVersion('3.2.1+250', part: part), endsWith('+251'));
      }
      expect(bumpVersion('0.9.9', part: VersionPart.minor), '0.10.0+1');
    });

    test('patch is the default, and what bumpPatchVersion does', () {
      expect(bumpVersion('1.0.0+1'), '1.0.1+2');
      expect(bumpVersion('1.0.0+1'), bumpPatchVersion('1.0.0+1'));
    });

    test(
      'a bumped version always compares higher than the one it came from',
      () {
        for (final part in VersionPart.values) {
          final next = bumpVersion('1.9.27+103', part: part);
          expect(compareVersions(next, '1.9.27+103'), greaterThan(0));
        }
      },
    );

    test('rejects malformed input whatever the part', () {
      for (final part in VersionPart.values) {
        expect(() => bumpVersion('1.0', part: part), throwsFormatException);
      }
    });
  });

  group('bumpPatchVersion', () {
    test('increments patch and build number', () {
      expect(bumpPatchVersion('1.0.0+1'), '1.0.1+2');
    });

    test('defaults build to 1 when absent', () {
      expect(bumpPatchVersion('0.0.1'), '0.0.2+1');
    });

    test('handles multi-digit patch and build without touching minor', () {
      expect(bumpPatchVersion('1.0.9+9'), '1.0.10+10');
    });

    test('ignores surrounding whitespace', () {
      expect(bumpPatchVersion('  2.5.7+3  '), '2.5.8+4');
    });

    test('throws on malformed input', () {
      expect(() => bumpPatchVersion('1.0'), throwsFormatException);
      expect(() => bumpPatchVersion('v1.0.0'), throwsFormatException);
      expect(() => bumpPatchVersion(''), throwsFormatException);
    });
  });

  group('marketingVersion', () {
    test('strips the build suffix', () {
      expect(marketingVersion('1.0.1+2'), '1.0.1');
    });

    test('passes through a version without a build suffix', () {
      expect(marketingVersion('3.4.5'), '3.4.5');
    });
  });

  group('compareVersions', () {
    test('orders numerically, not lexically', () {
      expect(compareVersions('0.1.9', '0.1.10'), lessThan(0));
      expect(compareVersions('0.2.0', '0.1.99'), greaterThan(0));
      expect(compareVersions('1.0.0', '1.0.0'), 0);
    });

    test('ignores the +build suffix', () {
      expect(compareVersions('1.0.0+9', '1.0.0+1'), 0);
      expect(compareVersions('0.1.30+30', '0.1.29'), greaterThan(0));
    });

    test('throws on malformed input', () {
      expect(() => compareVersions('1.0', '1.0.0'), throwsFormatException);
      expect(() => compareVersions('1.0.0', 'nope'), throwsFormatException);
    });
  });

  group('isBelowMinimum (forced-update gate)', () {
    test('true only when strictly below the minimum', () {
      expect(isBelowMinimum(current: '0.1.29', minimum: '0.1.30'), isTrue);
      expect(isBelowMinimum(current: '0.1.30', minimum: '0.1.30'), isFalse);
      expect(isBelowMinimum(current: '0.1.31', minimum: '0.1.30'), isFalse);
    });

    test(
      'fails open on absent or malformed minimum — never bricks the app',
      () {
        expect(isBelowMinimum(current: '0.1.29', minimum: null), isFalse);
        expect(isBelowMinimum(current: '0.1.29', minimum: '  '), isFalse);
        expect(isBelowMinimum(current: '0.1.29', minimum: 'garbage'), isFalse);
      },
    );
  });

  testWidgets('AppVersionLabel renders the baked-in version', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionLabel())),
    );

    expect(find.text('RoadMate v$appVersion'), findsOneWidget);
  });
}
