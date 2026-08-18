import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Whether the app runs as an installed PWA (web) — false elsewhere.
import 'display_mode_stub.dart'
    if (dart.library.js_interop) 'display_mode_web.dart'
    as display_mode;

import '../firebase_options.dart';
import 'auth_switched_stream.dart';
import 'google_credential.dart';
import 'username_logic.dart';

/// Thrown when the user dismisses a sign-in surface (the Android Google
/// account sheet). The UI treats it as a quiet no-op — never an error snack.
class SignInCancelledException implements Exception {
  const SignInCancelledException();
}

/// The first-party domain native (iOS/Android) provider sign-in round-trips
/// through, mirroring the web authDomain so no platform falls back to the
/// default roadmate-b1551.firebaseapp.com handler. Null on web: there the
/// authDomain in [DefaultFirebaseOptions.web] already applies.
String? nativeCustomAuthDomain({required bool isWeb}) =>
    isWeb ? null : DefaultFirebaseOptions.web.authDomain;

/// Ensures the user is signed in anonymously and exposes their uid. Anonymous
/// auth is the device-based identity used to attribute votes/reports/saves
/// without a login wall.
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

const initialAdminEmails = {
  'r3procamel@gmail.com',
  'hello@adrian2045.com',
  'adrian@darumatic.com',
  'leandropervieux@hotmail.com',
};

enum AppUserRole { anonymous, truckie, admin }

// userChanges() (not authStateChanges()) so the UI reacts when an anonymous
// account is *linked* to a provider — linking keeps the same uid, so
// authStateChanges() never fires for it.
final authStateProvider = StreamProvider<User?>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value(null);
  return ref.watch(firebaseAuthProvider).userChanges();
});

// The switching/retry behaviour lives in authSwitchedStream, where it is
// unit-tested — the old `await for` + `yield*` shape here never observed a
// sign-out or account switch after the first sign-in. Anonymous users map to
// null: an anonymous uid has no userRoles doc, so no listener is opened and
// they get the anonymous role directly.
final currentUserRoleProvider = StreamProvider<AppUserRole>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value(AppUserRole.anonymous);

  final auth = ref.watch(firebaseAuthProvider);
  final firestore = FirebaseFirestore.instance;
  return authSwitchedStream<String, AppUserRole>(
    authUsers: auth.userChanges().map(
      (user) => (user == null || user.isAnonymous) ? null : user.uid,
    ),
    sourceOf: (uid) =>
        firestore.collection('userRoles').doc(uid).snapshots().map((doc) {
          final role = doc.data()?['role'] as String?;
          return role == 'admin' ? AppUserRole.admin : AppUserRole.truckie;
        }),
    signedOutValue: AppUserRole.anonymous,
  );
});

/// True when [e] is the browser refusing to open the sign-in popup — the one
/// failure the redirect flow (a full-page navigation) always recovers from.
bool shouldFallBackToRedirect(Object e) =>
    e is FirebaseAuthException && e.code == 'popup-blocked';

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(
    auth: ref.watch(firebaseAuthProvider),
    firestore: FirebaseFirestore.instance,
  );
});

class AuthController {
  AuthController({
    required this.auth,
    required this.firestore,
    this.isWeb = kIsWeb,
    this.isStandalone = display_mode.isStandaloneDisplayMode,
    bool? useGoogleCredentialSheet,
    Future<OAuthCredential?> Function()? obtainGoogleCredential,
  }) : useGoogleCredentialSheet =
           useGoogleCredentialSheet ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
       obtainGoogleCredential =
           obtainGoogleCredential ?? GoogleCredentialSource().obtain;

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  /// Injectable so the web-only popup/redirect paths are testable on the VM.
  final bool isWeb;

  /// Installed-PWA detection. A PWA's "popup" opens as a custom tab with no
  /// window.opener, so the Firebase popup handler hangs on a blank page —
  /// those windows must use the redirect flow from the start.
  final bool Function() isStandalone;

  /// Android signs in with Google via the native Credential Manager sheet
  /// instead of `signInWithProvider`: the Custom-Tab flow delivers its result
  /// behind the scenes and leaves the tab parked on a blank page (0.1.70
  /// recording), and forces a full email/password/2FA round trip besides.
  final bool useGoogleCredentialSheet;

  /// Yields a Google credential from the account sheet, or null when the
  /// user dismisses it. Injectable for tests.
  final Future<OAuthCredential?> Function() obtainGoogleCredential;

  /// Returns null when a full-page redirect was started instead (blocked
  /// popup) — the page is about to navigate away and sign-in completes on
  /// the next load via [completeRedirectSignIn]. Throws
  /// [SignInCancelledException] when the Android account sheet is dismissed.
  Future<UserCredential?> signInWithGoogle() {
    if (useGoogleCredentialSheet) return _signInWithGoogleCredential();
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    return _signInWithProvider(provider);
  }

