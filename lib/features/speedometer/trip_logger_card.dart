import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/trip.dart';
import '../../theme/app_theme.dart';
import 'trip_controller.dart';

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
                onPressed: () => _confirmClearAll(context, ref),
              ),
          ],
        ),
        const SizedBox(height: 12),
        switch (state.phase) {
          TripPhase.running => _InProgress(state: state, controller: controller),
          TripPhase.denied => _Denied(onRetry: controller.start),
          TripPhase.idle => _Idle(onStart: controller.start),
        },
        if (trips.isEmpty && state.phase == TripPhase.idle) const _EmptyTrips(),
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
          for (final trip in trips)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TripTile(
                trip: trip,
                onDelete: () => _confirmDelete(context, ref, trip.id),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String tripId,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Trip'),
        content: const Text('Remove this trip from your log?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _stopRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(tripHistoryProvider.notifier).remove(tripId);
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all trips?'),
        content: const Text('This permanently deletes every saved trip.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(tripHistoryProvider.notifier).clear();
  }
}

/// One saved trip, per the design: date + time range on the left, distance /
/// duration / top-speed chips with the average underneath, and a delete ×.
class _TripTile extends StatelessWidget {
  const _TripTile({required this.trip, required this.onDelete});
  final Trip trip;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEE, d MMM').format(trip.startedAt),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_clock(trip.startedAt)} → '
                  '${_clock(trip.startedAt.add(trip.duration))}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _TripChip(
                        icon: Icons.place_outlined,
                        label: '${trip.distanceKm.toStringAsFixed(2)} km',
                      ),
                      _TripChip(
                        icon: Icons.schedule,
                        label: formatTripDuration(trip.duration),
                      ),
                      _TripChip(
                        icon: Icons.trending_up,
                        label: '${trip.maxSpeedKmh.toStringAsFixed(0)} km/h',
                        color: _amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.show_chart,
                        size: 13,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'avg ${trip.avgSpeedKmh.toStringAsFixed(0)} km/h',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onDelete,
              customBorder: const CircleBorder(),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripChip extends StatelessWidget {
  const _TripChip({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _clock(DateTime t) => DateFormat('h:mm a').format(t).toLowerCase();

/// Compact duration for a saved trip: "1h 5m", "12m 30s" or "45s".
String formatTripDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  return '${d.inSeconds}s';
}

class _InProgress extends StatelessWidget {
  const _InProgress({required this.state, required this.controller});
  final TripState state;
  final TripController controller;

  @override
  Widget build(BuildContext context) {
    final stats = state.stats;
    final started = state.startedAt;
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
