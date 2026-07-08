import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/firebase_options.dart';
import 'package:roadmate/services/auth_service.dart';

void main() {
  test('web authDomain stays first-party (roadmate.club)', () {
    // Hand-edited in firebase_options.dart so web sign-in redirects are
    // first-party. A `flutterfire configure` re-run silently reverts it to
    // roadmate-b1551.firebaseapp.com — this test catches that.
    expect(DefaultFirebaseOptions.web.authDomain, 'roadmate.club');
  });

  test('native sign-in round-trips through roadmate.club too', () {
    // iOS/Android ignore the web authDomain; startup sets customAuthDomain
    // from this helper so no platform uses the firebaseapp.com handler.
    expect(nativeCustomAuthDomain(isWeb: false), 'roadmate.club');
    expect(nativeCustomAuthDomain(isWeb: true), isNull);
  });
}
