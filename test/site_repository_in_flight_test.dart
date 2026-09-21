import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/firestore_site_repository.dart';
import 'package:roadmate/services/in_flight_posts.dart';
import 'package:roadmate/services/rate_limit.dart';
import 'package:roadmate/services/report_proximity.dart';
import 'package:roadmate/services/status_logic.dart';

/// Just enough Firestore to watch a post being written: auto-ids, exactly
/// what each batch writes, and commits the test settles by hand — an open one
/// is a write the server has not acknowledged. Every read fails, as it would
/// offline; the repository treats all of its reads here as best-effort.
class _FakeFirestore implements FirebaseFirestore {
  /// The batches handed to the SDK, in that order: one counts from its
  /// `commit()`, not from when it was built.
  final batches = <_FakeBatch>[];
  var _autoIds = 0;

  /// Reads the test is holding open, by document path — a weak connection.
  /// Let go, one fails like every other read here.
  final heldReads = <String, Completer<void>>{};

  String nextAutoId() => 'auto-${_autoIds++}';

  /// The report document each batch wrote, in order.
  List<String> get reportPaths => [
    for (final batch in batches)
      ...batch.writes.keys
          .map((write) => write.split(' ').last)
          .where((path) => path.contains('/reports/')),
  ];

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FakeCollection(this, path);

