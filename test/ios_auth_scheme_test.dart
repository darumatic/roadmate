import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/firebase_options.dart';

void main() {
  test('Info.plist registers the Firebase encoded-app-id URL scheme', () {
    // Native sign-in uses signInWithProvider, which round-trips through a web
    // auth session and returns to the app via a custom URL scheme equal to
    // the iOS app's *encoded* Firebase app id (app-1-...-ios-...). Without it
    // the sign-in button silently goes nowhere on iOS.
    final scheme =
        'app-${DefaultFirebaseOptions.ios.appId.replaceAll(':', '-')}';
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<string>$scheme</string>'));
  });

  test('Info.plist carries the location purpose strings Apple requires', () {
    // geolocator references the always-authorization APIs, so App Store
    // ingestion (Transporter ITMS-90683) rejects the binary unless the
    // "always" purpose string exists too — even though RoadMate only ever
    // requests when-in-use.
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>NSLocationWhenInUseUsageDescription</key>'));
    expect(
      plist,
      contains('<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>'),
    );
  });
}
