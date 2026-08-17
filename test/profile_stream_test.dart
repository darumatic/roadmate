import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/profile_stream.dart';

/// Regression tests for the 0.1.74 nickname re-prompt bug: the profile
/// stream behind `signatureNameProvider` must survive a dead `users/{uid}`
/// listener and always reflect a road name the session already committed —
/// otherwise every vote asks the user to pick a name again.
void main() {
  const user = ProfileAuthUser(uid: 'u1', isAnonymous: true);

  ProfileAuthUser? lastRequested;

  test('delivers the doc profile for the signed-in user', () async {
    final auth = StreamController<ProfileAuthUser?>();
    final doc = StreamController<UserProfile?>();
    final emitted = <UserProfile?>[];
    final sub = profileStream(
      authUsers: auth.stream,
      profileDocOf: (u) => doc.stream,
    ).listen(emitted.add);

    auth.add(user);
    doc.add(const UserProfile(isAnonymous: true, username: 'Dusty Nomad'));
    await pumpEventQueue();

    expect(emitted.single?.signature, 'Dusty Nomad');
    await sub.cancel();
  });

  test('signing out emits a null profile', () async {
    final auth = StreamController<ProfileAuthUser?>();
    final emitted = <UserProfile?>[];
    final sub = profileStream(
      authUsers: auth.stream,
      profileDocOf: (u) => const Stream.empty(),
    ).listen(emitted.add);

    auth.add(null);
    await pumpEventQueue();

    expect(emitted, [null]);
    await sub.cancel();
  });

  test(
    'a dead doc listener is re-opened and recovers the profile '
    '(0.1.74: it stayed dead, so every post re-prompted)',
    () async {
      final auth = StreamController<ProfileAuthUser?>();
      var opens = 0;
      final emitted = <UserProfile?>[];
      final sub =
          profileStream(
            authUsers: auth.stream,
            retryDelay: const Duration(milliseconds: 10),
            profileDocOf: (u) {
              opens += 1;
              if (opens == 1) {
                // A terminal listener error, like Firestore's
                // permission-denied: one error, then the stream is done.
                return Stream<UserProfile?>.error(
                  StateError('permission denied'),
                );
              }
              return Stream.value(
                const UserProfile(isAnonymous: true, username: 'Dusty Nomad'),
              );
            },
          ).listen(emitted.add);

      auth.add(user);
      await pumpEventQueue();
      // Fail-soft: the UI sees null (never an error) while the listener is
      // down...
      expect(emitted, [null]);

      // ...and the listener comes back on its own.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(opens, greaterThanOrEqualTo(2));
      expect(emitted.last?.signature, 'Dusty Nomad');
      await sub.cancel();
    },
  );

  test('a committed claim reaches the stream even with the doc listener dead '
      '(the video: saved name must stick for the next post)', () async {
    final auth = StreamController<ProfileAuthUser?>();
    final claims = StreamController<ClaimedName>();
    final emitted = <UserProfile?>[];
    final sub =
        profileStream(
          authUsers: auth.stream,
          retryDelay: const Duration(minutes: 5),
          profileDocOf: (u) =>
              Stream.error(StateError('permission denied')),
          localClaims: claims.stream,
        ).listen(emitted.add);

    auth.add(user);
    await pumpEventQueue();
    expect(emitted.last, isNull);

    claims.add(
      const ClaimedName(
        uid: 'u1',
        profile: UserProfile(isAnonymous: true, username: 'Longhaul Convoy'),
      ),
    );
    await pumpEventQueue();

    expect(emitted.last?.signature, 'Longhaul Convoy');
    await sub.cancel();
  });

  test('a stale doc snapshot without a name never undoes a committed claim',
      () async {
    final auth = StreamController<ProfileAuthUser?>();
    final doc = StreamController<UserProfile?>();
    final claims = StreamController<ClaimedName>();
    final emitted = <UserProfile?>[];
    final sub = profileStream(
      authUsers: auth.stream,
      profileDocOf: (u) => doc.stream,
      localClaims: claims.stream,
    ).listen(emitted.add);

    auth.add(user);
    claims.add(
      const ClaimedName(
        uid: 'u1',
        profile: UserProfile(isAnonymous: true, username: 'Longhaul Convoy'),
      ),
    );
    await pumpEventQueue();
    // A pre-claim snapshot served from cache after the claim committed.
    doc.add(const UserProfile(isAnonymous: true, username: null));
    await pumpEventQueue();

    expect(emitted.last?.signature, 'Longhaul Convoy');
    await sub.cancel();
  });

  test(
    'a new auth user switches the doc listener '
    '(asyncExpand queued it forever behind the first, never-ending stream)',
    () async {
      final auth = StreamController<ProfileAuthUser?>();
      final emitted = <UserProfile?>[];
      final sub = profileStream(
        authUsers: auth.stream,
        profileDocOf: (u) {
          lastRequested = u;
          // Never completes, like a real Firestore listener.
          return StreamController<UserProfile?>().stream;
        },
      ).listen(emitted.add);

      auth.add(user);
      await pumpEventQueue();
      expect(lastRequested?.uid, 'u1');

      auth.add(
        const ProfileAuthUser(
          uid: 'u2',
          isAnonymous: false,
          displayName: 'Adrian',
        ),
      );
      await pumpEventQueue();
      expect(lastRequested?.uid, 'u2');
      await sub.cancel();
    },
  );

  test('a token refresh (same identity) does not churn a healthy listener',
      () async {
    final auth = StreamController<ProfileAuthUser?>();
    var opens = 0;
    final sub = profileStream(
      authUsers: auth.stream,
      profileDocOf: (u) {
        opens += 1;
        return StreamController<UserProfile?>().stream;
      },
    ).listen((_) {});

    auth.add(user);
    await pumpEventQueue();
    auth.add(user); // userChanges fires on token refresh with the same user
    await pumpEventQueue();

    expect(opens, 1);
    await sub.cancel();
  });
}
