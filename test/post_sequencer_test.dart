import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/post_sequencer.dart';

/// A write the test answers by hand, as the server would.
class _Write {
  final _answer = Completer<void>();

  void acknowledge() => _answer.complete();
  void refuse() => _answer.completeError(StateError('denied'));
}

/// A post the test drives by hand: it starts when its turn comes, [send]s a
/// write through the sequencer whenever the test says so — [sent] records the
/// order writes actually reached the SDK in — and ends when told to.
class _Post {
  _Post(this.name, this.sent);

  final String name;
  final List<String> sent;
  final _ending = Completer<String>();
  PostWrite? _write;

  bool get started => _write != null;

  Future<String> call(PostWrite write) {
    _write = write;
    return _ending.future;
  }

  _Write send([String attempt = '']) {
    final write = _Write();
    _write!(() {
      sent.add('$name$attempt');
      return write._answer.future;
    }).ignore();
    return write;
  }

  void end() => _ending.complete(name);
  void fail(Object error) => _ending.completeError(error);
}

/// Issue #57: two quick posts could commit in the wrong order, so the EARLIER
/// tap won for everyone. `PostSequencer` makes posts take turns; these pin
/// when a post starts and when each of its writes reaches the SDK.
/// (testWidgets for its fake clock — `patience` is a minute long.)
void main() {
  late List<String> sent;
  _Post post(String name) => _Post(name, sent);

  setUp(() => sent = []);

  testWidgets('with nothing ahead of it a post starts at the tap, and its '
      'write goes out — synchronously, before anything is awaited', (
    tester,
  ) async {
    final order = PostSequencer();
    final closed = post('closed');

    unawaited(order.run(closed.call));
    expect(closed.started, isTrue);

    final write = closed.send();
    expect(sent, ['closed']);

    write.acknowledge();
    closed.end();
    await tester.pump();
  });

  testWidgets('a post starts only once the one before it has handed its '
      'write over — acknowledged or not: offline it never is', (tester) async {
    // A patience that can't be what lets the correction through.
    final order = PostSequencer(patience: const Duration(days: 1));
    final press = post('camera only');
    final correction = post('closed');

    unawaited(order.run(press.call));
    unawaited(order.run(correction.call));
    await tester.pump();
    expect(correction.started, isFalse);

    final unacknowledged = press.send();
    await tester.pump();
    expect(correction.started, isTrue);

    correction.send().acknowledge();
    await tester.pump();
    expect(sent, ['camera only', 'closed']);

    unacknowledged.acknowledge();
    press.end();
    correction.end();
    await tester.pump();
  });

  testWidgets('turns go in the order the posts were made, however many are '
      'waiting', (tester) async {
    final order = PostSequencer();
    final posts = [for (final name in 'abcd'.split('')) post(name)];
    List<String> started() => [
      for (final p in posts)
        if (p.started) p.name,
    ];

    for (final p in posts) {
      unawaited(order.run(p.call));
    }
    expect(started(), ['a']);

    for (final (i, p) in posts.indexed) {
      p.send().acknowledge();
      await tester.pump();
      expect(started(), [for (final q in posts.take(i + 2)) q.name]);
    }
    expect(sent, ['a', 'b', 'c', 'd']);

    for (final p in posts) {
      p.end();
    }
    await tester.pump();
  });

  testWidgets('a post refused before it wrote anything lets the next one '
      'through, and its error stays its own', (tester) async {
    final order = PostSequencer();
    final tooFar = post('blitz');
    final next = post('closed');
    Object? tooFarError;
    String? nextResult;

    unawaited(
      order.run(tooFar.call).catchError((Object e) {
        tooFarError = e;
        return '';
      }),
    );
    unawaited(order.run(next.call).then((name) => nextResult = name));
    tooFar.fail(StateError('too far'));
    await tester.pump();

    expect(tooFarError, isA<StateError>());
    expect(next.started, isTrue);

    next.end();
    await tester.pump();
    expect(nextResult, 'closed');
  });

  testWidgets('so does one that throws before it has awaited anything', (
    tester,
  ) async {
    final order = PostSequencer();
    final next = post('closed');
    Object? error;

    unawaited(
      order
          .run<void>((write) => throw ArgumentError('no stored form'))
          .catchError((Object e) => error = e),
    );
    unawaited(order.run(next.call));
    await tester.pump();

    expect(error, isArgumentError);
    expect(next.started, isTrue);
    next.end();
    await tester.pump();
  });

  testWidgets('a post made after the last one handed over does not wait at '
      'all', (tester) async {
    final order = PostSequencer();
    final first = post('blitz');
    final later = post('closed');

    unawaited(order.run(first.call));
    final unacknowledged = first.send();
    unawaited(order.run(later.call));

    // Synchronously again: the first is unacknowledged, and irrelevant.
    expect(later.started, isTrue);

    unacknowledged.acknowledge();
    first.end();
    later.end();
    await tester.pump();
  });

  // A refused write is re-sent in another shape (the rate-limit ledger), and
  // the re-send joins the SDK's queue at the BACK. Measured against the
  // emulator with the real rules: with three quick posts, the first opening a
  // rate-limit window, the third slipped in ahead of the second's re-send and
  // landed before it — open, blitz, closed read "blitz" for everyone.
  group('a post the server has just refused is back in the way', () {
    testWidgets('a later post holds its first write until the refused one '
        'settles — even a refusal that arrives after that post began', (
      tester,
    ) async {
      final order = PostSequencer();
      final blitz = post('blitz');
      final closed = post('closed');

      unawaited(order.run(blitz.call));
      final first = blitz.send('.inc');
      unawaited(order.run(closed.call));
      expect(closed.started, isTrue);

      // The refusal comes back while `closed` is still at its GPS fix.
      first.refuse();
      await tester.pump();
      final resend = blitz.send('.reset');
      closed.send('.inc');
      await tester.pump();
      expect(sent, ['blitz.inc', 'blitz.reset']);

      resend.acknowledge();
      blitz.end();
      await tester.pump();
      expect(sent, ['blitz.inc', 'blitz.reset', 'closed.inc']);

      closed.end();
      await tester.pump();
    });

    testWidgets("three quick posts: the second's re-sends all go ahead of "
        "the third's first write", (tester) async {
      final order = PostSequencer();
      final open = post('open');
      final blitz = post('blitz');
      final closed = post('closed');

      unawaited(order.run(open.call));
      final openInc = open.send('.inc');
      unawaited(order.run(blitz.call));
      final blitzInc = blitz.send('.inc');

      openInc.refuse(); // no window yet
      await tester.pump();
      final openReset = open.send('.reset'); // nothing ahead of it: at once
      blitzInc.refuse(); // still none
      await tester.pump();
      final blitzReset = blitz.send('.reset'); // waits for `open` to settle

      // The correction, tapped mid-retry.
      unawaited(order.run(closed.call));
      await tester.pump();
      expect(closed.started, isFalse);
      expect(sent, ['open.inc', 'blitz.inc', 'open.reset']);

      openReset.acknowledge();
      open.end();
      await tester.pump();
      expect(sent.last, 'blitz.reset');
      expect(closed.started, isFalse);

      blitzReset.refuse(); // the window is open now
      await tester.pump();
      final blitzAgain = blitz.send('.inc again');
      await tester.pump();
      expect(closed.started, isFalse);

      blitzAgain.acknowledge();
      blitz.end();
      await tester.pump();
      expect(closed.started, isTrue);
      closed.send('.inc').acknowledge();
      await tester.pump();

      expect(sent, [
        'open.inc',
        'blitz.inc',
        'open.reset',
        'blitz.reset',
        'blitz.inc again',
        'closed.inc',
      ]);
      closed.end();
      await tester.pump();
    });

    testWidgets('whoever waited checks again: a post already holding its '
        'first write behind TWO refused posts keeps holding it when the '
        'first of them settles', (tester) async {
      final order = PostSequencer();
      final open = post('open');
      final blitz = post('blitz');
      final closed = post('closed');

      unawaited(order.run(open.call));
      final openInc = open.send('.inc');
      unawaited(order.run(blitz.call));
      final blitzInc = blitz.send('.inc');
      unawaited(order.run(closed.call));
      expect(closed.started, isTrue); // both ahead have handed over

      openInc.refuse();
      await tester.pump();
      final openReset = open.send('.reset');
      // The correction's GPS fix lands between the two refusals (a refusal
      // restarts the SDK's write stream, so they are a round trip apart):
      // it is now the FIRST to wait on `open`, ahead of blitz's re-send.
      closed.send('.inc');
      blitzInc.refuse();
      await tester.pump();
      final blitzReset = blitz.send('.reset');
      await tester.pump();
      expect(sent, ['open.inc', 'blitz.inc', 'open.reset']);

      openReset.acknowledge();
      open.end();
      await tester.pump();
      // Woken first, it must see blitz mid-retry and keep waiting.
      expect(sent, ['open.inc', 'blitz.inc', 'open.reset', 'blitz.reset']);

      blitzReset.acknowledge();
      blitz.end();
      await tester.pump();
      expect(sent.last, 'closed.inc');
      closed.end();
      await tester.pump();
    });

    testWidgets('only by the posts AHEAD of it: an earlier post never waits '
        "for a later one's refusal, or the two would wait on each other", (
      tester,
    ) async {
      final order = PostSequencer();
      final first = post('first');
      final second = post('second');

      unawaited(order.run(first.call));
      final firstInc = first.send('.inc');
      unawaited(order.run(second.call));
      final secondInc = second.send('.inc');

      secondInc.refuse();
      firstInc.refuse();
      await tester.pump();
      second.send('.reset');
      final firstReset = first.send('.reset');
      await tester.pump();
      expect(sent, ['first.inc', 'second.inc', 'first.reset']);

      firstReset.acknowledge();
      first.end();
      await tester.pump();
      expect(sent.last, 'second.reset');

      second.end();
      await tester.pump();
    });

    testWidgets('and for `patience` at most: a link that drops mid-retry '
        'must not hold the next post back for good', (tester) async {
      final order = PostSequencer(patience: const Duration(seconds: 40));
      final blitz = post('blitz');
      final closed = post('closed');

      unawaited(order.run(blitz.call));
      blitz.send('.inc').refuse();
      await tester.pump();
      blitz.send('.reset'); // never answered
      unawaited(order.run(closed.call));

      await tester.pump(const Duration(seconds: 39));
      expect(closed.started, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(closed.started, isTrue);

      closed.send('.inc').acknowledge();
      await tester.pump();
      expect(sent.last, 'closed.inc');

      blitz.end();
      closed.end();
      await tester.pump();
    });
  });

  testWidgets('every answer from the server restarts `patience`: it runs '
      'from the last refusal, not the first', (tester) async {
    final order = PostSequencer(patience: const Duration(seconds: 40));
    final blitz = post('blitz');
    final closed = post('closed');

    unawaited(order.run(blitz.call));
    blitz.send('.inc').refuse();
    await tester.pump();
    final reset = blitz.send('.reset');
    unawaited(order.run(closed.call));
    await tester.pump(const Duration(seconds: 30));
    reset.refuse(); // the server is still answering
    await tester.pump();
    blitz.send('.inc again'); // never answered

    await tester.pump(const Duration(seconds: 39)); // 69 s after the first
    expect(closed.started, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(closed.started, isTrue);

    blitz.end();
    closed.end();
    await tester.pump();
  });

  testWidgets('ordering never stops a post: one that hangs before its first '
      'write is in the way for `patience` and no longer, and the posts '
      'behind it still go in order', (tester) async {
    final order = PostSequencer(patience: const Duration(seconds: 40));
    final hung = post('blitz');
    final next = post('closed');
    final afterNext = post('open');

    unawaited(order.run(hung.call));
    unawaited(order.run(next.call));
    unawaited(order.run(afterNext.call));
    await tester.pump(const Duration(seconds: 39));
    expect(next.started, isFalse);

    await tester.pump(const Duration(seconds: 1));
    expect(next.started, isTrue);
    // Tapped at the same moment, yet not set loose with it: the one behind is
    // waiting for `next` now, whose own turn has only just begun.
    expect(afterNext.started, isFalse);

    next.send().acknowledge();
    await tester.pump();
    expect(afterNext.started, isTrue);

    // The post that hung may still land — just no longer in order.
    hung.send().acknowledge();
    await tester.pump();
    expect(sent, ['closed', 'blitz']);

    for (final p in [hung, next, afterNext]) {
      p.end();
    }
    await tester.pump();
  });

  testWidgets('no timer outlives what it was for — a write handed over, a '
      'post refused, one never acknowledged at all', (tester) async {
    final order = PostSequencer();
    final offline = post('blitz');
    final refused = post('closed');

    unawaited(order.run(offline.call));
    offline.send(); // never acknowledged
    unawaited(order.run(refused.call).catchError((Object _) => ''));
    await tester.pump();
    refused.send().refuse();
    await tester.pump();
    refused.fail(StateError('rate limited'));
    await tester.pump();

    // testWidgets fails a test that ends with a timer pending, so reaching
    // the end is the assertion.
  });

  // Neither can happen through the repository, which awaits every write
  // before its post ends — the sequencer must not depend on that.
  group('a write that outlives its post', () {
    testWidgets('starts no timer when it is refused', (tester) async {
      final order = PostSequencer();
      final blitz = post('blitz');

      unawaited(order.run(blitz.call));
      final write = blitz.send();
      blitz.end();
      await tester.pump();
      write.refuse();
      await tester.pump();
      // Again, ending with no timer pending is the assertion.
    });

    testWidgets('never waits for a LATER post', (tester) async {
      final order = PostSequencer(patience: const Duration(days: 1));
      final first = post('first');
      final second = post('second');
      final third = post('third');

      unawaited(order.run(first.call));
      final firstInc = first.send('.inc');
      unawaited(order.run(second.call));
      firstInc.refuse();
      await tester.pump();
      second.send('.inc'); // held behind `first`, which is mid-retry…
      second.end(); // …and its post ends without waiting for it
      // `third` has handed nothing over. Were it taken for a post AHEAD of
      // that held write, the write would wait on it for good.
      unawaited(order.run(third.call));
      await tester.pump();

      first.end();
      await tester.pump();
      expect(sent, ['first.inc', 'second.inc']);

      third.end();
      await tester.pump();
    });
  });
}
