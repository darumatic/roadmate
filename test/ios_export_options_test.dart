import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the iOS App Store signing path — manual end to end.
///
/// Xcode's *automatic* signing asks the Apple ID signed into Xcode.app to
/// resolve certificates and profiles, and no machine that releases RoadMate
/// has one: the release Mac is CLI-only, and hosted CI runners are fresh.
/// Automatic signing bit twice, each time only after a slow build:
///   - export: "No Accounts / No signing certificate iOS Distribution found"
///     (the original release-Mac failure ios/ExportOptions.plist fixed);
///   - archive: "No Accounts" + "No profiles for 'com.darumatic.roadmate'"
///     (the first Mobile Release iOS dry run on a GitHub runner, 2026-08-24 —
///     locally the archive had quietly leaned on leftover development signing
///     material the runner doesn't have).
///
/// So the Runner Release config pins manual distribution signing for the
/// archive, ios/ExportOptions.plist does the same for the export, and
/// scripts/release_ios.sh preflights the identity + profile both rely on.
/// These tests keep the three in sync.
void main() {
  final plist = File('ios/ExportOptions.plist');
  final script = File('scripts/release_ios.sh');
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');

  test('export options use manual App Store signing', () {
    expect(
      plist.existsSync(),
      isTrue,
      reason: 'ios/ExportOptions.plist is required by scripts/release_ios.sh',
    );
    final xml = plist.readAsStringSync();

    // Manual signing is the whole point — automatic needs an Xcode account.
    expect(xml, contains('<key>signingStyle</key>'));
    expect(xml, contains('<string>manual</string>'));
    expect(xml, contains('<string>app-store-connect</string>'));
    expect(xml, contains('<string>Apple Distribution</string>'));
    expect(xml, contains('<string>76UL6RCLTT</string>'));

    // The bundle id must map to the profile name installed on the release Mac.
    expect(xml, contains('<key>com.darumatic.roadmate</key>'));
    expect(xml, contains('<string>RoadMate App Store</string>'));
  });

  test('the Xcode project archives with manual distribution signing', () {
    expect(pbxproj.existsSync(), isTrue);
    final proj = pbxproj.readAsStringSync();

    // Regenerating the project (flutterfire configure, an Xcode "fix") must
    // not revert the Release configuration to automatic signing — that only
    // fails after a full archive, and only off the machines that hide it.
    expect(proj, contains('CODE_SIGN_STYLE = Manual'));
    expect(proj, contains('CODE_SIGN_IDENTITY = "Apple Distribution"'));
    expect(
      proj,
      contains('PROVISIONING_PROFILE_SPECIFIER = "RoadMate App Store"'),
      reason: 'the archive must sign with the same named profile the export '
          'options map to the bundle id',
    );
  });

  test('release_ios.sh exports with the plist and preflights signing', () {
    expect(script.existsSync(), isTrue);
    final sh = script.readAsStringSync();

    expect(
      sh,
      contains('--export-options-plist=ios/ExportOptions.plist'),
      reason: 'a bare `flutter build ipa` falls back to automatic signing',
    );

    // Fail fast on missing signing material rather than after the archive.
    expect(sh, contains('security find-identity'));
    expect(sh, contains('Apple Distribution: DARUMATIC PTY LTD'));
    expect(sh, contains('RoadMate App Store'));
  });
}
