import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'read_meter.dart';

/// The platform a build's reads are filed under, or null for one that isn't
/// metered (a desktop build is a developer's, not a driver's).
String? readMeterPlatform({bool isWeb = kIsWeb, TargetPlatform? platform}) {
  if (isWeb) return 'web';
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => null,
  };
}

/// Empties the [ReadMeter] into the day's counter document (issue #54): about
/// one write when the app is put away, plus one per [interval] while it stays
/// open — **never per action**, because writes have their own daily quota.
///
/// Firebase-free: the write itself and the two sentinels are injected (the
/// provider supplies `FieldValue.increment` / `.serverTimestamp()`), so the
/// cadence is testable with a fake clock.
class ReadMeterFlusher {
  ReadMeterFlusher({
    required this.meter,
    required this.platform,
    required this.ready,
    required this.write,
    required this.plus,
    required this.serverTime,
    this.interval = readMeterFlushInterval,
    this.minGap = readMeterMinFlushGap,
    this.firstFlush = readMeterFirstFlush,
    this.firstFlushTries = readMeterFirstFlushTries,
  });

  final ReadMeter meter;
  final String platform;

  /// Whether a write can go out at all — it needs a signed-in user, and the
  /// anonymous sign-in may still be on its way. Until then the counts wait.
  final bool Function() ready;

  /// Adds [data] to the counter document of [day].
  final Future<void> Function(String day, Map<String, Object> data) write;

  final Object Function(int reads) plus;
  final Object serverTime;
  final Duration interval;
  final Duration minGap;
  final Duration firstFlush;
  final int firstFlushTries;

  Timer? _timer;
  Timer? _firstTimer;
  DateTime? _flushedAt;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => flush());
    // The cold start is the dearest thing a session does, and a browser tab
    // closed within [interval] would flush it only while unloading — a write
    // that dies with the page. So the first flush comes early, and is tried
    // again until one has gone out (the sign-in may not be there yet).
    _firstTimer ??= Timer.periodic(firstFlush, (timer) {
      if (_flushedAt == null) flush();
      if (_flushedAt != null || timer.tick >= firstFlushTries) timer.cancel();
    });
  }

  /// The app was put away. Mobile reports that in two or three steps (hidden,
  /// paused, detached) and a browser on every tab switch, so a flush that
  /// follows another within [minGap] is left for the next occasion.
  void onBackground() {
    final last = _flushedAt;
    if (last != null && clock.now().difference(last) < minGap) return;
    flush();
  }

  void flush() {
    if (meter.isEmpty || !ready()) return;
    final at = clock.now();
    final flush = readMeterFlush(
      meter.take(),
      platform: platform,
      at: at,
      plus: plus,
      serverTime: serverTime,
    );
    if (flush == null) return;
    _flushedAt = at;
    // Not awaited: offline the write just queues. And never put back when it
    // fails: a refused count that kept growing would outgrow the step the
    // rules accept, and every flush after it would be refused too. The meter
    // is a floor; this is one more way it stays one.
    unawaited(write(flush.day, flush.data).catchError((Object _) {}));
  }

  void dispose() {
    _timer?.cancel();
    _firstTimer?.cancel();
  }
}
