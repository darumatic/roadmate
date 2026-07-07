import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
};

enum AppUserRole { anonymous, truckie, admin }

// userChanges() (not authStateChanges()) so the UI reacts when an anonymous
// account is *linked* to a provider — linking keeps the same uid, so
// authStateChanges() never fires for it.
final authStateProvider = StreamProvider<User?>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value(null);
  return ref.watch(firebaseAuthProvider).userChanges();
});

final currentUserRoleProvider = StreamProvider<AppUserRole>((ref) async* {
  if (Firebase.apps.isEmpty) {
    yield AppUserRole.anonymous;
    return;
  }

  final auth = ref.watch(firebaseAuthProvider);
  final firestore = FirebaseFirestore.instance;
  await for (final user in auth.userChanges()) {
    if (user == null) {
      yield AppUserRole.anonymous;
      continue;
    }
    if (user.isAnonymous) {
      yield AppUserRole.anonymous;
      continue;
    }

    yield* firestore.collection('userRoles').doc(user.uid).snapshots().map((
      doc,
    ) {
      final role = doc.data()?['role'] as String?;
      return role == 'admin' ? AppUserRole.admin : AppUserRole.truckie;
    });
  }
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
  });

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  /// Injectable so the web-only popup/redirect paths are testable on the VM.
  final bool isWeb;

  /// Returns null when a full-page redirect was started instead (blocked
  /// popup) — the page is about to navigate away and sign-in completes on
  /// the next load via [completeRedirectSignIn].
  Future<UserCredential?> signInWithGoogle() {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    return _signInWithProvider(provider);
  }

  Future<void> signOut() => auth.signOut();

  /// Finishes a redirect sign-in after the round-trip back from the provider
  /// (web only; called once at startup). No redirect pending is a no-op.
  /// Mirrors the popup path's conflict handling: if linking the anonymous
  /// user failed because the Google account already exists, sign in to that
  /// account directly.
  Future<void> completeRedirectSignIn() async {
    if (!isWeb) return;
    try {
      final result = await auth.getRedirectResult();
      await syncUser(result.user);
    } on FirebaseAuthException catch (e) {
      final credential = e.credential;
      if ((e.code == 'credential-already-in-use' ||
              e.code == 'email-already-in-use') &&
          credential != null) {
        final signedIn = await auth.signInWithCredential(credential);
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
    await syncUser(credential.user);
    return credential;
  }

  // firebase_auth exposes the *Provider variants only on mobile/desktop; web
  // must use the popup flow (falling back to a redirect when the browser
  // blocks the popup), otherwise it throws UnimplementedError.
  Future<UserCredential?> _signIn(AuthProvider provider) async {
    if (!isWeb) return auth.signInWithProvider(provider);
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
