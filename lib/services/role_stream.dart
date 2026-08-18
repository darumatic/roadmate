/// The stream behind `currentUserRoleProvider` — pure Dart (no Firebase
/// imports), so the switching/retry behaviour that decides whether the admin
/// UI tracks auth changes is directly unit-testable.
///
/// Deliberately mirrors `profile_stream.dart` (same bug family, fixed the
/// same release): the old `await for` + `yield*` shape parked the provider
/// inside a never-ending Firestore listener, so a sign-out or account switch
/// after the first sign-in was never observed — the admin UI stayed on the
/// old identity until restart — and a single listener error killed the
/// stream for the session. Kept separate rather than shared with
/// profileStream: the claim-echo overlay there doesn't layer cleanly over a
/// generic combinator, and each flat version stays simple enough to read.
library;

import 'dart:async';

/// The slice of the Firebase auth user the role stream needs.
class RoleAuthUser {
  const RoleAuthUser({required this.uid, required this.isAnonymous});

  final String uid;
  final bool isAnonymous;
}

/// Builds the current-user-role stream.
///
/// - [authUsers]: the auth state (null = signed out). The newest emission
///   always wins; signed-out and anonymous users get [anonymousRole] with no
///   doc listener at all (an anonymous uid has no `userRoles` doc — don't
///   pay for a listener that can only say "not admin").
/// - [roleDocOf]: opens the `userRoles/{uid}` doc listener for a signed-in
///   user; may error. An error is fail-soft — [anonymousRole] when nothing
///   was emitted yet (fail closed, never a phantom admin), the last emission
///   otherwise — and the listener re-opens after [retryDelay] instead of
///   staying dead for the session. The rules enforce admin rights regardless;
///   this stream only drives UI.
Stream<T> roleStream<T>({
  required Stream<RoleAuthUser?> authUsers,
  required Stream<T> Function(String uid) roleDocOf,
  required T anonymousRole,
  Duration retryDelay = const Duration(seconds: 5),
}) {
  final controller = StreamController<T>();
  StreamSubscription<RoleAuthUser?>? authSub;
  StreamSubscription<T>? docSub;
  Timer? retry;
  RoleAuthUser? user;
  var emittedAnything = false;

  void emit(T role) {
    emittedAnything = true;
    if (!controller.isClosed) controller.add(role);
  }

  void openDoc() {
    docSub?.cancel();
    final current = user;
    if (current == null || current.isAnonymous) return;
    docSub = roleDocOf(current.uid).listen(
      emit,
      onError: (Object _) {
        docSub?.cancel();
        docSub = null;
        if (!emittedAnything) emit(anonymousRole);
        retry?.cancel();
        retry = Timer(retryDelay, openDoc);
      },
    );
  }

  void onAuth(RoleAuthUser? next) {
    final previous = user;
    user = next;
    // Token refreshes fire userChanges too; don't churn a healthy listener
    // when the identity is unchanged.
    if (next != null &&
        previous != null &&
        docSub != null &&
        next.uid == previous.uid &&
        next.isAnonymous == previous.isAnonymous) {
      return;
    }
    retry?.cancel();
    docSub?.cancel();
    docSub = null;
    if (next == null || next.isAnonymous) {
      emit(anonymousRole);
      return;
    }
    openDoc();
  }

  controller.onListen = () {
    authSub = authUsers.listen(onAuth, onError: (Object _) {
      emit(anonymousRole);
    });
  };
  controller.onCancel = () {
    retry?.cancel();
    authSub?.cancel();
    docSub?.cancel();
  };
  return controller.stream;
}
