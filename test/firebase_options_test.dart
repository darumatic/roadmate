import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/firebase_options.dart';

void main() {
  test('web authDomain stays first-party (roadmate.club)', () {
    // Hand-edited in firebase_options.dart so web sign-in redirects are
    // first-party. A `flutterfire configure` re-run silently reverts it to
    // roadmate-b1551.firebaseapp.com — this test catches that.
    expect(DefaultFirebaseOptions.web.authDomain, 'roadmate.club');
  });
}
