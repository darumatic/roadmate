import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/trip.dart';
import '../../services/providers.dart';
import '../../services/speed_alert.dart';
import '../../services/trip_history_store.dart';
import '../../services/trip_stats.dart';

/// Whether the always-on GPS stream is feeding the speedometer.
enum GpsStatus { off, denied, active }

/// Immutable state for the Home speedometer + Trip Logger. The speedometer
/// (live speed + AVG) and the trip recording are independent (issues #6/#9):
/// GPS runs from app open, RESET re-baselines only [avgStats], and
/// Start/Stop only controls [tripStats].
class TripState {
  const TripState({
    this.gps = GpsStatus.off,
    this.avgStats = const TripStats.initial(),
    this.tripStats,
    this.tripStartedAt,
  });

  final GpsStatus gps;

  /// Drives the live speed readout and AVG SPEED; reset by the RESET button
  /// without touching a recording trip.
  final TripStats avgStats;

  /// Accumulates the trip being recorded; null when no trip is running.
  final TripStats? tripStats;

  /// Wall-clock time the recording trip started.
  final DateTime? tripStartedAt;

  bool get isRecording => tripStats != null;
  double get currentSpeedKmh => avgStats.currentSpeedKmh;

  static const _unset = Object();

  TripState copyWith({
    GpsStatus? gps,
    TripStats? avgStats,
    Object? tripStats = _unset,
    Object? tripStartedAt = _unset,
  }) {
    return TripState(
      gps: gps ?? this.gps,
      avgStats: avgStats ?? this.avgStats,
      tripStats: identical(tripStats, _unset)
          ? this.tripStats
          : tripStats as TripStats?,
      tripStartedAt: identical(tripStartedAt, _unset)
          ? this.tripStartedAt
          : tripStartedAt as DateTime?,
    );
  }
}

/// Drives one GPS stream feeding the live speedo and the Trip Logger: gates
/// permission, folds fixes into a pure [TripStats], sounds the over-limit
/// warning, and saves finished trips. GPS is reached only through
/// [locationSourceProvider]; audio/storage through their providers — all
/// overridable in tests.
class TripController extends Notifier<TripState> {
  StreamSubscription<Position>? _sub;
  DateTime? _lastAlertAt;
  Future<void>? _starting;

