import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/fresh_window_stream.dart';

/// One listener the combinator opened: its cutoff, the source the test feeds,
/// and whether the combinator has cancelled it.
class _Opened {
  _Opened(this.cutoff);

  final DateTime cutoff;
  bool cancelled = false;
  late final StreamController<WindowSnapshot<List<String>>> source =
      StreamController(onCancel: () => cancelled = true);

  void server(List<String> docs, {bool dataChanged = true}) => source.add(
    WindowSnapshot(docs, isFromCache: false, dataChanged: dataChanged),
  );

  void cache(List<String> docs, {bool dataChanged = true}) => source.add(
    WindowSnapshot(docs, isFromCache: true, dataChanged: dataChanged),
  );
}

/// Drives `freshWindowStream` with a clock and a "checks" stream the test
/// owns, so 30-minute rules run in microseconds. [sleep] advances the clock
/// WITHOUT a check — a frozen process, whose ticks don't fire; [tick] is one
/// check after a minute of ordinary running.
class _Harness {
  _Harness() {
    sub = freshWindowStream<List<String>>(
      open: (cutoff) {
        final opened = _Opened(cutoff);
        listeners.add(opened);
        return opened.source.stream;
      },
      window: const Duration(hours: 10),
      checks: checks.stream,
      now: () => now,
    ).listen(emitted.add, onError: (Object e) => errors.add(e));
  }

  DateTime now = DateTime.utc(2026, 9, 20, 8);
  final checks = StreamController<void>();
  final listeners = <_Opened>[];
  final emitted = <List<String>>[];
  final errors = <Object>[];
  late final StreamSubscription<List<String>> sub;

  _Opened get current => listeners.last;

  void sleep(Duration d) => now = now.add(d);

  Future<void> check() async {
    checks.add(null);
    await pumpEventQueue();
  }

  Future<void> tick([int minutes = 1]) async {
    for (var i = 0; i < minutes; i++) {
      now = now.add(const Duration(minutes: 1));
      await check();
    }
  }
}

