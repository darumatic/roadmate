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
  final batches = <_FakeBatch>[];
  var _autoIds = 0;

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
  WriteBatch batch() {
    final batch = _FakeBatch();
    batches.add(batch);
    return batch;
  }

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
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      Future.error(_firestoreError('unavailable'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBatch implements WriteBatch {
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
  Future<void> commit() => _commit.future;

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

/// Issue #50: nothing showed until the server acknowledged a post. The
/// repository is the one place that sees a post's whole life — the tap, the
/// gate, both ledger attempts, the ack or the refusal — so it is what holds
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
    await pumpEventQueue();

    firestore.batches[0].refuse(_firestoreError('permission-denied'));
    await pumpEventQueue();
    firestore.batches[1].refuse(_firestoreError('permission-denied'));

    await expectLater(voting, throwsA(isA<RateLimitedException>()));
    expect(posts.current, isEmpty);
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
    final marulan = Site(
      id: _site.id,
      name: _site.name,
      type: _site.type,
      state: _site.state,
      suburb: _site.suburb,
      address: _site.address,
      lat: -34.71,
      lng: 150.01,
    );
    final repo = repoWith(
      // Sydney — some 150 km up the Hume.
      locate: () async => (lat: -33.87, lng: 151.21),
    );

    final voting = repo.vote(marulan, SiteStatus.blitz);
    expect(posts.current, hasLength(1));

    await expectLater(voting, throwsA(isA<TooFarException>()));
    expect(posts.current, isEmpty);
    expect(firestore.batches, isEmpty);
  });

  test('a status with no stored form is refused before anything is held', () {
    expect(repoWith().vote(_site, SiteStatus.unknown), throwsArgumentError);
    expect(posts.current, isEmpty);
  });
}
