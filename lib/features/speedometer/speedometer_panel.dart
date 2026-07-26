import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/gps_signal.dart';
import '../../services/speed_alert.dart';
import '../../theme/app_theme.dart';
import '../info/camera_timer.dart';
import 'trip_controller.dart';

const _speedGreen = Color(0xFF4ADE80);
const _speedOver = Color(0xFFEF4444);
const _avgOrange = Color(0xFFF59E0B);

// Panel buttons sit on pure black — they need a fill and a bright border to
// stay visible at night (AppTheme.border alone disappears on #000).
const _buttonFill = Color(0xFF1F1F23);
const _buttonBorder = Color(0xFF4A4A52);

/// The live speedometer block at the top of Home: current speed, nearest site,
/// average speed + reset, manual limit + steppers, and GPS/tracking status.
class SpeedometerPanel extends ConsumerStatefulWidget {
  const SpeedometerPanel({super.key});

  @override
  ConsumerState<SpeedometerPanel> createState() => _SpeedometerPanelState();
}

class _SpeedometerPanelState extends ConsumerState<SpeedometerPanel> {
  @override
  void initState() {
    super.initState();
    // GPS is always on from app open (issue #9); the trip logger only records.
    Future.microtask(
      () => ref.read(tripControllerProvider.notifier).ensureStarted(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tripControllerProvider);
    final limit = ref.watch(speedLimitProvider);
    final stats = state.avgStats;
    final over = isOverLimit(stats.currentSpeedKmh, limit);
    final speedColor = over ? _speedOver : _speedGreen;

    return Column(
      children: [
        const _Label('SPEED'),
        const SizedBox(height: 4),
        Text(
          pad3(stats.currentSpeedKmh),
          style: TextStyle(
            fontSize: 96,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: speedColor,
            letterSpacing: 2,
            shadows: [
              Shadow(color: speedColor.withValues(alpha: 0.55), blurRadius: 26),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const _Label('km  /  h'),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _AvgColumn(
                avgKmh: stats.avgSpeedKmh,
                // RESET re-baselines the average only — never the trip (#9).
                onReset: state.gps == GpsStatus.active
                    ? ref.read(tripControllerProvider.notifier).resetAvg
                    : null,
              ),
            ),
            Container(width: 1, height: 92, color: AppTheme.border),
            Expanded(
              child: _LimitColumn(
                limitKmh: limit,
                onMinus: ref.read(speedLimitProvider.notifier).decrement,
                onPlus: ref.read(speedLimitProvider.notifier).increment,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _StatusLine(signal: state.signal, recording: state.isRecording),
        // A running camera "Time me" session follows the driver to Home
        // (same panel as the Camera Times page — one source of truth).
        if (ref.watch(cameraTimerProvider) != null) ...[
          const SizedBox(height: 14),
          const CameraTimerPanel(),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppTheme.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 4,
    ),
  );
}

class _AvgColumn extends StatelessWidget {
  const _AvgColumn({required this.avgKmh, required this.onReset});
  final double avgKmh;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Label('AVG SPEED'),
        const SizedBox(height: 6),
        Text(
          pad3(avgKmh),
          style: const TextStyle(
            fontSize: 44,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: _avgOrange,
            shadows: [Shadow(color: Color(0x66F59E0B), blurRadius: 18)],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'km/h',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textPrimary,
            backgroundColor: _buttonFill,
            disabledForegroundColor: AppTheme.textSecondary,
            side: const BorderSide(color: _buttonBorder, width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('RESET'),
          onPressed: onReset,
        ),
      ],
    );
  }
}

class _LimitColumn extends StatelessWidget {
  const _LimitColumn({
    required this.limitKmh,
    required this.onMinus,
    required this.onPlus,
  });
  final int limitKmh;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Label('LIMIT'),
        const SizedBox(height: 6),
        Text(
          '$limitKmh',
          style: const TextStyle(
            fontSize: 44,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: _speedGreen,
            shadows: [Shadow(color: Color(0x664ADE80), blurRadius: 18)],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'km/h',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepButton(icon: Icons.remove, onPressed: onMinus),
            const SizedBox(width: 10),
            _StepButton(icon: Icons.add, onPressed: onPlus),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 40,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textPrimary,
          backgroundColor: _buttonFill,
          side: const BorderSide(color: _buttonBorder, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onPressed,
        child: Icon(icon, size: 22),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.signal, required this.recording});
  final GpsSignal signal;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    if (signal == GpsSignal.off || signal == GpsSignal.denied) {
      return Text(
        gpsSignalLabel(signal),
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      );
    }
    // Green only once fixes are actually arriving — amber while waiting, red
    // when the feed dropped. A frozen speedo then explains itself.
    final dot = switch (signal) {
      GpsSignal.live => _speedGreen,
      GpsSignal.acquiring => _avgOrange,
      _ => _speedOver,
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          gpsSignalLabel(signal),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        if (recording) ...[
          const SizedBox(width: 10),
          const Text('|', style: TextStyle(color: AppTheme.border)),
          const SizedBox(width: 10),
          const Icon(Icons.navigation, size: 14, color: AppTheme.accent),
          const SizedBox(width: 4),
          const Text(
            'Tracking',
            style: TextStyle(
              color: AppTheme.accent,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}
