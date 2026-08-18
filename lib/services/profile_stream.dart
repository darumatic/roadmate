/// The profile stream behind `signatureNameProvider` — pure Dart (no
/// Firebase imports), so the switching/retry/echo behaviour that decides
/// whether posting re-prompts for a road name is directly unit-testable.
///
/// Extracted from `FirestoreUsernameStore.watchProfile` after the 0.1.74
/// re-prompt bug: the old `userChanges().asyncExpand(...)` shape both queued
/// auth events forever behind a never-ending Firestore listener and, worse,
/// converted a terminal listener error into a silent `null` it never
/// recovered from — so a single dropped `users/{uid}` listener meant every
/// vote for the rest of the session asked the user to pick a name again.
library;

import 'dart:async';

import 'auth_switched_stream.dart';

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

/// The slice of the Firebase auth user the profile stream needs.
class ProfileAuthUser {
  const ProfileAuthUser({
    required this.uid,
    required this.isAnonymous,
    this.displayName,
  });

  final String uid;
  final bool isAnonymous;
  final String? displayName;
}

/// A road name `claimUsername` just committed, echoed straight into the
/// profile stream so the UI learns the name without waiting on (or trusting)
/// the doc listener.
class ClaimedName {
  const ClaimedName({required this.uid, required this.profile});

  final String uid;
  final UserProfile profile;
}

/// Builds the user-profile stream from its sources.
///
/// - [authUsers]: the auth state (null = signed out). The newest emission
///   always wins — a previous user's doc listener is cancelled, never queued
///   behind.
/// - [profileDocOf]: opens the `users/{uid}` doc listener; may error. An
///   error is fail-soft (the UI sees the last good profile, or null when
///   there was none — never an error), but the listener is re-opened after
///   [retryDelay] instead of staying dead for the session.
/// - [localClaims]: names committed by `claimUsername`, applied immediately.
///   A later doc snapshot *without* a name (e.g. served from cache) never
///   undoes a name this session already committed.
Stream<UserProfile?> profileStream({
  required Stream<ProfileAuthUser?> authUsers,
  required Stream<UserProfile?> Function(ProfileAuthUser user) profileDocOf,
  Stream<ClaimedName>? localClaims,
  Duration retryDelay = const Duration(seconds: 5),
}) {
  final controller = StreamController<UserProfile?>();
  StreamSubscription<UserProfile?>? baseSub;
  StreamSubscription<ClaimedName>? claimSub;
  ClaimedName? claimed;

  // The claim overlay: a base emission may not undo a name this session
  // already committed — whether it's a stale cache snapshot without the name
  // or a fail-soft null from a dead listener. A real sign-out (or account
  // switch) clears [claimed] via onSwitch first, so its null passes through.
  UserProfile? withClaim(UserProfile? fromBase) {
    final claim = claimed;
    if (claim == null) return fromBase;
    if (fromBase == null) return claim.profile;
    if (fromBase.username == null || fromBase.username!.trim().isEmpty) {
      return UserProfile(
        isAnonymous: fromBase.isAnonymous,
        username: claim.profile.username,
        displayName: fromBase.displayName,
      );
    }
    return fromBase;
  }

  controller.onListen = () {
    baseSub =
        authSwitchedStream<ProfileAuthUser, UserProfile?>(
          authUsers: authUsers,
          sourceOf: profileDocOf,
          signedOutValue: null,
          // userChanges fires on token refreshes too; only these three fields
          // feed the profile, so nothing else warrants churning the listener.
          isSameIdentity: (previous, next) =>
              next.uid == previous.uid &&
              next.isAnonymous == previous.isAnonymous &&
              next.displayName == previous.displayName,
          onSwitch: (next) {
            if (next?.uid != claimed?.uid) claimed = null;
          },
          retryDelay: retryDelay,
        ).listen((profile) {
          if (!controller.isClosed) controller.add(withClaim(profile));
        });
    claimSub = localClaims?.listen((claim) {
      claimed = claim;
      if (!controller.isClosed) controller.add(claim.profile);
    });
  };
  controller.onCancel = () {
    baseSub?.cancel();
    claimSub?.cancel();
  };
  return controller.stream;
}
