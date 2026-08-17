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
  StreamSubscription<ProfileAuthUser?>? authSub;
  StreamSubscription<UserProfile?>? docSub;
  StreamSubscription<ClaimedName>? claimSub;
  Timer? retry;
  ProfileAuthUser? user;
  var emittedAnything = false;
  String? claimedUid;
  String? claimedName;

  void emit(UserProfile? profile) {
    emittedAnything = true;
    if (!controller.isClosed) controller.add(profile);
  }

  void openDoc() {
    docSub?.cancel();
    final current = user;
    if (current == null) return;
    docSub = profileDocOf(current).listen(
      (profile) {
        final echoed = claimedUid == current.uid ? claimedName : null;
        if (profile != null &&
            echoed != null &&
            (profile.username == null || profile.username!.trim().isEmpty)) {
          profile = UserProfile(
            isAnonymous: profile.isAnonymous,
            username: echoed,
            displayName: profile.displayName,
          );
        }
        emit(profile);
      },
      onError: (Object _) {
        docSub?.cancel();
        docSub = null;
        if (!emittedAnything) emit(null);
        retry?.cancel();
        retry = Timer(retryDelay, openDoc);
      },
    );
  }

  void onAuth(ProfileAuthUser? next) {
    final previous = user;
    user = next;
    if (next?.uid != claimedUid) {
      claimedUid = null;
      claimedName = null;
    }
    // Token refreshes fire userChanges too; don't churn a healthy listener
    // when nothing the profile depends on has changed.
    if (next != null &&
        previous != null &&
        docSub != null &&
        next.uid == previous.uid &&
        next.isAnonymous == previous.isAnonymous &&
        next.displayName == previous.displayName) {
      return;
    }
    retry?.cancel();
    docSub?.cancel();
    docSub = null;
    if (next == null) {
      emit(null);
      return;
    }
    openDoc();
  }

  controller.onListen = () {
    authSub = authUsers.listen(onAuth, onError: (Object _) => emit(null));
    claimSub = localClaims?.listen((claim) {
      claimedUid = claim.uid;
      claimedName = claim.profile.username;
      emit(claim.profile);
    });
  };
  controller.onCancel = () {
    retry?.cancel();
    authSub?.cancel();
    docSub?.cancel();
    claimSub?.cancel();
  };
  return controller.stream;
}
