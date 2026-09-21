/// Hands this device's posts to Firestore in the order they were tapped
/// (issue #57) — pure Dart (no Firebase/Flutter imports), so the ordering is
/// directly unit-testable.
///
/// The status everyone sees is a site's newest status report, and the server
/// stamps a report when its batch **commits** — which is not at the tap. A
/// post first awaits sign-in, the proximity gate's GPS fix and, on the
/// activity path only, a participation-stats read. Run side by side, whichever
/// post got through those first committed first: a Camera Only / BGD press
/// corrected with Closed a second later landed *after* its correction (its
/// stats read still out on a weak connection) and stood for everyone, on
/// every build, for the next 10 hours.
///
/// So posts take turns. Each starts only once the one before it has **handed
/// its first write to the SDK**, which sends writes in the order it was given
/// them, online or off. Never once that write is *acknowledged*: offline an
/// ack never comes, and a post still waiting here dies with the app.
///
/// With one exception, because a refused write is re-sent in another shape
/// (the rate-limit ledger, `rate_limit.dart`) and the re-send joins the SDK's
/// queue at the **back** — behind any post let through meanwhile, which would
/// then land first. So a post the server has just refused is back in the way
/// until it settles, and every write, first or re-sent, waits for the posts
/// ahead of it. That is no wait on a dead link: a refusal is proof the server
/// answered a moment ago.
library;

import 'dart:async';

/// How a post gives the SDK a write: `write(batch.commit)`, for every attempt.
/// [PostSequencer] runs `issue` when the posts ahead are out of the way, and
/// completes — or fails — as the write itself does.
typedef PostWrite = Future<void> Function(Future<void> Function() issue);

class PostSequencer {
  PostSequencer({this.patience = const Duration(minutes: 1)});

  /// The longest a post stays in the way without anything happening: from the
  /// start of its turn to its first write, and from a refusal to the server's
  /// next answer. Past any wait a post causes by itself (the gate's GPS fix
  /// gives up at 15 s) — what outlasts it is a post that hung, a link that
  /// dropped mid-retry, or a permission prompt left unanswered. Without it,
  /// one stuck post would silently hold back every later one for the rest of
  /// the session, each of them showing as posted (issue #50). A post passed
  /// over this way may still land, just no longer in order: the worst that
  /// could happen to any post before there was an order at all.
  final Duration patience;

  /// The posts that have not ended yet, in tap order.
  final _turns = <_Turn>[];

  /// Runs [post] once the posts before it are out of the way — each has handed
  /// its write over, ended without one, or outlasted [patience]. The turn is
  /// taken synchronously: call this at the tap, before any await, and with
  /// nothing ahead [post] starts synchronously too.
  ///
  /// [post] gives the SDK every write through the [PostWrite] it is handed —
  /// the first and any re-send alike — and ending, either way, ends its turn:
  /// a post refused before it wrote anything must not block the next.
  Future<T> run<T>(Future<T> Function(PostWrite write) post) async {
    final turn = _Turn(patience);
    _turns.add(turn);
    try {
      for (var e = _aheadOf(turn); e != null; e = _aheadOf(turn)) {
        await e.outOfTheWay;
      }
      turn.begin();
      return await post((issue) => _write(turn, issue));
    } finally {
      turn.end();
      _turns.remove(turn);
    }
  }

  Future<void> _write(_Turn turn, Future<void> Function() issue) async {
    for (var e = _aheadOf(turn); e != null; e = _aheadOf(turn)) {
      await e.outOfTheWay;
    }
    // The same synchronous run as the loop's last check: no refusal — and so
    // no re-send of an earlier post — can come between the two. (An async
    // helper for the loop would put a microtask boundary right here.)
    final issued = issue();
    turn.handedOver();
    try {
      await issued;
    } catch (_) {
      turn.refused();
      rethrow;
    }
  }

  /// The first post tapped before [turn] that is still in its way.
  _Turn? _aheadOf(_Turn turn) {
    if (turn.ended) return null;
    for (final earlier in _turns) {
      if (identical(earlier, turn)) break;
      if (earlier.inTheWay) return earlier;
    }
    return null;
  }
}

class _Turn {
  _Turn(this._patience);

  final Duration _patience;
  var _handedOver = false;
  var _refused = false;
  var ended = false;
  Timer? _stalled;
  var _moved = Completer<void>();

  /// No write with the SDK yet, or one the server refused: what this post
  /// sends next has to go ahead of any later post's.
  bool get inTheWay => !_handedOver || _refused;

  /// Completes when this post is next out of the way. It can be back in it
  /// (a refusal), so whoever waited checks again.
  Future<void> get outOfTheWay => _moved.future;

  void begin() => _expectProgress();

  void handedOver() {
    _handedOver = true;
    if (!_refused) _stepAside();
  }

  void refused() {
    if (ended) return;
    _refused = true;
    if (_moved.isCompleted) _moved = Completer<void>();
    _expectProgress();
  }

  void end() {
    ended = true;
    _stepAside();
  }

  void _expectProgress() {
    _stalled?.cancel();
    _stalled = Timer(_patience, _stepAside);
  }

  void _stepAside() {
    _stalled?.cancel();
    _handedOver = true;
    _refused = false;
    if (!_moved.isCompleted) _moved.complete();
  }
}
