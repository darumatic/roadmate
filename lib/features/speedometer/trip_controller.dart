import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/trip.dart';
import '../../services/providers.dart';
import '../../services/speed_alert.dart';
import '../../services/trip_history_store.dart';
import '../../services/trip_stats.dart';

/// Lifecycle of the trip / live speedo.
enum TripPhase { idle, denied, running }

/// Immutable state for the Home speedometer + Trip Logger.
class TripState {
  const TripState({
    this.phase = TripPhase.idle,
    this.stats = const TripStats.initial(),
    this.startedAt,
  });

  final TripPhase phase;
  final TripStats stats;

  /// Wall-clock time the current trip started (or was last reset).
  final DateTime? startedAt;

  bool get isRunning => phase == TripPhase.running;
}

/// Drives one GPS stream feeding the live speedo and the Trip Logger: gates
/// permission, folds fixes into a pure [TripStats], sounds the over-limit
/// warning, and saves finished trips. GPS is reached only through
/// [locationSourceProvider]; audio/storage through their providers — all
/// overridable in tests.
class TripController extends Notifier<TripState> {
  StreamSubscription<Position>? _sub;
  DateTime? _lastAlertAt;

  @override
  TripState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _setWakelock(false);
    });
    return const TripState();
  }

  /// Requests permission (if needed) and starts a fresh trip.
  Future<void> start() async {
    final source = ref.read(locationSourceProvider);
    if (!await source.ensurePermission()) {
      await _sub?.cancel();
      _sub = null;
      _setWakelock(false);
      state = const TripState(phase: TripPhase.denied);
      return;
    }
    _lastAlertAt = null;
    state = TripState(phase: TripPhase.running, startedAt: DateTime.now());
    _setWakelock(true);
    unawaited(_sub?.cancel().catchError((_) {}));
    // A stream error (GPS dropout, service toggled) must not become an
    // unhandled exception; the subscription stays live and recovers.
    _sub = source.positions().listen(_onPosition, onError: (Object _) {});
  }

  /// Re-baselines the running trip (zeroes avg/max/distance/elapsed) without
  /// ending it — the RESET control under AVG SPEED.
  void reset() {
    if (!state.isRunning) return;
    _lastAlertAt = null;
    state = TripState(phase: TripPhase.running, startedAt: DateTime.now());
  }

  /// Ends the trip and saves it to on-device history. The UI returns to idle
  /// synchronously, before any platform call: a hung GPS-stream cancel or a
  /// failing storage write must never leave the card stuck on
  /// "Trip in progress" (the stop button looking dead).
  Future<void> stopAndSave() async {
    final s = state.stats;
    final startedAt = state.startedAt;
    final sub = _sub;
    _sub = null;
    _lastAlertAt = null;
    state = const TripState();
    _setWakelock(false);
    // Fire-and-forget: cancel stops event delivery immediately even if the
    // platform never completes the returned future.
    unawaited(sub?.cancel().catchError((_) {}));

    if (startedAt != null && s.hasStarted) {
      final trip = Trip(
        id: startedAt.microsecondsSinceEpoch.toString(),
        startedAt: startedAt,
        duration: s.duration,
        distanceKm: s.distanceKm,
        maxSpeedKmh: s.maxSpeedKmh,
        avgSpeedKmh: s.avgSpeedKmh,
      );
      try {
        await ref.read(tripHistoryStoreProvider).save(trip);
        ref.invalidate(tripHistoryProvider);
      } catch (_) {
        // History is a nicety — a storage failure must not surface here.
      }
    }
  }

  void _onPosition(Position pos) {
    // A fix delivered after stop must not flip the UI back to running.
    if (_sub == null) return;
    final stats = state.stats.addSample(
      TripSample(
        lat: pos.latitude,
        lng: pos.longitude,
        timestamp: pos.timestamp,
        speedMps: pos.speed,
      ),
    );
    state = TripState(
      phase: TripPhase.running,
      stats: stats,
      startedAt: state.startedAt,
    );
    _maybeAlert(stats.currentSpeedKmh);
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
    } catch (_) {
      // Keep whatever the list showed; storage is best-effort.
    }
  }

  /// Deletes every saved trip.
  Future<void> clear() async {
    try {
      await ref.read(tripHistoryStoreProvider).clear();
      state = const AsyncData([]);
    } catch (_) {
      // Keep whatever the list showed; storage is best-effort.
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
    } catch (_) {
      // Storage unavailable (e.g. first launch or test harness) — keep default.
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
