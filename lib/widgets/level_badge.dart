import 'package:flutter/material.dart';

import '../services/participation_logic.dart';
import '../theme/app_theme.dart';

/// Icon for each ladder rung — kept here (not in participation_logic.dart)
/// so the logic file stays pure Dart. Unknown rungs fall back to the trophy.
IconData levelIcon(ParticipationLevel level) {
  return switch (level.index1) {
    1 => Icons.flag_outlined,
    2 => Icons.local_shipping_outlined,
    3 => Icons.local_shipping,
    4 => Icons.military_tech,
    5 => Icons.workspace_premium,
    _ => Icons.emoji_events,
  };
}

/// The level icon in a tinted rounded square, optionally with the title —
/// the one visual for a participation level, reused by the account panel,
/// report rows and the Achievements page.
class LevelBadge extends StatelessWidget {
  const LevelBadge({
    super.key,
    required this.level,
    this.showTitle = false,
    this.size = 34,
  });

  final ParticipationLevel level;
  final bool showTitle;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(levelIcon(level), color: AppTheme.accent, size: size * 0.58),
    );
    if (!showTitle) return badge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(width: 8),
        Text(
          level.title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// The small level marker beside a reporter's name on report rows. Icon only
/// (the row is 12px text — a title would shout); the tooltip and semantics
/// carry the rung's name. Renders nothing when the report has no stored
/// level (older clients) or one this build doesn't know.
class ReporterLevelIcon extends StatelessWidget {
  const ReporterLevelIcon({super.key, required this.reporterLevel});

  final int? reporterLevel;

  @override
  Widget build(BuildContext context) {
    final level = levelForIndex(reporterLevel);
    if (level == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: level.title,
        child: Icon(
          levelIcon(level),
          size: 14,
          color: AppTheme.accent,
          semanticLabel: level.title,
        ),
      ),
    );
  }
}
