import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/camera_times.dart';
import '../../theme/app_theme.dart';
import '../speedometer/trip_controller.dart';

/// "Time me" for an average-speed camera stretch: the driver starts it at the
/// first camera and the panel counts up against the expected minimum time,
/// flipping green once passing the end camera is legal. Lives in a global
/// provider so the timer keeps running while the driver uses other tabs.

class CameraTimerSession {
  const CameraTimerSession({
    required this.targetTitle,
    required this.distanceKm,
    required this.expectedSeconds,
    required this.startedAt,
    this.baselineKm,
    this.upcoming = const [],
  });

  /// What is being timed, e.g. "Marulan → Gundagai".
  final String targetTitle;
  final int distanceKm;
  final int expectedSeconds;
  final DateTime startedAt;

  /// The shared GPS odometer reading (`avgStats.distanceKm`) when the session
  /// started, so the panel can show a session average without opening a second
  /// GPS stream. Null when GPS wasn't active at start.
  final double? baselineKm;

  /// The legs after the current target, in run order — lets the driver jump
  /// to the next camera stretch as soon as they pass the end camera.
  final List<CameraLeg> upcoming;

  CameraLeg? get nextLeg => upcoming.isEmpty ? null : upcoming.first;

  Duration elapsedAt(DateTime now) => now.difference(startedAt);
}

class CameraTimerController extends Notifier<CameraTimerSession?> {
  @override
  CameraTimerSession? build() => null;

  /// Starts timing (replacing any running session). [startedAt] is
  /// injectable for tests.
  void start({
    required String targetTitle,
    required int distanceKm,
    required int expectedSeconds,
    List<CameraLeg> upcoming = const [],
    DateTime? startedAt,
  }) {
    final trip = ref.read(tripControllerProvider);
    state = CameraTimerSession(
      targetTitle: targetTitle,
      distanceKm: distanceKm,
      expectedSeconds: expectedSeconds,
      startedAt: startedAt ?? DateTime.now(),
      baselineKm: trip.gps == GpsStatus.active
          ? trip.avgStats.distanceKm
          : null,
      upcoming: upcoming,
    );
  }

  /// Rolls the session to the next camera stretch: the driver passed the end
  /// camera and starts timing the following leg (fresh clock and baseline).
  /// No-op when nothing is queued.
  void startNext({DateTime? startedAt}) {
    final next = state?.nextLeg;
    if (next == null) return;
    start(
      targetTitle: next.title,
      distanceKm: next.distanceKm,
      expectedSeconds: next.expectedSeconds,
      upcoming: state!.upcoming.sublist(1),
      startedAt: startedAt,
    );
  }

  void stop() => state = null;
}

final cameraTimerProvider =
    NotifierProvider<CameraTimerController, CameraTimerSession?>(
      CameraTimerController.new,
    );

/// The running-session card: countdown to "clear to pass", elapsed vs target,
/// and (when GPS is live) the session's own average speed.
class CameraTimerPanel extends ConsumerStatefulWidget {
  const CameraTimerPanel({super.key});

  @override
  ConsumerState<CameraTimerPanel> createState() => _CameraTimerPanelState();
}

class _CameraTimerPanelState extends ConsumerState<CameraTimerPanel> {
  Timer? _tick;

  static const _green = Color(0xFF22C55E); // matches SiteStatus.open

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cameraTimerProvider);
    if (session == null) return const SizedBox.shrink();

    final elapsed = session.elapsedAt(DateTime.now());
    final wait = legalWaitSeconds(
      expectedSeconds: session.expectedSeconds,
      elapsedSeconds: elapsed.inSeconds,
    );
    final clear = wait == 0;
    final color = clear ? _green : AppTheme.accent;

    // Session average from the shared GPS odometer (null when GPS is off or
    // the driver reset the speedo mid-session).
    final trip = ref.watch(tripControllerProvider);
    double? avg;
    if (session.baselineKm != null && trip.gps == GpsStatus.active) {
      avg = sessionAvgKmh(
        distanceKm: trip.avgStats.distanceKm - session.baselineKm!,
        elapsed: elapsed,
      );
    }
    final maxAvg = maxLegalAvgKmh(
      distanceKm: session.distanceKm,
      expectedSeconds: session.expectedSeconds,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  clear ? Icons.check_circle_outline : Icons.timer_outlined,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'TIMING · ${session.targetTitle}',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      ref.read(cameraTimerProvider.notifier).stop(),
                  icon: const Icon(Icons.close_rounded),
                  color: AppTheme.textSecondary,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Stop timing',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              clear ? 'Clear to pass' : formatCameraDuration(wait),
              style: TextStyle(
                color: color,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              clear
                  ? 'Passing the end camera now means a legal average.'
                  : 'until passing the end camera is legal',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Elapsed ${formatCameraDuration(elapsed.inSeconds)} · '
              'target ${formatCameraDuration(session.expectedSeconds)}'
              '${avg != null ? ' · avg ${avg.round()} km/h' : ''} · '
              'max legal avg ${maxAvg.round()} km/h',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            if (session.nextLeg case final next?) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next · ${next.title}',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${next.distanceKm} km · '
                          '${formatCameraDuration(next.expectedSeconds)}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        ref.read(cameraTimerProvider.notifier).startNext(),
                    icon: const Icon(Icons.skip_next_rounded, size: 18),
                    label: const Text('Start next'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
