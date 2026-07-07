import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/auth_service.dart';

// Records the calls the controller makes; every member the code under test
// doesn't touch is covered by noSuchMethod.
class FakeFirebaseAuth implements FirebaseAuth {
  User? current;
  Object? popupError;
  int anonSignIns = 0;
  int redirectSignIns = 0;
  int credentialSignIns = 0;
  Object? redirectResultError;

  @override
  User? get currentUser => current;

  @override
  Stream<User?> authStateChanges() => Stream.value(current);

  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) async {
    if (popupError != null) throw popupError!;
    return FakeUserCredential();
  }

  @override
  Future<void> signInWithRedirect(AuthProvider provider) async {
    redirectSignIns++;
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentialSignIns++;
    return FakeUserCredential();
  }

  @override
  Future<UserCredential> getRedirectResult() async {
    if (redirectResultError != null) throw redirectResultError!;
    return FakeUserCredential();
  }

  @override
  Future<UserCredential> signInAnonymously() async {
    anonSignIns++;
    return FakeUserCredential(fakeUser: FakeUser(fakeUid: 'anon-1'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUser implements User {
  FakeUser({this.fakeUid = 'u-1', this.anonymous = false, this.linkPopupError});

  final String fakeUid;
  final bool anonymous;
  final Object? linkPopupError;
  int linkRedirects = 0;

  @override
  String get uid => fakeUid;

  @override
  bool get isAnonymous => anonymous;

  @override
  Future<UserCredential> linkWithPopup(AuthProvider provider) async {
    if (linkPopupError != null) throw linkPopupError!;
    return FakeUserCredential();
  }

  @override
  Future<void> linkWithRedirect(AuthProvider provider) async {
    linkRedirects++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// user is null by default so syncUser is a no-op and Firestore stays untouched.
class FakeUserCredential implements UserCredential {
  FakeUserCredential({this.fakeUser});

  final User? fakeUser;

  @override
  User? get user => fakeUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthController _controller(FakeFirebaseAuth auth, {bool isWeb = true}) =>
    AuthController(auth: auth, firestore: FakeFirestore(), isWeb: isWeb);

FirebaseAuthException _blocked() => FirebaseAuthException(
  code: 'popup-blocked',
  message: 'Unable to establish a connection with the popup.',
);

void main() {
  group('shouldFallBackToRedirect', () {
    test('true only for popup-blocked', () {
      expect(shouldFallBackToRedirect(_blocked()), isTrue);
      expect(
        shouldFallBackToRedirect(
          FirebaseAuthException(code: 'popup-closed-by-user'),
        ),
        isFalse,
      );
      expect(shouldFallBackToRedirect(Exception('boom')), isFalse);
    });
  });

  group('signInWithGoogle on web', () {
    test('popup success returns the credential without redirecting', () async {
      final auth = FakeFirebaseAuth();
      final credential = await _controller(auth).signInWithGoogle();

      expect(credential, isNotNull);
      expect(auth.redirectSignIns, 0);
    });

    test('blocked popup falls back to a redirect and returns null', () async {
      final auth = FakeFirebaseAuth()..popupError = _blocked();
      final credential = await _controller(auth).signInWithGoogle();

      expect(credential, isNull);
      expect(auth.redirectSignIns, 1);
    });

    test('other popup errors rethrow instead of silently redirecting', () {
      final auth = FakeFirebaseAuth()
        ..popupError = FirebaseAuthException(code: 'popup-closed-by-user');

      expect(
        () => _controller(auth).signInWithGoogle(),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(auth.redirectSignIns, 0);
    });

    test('anonymous user with a blocked popup gets linkWithRedirect', () async {
      final anon = FakeUser(anonymous: true, linkPopupError: _blocked());
      final auth = FakeFirebaseAuth()..current = anon;

      final credential = await _controller(auth).signInWithGoogle();

      expect(credential, isNull);
      expect(anon.linkRedirects, 1);
      expect(auth.redirectSignIns, 0); // linked, not a fresh sign-in
    });
  });

  group('completeRedirectSignIn', () {
    test('no-op off web', () async {
      final auth = FakeFirebaseAuth()
        ..redirectResultError = Exception('must not be called');
      await _controller(auth, isWeb: false).completeRedirectSignIn();
    });

    test('a pending result with no user completes quietly', () async {
      final auth = FakeFirebaseAuth();
      await _controller(auth).completeRedirectSignIn();
      expect(auth.credentialSignIns, 0);
    });

    test('link conflict falls back to signing in with the credential', () async {
      final auth = FakeFirebaseAuth()
        ..redirectResultError = FirebaseAuthException(
          code: 'credential-already-in-use',
          credential: GoogleAuthProvider.credential(idToken: 'token'),
        );

      await _controller(auth).completeRedirectSignIn();

      expect(auth.credentialSignIns, 1);
    });

    test('other redirect failures are swallowed', () async {
      final auth = FakeFirebaseAuth()
        ..redirectResultError = FirebaseAuthException(code: 'internal-error');

      await _controller(auth).completeRedirectSignIn();

      expect(auth.credentialSignIns, 0);
    });
  });

  group('ensureSignedIn', () {
    test('keeps a restored session instead of signing in anonymously', () async {
      final auth = FakeFirebaseAuth()..current = FakeUser(fakeUid: 'google-1');

      expect(await ensureSignedIn(auth), 'google-1');
      expect(auth.anonSignIns, 0);
    });

    test('signs in anonymously when nobody is restored', () async {
      final auth = FakeFirebaseAuth();

      expect(await ensureSignedIn(auth), 'anon-1');
      expect(auth.anonSignIns, 1);
    });
  });
}
