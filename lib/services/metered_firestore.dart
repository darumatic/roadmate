/// The Firestore half of the read meter (issue #54): what the billing rules
/// in `read_meter.dart` need to know, taken from real snapshots.
///
/// **Every read in `lib/` goes through `.metered(...)`** — listeners and
/// one-shot gets alike; `test/read_meter_coverage_test.dart` fails on one that
/// doesn't. Counting is passive: it observes what the app was going to read
/// anyway and never reads anything itself.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'read_meter.dart';

/// The one meter of this process: there is one app, one day's counter to add
/// to, and reads are made from a dozen classes that share nothing else.
/// `ReadMeterFlusher` empties it.
final ReadMeter readMeter = ReadMeter();

/// Metering must never break a read: a snapshot that can't be measured — a
/// test fake with no metadata — counts for nothing.
int _measured(int Function() reads) {
  try {
    return reads();
  } catch (_) {
    return 0;
  }
}

/// Documents the **server** added or changed. A removal is not a read, and
/// neither is this device's own pending write — its acknowledgement is, and
/// arrives as a change of its own.
int _serverChanges<T>(QuerySnapshot<T> snapshot) => snapshot.docChanges
    .where(
      (change) =>
          change.type != DocumentChangeType.removed &&
          !change.doc.metadata.hasPendingWrites,
    )
    .length;

typedef _Facts = ({bool isFromCache, int size, int changed});

extension MeteredQueryListener<T> on Stream<QuerySnapshot<T>> {
  /// This listener, with what Firestore bills for it counted under [source].
  ///
  /// [checks] (`listenerChecksProvider`) lets the bill notice a process that
  /// was frozen past the resume window; a listener `freshWindowStream` swaps
  /// at those moments doesn't need them. [syncTimes] remembers the last sync
  /// across restarts — only worth it for a query that is the *same* from one
  /// run to the next, on a platform with a persisted cache (see
  /// [ListenerBill]). Both only tell the whole story for a listener opened
  /// with `includeMetadataChanges: true`.
  Stream<QuerySnapshot<T>> metered(
    ReadSource source, {
    Stream<void>? checks,
    SyncTimeStore? syncTimes,
    ReadMeter? meter,
  }) => _meteredListener(
    this,
    source,
    meter: meter,
    checks: checks,
    syncTimes: syncTimes,
    facts: (snapshot) => (
      isFromCache: snapshot.metadata.isFromCache,
      size: snapshot.size,
      changed: _serverChanges(snapshot),
    ),
  );

  /// Only the snapshots a listener *without* `includeMetadataChanges` would
  /// have raised: the first, and every one whose documents changed. The rest
  /// — the connection flipped, a write was acknowledged with nothing new in it
  /// — are for the meter alone, so consumers rebuild exactly as often as
  /// before.
  Stream<QuerySnapshot<T>> get dataEventsOnly {
    var first = true;
    return where((snapshot) {
      final raise = first || snapshot.docChanges.isNotEmpty;
      first = false;
      return raise;
    });
  }
}

extension MeteredDocumentListener<T> on Stream<DocumentSnapshot<T>> {
  /// A one-document listener: one read for its first answer — whether or not
  /// the document exists — and one for every change the server sends.
  Stream<DocumentSnapshot<T>> metered(ReadSource source, {ReadMeter? meter}) =>
      _meteredListener(
        this,
        source,
        meter: meter,
        facts: (snapshot) => (
          isFromCache: snapshot.metadata.isFromCache,
          size: 1,
          changed: snapshot.metadata.hasPendingWrites ? 0 : 1,
        ),
      );
}

extension MeteredQueryGet<T> on Future<QuerySnapshot<T>> {
  /// A one-shot query: what it returned, and one read when that was nothing.
  /// Served from the cache (offline) it cost nothing.
  Future<QuerySnapshot<T>> metered(ReadSource source, {ReadMeter? meter}) =>
      then((snapshot) {
        (meter ?? readMeter).add(
          source,
          _measured(
            () =>
                snapshot.metadata.isFromCache ? 0 : math.max(1, snapshot.size),
          ),
        );
        return snapshot;
      });
}

