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
                Row(
                  children: [
                    Text(
                      '${counts.open}',
                      style: TextStyle(
                        color: SiteStatus.open.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (counts.blitz > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${counts.blitz}',
                        style: TextStyle(
                          color: SiteStatus.blitz.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (counts.closed > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${counts.closed}',
                        style: TextStyle(
                          color: SiteStatus.closed.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
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
          if (counts.open > 0)
            Expanded(
              flex: counts.open,
              child: Container(height: 4, color: SiteStatus.open.color),
            ),
          if (counts.blitz > 0)
            Expanded(
              flex: counts.blitz,
              child: Container(height: 4, color: SiteStatus.blitz.color),
            ),
          if (counts.closed > 0)
            Expanded(
              flex: counts.closed,
              child: Container(height: 4, color: SiteStatus.closed.color),
            ),
        ],
      ),
    );
  }
}
