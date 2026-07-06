import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/trip.dart';
import '../../services/trip_stats.dart';
import '../../theme/app_theme.dart';
import 'trip_controller.dart';
import 'trip_tile.dart';

const _tripGreen = Color(0xFF4ADE80);
const _stopRed = Color(0xFFEF4444);
const _amber = Color(0xFFF59E0B);

/// The "Trip Logger" section: a live in-progress card while a trip runs, a
/// permission-denied prompt, or a Start button when idle.
class TripLoggerCard extends ConsumerWidget {
  const TripLoggerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tripControllerProvider);
    final controller = ref.read(tripControllerProvider.notifier);
    final trips = ref.watch(tripHistoryProvider).asData?.value ?? const <Trip>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.route, size: 18, color: AppTheme.accent),
            const SizedBox(width: 8),
            const Text(
              'Trip Logger',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const Spacer(),
            if (trips.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear all'),
                onPressed: () => confirmClearAllTrips(context, ref),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (state.isRecording)
          _InProgress(
            stats: state.tripStats!,
            startedAt: state.tripStartedAt,
            controller: controller,
          )
        else if (state.gps == GpsStatus.denied)
          _Denied(onRetry: controller.retry)
        else
          _Idle(onStart: controller.startTrip),
        if (trips.isEmpty && !state.isRecording) const _EmptyTrips(),
        if (trips.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '${trips.length} saved trip${trips.length == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // Home keeps the 3 most recent; the Trips tab lists all (issue #5).
          for (final trip in trips.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TripTile(
                trip: trip,
                onDelete: () => confirmDeleteTrip(context, ref, trip.id),
              ),
            ),
          if (trips.length > 3)
            Center(
              child: TextButton(
                onPressed: () => context.go('/trips'),
                child: Text('View all (${trips.length})'),
              ),
            ),
        ],
      ],
    );
  }
}

class _InProgress extends StatelessWidget {
  const _InProgress({
    required this.stats,
    required this.startedAt,
    required this.controller,
  });
  final TripStats stats;
  final DateTime? startedAt;
  final TripController controller;

  @override
  Widget build(BuildContext context) {
    final started = startedAt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _tripGreen.withValues(alpha: 0.06),
        border: Border.all(color: _tripGreen.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: _tripGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Trip in progress',
                  style: TextStyle(
                    color: _tripGreen,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (started != null)
                  Text(
                    'Started ${DateFormat('h:mm a').format(started).toLowerCase()}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    _Metric(value: _elapsed(stats.duration), label: 'ELAPSED'),
                    _Divider(),
                    _Metric(
                      value: '${stats.distanceKm.toStringAsFixed(2)} km',
                      label: 'DISTANCE',
                    ),
                    _Divider(),
                    _Metric(
                      value: '${stats.maxSpeedKmh.toStringAsFixed(0)} km/h',
                      label: 'TOP SPEED',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _stopRed,
                  backgroundColor: _stopRed.withValues(alpha: 0.14),
                  side: BorderSide(color: _stopRed.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.stop, size: 20),
                label: const Text(
                  'Stop & Save Trip',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                onPressed: controller.stopAndSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _amber.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _amber.withValues(alpha: 0.55)),
      ),
      child: InkWell(
        onTap: onStart,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.near_me_outlined,
                size: 22,
                color: AppTheme.textPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Start New Trip',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Records distance, speed & duration',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when idle with no saved trips — mirrors the design's empty state.
class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: const [
            Icon(Icons.map_outlined, size: 34, color: AppTheme.textSecondary),
            SizedBox(height: 10),
            Text(
              'No trips yet — start one above',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _Denied extends StatelessWidget {
  const _Denied({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Location access is needed to track your trip. Enable it, then '
              'try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: AppTheme.border);
}

String _elapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  return '${m}m ${s}s';
}
