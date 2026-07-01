import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/account_panel.dart';

class InfoScreen extends ConsumerWidget {
  const InfoScreen({super.key});

  static const shareUrl = 'https://roadmate.club';
  static const shareText =
      'RoadMate AU\n'
      'Know before you roll.\n'
      'Live community reports for heavy-vehicle inspection sites.\n\n'
      '$shareUrl';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref.watch(currentUserRoleProvider).value == AppUserRole.admin;
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
                    icon: Icons.info_outline_rounded,
                    title: 'About RoadMate',
                    body:
                        'RoadMate AU helps Australian heavy-vehicle drivers share live inspection-site status. Built by Leandro Pervieux and Adrian Deccico.',
                  ),
                  SizedBox(height: 12),
                  _ShareBlock(),
                  const SizedBox(height: 12),
                  const AccountPanel(),
                  if (isAdmin) ...[
                    const SizedBox(height: 12),
                    const _AdminBlock(),
                  ],
                  const SizedBox(height: 12),
                  const _InfoBlock(
                    icon: Icons.support_agent_rounded,
                    title: 'Support',
                    body: 'For support, please email: info@roadmate.club',
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

class _ShareBlock extends StatelessWidget {
  const _ShareBlock();

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
              child: const Icon(
                Icons.ios_share_rounded,
                color: AppTheme.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Share RoadMate',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Invite another driver to RoadMate.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SelectableText(
                    InfoScreen.shareUrl,
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Share RoadMate'),
                    onPressed: () => _shareRoadMate(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareRoadMate(BuildContext context) async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      final result = await SharePlus.instance.share(
        ShareParams(
          title: 'RoadMate AU',
          subject: 'RoadMate AU',
          text: InfoScreen.shareText,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (result.status != ShareResultStatus.unavailable) return;
    } catch (_) {
      // Fall through to clipboard fallback.
    }

    await Clipboard.setData(const ClipboardData(text: InfoScreen.shareUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('RoadMate link copied')));
  }
}

class _AdminBlock extends StatelessWidget {
  const _AdminBlock();

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
              child: const Icon(
                Icons.shield_outlined,
                color: AppTheme.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Admin',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Review submitted sites and reports.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Open moderation'),
                    onPressed: () => context.push('/admin'),
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
  });

  final IconData icon;
  final String title;
  final String body;

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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
