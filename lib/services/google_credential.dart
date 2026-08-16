import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The project's web OAuth client id, doubling as the `serverClientId` the
/// Android Credential Manager sheet mints Firebase-compatible ID tokens for.
/// Public by design (it ships in every roadmate.club page); pinned here and
/// guarded by `test/google_credential_test.dart` so a project reconfiguration
/// can't silently break Android sign-in.
const googleServerClientId =
    '976338726022-21r0fcvmk41tkba3q33ks6km7tu02ct4.apps.googleusercontent.com';

/// True when [e] is the user dismissing the Google account sheet — the one
/// sign-in failure the UI must swallow silently instead of reporting.
bool isGoogleSignInCancellation(Object e) =>
    e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled;

/// Obtains a Firebase credential from the native Google account sheet
/// (Credential Manager). Android only: the Custom-Tab `signInWithProvider`
/// flow hands its result back without ever closing the tab, stranding the
/// user on a blank page (diagnosed from the 0.1.70 screen recording) — the
/// sheet signs in on top of the app with no browser involved. iOS and web
/// keep their provider flows.
class GoogleCredentialSource {
  /// The plugin allows exactly one [GoogleSignIn.initialize] per process,
  /// so the guard is static rather than per-instance.
  static bool _initialized = false;

  /// Returns null when the user dismisses the sheet.
  Future<OAuthCredential?> obtain() async {
    final signIn = GoogleSignIn.instance;
    if (!_initialized) {
      await signIn.initialize(serverClientId: googleServerClientId);
      _initialized = true;
    }
    final GoogleSignInAccount account;
    try {
      account = await signIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (isGoogleSignInCancellation(e)) return null;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google returned an account without an ID token.',
      );
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }
}
