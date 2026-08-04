import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/participation_logic.dart';
import '../../services/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/level_badge.dart';

/// Achievements: the user's participation level, progress to the next rung,
/// and the badge grid (locked/unlocked). Everything on this page derives
/// client-side from the two counters in the stats doc — see
/// `participation_logic.dart`.
class AchievementsPage extends ConsumerWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats =
        ref.watch(myParticipationProvider).value ?? const ParticipationStats();
    final level = levelForPoints(stats.points);
    final next = nextLevelForPoints(stats.points);
    final unlocked = badgesFor(stats).map((b) => b.id).toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            // Level header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      LevelBadge(level: level, size: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              level.title,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${formatPoints(stats.points)} pts',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progressToNextLevel(stats.points),
                      minHeight: 6,
                      backgroundColor: AppTheme.border,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    next == null
                        ? 'Top of the ladder — thanks for keeping the '
                              'community rolling!'
                        : '${formatPoints(next.minPoints - stats.points)} pts '
                              'to ${next.title}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // How points are earned
            Text(
              'Status votes earn $kPointsPerVote pts · activity reports earn '
              '$kPointsPerReport pts. Posting works within 3 km of a site.',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Badges',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                for (final badge in kBadges)
                  _BadgeTile(
                    badge: badge,
                    unlocked: unlocked.contains(badge.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.unlocked});

  final ParticipationBadge badge;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final tint = unlocked ? AppTheme.accent : AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked
            ? AppTheme.accent.withValues(alpha: 0.10)
            : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked
              ? AppTheme.accent.withValues(alpha: 0.35)
              : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            unlocked ? Icons.emoji_events : Icons.lock_outline_rounded,
            color: tint,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unlocked ? AppTheme.textPrimary : tint,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  badge.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
