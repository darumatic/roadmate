/// This device's own votes and reports the app's listeners can't show yet
/// (issue #50) — pure Dart (no Firebase/Flutter imports), so the lifecycle is
/// directly unit-testable.
///
/// A post is written with `FieldValue.serverTimestamp()`, and until the server
/// acknowledges it neither listener has anything to show. The report is not
/// in the shared recent-reports listener at all: its query filters
/// `createdAt >= cutoff`, the Firestore SDK only compares same-typed values,
/// and a pending server timestamp is not a Timestamp — so the document first
/// appears at acknowledgement, already carrying its real time. The site doc's
/// pending `lastReportAt` reads as null meanwhile (`Query.snapshots()` has no
/// `serverTimestampBehavior` to ask for an estimate). A tap therefore changed
/// nothing on screen until the ack: seconds on a weak connection, indefinitely
/// offline — which invites repeat taps that all queue up and post later.
///
/// So each post is held here from the tap, and `withEffectiveStatus` /
/// `withInFlightPosts` (status_logic.dart) lay it over what the listeners
/// deliver. A held post carries **the id of the document it becomes**, which
/// is what makes the hand-over exact: the moment the listener delivers that
/// document the held copy is shadowed by it, whichever of the write's future
/// and the listener's snapshot the platform happens to raise first.
library;

import 'dart:async';

import '../models/site_report.dart';

class InFlightPosts {
  InFlightPosts({this.landingGrace = const Duration(seconds: 10)});

  /// How long an acknowledged post is still held. The write's future and the
  /// listener's snapshot are separate events and the SDK raises the future
  /// first, so dropping the post at the ack would flash the previous status in
  /// between. Holding it costs nothing — a delivered document shadows it by id
  /// — but it must not be held for long: a post whose document an admin has
  /// since removed would come back on its author's screen.
  final Duration landingGrace;

  final _changes = StreamController<List<SiteReport>>.broadcast();
  final _landing = <Timer>{};
  List<SiteReport> _posts = const [];

  /// The held posts in posting order, oldest first.
  List<SiteReport> get current => _posts;

  /// Every later value of [current].
  Stream<List<SiteReport>> get changes => _changes.stream;

  /// Shows [post] from now on and runs [write] — all of it, sign-in and the
  /// proximity gate included, so the feedback is at the tap and not after a
  /// GPS fix. A [write] that fails takes the post back down and rethrows (the
  /// caller's error snack says why); one that completes has been acknowledged
  /// by the server, and the post is held for [landingGrace] more.
  ///
  /// Offline the write's future simply stays open, and so does the post: the
  /// SDK sends the write when the connection returns.
  Future<T> track<T>(SiteReport post, Future<T> Function() write) async {
    _set([..._posts, post]);
    final T result;
    try {
      result = await write();
    } catch (_) {
      _drop(post);
      rethrow;
    }
    if (!_changes.isClosed) {
      late final Timer timer;
      timer = Timer(landingGrace, () {
        _landing.remove(timer);
        _drop(post);
      });
      _landing.add(timer);
    }
    return result;
  }

  void _drop(SiteReport post) =>
      _set([..._posts.where((held) => !identical(held, post))]);

  void _set(List<SiteReport> posts) {
    _posts = List.unmodifiable(posts);
    if (!_changes.isClosed) _changes.add(_posts);
  }

  void dispose() {
    for (final timer in _landing) {
      timer.cancel();
    }
    _landing.clear();
    _changes.close();
  }
}
