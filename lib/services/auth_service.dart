import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ensures the user is signed in anonymously and exposes their uid. Anonymous
/// auth is the device-based identity used to attribute votes/reports/saves
/// without a login wall.
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Sign in anonymously if not already, returning the uid. Safe to call more
/// than once — Firebase reuses the existing anonymous user.
Future<String> ensureSignedIn(FirebaseAuth auth) async {
  final current = auth.currentUser;
  if (current != null) return current.uid;
  final cred = await auth.signInAnonymously();
  return cred.user!.uid;
}