extension MeteredDocumentGet<T> on Future<DocumentSnapshot<T>> {
  /// A one-shot document read — a transaction's `get` included: one read,
  /// found or not.
  Future<DocumentSnapshot<T>> metered(ReadSource source, {ReadMeter? meter}) =>
      then((snapshot) {
        (meter ?? readMeter).add(
          source,
          _measured(() => snapshot.metadata.isFromCache ? 0 : 1),
        );
        return snapshot;
      });
}

Stream<S> _meteredListener<S>(
  Stream<S> source,
  ReadSource kind, {
  required _Facts Function(S snapshot) facts,
  Stream<void>? checks,
  SyncTimeStore? syncTimes,
  ReadMeter? meter,
}) {
  final counts = meter ?? readMeter;
  final bill = ListenerBill();
  DateTime? savedAt;

  // Snapshots go straight through: the UI never waits for the meter. What
  // they cost is worked out behind them, in order, once the last sync time
  // has been read back (a few milliseconds, once).
  // Bounded: everything counted afterwards queues behind this, holding on to
  // its snapshot, so a store that never answered would stop the count for the
  // session and grow without end.
  var billing = syncTimes == null
      ? Future<void>.value()
      : syncTimes
            .load()
            .timeout(syncTimeLoadTimeout, onTimeout: () => null)
            .then<void>((at) {
              bill.lastSyncedAt ??= at;
              savedAt = at;
            }, onError: (Object _) {});

  void count(int Function() reads) {
    billing = billing.then((_) {
      counts.add(kind, _measured(reads));
      final synced = bill.lastSyncedAt;
      if (syncTimes == null || synced == null) return;
      final saved = savedAt;
      if (saved != null && synced.difference(saved) < syncTimeSaveInterval) {
        return;
      }
      savedAt = synced;
      unawaited(syncTimes.save(synced).catchError((Object _) {}));
    });
  }

  StreamSubscription<S>? sourceSub;
  StreamSubscription<void>? checksSub;
  late final StreamController<S> out;
  out = StreamController<S>(
    onListen: () {
      sourceSub = source.listen(
        (snapshot) {
          count(() {
            final seen = facts(snapshot);
            return bill.onSnapshot(
              isFromCache: seen.isFromCache,
              size: seen.size,
              changed: seen.changed,
            );
          });
          out.add(snapshot);
        },
        onError: out.addError,
        onDone: out.close,
      );
      checksSub = checks?.listen((_) => count(bill.onCheck));
    },
    onPause: () => sourceSub?.pause(),
    onResume: () => sourceSub?.resume(),
    // The Firestore listener first, and whatever becomes of the checks: a
    // listener left open is a listener still being billed.
    onCancel: () {
      final closed = sourceSub?.cancel();
      checksSub?.cancel();
      return closed;
    },
  );
  return out.stream;
}

/// How often, at most, a listener's last sync time is written down — it moves
/// every minute while the listener is connected — and how long reading it
/// back may take before the listener is billed without it.
const Duration syncTimeSaveInterval = Duration(minutes: 5);
const Duration syncTimeLoadTimeout = Duration(seconds: 5);

/// Remembers when a listener last heard from the server, across restarts —
/// what tells a cheap resume from a full re-read on a platform with a
/// persisted cache (see [ListenerBill]). Injectable, like
/// `AnnouncementDismissStore`, so tests need no platform channels.
abstract class SyncTimeStore {
  Future<DateTime?> load();

  Future<void> save(DateTime at);
}

class PrefsSyncTimeStore implements SyncTimeStore {
  const PrefsSyncTimeStore(this.listener);

  /// Which listener this is the clock of, e.g. `sites`.
  final String listener;

  String get _key => 'readMeter.syncedAt.$listener';

  @override
  Future<DateTime?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_key);
    return millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  @override
  Future<void> save(DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, at.millisecondsSinceEpoch);
  }
}
