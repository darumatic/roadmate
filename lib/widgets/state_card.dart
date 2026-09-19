import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../models/site.dart';
import '../services/site_stats.dart';
import '../theme/app_theme.dart';
import 'status_labels.dart';

/// A "Browse by State" card showing the state, its site count and a status
/// breakdown. Highlights when a blitz is active somewhere in the state.
class StateCard extends StatelessWidget {
  const StateCard({
    super.key,
    required this.state,
    required this.sites,
    this.onTap,
  });

  final AusState state;
  final List<Site> sites;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final counts = countByStatus(sites);
    final hasBlitz = counts.blitz > 0;
    final accent = hasBlitz ? SiteStatus.blitz.color : AppTheme.border;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent, width: hasBlitz ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(state.emoji, style: const TextStyle(fontSize: 24)),
                if (hasBlitz)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: SiteStatus.blitz.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: SiteStatus.blitz.color.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 12,
                          color: SiteStatus.blitz.color,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          statusDisplayLabel(SiteStatus.blitz),
                          style: TextStyle(
                            color: SiteStatus.blitz.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              state.code,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              state.fullName,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            _statusBar(counts),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Shrinks to fit: five non-zero tallies beside "N sites" are
                // wider than a grid cell on a small phone.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (count, status) in _tallies(counts))
                          // Open always shows (a bare "0" still says "none
                          // open"); the rest only when there is something.
                          if (status == SiteStatus.open || count > 0) ...[
                            if (status != SiteStatus.open)
                              const SizedBox(width: 8),
                            Text(
                              '$count',
                              style: TextStyle(
                                color: status.color,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${sites.length} sites',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The per-status tallies in display order — one list drives both the
  /// numbers and the bar, so a status can't appear in one and not the other.
  static List<(int, SiteStatus)> _tallies(StatusCounts counts) => [
    (counts.open, SiteStatus.open),
    (counts.blitz, SiteStatus.blitz),
    (counts.closed, SiteStatus.closed),
    (counts.cameraOnly, SiteStatus.cameraOnly),
    (counts.unknown, SiteStatus.unknown),
  ];

  Widget _statusBar(StatusCounts counts) {
    final total = counts.total;
    if (total == 0) {
      return Container(
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.border,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Row(
        children: [
          for (final (count, status) in _tallies(counts))
            if (count > 0)
              Expanded(
                flex: count,
                child: Container(height: 4, color: status.color),
              ),
        ],
      ),
    );
  }
}
