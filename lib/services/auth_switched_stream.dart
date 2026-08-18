/// One combinator for every "per-user Firestore listener" stream — pure Dart
/// (no Firebase imports), so the behaviour is directly unit-testable.
///
/// The app used to hand-roll this shape four times (profile, role, stats,
/// favourites) as `authChanges.asyncExpand((user) => doc.snapshots())`, and
/// that shape has two latent bugs which both shipped: `asyncExpand` waits for
/// the inner stream to *complete* before taking the next auth event — a
/// Firestore listener never completes, so a later sign-in/out was queued
/// forever behind the old identity's listener — and a terminal listener error
/// (how Firestore listeners die) silently ended updates for the session.
/// The 0.1.74 nickname re-prompt bug was exactly this. Every auth-scoped
/// stream must go through here instead.
library;

import 'dart:async';

/// Builds a stream that follows the auth user and, for each signed-in user,
/// relays their [sourceOf] listener.
///
/// - [authUsers]: the auth identity (null = nothing to listen for — signed
///   out, or an identity the caller maps away, e.g. anonymous users for the
///   role stream). The NEWEST emission always wins: the previous identity's
///   listener is cancelled, never queued behind.
/// - [sourceOf]: opens the per-user listener; may error. An error is
///   fail-soft — [signedOutValue] when nothing was emitted yet, the last
///   emission otherwise (never an error downstream) — and the listener
///   re-opens after [retryDelay] instead of staying dead for the session.
/// - [isSameIdentity]: when the new auth emission is the same identity (e.g.
///   a token refresh re-firing userChanges), a healthy listener is kept
///   rather than churned. Defaults to `==`, which is right when A is a uid.
/// - [onSwitch]: called for every auth emission before anything is emitted —
///   a hook for callers that keep per-identity state (the profile stream's
///   claimed-name echo).
Stream<T> authSwitchedStream<A, T>({
  required Stream<A?> authUsers,
  required Stream<T> Function(A user) sourceOf,
  required T signedOutValue,
  bool Function(A previous, A next)? isSameIdentity,
  void Function(A? next)? onSwitch,
  Duration retryDelay = const Duration(seconds: 5),
}) {
  final controller = StreamController<T>();
  StreamSubscription<A?>? authSub;
  StreamSubscription<T>? sourceSub;
  Timer? retry;
  A? user;
  var emittedAnything = false;

  void emit(T value) {
    emittedAnything = true;
    if (!controller.isClosed) controller.add(value);
  }

  void openSource() {
    sourceSub?.cancel();
    final current = user;
    if (current == null) return;
    sourceSub = sourceOf(current).listen(
      emit,
      onError: (Object _) {
        sourceSub?.cancel();
        sourceSub = null;
        if (!emittedAnything) emit(signedOutValue);
        retry?.cancel();
        retry = Timer(retryDelay, openSource);
      },
    );
  }

  void onAuth(A? next) {
    final previous = user;
    user = next;
    onSwitch?.call(next);
    final unchanged =
        next != null &&
        previous != null &&
        (isSameIdentity?.call(previous, next) ?? next == previous);
    if (unchanged && sourceSub != null) return;
    retry?.cancel();
    sourceSub?.cancel();
    sourceSub = null;
    if (next == null) {
      emit(signedOutValue);
      return;
    }
    openSource();
  }

  controller.onListen = () {
    authSub = authUsers.listen(
      onAuth,
      onError: (Object _) => emit(signedOutValue),
    );
  };
  controller.onCancel = () {
    retry?.cancel();
    authSub?.cancel();
    sourceSub?.cancel();
  };
  return controller.stream;
}
