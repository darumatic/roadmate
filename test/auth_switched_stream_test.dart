import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/auth_switched_stream.dart';

/// The shared combinator behind every auth-scoped listener (profile, role,
/// participation stats, favourites). Regression tests for the asyncExpand
/// wedge that shipped in all four: a new auth identity must switch the
/// listener immediately (never queue behind the old, never-completing one),
/// and a dead listener must fail soft and re-open — not stay silent for the
/// session (the 0.1.74 nickname re-prompt bug).
void main() {
  test(
    'a null auth identity emits the signed-out value, no listener',
    () async {
      final auth = StreamController<String?>();
      var opens = 0;
      final emitted = <String>[];
      final sub = authSwitchedStream<String, String>(
        authUsers: auth.stream,
        sourceOf: (uid) {
          opens += 1;
          return const Stream.empty();
        },
        signedOutValue: 'signed-out',
      ).listen(emitted.add);

      auth.add(null);
      await pumpEventQueue();

      expect(emitted, ['signed-out']);
      expect(opens, 0);
      await sub.cancel();
    },
  );

  test('a signed-in identity relays its source stream', () async {
    final auth = StreamController<String?>();
    final emitted = <String>[];
    final sub = authSwitchedStream<String, String>(
      authUsers: auth.stream,
      sourceOf: (uid) => Stream.value('data:$uid'),
      signedOutValue: 'signed-out',
    ).listen(emitted.add);

    auth.add('u1');
    await pumpEventQueue();

    expect(emitted, ['data:u1']);
    await sub.cancel();
  });

  test('signing out after signing in emits the signed-out value '
      '(the old asyncExpand shape queued it forever)', () async {
    final auth = StreamController<String?>();
    final emitted = <String>[];
    final sub = authSwitchedStream<String, String>(
      authUsers: auth.stream,
      // Emits once then never completes, like a real Firestore listener.
      sourceOf: (uid) => Stream.value(
        'data:$uid',
      ).followedBy(StreamController<String>().stream),
      signedOutValue: 'signed-out',
    ).listen(emitted.add);

    auth.add('u1');
    await pumpEventQueue();
    expect(emitted.last, 'data:u1');

    auth.add(null);
    await pumpEventQueue();
    expect(emitted.last, 'signed-out');
    await sub.cancel();
  });

  test('an account switch moves the listener to the new identity '
      '(favourites/stats used to stay frozen on the old account)', () async {
    final auth = StreamController<String?>();
    final emitted = <String>[];
    final sub = authSwitchedStream<String, String>(
      authUsers: auth.stream,
      sourceOf: (uid) => Stream.value(
        'data:$uid',
      ).followedBy(StreamController<String>().stream),
      signedOutValue: 'signed-out',
    ).listen(emitted.add);

    auth.add('u1');
    await pumpEventQueue();
    auth.add('u2');
    await pumpEventQueue();

    expect(emitted, ['data:u1', 'data:u2']);
    await sub.cancel();
  });

  test('a dead listener fails soft and recovers on retry', () async {
    final auth = StreamController<String?>();
    var opens = 0;
    final emitted = <String>[];
    final sub = authSwitchedStream<String, String>(
      authUsers: auth.stream,
      retryDelay: const Duration(milliseconds: 10),
      sourceOf: (uid) {
        opens += 1;
        if (opens == 1) return Stream.error(StateError('permission denied'));
        return Stream.value('data:$uid');
      },
      signedOutValue: 'signed-out',
    ).listen(emitted.add);

    auth.add('u1');
    await pumpEventQueue();
    // Fail soft: the signed-out value, never an error downstream.
    expect(emitted, ['signed-out']);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(opens, greaterThanOrEqualTo(2));
    expect(emitted.last, 'data:u1');
    await sub.cancel();
  });

  test(
    'a repeat of the same identity does not churn a healthy listener',
    () async {
      final auth = StreamController<String?>();
      var opens = 0;
      final sub = authSwitchedStream<String, String>(
        authUsers: auth.stream,
        sourceOf: (uid) {
          opens += 1;
          return StreamController<String>().stream;
        },
        signedOutValue: 'signed-out',
      ).listen((_) {});

      auth.add('u1');
      await pumpEventQueue();
      auth.add('u1'); // e.g. userChanges firing on a token refresh
      await pumpEventQueue();

      expect(opens, 1);
      await sub.cancel();
    },
  );

  test(
    'onSwitch sees every auth emission before anything is emitted',
    () async {
      final auth = StreamController<String?>();
      final log = <String>[];
      final sub = authSwitchedStream<String, String>(
        authUsers: auth.stream,
        sourceOf: (uid) => const Stream.empty(),
        signedOutValue: 'signed-out',
        onSwitch: (next) => log.add('switch:$next'),
      ).listen((value) => log.add('emit:$value'));

      auth.add('u1');
      auth.add(null);
      await pumpEventQueue();

      expect(log, ['switch:u1', 'switch:null', 'emit:signed-out']);
      await sub.cancel();
    },
  );
}

extension<T> on Stream<T> {
  /// This stream's events, then [next]'s — used to build a listener that
  /// emits once and then stays open forever, like a real Firestore listener.
  Stream<T> followedBy(Stream<T> next) async* {
    yield* this;
    yield* next;
  }
}
