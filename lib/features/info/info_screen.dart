import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  static const supportEmail = 'support@roadmate.club';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Info',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList.list(
                children: [
                  _InfoBlock(
                    icon: Icons.warning_amber_rounded,
                    title: 'Use as a heads-up only',
                    body:
                        'RoadMate is community-reported, may be inaccurate or out of date, and is not official NHVR data. Always follow roadside signage, authorised directions, and official information.',
                  ),
                  SizedBox(height: 12),
                  _InfoBlock(
                    icon: Icons.notes_rounded,
                    title: 'Report activity data',
                    body:
                        'Activity reports are saved to the selected site in Firestore with the note, anonymous device user ID, and timestamp. They refresh the site activity time and can support future moderation or review tools.',
                  ),
                  SizedBox(height: 12),
                  _InfoBlock(
                    icon: Icons.volunteer_activism_rounded,
                    title: 'Donations',
                    body:
                        'Donations are not enabled yet. A contribution link can be added here when RoadMate has a confirmed payment account.',
                  ),
                  SizedBox(height: 12),
                  _InfoBlock(
                    icon: Icons.support_agent_rounded,
                    title: 'Support',
                    body:
                        'For feedback, corrections, or support, email support@roadmate.club.',
                    selectableBody: supportEmail,
                  ),
                  SizedBox(height: 12),
                  _InfoBlock(
                    icon: Icons.info_outline_rounded,
                    title: 'About RoadMate',
                    body:
                        'RoadMate AU helps Australian heavy-vehicle drivers share live inspection-site status. Built for Leandro and the RoadMate community.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.title,
    required this.body,
    this.selectableBody,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? selectableBody;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  if (selectableBody != null) ...[
                    const SizedBox(height: 10),
                    SelectableText(
                      selectableBody!,
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
