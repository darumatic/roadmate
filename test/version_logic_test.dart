import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/version_logic.dart';
import 'package:roadmate/version.dart';
import 'package:roadmate/widgets/app_version_label.dart';

void main() {
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

  testWidgets('AppVersionLabel renders the baked-in version', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppVersionLabel())),
    );

    expect(find.text('RoadMate v$appVersion'), findsOneWidget);
  });
}
