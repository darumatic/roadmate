/// An unofficial count of the document reads Firestore bills this app for
/// (issue #54) — pure Dart (no Firebase/Flutter imports), so every rule in it
/// is directly unit-testable.
///
/// The project has no billing account, so the 50,000 reads/day quota is a
/// cliff: past it Firestore *refuses* reads until the daily reset — an outage,
/// not a bill. The same fact blocks measuring it (Google's metrics API wants
/// billing enabled), so usage could only be seen by hand in the console. This
/// is the client half of the alternative: each build counts what Firestore
/// delivers to it, by Firestore's own billing rules, and flushes the totals —
/// by source and platform — to one counter document a day. An hourly cron
/// (`scripts/read_meter.py`) reads that document and alerts at 70 %.
///
/// **It is a floor, not the true figure.** Builds without the meter are
/// invisible, reads made *inside security rules* (the ban check on every
/// post, the admin checks) can't be seen from here, console browsing isn't
/// counted, and a session that dies before its next flush takes its tail with
/// it. What it adds that even Google's total would not: where the reads go.
library;

import 'dart:math' as math;

import 'package:clock/clock.dart';

import 'fresh_window_stream.dart'
    show listenerCheckInterval, listenerResumeWindow;

/// Where a read came from: the two shared listeners that make up nearly all
/// of a session, and everything else (single documents, one-shot gets, the
/// admin screens).
enum ReadSource { sites, reports, other }

/// The collection of daily counter documents, one per quota day.
const String readMeterCollection = 'usage';

/// The most one flush may add to one counter — `usageMaxStep()` in
/// firestore.rules refuses more, so a larger count is clamped rather than
/// lost whole (pinned in `test/rules/rules_test.mjs`). Far above any real
/// half hour: a cold start is ~110 reads.
const int readMeterMaxStep = 20000;

/// How often an open app flushes, and the least time between two flushes
/// that the app going to the background can cause. Writes have their own
/// quota (20,000/day), so never per action: about one write when the app is
/// put away, plus one per half hour while it stays open.
const Duration readMeterFlushInterval = Duration(minutes: 30);
const Duration readMeterMinFlushGap = Duration(minutes: 1);

/// When a fresh start makes its first flush — and, until one has gone out,
/// how often it tries again ([readMeterFirstFlushTries] times at most). A cold
/// start is the dearest thing a session does (~110 reads), and on the web a
/// tab closed within the half hour would otherwise flush only while unloading
/// — a write that dies with the page. One extra write a session.
const Duration readMeterFirstFlush = Duration(seconds: 30);
const int readMeterFirstFlushTries = 10;

/// How long after a freeze a re-run is billed on trust. The SDK takes up to
/// 10 s to decide it is offline; past that, a listener that is says so.
const Duration listenerRerunGrace = Duration(seconds: 12);

/// When `listenerChecksProvider` checks again after the app comes back — just
/// past [listenerRerunGrace], so a re-run is billed within the glance.
const Duration listenerCheckFollowUp = Duration(seconds: 15);

/// The quota day [moment] falls in, as `yyyy-mm-dd` — the id of that day's
/// counter document. Firestore's daily quota resets at **midnight Pacific
/// time**, so that, not UTC or the device's zone, is the day to count in:
/// an Australian driving day straddles UTC midnight, and a meter that split
/// it there would never see the total the quota sees.
///
/// US daylight-time rules (in force since 2007) are applied by hand: Dart has
/// no zone database, and the device's own zone is the wrong one. Were they to
/// change, shipped builds would file up to an hour of reads under the
/// neighbouring day for part of the year — noise for a 70 % alert. The cron
/// uses the real zone database; `test/read_meter_script_test.dart` holds the
/// two to the same answers.
String quotaDayOf(DateTime moment) {
  final utc = moment.toUtc();
  final pacific = utc.subtract(
    Duration(hours: _isPacificDaylightTime(utc) ? 7 : 8),
  );
  String two(int n) => n.toString().padLeft(2, '0');
  return '${pacific.year.toString().padLeft(4, '0')}-'
      '${two(pacific.month)}-${two(pacific.day)}';
}

/// Daylight time runs from 2 am PST on the second Sunday of March (10:00 UTC)
/// to 2 am PDT on the first Sunday of November (09:00 UTC).
bool _isPacificDaylightTime(DateTime utc) {
  final starts = _nthSunday(
    utc.year,
    DateTime.march,
    2,
  ).add(const Duration(hours: 10));
  final ends = _nthSunday(
    utc.year,
    DateTime.november,
    1,
  ).add(const Duration(hours: 9));
  return !utc.isBefore(starts) && utc.isBefore(ends);
}

DateTime _nthSunday(int year, int month, int n) {
  final first = DateTime.utc(year, month);
  final toSunday = (DateTime.sunday - first.weekday) % 7;
  return first.add(Duration(days: toSunday + 7 * (n - 1)));
}

/// The name of one counter in the day's document: `sites_web`, `other_ios`…
String readCounterField(ReadSource source, String platform) =>
    '${source.name}_$platform';

/// What has been counted and not yet flushed.
class ReadMeter {
  final _pending = <ReadSource, int>{};

  void add(ReadSource source, int reads) {
    if (reads <= 0) return;
    _pending[source] = (_pending[source] ?? 0) + reads;
  }

  bool get isEmpty => _pending.isEmpty;

