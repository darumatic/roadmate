import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/role_stream.dart';

/// Regression tests for the role-stream wedge (same family as the 0.1.75
/// profile-stream fix): the stream behind `currentUserRoleProvider` must
/// follow every auth change — the old `await for` + `yield*` shape never
/// observed a sign-out or account switch after the first sign-in.
void main() {
  const anonymous = 'anonymous';
  const admin = RoleAuthUser(uid: 'a1', isAnonymous: false);

  test('anonymous users get the anonymous role with no doc listener', () async {
    final auth = StreamController<RoleAuthUser?>();
    var opens = 0;
    final emitted = <String>[];
    final sub = roleStream<String>(
      authUsers: auth.stream,
      roleDocOf: (uid) {
        opens += 1;
        return const Stream.empty();
      },
      anonymousRole: anonymous,
    ).listen(emitted.add);

    auth.add(const RoleAuthUser(uid: 'u1', isAnonymous: true));
    await pumpEventQueue();

    expect(emitted, [anonymous]);
    expect(opens, 0);
    await sub.cancel();
  });

  test('a signed-in user gets the role from their userRoles doc', () async {
    final auth = StreamController<RoleAuthUser?>();
    final emitted = <String>[];
    final sub = roleStream<String>(
      authUsers: auth.stream,
      roleDocOf: (uid) => Stream.value('admin:$uid'),
      anonymousRole: anonymous,
    ).listen(emitted.add);

    auth.add(admin);
    await pumpEventQueue();

    expect(emitted, ['admin:a1']);
    await sub.cancel();
  });

  test(
    'signing out after signing in drops back to anonymous '
    '(the old shape kept the admin role until restart)',
    () async {
      final auth = StreamController<RoleAuthUser?>();
      final emitted = <String>[];
      final sub = roleStream<String>(
        authUsers: auth.stream,
        // Never completes, like a real Firestore listener.
        roleDocOf: (uid) => Stream.value('admin:$uid')
            .followedBy(StreamController<String>().stream),
        anonymousRole: anonymous,
      ).listen(emitted.add);

      auth.add(admin);
      await pumpEventQueue();
      expect(emitted.last, 'admin:a1');

      auth.add(null);
      await pumpEventQueue();
      expect(emitted.last, anonymous);
      await sub.cancel();
    },
  );

  test('an account switch moves the listener to the new uid', () async {
    final auth = StreamController<RoleAuthUser?>();
    final emitted = <String>[];
    final sub = roleStream<String>(
      authUsers: auth.stream,
      roleDocOf: (uid) => Stream.value('role:$uid')
          .followedBy(StreamController<String>().stream),
      anonymousRole: anonymous,
    ).listen(emitted.add);

    auth.add(admin);
    await pumpEventQueue();
    auth.add(const RoleAuthUser(uid: 'a2', isAnonymous: false));
    await pumpEventQueue();

    expect(emitted, ['role:a1', 'role:a2']);
    await sub.cancel();
  });

  test('a dead doc listener fails closed and recovers on retry', () async {
    final auth = StreamController<RoleAuthUser?>();
    var opens = 0;
    final emitted = <String>[];
    final sub = roleStream<String>(
      authUsers: auth.stream,
      retryDelay: const Duration(milliseconds: 10),
      roleDocOf: (uid) {
        opens += 1;
        if (opens == 1) return Stream.error(StateError('permission denied'));
        return Stream.value('admin:$uid');
      },
      anonymousRole: anonymous,
    ).listen(emitted.add);

    auth.add(admin);
    await pumpEventQueue();
    // Fail closed: never a phantom admin while the listener is down.
    expect(emitted, [anonymous]);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(opens, greaterThanOrEqualTo(2));
    expect(emitted.last, 'admin:a1');
    await sub.cancel();
  });

  test('a token refresh (same identity) does not churn a healthy listener',
      () async {
    final auth = StreamController<RoleAuthUser?>();
    var opens = 0;
    final sub = roleStream<String>(
      authUsers: auth.stream,
      roleDocOf: (uid) {
        opens += 1;
        return StreamController<String>().stream;
      },
      anonymousRole: anonymous,
    ).listen((_) {});

    auth.add(admin);
    await pumpEventQueue();
    auth.add(const RoleAuthUser(uid: 'a1', isAnonymous: false));
    await pumpEventQueue();

    expect(opens, 1);
    await sub.cancel();
  });
}

extension<T> on Stream<T> {
  /// This stream's events, then [next]'s — used to build a listener that
  /// emits once and then stays open forever, like a real Firestore listener.
  Stream<T> followedBy(Stream<T> next) async* {
    yield* this;
    yield* next;
  }
}
