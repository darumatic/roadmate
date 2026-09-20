/// A Firestore listener over a sliding time window ("the last 10 hours") whose
/// full re-runs never reach further back than the window — pure Dart (no
/// Firebase imports), so the behaviour is directly unit-testable.
///
/// The query behind such a listener has to bake its cutoff in when it starts
/// (`createdAt >= start − window`), and while it stays connected that wastes
/// nothing: Firestore bills one read per NEW document. The waste comes when
/// Firestore re-runs the whole query — after the listener has been
/// disconnected for more than 30 minutes it is billed "as if you had issued a
/// brand-new query", with the ORIGINAL cutoff. A tab left open for three days
/// re-read 3.4 days of reports on every wake-up to show the last 10 hours.
///
/// So the listener is re-opened with a fresh cutoff at exactly the moments a
/// full re-run is unavoidable anyway — and at no other time. **Never on a
/// timer while connected:** every re-subscribe is itself a brand-new query
/// that re-bills the whole window, so an hourly refresh would cost roughly ten
/// times what it saves.
library;

import 'dart:async';

import 'package:clock/clock.dart';

/// Firestore's own rule: a listener disconnected for longer than this is
/// re-billed in full when it comes back; within it, a resume token makes the
/// reconnect cost only what changed.
const Duration listenerResumeWindow = Duration(minutes: 30);

/// How often production asks "has anything gone stale?" (see `checks`).
const Duration listenerCheckInterval = Duration(minutes: 1);

/// One snapshot of the window, with what the combinator needs to know about
/// where it came from.
class WindowSnapshot<T> {
  const WindowSnapshot(
    this.value, {
    required this.isFromCache,
    this.dataChanged = true,
  });

  final T value;

  /// True while the listener is being served from the local cache — i.e. it is
  /// disconnected. The Firestore listener must be opened with
  /// `includeMetadataChanges: true` to see this flip.
  final bool isFromCache;

  /// False for a metadata-only event (the connection state flipped, the data
  /// did not). Those feed the offline clock but are not re-emitted, so
  /// consumers rebuild exactly as often as they would without any of this.
  final bool dataChanged;
}

/// Relays the listener [open] returns for the cutoff `now − window`, swapping
/// it for one with a fresh cutoff when — and only when — its next reconnect
/// would be a full re-run anyway:
///
/// - **suspended:** the gap between two consecutive [checks] reached
///   [resumeWindow] + [checkInterval]. Checks are a steady tick plus "the app
///   just came back" events; a frozen process ticks nothing, so the first
///   check after waking sees the whole gap, and the resume event makes that
///   check immediate — before the SDK has reconnected and re-sent the stale
///   query. (The extra [checkInterval] is because the gap is measured from the
///   last tick, up to one interval before the freeze: never swap a listener
///   that could still have resumed for free.)
/// - **offline:** its snapshots have been from-cache for [resumeWindow].
///   Swapping while offline costs nothing — the SDK re-sends only the
///   listeners that still exist when the connection returns — and repeats
///   every [resumeWindow] while the outage lasts.
///
/// A swap opens the new listener first and cancels the old one in the same
/// turn, then emits nothing until the new one answers: downstream keeps the
/// last value, so no screen ever blanks, and on the web's in-memory cache the
/// documents stay referenced throughout. Nothing a consumer can see is lost —
/// only documents older than the window are dropped, which every consumer
/// filters out anyway — and no update can be missed, because a listener
/// delivers the full current result when it starts.
///
/// Errors are forwarded untouched: recovery (fail-soft to stored statuses,
/// pull-to-refresh, the provider's own retry) stays where it already lives.
Stream<T> freshWindowStream<T>({
  required Stream<WindowSnapshot<T>> Function(DateTime cutoff) open,
  required Duration window,
  required Stream<void> checks,
  DateTime Function()? now,
  Duration resumeWindow = listenerResumeWindow,
  Duration checkInterval = listenerCheckInterval,
}) {
  final timeNow = now ?? () => clock.now();
  final controller = StreamController<T>();
  StreamSubscription<WindowSnapshot<T>>? sourceSub;
  StreamSubscription<void>? checksSub;
  var lastCheckAt = timeNow();
  DateTime? offlineSince;
  var awaitingFirst = true;

  void onSnapshot(WindowSnapshot<T> snapshot) {
    if (snapshot.isFromCache) {
      offlineSince ??= timeNow();
    } else {
      offlineSince = null;
    }
    // A listener's first answer always goes out, whatever it says about
    // itself: it is what ends the silence of a swap.
    if (!awaitingFirst && !snapshot.dataChanged) return;
    awaitingFirst = false;
    if (!controller.isClosed) controller.add(snapshot.value);
  }

  void openSource() {
    final stale = sourceSub;
    awaitingFirst = true;
    offlineSince = null;
    try {
      sourceSub = open(timeNow().subtract(window)).listen(
        onSnapshot,
        onError: (Object error, StackTrace stack) {
          if (!controller.isClosed) controller.addError(error, stack);
        },
      );
    } catch (error, stack) {
      sourceSub = null;
      if (!controller.isClosed) controller.addError(error, stack);
    }
    // After the new one is attached, never before — see the doc comment.
    stale?.cancel();
  }

  void onCheck() {
    final at = timeNow();
    final sinceLastCheck = at.difference(lastCheckAt);
    lastCheckAt = at;
    final suspended = sinceLastCheck >= resumeWindow + checkInterval;
    final since = offlineSince;
    final offline = since != null && at.difference(since) >= resumeWindow;
    if (suspended || offline) openSource();
  }

  controller.onListen = () {
    lastCheckAt = timeNow();
    openSource();
    checksSub = checks.listen((_) => onCheck());
  };
  controller.onCancel = () {
    checksSub?.cancel();
    sourceSub?.cancel();
  };
  return controller.stream;
}
