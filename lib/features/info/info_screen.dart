import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../widgets/account_panel.dart';
import '../../widgets/app_version_label.dart';

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});

  static const shareUrl = 'https://roadmate.club';
  static const usefulLinksUrl = 'https://roadmate.club/useful-links.html';
  static const shareText =
      'RoadMate AU\n'
      'Know before you roll.\n'
      'Live community reports for heavy-vehicle inspection sites.\n\n'
      '$shareUrl';

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
                    icon: Icons.link_rounded,
                    title: 'Useful Links',
                    body:
                        'Official road-access & live-traffic sites — NHVR and each state.',
                    onTap: () => _openUsefulLinks(context),
                  ),
                  const SizedBox(height: 12),
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
                        'RoadMate AU is built by truck drivers, for truck drivers. It brings together essential tools to help make every trip easier, safer, and more efficient.

                        With RoadMate AU, you can:

                        View community-reported NHVR inspection site activity.
                        Find nearby inspection sites and save your favourites.
                        Submit new inspection sites to help grow the community database.
                        Use the built-in GPS Speedometer with average speed tracking, speed limit checking, custom maximum speed warnings, and a trip logger to record your journeys.

                        All inspection site information is contributed by the trucking community and is provided as a guide only. Conditions and site activity may change at any time, so always drive safely, obey road rules, and follow the directions of authorised officers.

                        Developed by Leandro Pervieux and Adrian Deccico.

                        RoadMate AU – Built by truckies, for truckies. Helping keep Australia's roads connected, informed, and safer.',
                  ),
                  SizedBox(height: 12),
                  _ShareBlock(),
                  SizedBox(height: 12),
                  AccountPanel(),
                  SizedBox(height: 12),
                  _InfoBlock(
                    icon: Icons.support_agent_rounded,
                    title: 'Support',
                    body: 'For support, please email: info@roadmate.club',
                  ),
                  SizedBox(height: 16),
                  AppVersionLabel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUsefulLinks(BuildContext context) async {
    try {
      // In-app browser (Custom Tabs on Android / SafariViewController on iOS)
      // so the page opens within the app rather than the external browser.
      final ok = await launchUrl(
        Uri.parse(usefulLinksUrl),
        mode: LaunchMode.inAppBrowserView,
      );
      if (ok) return;
    } catch (_) {
      // Fall through to clipboard fallback.
    }

    await Clipboard.setData(const ClipboardData(text: usefulLinksUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied — open it in your browser')),
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

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.title,
    required this.body,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;

  /// When set, the card becomes tappable and shows a trailing "open externally"
  /// affordance.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
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
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.open_in_new_rounded,
              color: AppTheme.accent,
              size: 18,
            ),
          ],
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }
}
