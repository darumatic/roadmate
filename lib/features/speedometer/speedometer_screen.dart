import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../services/providers.dart';
import '../../services/trip_stats.dart';
import '../../theme/app_theme.dart';

/// Lifecycle of a trip on the speedometer.
enum TripPhase { idle, denied, running, stopped }

/// Immutable UI state for the speedometer: the phase plus the live trip stats.
class TripState {
  const TripState({
    this.phase = TripPhase.idle,
    this.stats = const TripStats.initial(),
  });

  final TripPhase phase;
  final TripStats stats;
}

/// Drives a trip: gates location permission, subscribes to the position stream,
/// folds fixes into a pure [TripStats], and keeps the screen awake while
/// tracking. The GPS plugin is reached only through [locationSourceProvider] so
/// the controller stays testable.
class TripController extends Notifier<TripState> {
  StreamSubscription<Position>? _sub;

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
      _sub?.cancel();
      _sub = null;
      _setWakelock(false);
      state = const TripState(phase: TripPhase.denied);
      return;
    }
    state = const TripState(phase: TripPhase.running);
    _setWakelock(true);
    await _sub?.cancel();
    _sub = source.positions().listen((pos) {
      final sample = TripSample(
        lat: pos.latitude,
        lng: pos.longitude,
        timestamp: pos.timestamp,
        speedMps: pos.speed,
      );
      state = TripState(
        phase: TripPhase.running,
        stats: state.stats.addSample(sample),
      );
    });
  }

  /// Stops tracking but keeps the final stats on screen.
  void stop() {
    _sub?.cancel();
    _sub = null;
    _setWakelock(false);
    state = TripState(phase: TripPhase.stopped, stats: state.stats);
  }

  /// Clears the trip back to the initial idle state.
  void reset() {
    _sub?.cancel();
    _sub = null;
    _setWakelock(false);
    state = const TripState();
  }

  // Best-effort: never let a missing/failed wakelock plugin break a trip (it
  // also throws in the test harness). No-op on web.
  Future<void> _setWakelock(bool on) async {
    if (kIsWeb) return;
    try {
      on ? await WakelockPlus.enable() : await WakelockPlus.disable();
    } catch (_) {
      // Ignore — keeping the screen awake is a nicety, not a requirement.
    }
  }
}

final tripControllerProvider = NotifierProvider<TripController, TripState>(
  TripController.new,
);

/// Full-screen GPS speedometer for a driver's trip. Mobile-only; the web build
/// shows an unsupported notice since browser GPS has no reliable speed.
class SpeedometerScreen extends ConsumerWidget {
  const SpeedometerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Trip',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: kIsWeb ? const _WebUnsupported() : _body(context, ref),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tripControllerProvider);
    final controller = ref.read(tripControllerProvider.notifier);

    if (state.phase == TripPhase.denied) {
      return _PermissionDenied(onRetry: controller.start);
    }

    final stats = state.stats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          const Spacer(),
          _CurrentSpeed(kmh: stats.currentSpeedKmh),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'MAX',
                  value: stats.maxSpeedKmh.toStringAsFixed(0),
                  unit: 'km/h',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'AVG',
                  value: stats.avgSpeedKmh.toStringAsFixed(0),
                  unit: 'km/h',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'DISTANCE',
                  value: stats.distanceKm.toStringAsFixed(1),
                  unit: 'km',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'TIME',
                  value: _formatDuration(stats.duration),
                  unit: '',
                ),
              ),
            ],
          ),
          const Spacer(),
          _Controls(state: state, controller: controller),
          const SizedBox(height: 16),
          const Text(
            'GPS speed is approximate. Don’t interact while driving. '
            'Not a certified speedometer — always follow your dashboard '
            'and road signage.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class _CurrentSpeed extends StatelessWidget {
  const _CurrentSpeed({required this.kmh});

  final double kmh;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          kmh.toStringAsFixed(0),
          style: const TextStyle(
            fontSize: 112,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'km/h',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.accent,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.controller});

  final TripState state;
  final TripController controller;

  @override
  Widget build(BuildContext context) {
    switch (state.phase) {
      case TripPhase.running:
        return _WideButton(
          label: 'Stop',
          icon: Icons.stop_rounded,
          filled: false,
          onPressed: controller.stop,
        );
      case TripPhase.stopped:
        return Row(
          children: [
            Expanded(
              child: _WideButton(
                label: 'Reset',
                icon: Icons.refresh_rounded,
                filled: false,
                onPressed: controller.reset,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _WideButton(
                label: 'New Trip',
                icon: Icons.play_arrow_rounded,
                filled: true,
                onPressed: controller.start,
              ),
            ),
          ],
        );
      case TripPhase.idle:
      case TripPhase.denied:
        return _WideButton(
          label: 'Start Trip',
          icon: Icons.play_arrow_rounded,
          filled: true,
          onPressed: controller.start,
        );
    }
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              onPressed: onPressed,
              child: child,
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.border),
              ),
              onPressed: onPressed,
              child: child,
            ),
    );
  }
}

class _PermissionDenied extends StatelessWidget {
  const _PermissionDenied({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_off_outlined,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Location needed',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Grant location access to track your speed. Enable it, then try '
              'again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: const BorderSide(color: AppTheme.border),
                  ),
                  onPressed: Geolocator.openAppSettings,
                  child: const Text('Open settings'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WebUnsupported extends StatelessWidget {
  const _WebUnsupported();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_iphone, size: 48, color: AppTheme.textSecondary),
            SizedBox(height: 12),
            Text(
              'Available in the app',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'The GPS speedometer needs a phone’s GPS and works in the '
              'iOS and Android apps, not the web version.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
