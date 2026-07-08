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
}
