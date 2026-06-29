import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../services/site_stats.dart';
import '../theme/app_theme.dart';

/// The Open / Blitz / Closed summary row at the top of Home. Each tile is
/// tappable and acts as a status filter.
class StatsBar extends StatelessWidget {
  const StatsBar({
    super.key,
    required this.counts,
    this.selected,
    this.onSelect,
  });

  final StatusCounts counts;
  final SiteStatus? selected;
  final ValueChanged<SiteStatus?>? onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _tile(SiteStatus.open, counts.open),
        const SizedBox(width: 10),
        _tile(SiteStatus.blitz, counts.blitz),
        const SizedBox(width: 10),
        _tile(SiteStatus.closed, counts.closed),
      ],
    );
  }

  Widget _tile(SiteStatus status, int count) {
    final isSelected = selected == status;
    return Expanded(
      child: GestureDetector(
        onTap: onSelect == null
            ? null
            : () => onSelect!(isSelected ? null : status),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          decoration: BoxDecoration(
            color: status.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: status.color.withValues(alpha: isSelected ? 1 : 0.35),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: status.color,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: status.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status.label.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
