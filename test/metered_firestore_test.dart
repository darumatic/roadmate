import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/metered_firestore.dart';
import 'package:roadmate/services/read_meter.dart';

// The cloud_firestore types are @sealed against app-code subclassing; a
// hand-rolled test fake is the intended exception (project convention).

class _Metadata implements SnapshotMetadata {
  _Metadata({this.isFromCache = false, this.hasPendingWrites = false});

  @override
  final bool isFromCache;
  @override
  final bool hasPendingWrites;
}

// ignore: subtype_of_sealed_class
class _Doc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _Doc({bool pending = false, bool fromCache = false})
    : metadata = _Metadata(hasPendingWrites: pending, isFromCache: fromCache);

  @override
  final SnapshotMetadata metadata;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Change implements DocumentChange<Map<String, dynamic>> {
  _Change(this.type, {bool pending = false}) : doc = _Doc(pending: pending);

  @override
  final DocumentChangeType type;
  @override
  final DocumentSnapshot<Map<String, dynamic>> doc;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Query implements QuerySnapshot<Map<String, dynamic>> {
  _Query(this.size, this.docChanges, {bool fromCache = false})
    : metadata = _Metadata(isFromCache: fromCache);

  @override
  final int size;
  @override
  final List<DocumentChange<Map<String, dynamic>>> docChanges;
  @override
  final SnapshotMetadata metadata;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A snapshot with no metadata at all — what most of the suite's hand-rolled
/// Firestore fakes hand back.
class _Opaque implements QuerySnapshot<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<_Change> _added(int n) => [
  for (var i = 0; i < n; i++) _Change(DocumentChangeType.added),
];

class _MemorySyncTimes implements SyncTimeStore {
  _MemorySyncTimes([this.at]);

  DateTime? at;
  final saves = <DateTime>[];

  @override
  Future<DateTime?> load() async => at;

  @override
  Future<void> save(DateTime at) async => saves.add(at);
}

class _DeadSyncTimes implements SyncTimeStore {
  @override
  Future<DateTime?> load() => Completer<DateTime?>().future;

  @override
  Future<void> save(DateTime at) async {}
}

/// Issue #54: the Firestore half of the read meter. The billing rules are
/// pinned in read_meter_test.dart; these pin what is read off a real snapshot
/// to feed them, and that metering can never get in a read's way.
void main() {
  late ReadMeter meter;
  setUp(() => meter = ReadMeter());

  group('a query listener', () {
    test('bills its first answer in full and then only what the server '
        'added or changed — never a removal, never this device\'s own '
        'pending write', () async {
      final source = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      final seen = <int>[];
      final sub = source.stream
          .metered(ReadSource.sites, meter: meter)
          .listen((snap) => seen.add(snap.size));

      source.add(_Query(89, _added(89)));
      await pumpEventQueue();
      expect(meter.take(), {ReadSource.sites: 89});

      source.add(
        _Query(89, [
          _Change(DocumentChangeType.modified),
          _Change(DocumentChangeType.modified, pending: true),
          _Change(DocumentChangeType.removed),
          _Change(DocumentChangeType.added),
        ]),
      );
      await pumpEventQueue();
      expect(meter.take(), {ReadSource.sites: 2});

      // Every snapshot still reaches the consumer, untouched and in order.
      expect(seen, [89, 89]);
      await sub.cancel();
      await source.close();
    });

    test('an empty first answer is one read; the cache is none', () async {
      final source = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      final sub = source.stream
          .metered(ReadSource.reports, meter: meter)
          .listen((_) {});

      source.add(_Query(14, _added(14), fromCache: true));
      await pumpEventQueue();
      expect(meter.isEmpty, isTrue);

      source.add(_Query(0, const []));
      await pumpEventQueue();
      expect(meter.take(), {ReadSource.reports: 1});
      await sub.cancel();
      await source.close();
    });

    test('resumes cheaply when the stored sync is young, and writes the new '
        'one down — not on every snapshot', () async {
      final now = DateTime.now().toUtc();
      final store = _MemorySyncTimes(now.subtract(const Duration(minutes: 5)));
      final source = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      final sub = source.stream
          .metered(ReadSource.sites, meter: meter, syncTimes: store)
          .listen((_) {});

      source.add(_Query(89, _added(89), fromCache: true));
      source.add(_Query(89, [_Change(DocumentChangeType.modified)]));
      await pumpEventQueue();
      expect(meter.take(), {ReadSource.sites: 1});
      expect(store.saves, hasLength(1));
      expect(store.saves.single.isBefore(now), isFalse);

      source.add(_Query(89, [_Change(DocumentChangeType.modified)]));
      await pumpEventQueue();
      expect(meter.take(), {ReadSource.sites: 1});
      expect(store.saves, hasLength(1));
      await sub.cancel();
      await source.close();
    });

    testWidgets('a store that never answers holds the count up for 5 s, not '
        'for the session', (tester) async {
      final source = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      final sub = source.stream
          .metered(ReadSource.sites, meter: meter, syncTimes: _DeadSyncTimes())
          .listen((_) {});

      source.add(_Query(89, _added(89)));
      await tester.pump(const Duration(seconds: 4));
      expect(meter.isEmpty, isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(meter.take(), {ReadSource.sites: 89});
      // Not awaited: under the fake clock these never complete.
      unawaited(sub.cancel());
      unawaited(source.close());
    });

    test('pays in full when nobody remembers a sync', () async {
      final source = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      final sub = source.stream
          .metered(
            ReadSource.sites,
            meter: meter,
            syncTimes: _MemorySyncTimes(),
          )
          .listen((_) {});

      source.add(_Query(89, _added(89), fromCache: true));
      source.add(_Query(89, const []));
      await pumpEventQueue();

      expect(meter.take(), {ReadSource.sites: 89});
      await sub.cancel();
      await source.close();
    });

    test(
      'listens to the checks for as long as it is listened to itself',
      () async {
        final checks = StreamController<void>.broadcast();
        final source = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        final metered = source.stream.metered(
          ReadSource.sites,
          meter: meter,
          checks: checks.stream,
        );
        expect(checks.hasListener, isFalse);

        final sub = metered.listen((_) {});
        expect(checks.hasListener, isTrue);

        await sub.cancel();
        expect(checks.hasListener, isFalse);
        expect(source.hasListener, isFalse);
      },
    );

    test('errors and the end of the stream pass straight through', () async {
      final source = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      final errors = <Object>[];
      var done = false;
      source.stream
          .metered(ReadSource.sites, meter: meter)
          .listen((_) {}, onError: errors.add, onDone: () => done = true);

      source.addError(StateError('permission-denied'));
      await source.close();
      await pumpEventQueue();

      expect(errors.single, isA<StateError>());
      expect(done, isTrue);
    });

    test(
      'dataEventsOnly: the first snapshot and every one whose documents '
      'changed — what a listener without metadata changes would raise',
      () async {
        final source = StreamController<QuerySnapshot<Map<String, dynamic>>>();
        final raised = <int>[];
        final sub = source.stream.dataEventsOnly.listen(
          (snap) => raised.add(snap.size),
        );

        source
          ..add(_Query(0, const [], fromCache: true)) // first, though empty
          ..add(_Query(0, const [])) // the connection came up: metadata only
          ..add(_Query(1, _added(1)))
          ..add(_Query(1, const [], fromCache: true)) // and went away again
          ..add(_Query(2, _added(1)));
        await pumpEventQueue();

        expect(raised, [0, 1, 2]);
        await sub.cancel();
        await source.close();
      },
    );
  });

  group('a document listener', () {
    Stream<DocumentSnapshot<Map<String, dynamic>>> events(List<_Doc> docs) =>
        Stream.fromIterable(docs);

    test('one read for its first answer and one per change from the server '
        '— not for the cache, not for a pending write', () async {
      await events([
        _Doc(fromCache: true),
        _Doc(),
        _Doc(pending: true),
        _Doc(),
      ]).metered(ReadSource.other, meter: meter).drain<void>();
      await pumpEventQueue();

      // The first server answer after a cache one with no remembered sync is
      // billed as the whole (one-document) result; the last as one change.
      expect(meter.take(), {ReadSource.other: 2});
    });
  });

  group('one-shot reads', () {
    test('a query costs what it returned — one read when that was nothing, '
        'none when the cache served it', () async {
      await Future.value(
        _Query(7, const []),
      ).metered(ReadSource.other, meter: meter);
      expect(meter.take(), {ReadSource.other: 7});

      await Future.value(
        _Query(0, const []),
      ).metered(ReadSource.other, meter: meter);
      expect(meter.take(), {ReadSource.other: 1});

      await Future.value(
        _Query(7, const [], fromCache: true),
      ).metered(ReadSource.other, meter: meter);
      expect(meter.isEmpty, isTrue);
    });

    test('a document costs one read, found or not', () async {
      final DocumentSnapshot<Map<String, dynamic>> doc = _Doc();
      final got = await Future.value(
        doc,
      ).metered(ReadSource.other, meter: meter);

      expect(got, same(doc));
      expect(meter.take(), {ReadSource.other: 1});
    });

    test('a read that fails is not a read, and fails just as it did', () {
      expect(
        Future<QuerySnapshot<Map<String, dynamic>>>.error(
          StateError('unavailable'),
        ).metered(ReadSource.other, meter: meter),
        throwsStateError,
      );
      expect(meter.isEmpty, isTrue);
    });
  });

  test('metering never breaks a read: a snapshot it cannot measure counts '
      'for nothing and goes through', () async {
    final opaque = _Opaque();

    final got = await Future<QuerySnapshot<Map<String, dynamic>>>.value(
      opaque,
    ).metered(ReadSource.other, meter: meter);
    final streamed = await Stream<QuerySnapshot<Map<String, dynamic>>>.value(
      opaque,
    ).metered(ReadSource.sites, meter: meter).first;
    await pumpEventQueue();

    expect(got, same(opaque));
    expect(streamed, same(opaque));
    expect(meter.isEmpty, isTrue);
  });
}
