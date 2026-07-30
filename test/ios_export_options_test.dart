import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the iOS App Store export path.
///
/// `flutter build ipa` defaults to *automatic* export signing, which asks the
/// Apple ID signed into Xcode.app for a distribution certificate. The release
/// Mac builds from the CLI and has no Xcode account, so that default fails the
/// whole release at the very last step with "No Accounts / No signing
/// certificate iOS Distribution found" — after a full archive has been built.
///
/// The fix is manual export options (ios/ExportOptions.plist) wired into
/// scripts/release_ios.sh. These tests keep the two in sync: the plist must
/// stay manual, and the script must actually pass it.
void main() {
  final plist = File('ios/ExportOptions.plist');
  final script = File('scripts/release_ios.sh');

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