  /// The Android path: one native sheet, then a plain credential sign-in —
  /// linking first so an anonymous user keeps their uid, mirroring
  /// [_signInWithProvider]'s conflict handling.
  Future<UserCredential?> _signInWithGoogleCredential() async {
    final credential = await obtainGoogleCredential();
    if (credential == null) throw const SignInCancelledException();

    final current = auth.currentUser;
    UserCredential signedIn;
    if (current != null && current.isAnonymous) {
      try {
        signedIn = await current.linkWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use' &&
            e.code != 'provider-already-linked' &&
            e.code != 'email-already-in-use') {
          rethrow;
        }
        // The Google account already backs a user: sign in to it directly.
        signedIn = await auth.signInWithCredential(e.credential ?? credential);
      }
    } else {
      signedIn = await auth.signInWithCredential(credential);
    }

    await _refreshClaims(signedIn.user);
    await syncUser(signedIn.user);
    return signedIn;
  }

  /// Apple returns name/email only on the first authorization; [syncUser]
  /// tolerates the nulls on later sign-ins.
  Future<UserCredential?> signInWithApple() {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    return _signInWithProvider(provider);
  }

  Future<void> signOut() => auth.signOut();

  /// Deletes the signed-in account (App Store 5.1.1(v)). Erases the user's
  /// favourites and profile doc, revokes the Apple token when one is linked,
  /// deletes the Firebase user, then restores the anonymous-first identity.
  /// Votes/reports keep their now-orphaned uid by design — they can no
  /// longer be linked to a person. No-op for anonymous sessions.
  Future<void> deleteAccount() async {
    final user = auth.currentUser;
    if (user == null || user.isAnonymous) return;

    // Firestore first: after user.delete() the uid no longer authorises
    // these writes. One batch — favourites are far under the 500-op limit.
    // If the auth deletion fails below, syncUser recreates the profile doc
    // on the next userChanges emission.
    final userDoc = firestore.collection('users').doc(user.uid);

    // Release the road-name claim so the name frees up for others. A separate
    // best-effort delete, deliberately NOT in the batch below: a missing or
    // inconsistent claim doc would fail the whole batch, and nothing may ever
    // block the user's right to delete their account (App Store 5.1.1(v)).
    try {
      final profile = await userDoc.get();
      final username = profile.data()?['username'] as String?;
      if (username != null && username.trim().isNotEmpty) {
        await firestore
            .collection('usernames')
            .doc(usernameKey(username))
            .delete();
      }
    } catch (e) {
      debugPrint('RoadMate: road-name release skipped: $e');
    }

    final favourites = await userDoc.collection('favourites').get();
    final batch = firestore.batch();
    for (final favourite in favourites.docs) {
      batch.delete(favourite.reference);
    }
    // Rate-limit ledger (issue #15) and participation stats: blind deletes —
    // no-ops when absent.
    batch.delete(userDoc.collection('limits').doc('actions'));
    batch.delete(userDoc.collection('stats').doc('participation'));
    batch.delete(userDoc);
    await batch.commit();

    // Apple requires apps to revoke the sign-in token on account deletion.
    // Needs a fresh authorization code, hence the reauthentication. Best
    // effort: revocation must never block the user's right to delete, and
    // firebase_auth only implements it on Apple platforms.
    final hasApple = user.providerData.any(
      (info) => info.providerId == 'apple.com',
    );
    var reauthenticated = false;
    if (hasApple && !isWeb) {
      try {
        final credential = await user.reauthenticateWithProvider(
          AppleAuthProvider(),
        );
        reauthenticated = true;
        final code = credential.additionalUserInfo?.authorizationCode;
        if (code != null) await auth.revokeTokenWithAuthorizationCode(code);
      } on FirebaseAuthException catch (e) {
        debugPrint('RoadMate: Apple token revocation skipped: ${e.code}');
      }
    }

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code != 'requires-recent-login' || reauthenticated) rethrow;
      await _reauthenticate(user);
      await user.delete();
    }

    // Only after a successful deletion — never resurrect a failed one.
    await auth.signInAnonymously();
  }

  Future<UserCredential> _reauthenticate(User user) async {
    final providerId = user.providerData
        .map((info) => info.providerId)
        .firstWhere(
          (id) => id == 'apple.com' || id == 'google.com',
          orElse: () => 'google.com',
        );
    if (providerId == 'google.com' && useGoogleCredentialSheet) {
      final credential = await obtainGoogleCredential();
      if (credential == null) throw const SignInCancelledException();
      return user.reauthenticateWithCredential(credential);
    }
    final provider = providerId == 'apple.com'
        ? AppleAuthProvider()
        : (GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'}));
    // Web always uses the popup: a redirect would navigate away and abandon
    // the deletion mid-flight.
    return isWeb
        ? user.reauthenticateWithPopup(provider)
        : user.reauthenticateWithProvider(provider);
  }

  /// Finishes a redirect sign-in after the round-trip back from the provider
  /// (web only; called once at startup). No redirect pending is a no-op.
  /// Mirrors the popup path's conflict handling: if linking the anonymous
  /// user failed because the Google account already exists, sign in to that
  /// account directly.
  Future<void> completeRedirectSignIn() async {
    if (!isWeb) return;
    try {
      final result = await auth.getRedirectResult();
      await _refreshClaims(result.user);
      await syncUser(result.user);
    } on FirebaseAuthException catch (e) {
      final credential = e.credential;
      if ((e.code == 'credential-already-in-use' ||
              e.code == 'email-already-in-use') &&
          credential != null) {
        final signedIn = await auth.signInWithCredential(credential);
        await _refreshClaims(signedIn.user);
        await syncUser(signedIn.user);
        return;
      }
      // The user lands where they started and can simply retry.
      debugPrint('RoadMate: redirect sign-in failed: ${e.code}');
    } catch (e) {
      debugPrint('RoadMate: redirect sign-in failed: $e');
    }
  }

  Future<UserCredential?> _signInWithProvider(AuthProvider provider) async {
    final current = auth.currentUser;
    UserCredential? credential;
    if (current != null && current.isAnonymous) {
      try {
        credential = await _linkCurrentUser(current, provider);
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use' &&
            e.code != 'provider-already-linked' &&
            e.code != 'email-already-in-use') {
          rethrow;
        }
        credential = await _signIn(provider);
      }
    } else {
      credential = await _signIn(provider);
    }

    if (credential == null) return null; // redirecting — completes next load
    await _refreshClaims(credential.user);
    await syncUser(credential.user);
    return credential;
  }

  /// Forces a fresh ID token after a sign-in or link.
  ///
  /// Linking a provider onto an anonymous uid keeps the same uid, so a cached
  /// token can still read as anonymous right after a sign-in — anything keyed
  /// on token claims (admin checks) would lag behind. Best effort: a failed
  /// refresh must never turn a successful sign-in into an error, and the token
  /// refreshes itself within the hour regardless.
  Future<void> _refreshClaims(User? user) async {
    try {
      await user?.getIdToken(true);
    } catch (e) {
      debugPrint('RoadMate: token refresh after sign-in failed: $e');
    }
  }

  // firebase_auth exposes the *Provider variants only on mobile/desktop; web
  // must use the popup flow (falling back to a redirect when the browser
  // blocks the popup), otherwise it throws UnimplementedError. Installed
  // PWAs skip the popup entirely — see [isStandalone].
  Future<UserCredential?> _signIn(AuthProvider provider) async {
    if (!isWeb) return auth.signInWithProvider(provider);
    if (isStandalone()) {
      await auth.signInWithRedirect(provider);
      return null;
    }
    try {
      return await auth.signInWithPopup(provider);
    } catch (e) {
      if (!shouldFallBackToRedirect(e)) rethrow;
      await auth.signInWithRedirect(provider);
      return null;
    }
  }

  Future<UserCredential?> _linkCurrentUser(
    User user,
    AuthProvider provider,
  ) async {
    if (!isWeb) return user.linkWithProvider(provider);
    if (isStandalone()) {
      await user.linkWithRedirect(provider);
      return null;
    }
    try {
      return await user.linkWithPopup(provider);
    } catch (e) {
      if (!shouldFallBackToRedirect(e)) rethrow;
      await user.linkWithRedirect(provider);
      return null;
    }
  }

  Future<void> syncUser(User? user) async {
    if (user == null || user.isAnonymous) return;
    final email = user.email?.toLowerCase().trim();
    await firestore.collection('users').doc(user.uid).set({
      'email': email,
      'displayName': user.displayName,
      'photoUrl': user.photoURL,
      'isAnonymous': false,
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (email == null || !initialAdminEmails.contains(email)) return;
    final roleRef = firestore.collection('userRoles').doc(user.uid);
    final role = await roleRef.get();
    if (role.exists) return;
    await roleRef.set({
      'role': 'admin',
      'email': email,
      'bootstrappedAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Sign in anonymously if not already, returning the uid. Safe to call more
/// than once — Firebase reuses the existing anonymous user. Waits for the
/// first auth-state emission so a session still being restored (e.g. the
/// return leg of a redirect sign-in) is never clobbered by a fresh
/// anonymous account.
Future<String> ensureSignedIn(FirebaseAuth auth) async {
  final restored = await auth.authStateChanges().first;
  final current = restored ?? auth.currentUser;
  if (current != null) return current.uid;
  final cred = await auth.signInAnonymously();
  return cred.user!.uid;
}
