import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/trip.dart';
import '../../theme/app_theme.dart';
import 'trip_controller.dart';

const _amber = Color(0xFFF59E0B);
const _deleteRed = Color(0xFFEF4444);

/// One saved trip, per the design: date + time range on the left, distance /
/// average speed / elapsed-time chips, and a delete ×. Shared by the Home
/// Trip Logger and the Trips tab.
class TripTile extends StatelessWidget {
  const TripTile({super.key, required this.trip, required this.onDelete});
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
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _TripChip(
                    icon: Icons.place_outlined,
                    label: '${trip.distanceKm.toStringAsFixed(2)} km',
                  ),
                  _TripChip(
                    icon: Icons.show_chart,
                    label: 'avg ${trip.avgSpeedKmh.toStringAsFixed(0)} km/h',
                    color: _amber,
                  ),
                  _TripChip(
                    icon: Icons.schedule,
                    label: formatTripDuration(trip.duration),
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

/// Per-trip delete confirmation (design: "Delete Trip / Remove this trip from
/// your log?"). Removes the trip via [tripHistoryProvider] when confirmed.
Future<void> confirmDeleteTrip(
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
          style: TextButton.styleFrom(foregroundColor: _deleteRed),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok == true) await ref.read(tripHistoryProvider.notifier).remove(tripId);
}

/// "Clear all" confirmation; wipes the whole trip history when confirmed.
Future<void> confirmClearAllTrips(BuildContext context, WidgetRef ref) async {
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