  @override
  TripState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _setWakelock(false);
    });
    return const TripState();
  }

  /// Starts the always-on GPS stream (idempotent). The speedometer calls this
  /// once when it first builds so live speed runs from app open (issue #9).
  /// A previous denial is sticky — use [retry] to re-prompt.
  Future<void> ensureStarted() {
    if (_sub != null || state.gps == GpsStatus.denied) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  /// Re-prompts for permission after a denial (the Denied card's button).
  Future<void> retry() {
    if (_sub != null) return Future.value();
    state = state.copyWith(gps: GpsStatus.off);
    return ensureStarted();
  }

  Future<void> _start() async {
    final source = ref.read(locationSourceProvider);
    bool granted;
    try {
      granted = await source.ensurePermission();
    } catch (e) {
      // Plugin unavailable (or test harness) — treat as denied, never throw.
      debugPrint('RoadMate: location permission check failed: $e');
      granted = false;
    }
    if (!granted) {
      state = state.copyWith(gps: GpsStatus.denied);
      return;
    }
    _lastAlertAt = null;
    // A stream error (GPS dropout, service toggled) must not become an
    // unhandled exception; the subscription stays live and recovers.
    _sub = source.positions().listen(_onPosition, onError: (Object _) {});
    state = state.copyWith(gps: GpsStatus.active);
  }

  /// Re-baselines the average speed (and the live max) — the RESET control
  /// under AVG SPEED. Independent of trip recording (issue #9): a running
  /// trip's distance/elapsed are untouched.
  void resetAvg() {
    state = state.copyWith(avgStats: const TripStats.initial());
  }

  /// Begins recording a trip. GPS keeps running regardless.
  Future<void> startTrip() async {
    await ensureStarted();
    if (state.gps != GpsStatus.active || state.isRecording) return;
    _setWakelock(true);
    state = state.copyWith(
      tripStats: const TripStats.initial(),
      tripStartedAt: DateTime.now(),
    );
  }

  /// Ends the recording and saves it to on-device history. The UI leaves the
  /// in-progress card synchronously, before any platform call: a failing
  /// storage write must never leave the stop button looking dead. The GPS
  /// stream is NOT stopped — the speedometer stays live (issue #9).
  Future<void> stopAndSave() async {
    final s = state.tripStats ?? const TripStats.initial();
    final startedAt = state.tripStartedAt;
    state = state.copyWith(tripStats: null, tripStartedAt: null);
    _setWakelock(false);

    // Save even if no GPS fix ever arrived (the design keeps zero-stat trips).
    // Without samples the GPS duration is zero, so fall back to wall clock.
    if (startedAt != null) {
      final trip = Trip(
        id: startedAt.microsecondsSinceEpoch.toString(),
        startedAt: startedAt,
        duration: s.hasStarted
            ? s.duration
            : DateTime.now().difference(startedAt),
        distanceKm: s.distanceKm,
        maxSpeedKmh: s.maxSpeedKmh,
        avgSpeedKmh: s.avgSpeedKmh,
      );
      try {
        await ref.read(tripHistoryStoreProvider).save(trip);
        ref.invalidate(tripHistoryProvider);
      } catch (e) {
        // History is a nicety — a storage failure must not break stop. But
        // never swallow it invisibly (a silent catch masked a broken web
        // build for days): leave a trace in the console.
        debugPrint('RoadMate: failed to save trip: $e');
      }
    }
  }

  void _onPosition(Position pos) {
    // A fix delivered after dispose must not resurrect state.
    if (_sub == null) return;
    final sample = TripSample(
      lat: pos.latitude,
      lng: pos.longitude,
      timestamp: pos.timestamp,
      speedMps: pos.speed,
    );
    final avg = state.avgStats.addSample(sample);
    state = state.copyWith(
      gps: GpsStatus.active,
      avgStats: avg,
      tripStats: state.tripStats?.addSample(sample),
    );
    // Over-limit warning runs whenever GPS is live, trip or no trip (#6).
    _maybeAlert(avg.currentSpeedKmh);
  }

  void _maybeAlert(double speedKmh) {
    final limit = ref.read(speedLimitProvider);
    final now = DateTime.now();
    if (shouldAlert(
      speedKmh: speedKmh,
      limitKmh: limit,
      now: now,
      lastAlertAt: _lastAlertAt,
    )) {
      _lastAlertAt = now;
      ref.read(alertPlayerProvider).playOverLimit();
    } else if (!isOverLimit(speedKmh, limit)) {
      // Back within the limit — arm the next breach to fire immediately.
      _lastAlertAt = null;
    }
  }

  // Best-effort; never let a missing/failed plugin (or the test harness) break
  // tracking. No-op on web.
  Future<void> _setWakelock(bool on) async {
    if (kIsWeb) return;
    try {
      on ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {
      // Keeping the screen awake is a nicety, not a requirement.
    }
  }
}

final tripControllerProvider = NotifierProvider<TripController, TripState>(
  TripController.new,
);

/// Saved trips, newest first, for the list under the Trip Logger. Storage
/// failures collapse to an error state the UI renders as "no trips" — the
/// list is a nicety, never a blocker.
class TripHistoryController extends AsyncNotifier<List<Trip>> {
  @override
  Future<List<Trip>> build() => ref.read(tripHistoryStoreProvider).all();

  /// Deletes one saved trip by id.
  Future<void> remove(String id) async {
    final store = ref.read(tripHistoryStoreProvider);
    try {
      await store.delete(id);
      state = AsyncData(await store.all());
    } catch (e) {
      // Keep whatever the list showed; storage is best-effort.
      debugPrint('RoadMate: failed to delete trip: $e');
    }
  }

  /// Deletes every saved trip.
  Future<void> clear() async {
    try {
      await ref.read(tripHistoryStoreProvider).clear();
      state = const AsyncData([]);
    } catch (e) {
      // Keep whatever the list showed; storage is best-effort.
      debugPrint('RoadMate: failed to clear trips: $e');
    }
  }
}

final tripHistoryProvider =
    AsyncNotifierProvider<TripHistoryController, List<Trip>>(
      TripHistoryController.new,
    );

/// The manually-set speed limit (km/h), persisted on device. Loaded from the
/// store on build; `increment`/`decrement` step and persist within bounds.
class SpeedLimitController extends Notifier<int> {
  @override
  int build() {
    _load();
    return kDefaultSpeedLimit;
  }

  Future<void> _load() async {
    try {
      state = await ref.read(tripHistoryStoreProvider).loadLimit();
    } catch (e) {
      // Storage unavailable (e.g. first launch or test harness) — keep default.
      debugPrint('RoadMate: failed to load speed limit: $e');
    }
  }

  void increment() =>
      _set((state + kSpeedLimitStep).clamp(kMinSpeedLimit, kMaxSpeedLimit));

  void decrement() =>
      _set((state - kSpeedLimitStep).clamp(kMinSpeedLimit, kMaxSpeedLimit));

  void _set(int value) {
    state = value;
    ref.read(tripHistoryStoreProvider).saveLimit(value);
  }
}

final speedLimitProvider = NotifierProvider<SpeedLimitController, int>(
  SpeedLimitController.new,
);
