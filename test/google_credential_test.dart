import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:roadmate/services/google_credential.dart';

void main() {
  // The Android account sheet mints ID tokens for this exact client; a
  // project reconfiguration that changes it must fail loudly here, mirroring
  // the authDomain guard in firebase_options_test.dart.
  test('serverClientId stays pinned to the project web OAuth client', () {
    expect(
      googleServerClientId,
      '976338726022-21r0fcvmk41tkba3q33ks6km7tu02ct4'
      '.apps.googleusercontent.com',
    );
  });

  group('isGoogleSignInCancellation', () {
    test('true only for a dismissed sheet', () {
      expect(
        isGoogleSignInCancellation(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        ),
        isTrue,
      );
      expect(
        isGoogleSignInCancellation(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
          ),
        ),
        isFalse,
      );
      expect(isGoogleSignInCancellation(Exception('boom')), isFalse);
    });
  });
}
