import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_service.dart';
import 'rate_limit.dart';
import 'username_logic.dart';

/// What the current user signs their posts with.
///
/// A picked road name always wins; a signed-in account without one falls back
/// to its provider displayName; an anonymous user without one has no
/// signature at all — and posting paths must then ask them to pick one.
class UserProfile {
  const UserProfile({
    required this.isAnonymous,
    this.username,
    this.displayName,
  });

  final bool isAnonymous;

  /// The unique road name, when one has been claimed.
  final String? username;

  /// Provider (Google/Apple) display name, when signed in.
  final String? displayName;

  String? get signature {
    final name = username?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (isAnonymous) return null;
    final display = displayName?.trim();
    return (display == null || display.isEmpty) ? null : display;
  }
}

class UsernameTakenException implements Exception {
  const UsernameTakenException(this.name);
  final String name;
  String get message => '"$name" is already taken — try another.';
}

class UsernameInvalidException implements Exception {
  const UsernameInvalidException(this.message);
  final String message;
}

/// Storage for road names. Firestore-backed in production;
/// [MemoryUsernameStore] serves tests and Firebase-less dev runs.
abstract class UsernameStore {
  /// The current user's profile; null while signed out (or before auth
  /// resolves). Fail-soft: a broken stream yields null rather than an error,
  /// so the load-time prompt can never wedge itself on screen.
  Stream<UserProfile?> watchProfile();

  /// Claims [rawName] (normalized) for the current user, releasing any name
  /// they held before. Returns the stored name. Throws
  /// [UsernameInvalidException] / [UsernameTakenException].
  Future<String> claimUsername(String rawName);
}

/// Firestore model: `usernames/{key}` (key = lowercased name) is the
/// uniqueness claim — create-if-free is enforced by the rules — and the
/// display-cased name is denormalized onto `users/{uid}.username`. Both are
/// written in one transaction so a claim and its profile can never disagree.
class FirestoreUsernameStore implements UsernameStore {
  FirestoreUsernameStore({required this.firestore, required this.auth});

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  @override
  Stream<UserProfile?> watchProfile() {
    // userChanges (not authStateChanges) so linking a provider onto the
    // anonymous uid is observed — same reasoning as authStateProvider.
    return auth.userChanges().asyncExpand((user) {
      if (user == null) return Stream<UserProfile?>.value(null);
      return firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .map<UserProfile?>((snap) {
            final data = snap.data();
            return UserProfile(
              isAnonymous: user.isAnonymous,
              username: data?['username'] as String?,
              displayName: user.displayName ?? data?['displayName'] as String?,
            );
          })
          .transform(
            StreamTransformer.fromHandlers(
              handleError: (error, stackTrace, EventSink<UserProfile?> sink) =>
                  sink.add(null),
            ),
          );
    });
  }

  @override
  Future<String> claimUsername(String rawName) async {
    final name = normalizeUsername(rawName);
    final error = validateUsername(name);
    if (error != null) throw UsernameInvalidException(error);

    final uid = await ensureSignedIn(auth);
    final isAnonymous = auth.currentUser?.isAnonymous ?? true;
    final key = usernameKey(name);
    final claimRef = firestore.collection('usernames').doc(key);
    final userRef = firestore.collection('users').doc(uid);

    try {
      await firestore.runTransaction((tx) async {
        final claim = await tx.get(claimRef);
        if (claim.exists && claim.data()?['uid'] != uid) {
          throw UsernameTakenException(name);
        }
        // Renaming releases the old claim so the name frees up for others.
        final me = await tx.get(userRef);
        final old = me.data()?['username'] as String?;
        if (old != null && old.trim().isNotEmpty && usernameKey(old) != key) {
          tx.delete(firestore.collection('usernames').doc(usernameKey(old)));
        }
        tx.set(claimRef, {
          'uid': uid,
          'username': name,
          'createdAt': FieldValue.serverTimestamp(),
        });
        tx.set(userRef, {
          'username': name,
          'isAnonymous': isAnonymous,
          'lastSeenAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      if (e is UsernameTakenException) rethrow;
      // A create-vs-create race loses as a rules denial (the doc exists by
      // the time the loser commits). One follow-up read turns that into the
      // honest answer; any other denial (e.g. a ban) surfaces unchanged.
      if (isRulesDenial(e)) {
        final claim = await claimRef.get();
        if (claim.exists && claim.data()?['uid'] != uid) {
          throw UsernameTakenException(name);
        }
      }
      rethrow;
    }
    return name;
  }
}

/// In-memory [UsernameStore] for tests and Firebase-less runs. Starts with no
/// profile (as if auth never resolved), so pumping the whole app never shows
/// the load-time prompt unless a test asks for it via [initialProfile].
class MemoryUsernameStore implements UsernameStore {
  MemoryUsernameStore({UserProfile? initialProfile, Set<String>? takenNames})
    : _profile = initialProfile,
      _taken = {
        for (final name in takenNames ?? const <String>{}) usernameKey(name),
      };

  UserProfile? _profile;
  final Set<String> _taken;
  final _controller = StreamController<UserProfile?>.broadcast();

  @override
  Stream<UserProfile?> watchProfile() async* {
    yield _profile;
    yield* _controller.stream;
  }

  @override
  Future<String> claimUsername(String rawName) async {
    final name = normalizeUsername(rawName);
    final error = validateUsername(name);
    if (error != null) throw UsernameInvalidException(error);
    final key = usernameKey(name);
    final old = _profile?.username;
    final oldKey = (old == null || old.trim().isEmpty)
        ? null
        : usernameKey(old);
    if (_taken.contains(key) && key != oldKey) {
      throw UsernameTakenException(name);
    }
    if (oldKey != null) _taken.remove(oldKey);
    _taken.add(key);
    _profile = UserProfile(
      isAnonymous: _profile?.isAnonymous ?? true,
      username: name,
      displayName: _profile?.displayName,
    );
    _controller.add(_profile);
    return name;
  }

  void dispose() => _controller.close();
}