  /// Hands over everything counted so far and starts again from nothing.
  Map<ReadSource, int> take() {
    final taken = Map<ReadSource, int>.of(_pending);
    _pending.clear();
    return taken;
  }
}

/// What Firestore bills one listener for, worked out from what the listener
/// itself can see. The rules (Firestore's, from its pricing documentation):
///
/// - a **new** listener is billed for every document in its first result,
///   and for one read when that result is empty;
/// - after that, one read per document **added or changed** — by the server;
///   this device's own pending write is not a read, its acknowledgement is;
/// - a listener cut off for more than [resumeWindow] is billed again **in
///   full** when it comes back, "as if it were a brand-new query" — and the
///   SDK raises no event for that when nothing changed meanwhile, so it has to
///   be inferred: from snapshots that were from-cache that long, or from a
///   process that was frozen that long (seen as a gap between [onCheck]s,
///   exactly as `freshWindowStream` sees it);
/// - with a persisted cache (phones) a restarted app's listener *resumes*
///   cheaply if its last sync is younger than [resumeWindow]: the first
///   snapshot comes from the cache, and the server then bills only what
///   changed. [lastSyncedAt] is that last sync, kept across restarts by
///   whoever owns the listener; without one the first answer counts in full.
class ListenerBill {
  ListenerBill({
    DateTime Function()? now,
    this.resumeWindow = listenerResumeWindow,
    this.checkInterval = listenerCheckInterval,
    this.lastSyncedAt,
  }) : _now = now ?? (() => clock.now()) {
    _lastCheckAt = _now();
  }

  final DateTime Function() _now;
  final Duration resumeWindow;
  final Duration checkInterval;

  /// When the server last answered this listener (or its query, in an earlier
  /// run of the app). Worth persisting: see the class comment.
  DateTime? lastSyncedAt;

  late DateTime _lastCheckAt;
  DateTime? _offlineSince;
  DateTime? _rerunDueSince;
  var _answered = false;
  var _cacheCameFirst = false;
  var _fromCache = false;
  var _size = 0;

  /// The reads billed for a snapshot of [size] documents, [changed] of them
  /// added or modified by the server since the last one.
  int onSnapshot({
    required bool isFromCache,
    required int size,
    required int changed,
  }) {
    final at = _now();
    _size = size;
    _fromCache = isFromCache;
    if (isFromCache) {
      _offlineSince ??= at;
      if (!_answered) _cacheCameFirst = true;
      return 0;
    }

    final bool inFull;
    if (!_answered) {
      final synced = lastSyncedAt;
      final resumed =
          _cacheCameFirst &&
          synced != null &&
          at.difference(synced) < resumeWindow;
      inFull = !resumed;
    } else {
      final since = _offlineSince;
      inFull =
          _rerunDueSince != null ||
          (since != null && at.difference(since) >= resumeWindow);
    }
    _answered = true;
    _rerunDueSince = null;
    _offlineSince = null;
    lastSyncedAt = at;
    return inFull ? math.max(1, size) : changed;
  }

  /// A steady tick, plus "the app just came back" and a follow-up shortly
  /// after (`listenerChecksProvider`). A frozen process ticks nothing, so the
  /// first check after waking sees the whole gap. The re-run that means is
  /// billed at the next answer from the server — or, because a re-run that
  /// changed nothing raises no snapshot at all, on trust at a check
  /// [listenerRerunGrace] later, unless the listener says it is offline. Never
  /// at the check that noticed it: the resume event and an overdue tick arrive
  /// together, before the SDK has had a chance to reconnect.
  int onCheck() {
    final at = _now();
    final gap = at.difference(_lastCheckAt);
    _lastCheckAt = at;
    if (!_answered) return 0;
    if (gap >= resumeWindow + checkInterval) {
      // A glance too short to reach the follow-up check still re-ran the
      // query — bill it now, or the next freeze would write it off.
      final owed = _rerunDueSince != null && !_fromCache
          ? math.max(1, _size)
          : 0;
      _rerunDueSince = at;
      return owed;
    }
    if (_fromCache) return 0;
    final due = _rerunDueSince;
    if (due == null) {
      // Connected, and nothing owed: the SDK keeps its resume token fresh
      // whether or not a document changes, so this — not the last change — is
      // when the listener last synced. After a quiet morning a restart is
      // still a cheap resume.
      lastSyncedAt = at;
      return 0;
    }
    if (at.difference(due) < listenerRerunGrace) return 0;
    _rerunDueSince = null;
    lastSyncedAt = at;
    return math.max(1, _size);
  }
}

/// The day's document and what to add to it for [counts], or null when there
/// is nothing to say. [plus] makes the increment sentinel and [serverTime] is
/// the timestamp one (`FieldValue.increment` / `.serverTimestamp()` in
/// production — injected, as in `rate_limit.dart`, so this stays testable).
({String day, Map<String, Object> data})? readMeterFlush(
  Map<ReadSource, int> counts, {
  required String platform,
  required DateTime at,
  required Object Function(int reads) plus,
  required Object serverTime,
}) {
  final data = <String, Object>{
    for (final MapEntry(key: source, value: reads) in counts.entries)
      if (reads > 0)
        readCounterField(source, platform): plus(
          math.min(reads, readMeterMaxStep),
        ),
  };
  if (data.isEmpty) return null;
  return (day: quotaDayOf(at), data: {...data, 'updatedAt': serverTime});
}
