import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/site.dart';
import '../../services/geo.dart';
import '../../theme/app_theme.dart';
import '../nearby/nearby_screen.dart' show currentPositionProvider;
import '../speedometer/trip_controller.dart';

/// The two closest sites to the driver (issue #7) — sits where the
/// Open/Blitz/Closed stats bar used to be. Coordinates come from the
/// always-on GPS stream when it has a fix (recomputed on every sample, so
/// fresher than the 1-minute ask); otherwise from the one-shot
/// [currentPositionProvider], re-polled every minute. Hidden when no
/// position is available at all.
class ClosestSitesCard extends ConsumerStatefulWidget {
  const ClosestSitesCard({super.key, required this.sites});
  final List<Site> sites;

  @override
  ConsumerState<ClosestSitesCard> createState() => _ClosestSitesCardState();
}

class _ClosestSitesCardState extends ConsumerState<ClosestSitesCard> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(minutes: 1), (_) {
      // Keeps the no-GPS fallback position fresh while the truck moves.
      ref.invalidate(currentPositionProvider);
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(tripControllerProvider);
    final oneShot = ref.watch(currentPositionProvider).asData?.value;

    final lat = trip.avgStats.lastLat ?? oneShot?.latitude;
    final lng = trip.avgStats.lastLng ?? oneShot?.longitude;
    if (lat == null || lng == null) return const SizedBox.shrink();

    final ranked = nearestSites(widget.sites, lat, lng, limit: 2);
    if (ranked.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CLOSEST SITES',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in ranked)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SiteRow(site: entry.site, km: entry.km),
          ),
      ],
    );
  }
}

class _SiteRow extends StatelessWidget {
  const _SiteRow({required this.site, required this.km});
  final Site site;
  final double km;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/state/${site.state.code}?site=${site.id}'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 20,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kmAwayLabel(km),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                color: site.currentStatus.color,
                label: site.currentStatus.label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