  @override
  WriteBatch batch() => _FakeBatch(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The cloud_firestore types are @sealed against app-code subclassing; a
// hand-rolled test fake is the intended exception (project convention).
// ignore: subtype_of_sealed_class
class _FakeCollection implements CollectionReference<Map<String, dynamic>> {
  _FakeCollection(this.store, this.collectionPath);

  final _FakeFirestore store;
  final String collectionPath;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _FakeDoc(store, collectionPath, path ?? store.nextAutoId());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _FakeDoc implements DocumentReference<Map<String, dynamic>> {
  _FakeDoc(this.store, this.parentPath, this.id);

  final _FakeFirestore store;
  final String parentPath;

  @override
  final String id;

  @override
  String get path => '$parentPath/$id';

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FakeCollection(store, '${this.path}/$path');

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    await store.heldReads[path]?.future;
    throw _firestoreError('unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBatch implements WriteBatch {
  _FakeBatch(this.store);

  final _FakeFirestore store;

  /// Everything this batch writes: `'<op> <path>'` → the data, where op is
  /// `set`, `set(merge)` or `update`.
  final writes = <String, Object?>{};
  final _commit = Completer<void>();

  void acknowledge() => _commit.complete();
  void refuse(Object error) => _commit.completeError(error);

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    final op = options?.merge ?? false ? 'set(merge)' : 'set';
    writes['$op ${document.path}'] = data;
  }

  @override
  void update(DocumentReference<Object?> document, Map<Object, Object?> data) =>
      writes['update ${document.path}'] = data;

  @override
  Future<void> commit() {
    store.batches.add(this);
    return _commit.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser implements User {
  @override
  String get uid => 'driver-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements FirebaseAuth {
  final _user = _FakeUser();

  @override
  User? get currentUser => _user;

  @override
  Stream<User?> authStateChanges() => Stream.value(_user);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FirebaseException _firestoreError(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

const _site = Site(
  id: 'nsw-1',
  name: 'Marulan',
  type: SiteType.checkingStation,
  state: AusState.nsw,
  suburb: 'Marulan',
  address: 'Hume Hwy',
);

/// [_site] with coordinates, so the proximity gate has something to measure.
const _marulan = Site(
  id: 'nsw-1',
  name: 'Marulan',
  type: SiteType.checkingStation,
  state: AusState.nsw,
  suburb: 'Marulan',
  address: 'Hume Hwy',
  lat: -34.71,
  lng: 150.01,
);

/// Some 150 km up the Hume from [_marulan] — far outside the gate.
const DevicePosition _sydney = (lat: -33.87, lng: 151.21);

/// Issue #50: nothing showed until the server acknowledged a post. The
/// repository is the one place that sees a post's whole life — the tap, the
/// gate, every ledger attempt, the ack or the refusal — so it is what holds
/// each post in `InFlightPosts` meanwhile. These run the real repository.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeFirestore firestore;
  late InFlightPosts posts;
  late List<List<String>> changes;

  FirestoreSiteRepository repoWith({DevicePositionResolver? locate}) =>
      FirestoreSiteRepository(
        firestore: firestore,
        auth: _FakeAuth(),
        locate: locate ?? () async => null,
        inFlight: posts,
      );

  setUp(() {
    firestore = _FakeFirestore();
    posts = InFlightPosts();
    addTearDown(posts.dispose);
    changes = [];
    final sub = posts.changes.listen(
      (held) => changes.add([for (final post in held) post.id]),
    );
    addTearDown(sub.cancel);
  });

  test('a vote is held from the tap — before sign-in, the proximity gate or '
      'the commit have answered — under the id of the document it '
      'becomes', () async {
    final voting = repoWith().vote(
      _site,
      SiteStatus.blitz,
      reporterName: '  Dusty ',
    );

    // Synchronously: nothing has been awaited yet.
    final held = posts.current.single;
    expect(held.siteId, 'nsw-1');
    expect(held.status, SiteStatus.blitz);
    expect(held.reporterName, 'Dusty');

    await pumpEventQueue();
    expect(firestore.reportPaths, ['sites/nsw-1/reports/${held.id}']);
    // The server has said nothing; the post is what the app shows meanwhile.
    expect(posts.current.single, same(held));

    firestore.batches.single.acknowledge();
    await voting;
    // Still held through the landing grace: the listener's snapshot is a
    // separate event, and the delivered document shadows this copy by id.
    expect(posts.current.single, same(held));
  });

  // Holding a post must change nothing on the wire: shipped phones read and
  // write these same documents and can't be hot-updated, and the rules
  // type-check every optional key — a null or a blank where a key should be
  // absent is a refused write.
  group('what is written is exactly what it was', () {
    final serverTime = FieldValue.serverTimestamp();
    final plusOne = FieldValue.increment(1);
    final plusZero = FieldValue.increment(0);

    test('a vote: the report, the site\'s counter + status + touch, the '
        'stats credit and the ledger stamp', () async {
      unawaited(
        repoWith().vote(_site, SiteStatus.blitz, reporterName: '  Dusty '),
      );
      final id = posts.current.single.id;
      await pumpEventQueue();

      expect(firestore.batches.single.writes, {
        'set sites/nsw-1/reports/$id': {
          'siteId': 'nsw-1',
          'status': 'blitz',
          'uid': 'driver-1',
          'createdAt': serverTime,
          'reporterName': 'Dusty',
        },
        'update sites/nsw-1': {
          'blitzVotes': plusOne,
          'currentStatus': 'blitz',
          'lastReportAt': serverTime,
        },
        'set(merge) users/driver-1/stats/participation': {
          'votes': plusOne,
          'reports': plusZero,
          'sitesAdded': plusZero,
          'updatedAt': serverTime,
        },
        'update users/driver-1/limits/actions': {
          'count': plusOne,
          'lastActionAt': serverTime,
        },
      });
    });

    test('an unsigned vote leaves reporterName out altogether', () async {
      for (final name in [null, '', '   ']) {
        firestore = _FakeFirestore();
        unawaited(repoWith().vote(_site, SiteStatus.open, reporterName: name));
        await pumpEventQueue();

        final report = firestore.batches.single.writes.entries
            .singleWhere((write) => write.key.contains('/reports/'))
            .value;
        expect(report, {
          'siteId': 'nsw-1',
          'status': 'open',
          'uid': 'driver-1',
          'createdAt': serverTime,
        }, reason: 'reporterName: ${name == null ? 'null' : '"$name"'}');
      }
    });

    test('an activity report: the report and the site\'s touch — never its '
        'status or a counter — credited as a report', () async {
      unawaited(
        repoWith().report(
          _site,
          ActivityReportType.longQueue,
          activityNote: ' back to the ramp ',
          reporterName: 'Dusty',
        ),
      );
      final id = posts.current.single.id;
      await pumpEventQueue();

      expect(firestore.batches.single.writes, {
        'set sites/nsw-1/reports/$id': {
          'siteId': 'nsw-1',
          'activityType': 'longQueue',
          'uid': 'driver-1',
          'createdAt': serverTime,
          'activityNote': 'back to the ramp',
          'reporterName': 'Dusty',
          'reporterLevel': 1,
        },
        'update sites/nsw-1': {'lastReportAt': serverTime},
        'set(merge) users/driver-1/stats/participation': {
          'votes': plusZero,
          'reports': plusOne,
          'sitesAdded': plusZero,
          'updatedAt': serverTime,
        },
        'update users/driver-1/limits/actions': {
          'count': plusOne,
          'lastActionAt': serverTime,
        },
      });
    });

    test('a Camera Only / BGD press: that same activity batch, typed '
        "'Camera Only' and credited as a vote (issue #48)", () async {
      unawaited(repoWith().vote(_site, SiteStatus.cameraOnly));
      final id = posts.current.single.id;
      await pumpEventQueue();

      expect(firestore.batches.single.writes, {
        'set sites/nsw-1/reports/$id': {
          'siteId': 'nsw-1',
          'activityType': 'Camera Only',
          'uid': 'driver-1',
          'createdAt': serverTime,
          'reporterLevel': 1,
        },
        'update sites/nsw-1': {'lastReportAt': serverTime},
        'set(merge) users/driver-1/stats/participation': {
          'votes': plusOne,
          'reports': plusZero,
          'sitesAdded': plusZero,
          'updatedAt': serverTime,
        },
        'update users/driver-1/limits/actions': {
          'count': plusOne,
          'lastActionAt': serverTime,
        },
      });
    });

    test('the retry re-sends the same writes with the reset ledger '
        'shape', () async {
      unawaited(repoWith().vote(_site, SiteStatus.closed).catchError((_) {}));
      await pumpEventQueue();
      firestore.batches[0].refuse(_firestoreError('permission-denied'));
      await pumpEventQueue();

      final [first, second] = firestore.batches;
      const ledger = 'users/driver-1/limits/actions';
      expect(second.writes['set $ledger'], {
        'count': 1,
        'windowStart': serverTime,
        'lastActionAt': serverTime,
      });
      expect(
        {...second.writes}..remove('set $ledger'),
        {...first.writes}..remove('update $ledger'),
      );
    });
  });

  test('a Camera Only / BGD press is held as the status it lights', () async {
    unawaited(repoWith().vote(_site, SiteStatus.cameraOnly));

    final held = posts.current.single;
    expect(held.activityType, cameraOnlyWireType);
    expect(reportedStatusOf(held), SiteStatus.cameraOnly);

    await pumpEventQueue();
    expect(firestore.reportPaths, ['sites/nsw-1/reports/${held.id}']);
  });

  test('an activity report is held as the row it will list: type, trimmed '
      'note and name', () async {
    unawaited(
      repoWith().report(
        _site,
        ActivityReportType.longQueue,
        activityNote: '  back to the ramp ',
        reporterName: ' Dusty ',
      ),
    );

    final held = posts.current.single;
    expect(held.activityType, ActivityReportType.longQueue);
    expect(held.activityNote, 'back to the ramp');
    expect(held.reporterName, 'Dusty');
    expect(held.status, isNull);

    await pumpEventQueue();
    expect(firestore.reportPaths, ['sites/nsw-1/reports/${held.id}']);
  });

  // `_commitWithLedgerStamp` tries the increment shape, and on the first post
  // of every rate-limit window the rules refuse it and the reset shape goes
  // out instead. Both attempts must write the SAME report document, or the
  // held copy could never hand over to the one the listener delivers.
  for (final (label, post) in [
    ('a vote', (FirestoreSiteRepository r) => r.vote(_site, SiteStatus.open)),
    (
      'an activity report',
      (FirestoreSiteRepository r) => r.report(_site, ActivityReportType.delays),
    ),
  ]) {
    test('$label that retries with the other ledger shape writes the same '
        'report document, and stays held across the retry', () async {
      final posting = post(repoWith());
      final id = posts.current.single.id;
      await pumpEventQueue();

      firestore.batches[0].refuse(_firestoreError('permission-denied'));
      await pumpEventQueue();
      expect(firestore.batches, hasLength(2));

      firestore.batches[1].acknowledge();
      await posting;

      expect(firestore.reportPaths, [
        'sites/nsw-1/reports/$id',
        'sites/nsw-1/reports/$id',
      ]);
      // Added once and never taken down in between.
      expect(changes, [
        [id],
      ]);
    });
  }

  test('a refused write takes the post back down, and the error still '
      'reaches the caller for its snack', () async {
    final voting = repoWith().vote(_site, SiteStatus.blitz);

    // The increment, the reset, and the increment once more (issue #57): a
    // window that really is spent refuses all three.
    for (var attempt = 0; attempt < 3; attempt++) {
      await pumpEventQueue();
      firestore.batches[attempt].refuse(_firestoreError('permission-denied'));
    }

    await expectLater(voting, throwsA(isA<RateLimitedException>()));
    expect(posts.current, isEmpty);
    expect(firestore.batches, hasLength(3));
  });

  test('a write that fails outright is rolled back too', () async {
    final reporting = repoWith().report(_site, ActivityReportType.other);
    await pumpEventQueue();

    firestore.batches.single.refuse(_firestoreError('unavailable'));

    await expectLater(reporting, throwsA(isA<FirebaseException>()));
    expect(posts.current, isEmpty);
  });

  test('the proximity gate refusing takes the post back down before anything '
      'is written', () async {
    final repo = repoWith(locate: () async => _sydney);

    final voting = repo.vote(_marulan, SiteStatus.blitz);
    expect(posts.current, hasLength(1));

    await expectLater(voting, throwsA(isA<TooFarException>()));
    expect(posts.current, isEmpty);
    expect(firestore.batches, isEmpty);
  });

  test('a status with no stored form is refused before anything is held', () {
    expect(repoWith().vote(_site, SiteStatus.unknown), throwsArgumentError);
    expect(posts.current, isEmpty);
  });

  // Issue #57. The status everyone sees is a site's newest status report, and
  // the server stamps a report when its batch COMMITS — not at the tap. Each
  // post used to run its own sign-in, GPS fix and (activity path only) stats
  // read, so whichever got through those first committed first: a Camera
  // Only / BGD press corrected with Closed a second later landed AFTER its
  // correction, and stood for everyone for the next 10 hours.
  group('posts reach Firestore in the order they were tapped', () {
    const statsDoc = 'users/driver-1/stats/participation';
    const ledger = 'users/driver-1/limits/actions';

    String pathOf(SiteReport post) => 'sites/nsw-1/reports/${post.id}';

    test('a correction never overtakes the press it corrects, however long '
        "that press's stats read takes", () async {
      final statsRead = firestore.heldReads[statsDoc] = Completer<void>();
      final repo = repoWith();

      unawaited(repo.vote(_site, SiteStatus.cameraOnly));
      unawaited(repo.vote(_site, SiteStatus.closed));
      final [press, correction] = posts.current;
      await pumpEventQueue();

      // Both show from the tap (#50). Neither is written yet: the correction
      // is waiting its turn rather than racing ahead.
      expect(firestore.batches, isEmpty);

      statsRead.complete();
      await pumpEventQueue();
      expect(firestore.reportPaths, [pathOf(press), pathOf(correction)]);
    });

    test('nor one whose GPS fix comes quicker', () async {
      // The first lookup is a cold fix; by the second the fix is warm.
      final coldFix = Completer<DevicePosition?>();
      const atTheSite = (lat: -34.71, lng: 150.01);
      var lookups = 0;
      final repo = repoWith(
        locate: () => lookups++ == 0 ? coldFix.future : Future.value(atTheSite),
      );

      unawaited(repo.vote(_marulan, SiteStatus.blitz));
      unawaited(repo.vote(_marulan, SiteStatus.closed));
      final [first, second] = posts.current;
      await pumpEventQueue();
      expect(firestore.batches, isEmpty);

      coldFix.complete(atTheSite);
      await pumpEventQueue();
      expect(firestore.reportPaths, [pathOf(first), pathOf(second)]);
    });

    test('the wait is for a write to be handed to the SDK, never for the '
        'server to acknowledge it — offline that would be forever', () async {
      final repo = repoWith();

      unawaited(repo.vote(_site, SiteStatus.blitz));
      unawaited(repo.vote(_site, SiteStatus.closed));
      final [first, second] = posts.current;
      await pumpEventQueue();

      // Nothing has been acknowledged, and both are with the SDK — whose own
      // queue keeps this order and, on a phone, outlives the app being killed.
      expect(firestore.reportPaths, [pathOf(first), pathOf(second)]);
    });

    test('a post refused before it writes anything lets the next one '
        'through', () async {
      final fix = Completer<DevicePosition?>();
      final repo = repoWith(locate: () => fix.future);

      final refused = repo.vote(_marulan, SiteStatus.blitz);
      // [_site] has no coordinates, so this one never asks for a fix.
      unawaited(repo.vote(_site, SiteStatus.closed));
      final next = posts.current.last;
      await pumpEventQueue();
      expect(firestore.batches, isEmpty);

      fix.complete(_sydney);
      await expectLater(refused, throwsA(isA<TooFarException>()));
      await pumpEventQueue();
      expect(firestore.reportPaths, [pathOf(next)]);
    });

    // Measured against the emulator with the real rules: on a slow link both
    // posts' increments are with the server before either is answered. When
    // the first post opens a rate-limit window, the server refuses its
    // increment and the second post's, accepts the first's reset — and then
    // refuses the second's reset, because the window is open NOW. Stopping
    // there called the correction rate-limited after a single action.
    test('a post queued behind the one that opens a rate-limit window is not '
        'mistaken for rate-limited: refused in both shapes, it tries the '
        'increment once more', () async {
      final denied = _firestoreError('permission-denied');
      final repo = repoWith();

      final pressing = repo.vote(_site, SiteStatus.cameraOnly);
      final correcting = repo.vote(_site, SiteStatus.closed);
      final [press, correction] = posts.current;
      await pumpEventQueue();

      firestore.batches[0].refuse(denied); // the press's increment: no window
      await pumpEventQueue();
      firestore.batches[1].refuse(denied); // the correction's: still none
      await pumpEventQueue();
      // The press is mid-retry, so the correction's re-send waits for it.
      expect(firestore.batches, hasLength(3));
      firestore.batches[2].acknowledge(); // the press's reset opens one
      await pressing;
      await pumpEventQueue();
      firestore.batches[3].refuse(denied); // the correction's reset: it's open
      await pumpEventQueue();

      expect(firestore.batches, hasLength(5));
      expect(firestore.batches[4].writes.keys, contains('update $ledger'));
      firestore.batches[4].acknowledge();
      await correcting;

      // Tap order at every step, and one document per post throughout.
      expect(firestore.reportPaths, [
        pathOf(press), pathOf(correction), // the increments
        pathOf(press), pathOf(correction), // the resets
        pathOf(correction), // the increment that lands it
      ]);
      expect(posts.current, [press, correction]);
    });

    // A re-send joins the SDK's queue at the BACK. Measured against the
    // emulator with the real rules: tapped while the second post was between
    // ledger attempts, a third went in ahead of that post's re-send and landed
    // before it — open, blitz, closed read "blitz" for everyone. A refusal
    // proves the server is answering, so waiting out a refused post is no
    // wait on a dead link.
    test('three quick posts: the third is not written until the second, '
        'refused and re-sending, has landed', () async {
      final denied = _firestoreError('permission-denied');
      final repo = repoWith();

      final first = repo.vote(_site, SiteStatus.open);
      final mistake = repo.vote(_site, SiteStatus.blitz);
      await pumpEventQueue();
      firestore.batches[0].refuse(denied); // no window: the first re-sends
      await pumpEventQueue();
      firestore.batches[1].refuse(denied); // nor for the mistake
      await pumpEventQueue();

      // The correction, tapped while both are mid-retry.
      final correcting = repo.vote(_site, SiteStatus.closed);
      final [open, blitz, closed] = posts.current;
      await pumpEventQueue();
      expect(firestore.reportPaths, [
        pathOf(open),
        pathOf(blitz),
        pathOf(open),
      ]);

      firestore.batches[2].acknowledge(); // the first's reset opens a window
      await first;
      await pumpEventQueue();
      firestore.batches[3].refuse(denied); // the mistake's reset: it's open
      await pumpEventQueue();
      // Still nothing of the correction's: the mistake has not landed yet.
      expect(firestore.reportPaths.skip(3), [pathOf(blitz), pathOf(blitz)]);

      firestore.batches[4].acknowledge();
      await mistake;
      await pumpEventQueue();
      expect(firestore.reportPaths.last, pathOf(closed));
      // Into the open window, so the increment shape, first time.
      expect(firestore.batches[5].writes.keys, contains('update $ledger'));

      firestore.batches[5].acknowledge();
      await correcting;
      expect(firestore.batches, hasLength(6));
    });

    test('that last attempt failing for any other reason is not the rate '
        'limit speaking either', () async {
      final denied = _firestoreError('permission-denied');
      final voting = repoWith().vote(_site, SiteStatus.open);
      for (final error in [denied, denied, _firestoreError('unavailable')]) {
        await pumpEventQueue();
        firestore.batches.last.refuse(error);
      }

      await expectLater(
        voting,
        throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
      expect(firestore.batches, hasLength(3));
      expect(posts.current, isEmpty);
    });

    test('only a rules denial of the reset earns that last attempt — any '
        'other failure surfaces as it is', () async {
      // The site was removed meanwhile: the batch's site update finds nothing,
      // whatever the ledger shape.
      final voting = repoWith().vote(_site, SiteStatus.open);
      for (var attempt = 0; attempt < 2; attempt++) {
        await pumpEventQueue();
        firestore.batches[attempt].refuse(_firestoreError('not-found'));
      }

      await expectLater(
        voting,
        throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'not-found'),
        ),
      );
      expect(firestore.batches, hasLength(2));
    });
  });
}
