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
}