void main() {
  // Issue #51. A listener's cutoff is baked in when it starts, so Firestore's
  // full re-run after >30 min disconnected used to reach back as far as the
  // session was old — a tab open three days re-read 3.4 days of reports.
  test('opens one listener for the last 10 hours and relays it', () async {
    final h = _Harness();
    await pumpEventQueue();

    expect(h.listeners, hasLength(1));
    expect(h.current.cutoff, DateTime.utc(2026, 9, 19, 22));

    h.current.server(['a']);
    h.current.server(['b', 'a']);
    await pumpEventQueue();
    expect(h.emitted, [
      ['a'],
      ['b', 'a'],
    ]);
  });

  test('hours of ordinary running never re-open it — every re-subscribe is a '
      'brand-new query that re-bills the whole window', () async {
    final h = _Harness();
    await pumpEventQueue();
    h.current.server(['a']);

    await h.tick(600); // ten hours, connected throughout
    expect(h.listeners, hasLength(1));
  });

  test('a short pause keeps the listener: inside 30 minutes Firestore resumes '
      'it for the price of what changed', () async {
    final h = _Harness();
    await pumpEventQueue();
    h.current.server(['a']);

    h.sleep(const Duration(minutes: 30)); // frozen, no ticks
    await h.check(); // the app came back

    expect(h.listeners, hasLength(1));
    expect(h.current.cancelled, isFalse);
  });

  test('coming back after a long freeze re-opens it with a FRESH cutoff, and '
      'nothing is emitted until the new listener answers', () async {
    final h = _Harness();
    await pumpEventQueue();
    final first = h.current..server(['old', 'older']);
    await pumpEventQueue();

    h.sleep(const Duration(hours: 14)); // phone in a pocket all day
    await h.check();

    expect(h.listeners, hasLength(2));
    expect(first.cancelled, isTrue);
    // 14 hours later — not the original cutoff, which would now cover 24 h.
    expect(h.current.cutoff, DateTime.utc(2026, 9, 20, 12));
    // The screen keeps the last list: no blank, no flicker.
    expect(h.emitted, [
      ['old', 'older'],
    ]);

    h.current.cache(['old']);
    await pumpEventQueue();
    expect(h.emitted.last, ['old']);
  });

  test('the freeze is found by the next tick alone when nothing announces the '
      'wake-up (a laptop lid)', () async {
    final h = _Harness();
    await pumpEventQueue();
    h.current.server(['a']);

    h.sleep(const Duration(hours: 9));
    await h.tick();

    expect(h.listeners, hasLength(2));
    expect(h.current.cutoff, DateTime.utc(2026, 9, 20, 7, 1));
  });

  test('a gap that could still have resumed for free is never swapped: the '
      'gap is measured from the last tick, up to a minute early', () async {
    final h = _Harness();
    await pumpEventQueue();
    h.current.server(['a']);

    // Measured 30m59s: the real freeze may have been just under 30 minutes.
    h.sleep(const Duration(minutes: 30, seconds: 59));
    await h.check();
    expect(h.listeners, hasLength(1));

    h.sleep(const Duration(minutes: 31));
    await h.check();
    expect(h.listeners, hasLength(2));
  });

  test(
    'offline for 30 minutes → swapped WHILE offline (free: the SDK re-sends '
    'only the listeners that still exist), and again every 30 minutes',
    () async {
      final h = _Harness();
      await pumpEventQueue();
      final first = h.current..server(['a']);
      await pumpEventQueue();

      first.cache(['a'], dataChanged: false); // the connection dropped
      await pumpEventQueue();
      await h.tick(29);
      expect(h.listeners, hasLength(1));

      await h.tick();
      expect(h.listeners, hasLength(2));
      expect(first.cancelled, isTrue);
      expect(h.current.cutoff, DateTime.utc(2026, 9, 19, 22, 30));

      // Still in the coverage hole: the new listener answers from cache too.
      h.current.cache(['a']);
      await pumpEventQueue();
      await h.tick(29);
      expect(h.listeners, hasLength(2));
      await h.tick();
      expect(h.listeners, hasLength(3));
      expect(h.current.cutoff, DateTime.utc(2026, 9, 19, 23));
    },
  );

  test('a shorter outage that ends is left alone', () async {
    final h = _Harness();
    await pumpEventQueue();
    h.current.server(['a']);

    h.current.cache(['a'], dataChanged: false);
    await pumpEventQueue();
    await h.tick(20);
    h.current.server(['a'], dataChanged: false); // back online
    await pumpEventQueue();
    await h.tick(40);

    expect(h.listeners, hasLength(1));
  });

  test('connection flips are not re-emitted: consumers rebuild exactly as '
      'often as they did before', () async {
    final h = _Harness();
    await pumpEventQueue();
    h.current.server(['a']);
    h.current.cache(['a'], dataChanged: false);
    h.current.server(['a'], dataChanged: false);
    h.current.server(['b', 'a']);
    await pumpEventQueue();

    expect(h.emitted, [
      ['a'],
      ['b', 'a'],
    ]);
  });

  test("a new listener's first answer always goes out, even if it calls "
      'itself metadata-only — it is what ends the silence of a swap', () async {
    final h = _Harness();
    await pumpEventQueue();
    h.current.cache(const [], dataChanged: false);
    await pumpEventQueue();

    expect(h.emitted, [<String>[]]);
  });

  test(
    'errors are forwarded untouched — recovery stays with the provider',
    () async {
      final h = _Harness();
      await pumpEventQueue();
      h.current.source.addError(StateError('index missing'));
      await pumpEventQueue();

      expect(h.errors.single, isA<StateError>());
    },
  );

  test('a listener that cannot even be opened surfaces as an error', () async {
    final errors = <Object>[];
    final sub = freshWindowStream<int>(
      open: (_) => throw StateError('no firestore'),
      window: const Duration(hours: 10),
      checks: const Stream.empty(),
    ).listen((_) {}, onError: errors.add);
    await pumpEventQueue();

    expect(errors.single, isA<StateError>());
    await sub.cancel();
  });

  test('cancelling releases the listener and stops checking', () async {
    final h = _Harness();
    await pumpEventQueue();
    await h.sub.cancel();

    expect(h.current.cancelled, isTrue);
    expect(h.checks.hasListener, isFalse);
  });

  test("the thresholds are Firestore's rule and a one-minute tick", () {
    expect(listenerResumeWindow, const Duration(minutes: 30));
    expect(listenerCheckInterval, const Duration(minutes: 1));
  });
}
