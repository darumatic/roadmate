import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/in_flight_posts.dart';

SiteReport _vote(String id, {SiteStatus status = SiteStatus.blitz}) =>
    SiteReport(
      id: id,
      siteId: 's1',
      createdAt: DateTime(2026, 9, 20, 12),
      status: status,
    );

/// Issue #50: a vote or report showed nothing until the server acknowledged
/// it. `InFlightPosts` holds each post from the tap; these pin its lifecycle.
/// (testWidgets for its fake clock — the landing grace runs in microseconds.)
void main() {
  testWidgets('a post is held from the moment it is made, before its write '
      'has done anything', (tester) async {
    final posts = InFlightPosts();
    addTearDown(posts.dispose);
    final write = Completer<void>();

    unawaited(posts.track(_vote('r1'), () => write.future));

    expect(posts.current.map((p) => p.id), ['r1']);
  });

  testWidgets('a write that never completes keeps its post: offline the SDK '
      'sends it when the connection returns', (tester) async {
    final posts = InFlightPosts();
    addTearDown(posts.dispose);

    unawaited(posts.track(_vote('r1'), () => Completer<void>().future));
    await tester.pump(const Duration(hours: 3));

    expect(posts.current.map((p) => p.id), ['r1']);
  });

  testWidgets('a failed write takes the post back down and rethrows, so the '
      "caller's error snack still says why", (tester) async {
    final posts = InFlightPosts();
    addTearDown(posts.dispose);
    final write = Completer<void>();
    Object? caught;

    unawaited(
      posts
          .track(_vote('r1'), () => write.future)
          .catchError((Object e) => caught = e),
    );
    write.completeError(StateError('rate limited'));
    await tester.pump();

    expect(caught, isA<StateError>());
    expect(posts.current, isEmpty);
  });

  testWidgets('an acknowledged post is held for the landing grace — the '
      "listener's snapshot is a separate event from the write's future — and "
      'then dropped', (tester) async {
    final posts = InFlightPosts();
    addTearDown(posts.dispose);
    final write = Completer<String>();
    String? result;

    unawaited(
      posts.track(_vote('r1'), () => write.future).then((r) => result = r),
    );
    write.complete('acked');
    await tester.pump();

    expect(result, 'acked');
    expect(posts.current.map((p) => p.id), ['r1']);

    await tester.pump(posts.landingGrace - const Duration(milliseconds: 1));
    expect(posts.current.map((p) => p.id), ['r1']);

    // Not for long: a held post whose document an admin has since removed
    // would otherwise come back on its author's screen.
    await tester.pump(const Duration(milliseconds: 1));
    expect(posts.current, isEmpty);
  });

  testWidgets('posts are independent: each settles on its own write, and the '
      'list keeps posting order', (tester) async {
    final posts = InFlightPosts();
    addTearDown(posts.dispose);
    final first = Completer<void>();
    final second = Completer<void>();

    unawaited(posts.track(_vote('r1'), () => first.future));
    unawaited(
      posts
          .track(_vote('r2', status: SiteStatus.closed), () => second.future)
          .catchError((Object _) {}),
    );
    expect(posts.current.map((p) => p.id), ['r1', 'r2']);

    second.completeError(StateError('too far'));
    await tester.pump();
    expect(posts.current.map((p) => p.id), ['r1']);

    first.complete();
    await tester.pump(posts.landingGrace);
    expect(posts.current, isEmpty);
  });

  testWidgets('changes reports every value of the list', (tester) async {
    final posts = InFlightPosts();
    addTearDown(posts.dispose);
    final seen = <List<String>>[];
    final sub = posts.changes.listen(
      (held) => seen.add([for (final p in held) p.id]),
    );
    addTearDown(sub.cancel);
    final write = Completer<void>();

    unawaited(posts.track(_vote('r1'), () => write.future));
    await tester.pump();
    write.complete();
    await tester.pump(posts.landingGrace);

    expect(seen, [
      ['r1'],
      <String>[],
    ]);
  });

  // Neither test pumps the clock after dispose(): a timer still running then
  // fails it ("A Timer is still pending even after the widget tree was
  // disposed") — which IS the assertion.
  testWidgets('dispose cancels the landing timers', (tester) async {
    final posts = InFlightPosts();
    final write = Completer<void>();

    unawaited(posts.track(_vote('r1'), () => write.future));
    write.complete();
    await tester.pump(); // acknowledged: the landing timer is running
    expect(posts.current, hasLength(1));

    posts.dispose();
  });

  testWidgets('a write that settles after dispose is harmless: an ack starts '
      'no timer, and a failure still reaches its caller as itself', (
    tester,
  ) async {
    final posts = InFlightPosts();
    final acked = Completer<void>();
    final refused = Completer<void>();
    final refusal = Exception('rate limited');
    Object? caught;

    unawaited(posts.track(_vote('r1'), () => acked.future));
    unawaited(
      posts
          .track(_vote('r2'), () => refused.future)
          .catchError((Object e) => caught = e),
    );

    posts.dispose();
    acked.complete();
    refused.completeError(refusal);
    await tester.pump(); // zero duration: runs the continuations, no timers

    // Not "Bad state: Cannot add event after closing" in its place.
    expect(caught, same(refusal));
  });
}
