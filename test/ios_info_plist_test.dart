import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();

  test('export compliance is declared as exempt in Info.plist', () {
    // Every build uploaded to App Store Connect must answer Apple's export
    // compliance question before it can be submitted. RoadMate only uses
    // standard OS-provided TLS (Firebase over HTTPS), which is exempt, so the
    // answer is baked into the binary — without this key every upload needs a
    // manual declaration in App Store Connect (or an API call) per build.
    expect(
      plist,
      contains('<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
    );
  });

  test('background location mode is declared for site-approach alerts', () {
    // AppleSettings(allowBackgroundLocationUpdates: true) throws at runtime
    // unless the `location` background mode is in the plist — the alert would
    // die the moment the driver switched to maps.
    expect(plist, contains('<key>UIBackgroundModes</key>'));
    expect(plist, contains('<string>location</string>'));
  });

  test('the Always usage string tells the driver tracking continues', () {
    // App Review rejects background location whose purpose string only
    // describes foreground use.
    expect(
      plist,
      contains('<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>'),
    );
    expect(plist, contains('in the background'));
  });
}
