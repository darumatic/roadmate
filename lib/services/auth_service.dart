import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(
    auth: ref.watch(firebaseAuthProvider),
    firestore: FirebaseFirestore.instance,
  );
});

class AuthController {
  AuthController({required this.auth, required this.firestore});

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  Future<UserCredential> signInWithGoogle() {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});
    return _signInWithProvider(provider);
  }

  Future<void> signOut() => auth.signOut();

  Future<UserCredential> _signInWithProvider(AuthProvider provider) async {
    final current = auth.currentUser;
    UserCredential credential;
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

    await syncUser(credential.user);
    return credential;
  }

  // firebase_auth exposes the *Provider variants only on mobile/desktop; web
  // must use the popup flow, otherwise it throws UnimplementedError.
  Future<UserCredential> _signIn(AuthProvider provider) {
    return kIsWeb
        ? auth.signInWithPopup(provider)
        : auth.signInWithProvider(provider);
  }

  Future<UserCredential> _linkCurrentUser(User user, AuthProvider provider) {
    return kIsWeb
        ? user.linkWithPopup(provider)
        : user.linkWithProvider(provider);
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
/// than once — Firebase reuses the existing anonymous user.
Future<String> ensureSignedIn(FirebaseAuth auth) async {
  final current = auth.currentUser;
  if (current != null) return current.uid;
  final cred = await auth.signInAnonymously();
  return cred.user!.uid;
}
