import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/min_version.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_title.dart';

/// Info tab (issue #12 redesign): a hub of link rows, each opening a native
/// sub-page within the tab — Useful Links, About, Credits, Support the app,
/// Contact, Share, Disclaimer.
class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key, this.isWeb = kIsWeb, this.platform});

  /// Overridable in widget tests (which always run on the VM).
  final bool isWeb;
  final TargetPlatform? platform;

  static const shareUrl = 'https://roadmate.club';
  static const buyMeACoffeeUrl = 'https://buymeacoffee.com/darumatic';
  static const supportEmail = 'info@roadmate.club';
  static const shareText =
      'RoadMate AU\n'
      'Know before you roll.\n'
      'Live community reports for heavy-vehicle inspection sites.\n\n'
      'Web: $shareUrl\n'
      'iPhone: $kAppStoreUrl\n'
      'Android: $kPlayStoreUrl';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverScreenTitle('Info'),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList.list(
                children: [
                  for (final row in _hubRows(context)) ...[
                    row,
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _hubRows(BuildContext context) => [
    InfoLinkRow(
      icon: Icons.timer_outlined,
      title: 'Camera Times',
      subtitle: 'Expected times between average-speed cameras',
      onTap: () => context.go('/info/cameras'),
    ),
    InfoLinkRow(
      icon: Icons.link_rounded,
      title: 'Useful Links',
      subtitle: 'Official road-access & live-traffic sites',
      onTap: () => context.go('/info/links'),
    ),
    InfoLinkRow(
      icon: Icons.info_outline_rounded,
      title: 'About RoadMate',
      subtitle: 'What the app is and how it works',
      onTap: () => context.go('/info/about'),
    ),
    InfoLinkRow(
      icon: Icons.group_outlined,
      title: 'Credits',
      subtitle: 'The people behind RoadMate',
      onTap: () => context.go('/info/credits'),
    ),
    if (showDonationLink(
      isWeb: isWeb,
      platform: platform ?? defaultTargetPlatform,
    ))
      InfoLinkRow(
        icon: Icons.local_cafe_outlined,
        title: 'Support the app',
        subtitle: 'Shout the devs a coffee',
        onTap: () => context.go('/info/support'),
      ),
    InfoLinkRow(
      icon: Icons.support_agent_rounded,
      title: 'Contact / Support',
      subtitle: supportEmail,
      onTap: () => context.go('/info/contact'),
    ),
    InfoLinkRow(
      icon: Icons.ios_share_rounded,
      title: 'Share RoadMate',
      subtitle: 'Invite another driver',
      onTap: () => context.go('/info/share'),
    ),
    InfoLinkRow(
      icon: Icons.warning_amber_rounded,
      title: 'Disclaimer',
      subtitle: 'Use as a heads-up only',
      onTap: () => context.go('/info/disclaimer'),
    ),
  ];
}

/// Tappable hub/link row: accent icon square, title, subtitle, trailing icon.
class InfoLinkRow extends StatelessWidget {
  const InfoLinkRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailing = Icons.chevron_right_rounded,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
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
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(trailing, color: AppTheme.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sub-page scaffold: back row with an "Info" kicker, big title, content.
class InfoSubPage extends StatelessWidget {
  const InfoSubPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go('/info'),
                    ),
                    const Text(
                      'Info',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  title,
                  style: const TextStyle(
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
                  for (final child in children) ...[
                    child,
                    const SizedBox(height: 12),
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

/// Opens [url] in the in-app browser, falling back to copying the link.
Future<void> openExternal(BuildContext context, String url) async {
  try {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.inAppBrowserView,
    );
    if (ok) return;
  } catch (_) {
    // Fall through to clipboard fallback.
  }
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Link copied — open it in your browser')),
  );
}

// ---------------------------------------------------------------------------
// Sub-pages
// ---------------------------------------------------------------------------

class UsefulLinksPage extends StatelessWidget {
  const UsefulLinksPage({super.key});

  /// Official road-access and live-traffic sites (same set as the hosted
  /// useful-links.html page).
  static const links = <(String, String, String)>[
    (
      'NHVR — Road Access',
      'nhvr.gov.au',
      'https://www.nhvr.gov.au/road-access',
    ),
    ('Live Traffic NSW', 'livetraffic.com', 'https://www.livetraffic.com/'),
    (
      'VicTraffic',
      'traffic.transport.vic.gov.au',
      'https://traffic.transport.vic.gov.au/',
    ),
    ('QLDTraffic', 'qldtraffic.qld.gov.au', 'https://qldtraffic.qld.gov.au/'),
    ('Traffic SA', 'traffic.sa.gov.au', 'https://www.traffic.sa.gov.au/'),
    (
      'Main Roads WA',
      'mainroads.wa.gov.au/travelmap',
      'https://www.mainroads.wa.gov.au/travelmap/',
    ),
    (
      'NT Road Report',
      'roadreport.nt.gov.au',
      'https://roadreport.nt.gov.au/road-map',
    ),
    ('TasALERT', 'tasalert.com', 'https://www.tasalert.com/'),
  ];

  @override
  Widget build(BuildContext context) {
    return InfoSubPage(
      title: 'Useful Links',
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, right: 4, bottom: 2),
          child: Text(
            'Official road-access & live-traffic sites — NHVR and each state.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
        for (final (title, subtitle, url) in links)
          InfoLinkRow(
            icon: Icons.public,
            title: title,
            subtitle: subtitle,
            trailing: Icons.open_in_new_rounded,
            onTap: () => openExternal(context, url),
          ),
      ],
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const InfoSubPage(
      title: 'About RoadMate',
      children: [
        InfoBlock(
          icon: Icons.info_outline_rounded,
          title: 'Built by truck drivers, for truck drivers',
          body:
              'RoadMate AU brings together essential tools to help make every trip easier, safer, and more efficient.\n\n'
              'View community-reported NHVR inspection site activity. Find nearby inspection sites and save your favourites. '
              'Submit new inspection sites to help grow the community database. Use the built-in GPS Speedometer with average '
              'speed tracking, speed limit checking, custom maximum speed warnings, and a trip logger to record your journeys.',
        ),
        InfoBlock(
          icon: Icons.groups_outlined,
          title: 'Community-powered',
          body:
              'All inspection site information is contributed by the trucking community and is provided as a guide only. '
              "RoadMate AU – Built by truckies, for truckies. Helping keep Australia's roads connected, informed, and safer.",
        ),
      ],
    );
  }
}

class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoSubPage(
      title: 'Credits',
      children: [
        const _CreditCard(
          icon: Icons.local_shipping,
          kicker: 'ORIGINAL IDEA & DESIGN',
          name: 'Leandro Pervieux',
          line: 'Leo',
          italicLine: true,
        ),
        const _CreditCard(
          icon: Icons.code,
          kicker: 'LEAD DEVELOPER',
          name: 'Adrian Deccico',
        ),
        _CreditCard(
          icon: Icons.handshake_outlined,
          kicker: 'TECHNOLOGY PARTNER',
          name: 'Darumatic',
          line: 'darumatic.com',
          onLineTap: () => openExternal(context, 'https://darumatic.com'),
          image: const AssetImage('assets/images/darumatic-logo.png'),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Thanks to every driver who reports — RoadMate runs on you.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({
    required this.icon,
    required this.kicker,
    required this.name,
    this.line,
    this.italicLine = false,
    this.onLineTap,
    this.image,
  });

  final IconData icon;
  final String kicker;
  final String name;
  final String? line;
  final bool italicLine;
  final VoidCallback? onLineTap;
  final ImageProvider? image;

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
                    kicker,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (line != null) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onLineTap,
                      child: Text(
                        line!,
                        style: TextStyle(
                          color: onLineTap != null
                              ? AppTheme.accent
                              : AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: onLineTap != null
                              ? FontWeight.w700
                              : FontWeight.w400,
                          fontStyle: italicLine
                              ? FontStyle.italic
                              : FontStyle.normal,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (image != null) ...[
              const SizedBox(width: 8),
              ClipOval(
                child: Image(
                  image: image!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoSubPage(
      title: 'Support the app',
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.local_cafe_outlined,
                    color: AppTheme.accent,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Keep RoadMate rolling',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "RoadMate is free, ad-free and built after hours. If it's "
                  'saved you a surprise at the scales, you can shout the team '
                  'a coffee.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFDD00),
                      foregroundColor: const Color(0xFF0D0C22),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.local_cafe, size: 20),
                    label: const Text(
                      'Buy me a coffee',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () =>
                        openExternal(context, InfoScreen.buyMeACoffeeUrl),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Donations keep the servers running — the app stays free '
                  'for everyone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoSubPage(
      title: 'Contact / Support',
      children: [
        const InfoBlock(
          icon: Icons.support_agent_rounded,
          title: 'Support',
          body: 'For support, please email: ${InfoScreen.supportEmail}',
        ),
        InfoLinkRow(
          icon: Icons.bug_report_outlined,
          title: 'Report a problem',
          subtitle: 'Wrong site details, bugs, anything off',
          trailing: Icons.open_in_new_rounded,
          onTap: () =>
              openExternal(context, 'mailto:${InfoScreen.supportEmail}'),
        ),
      ],
    );
  }
}

class SharePage extends StatelessWidget {
  const SharePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const InfoSubPage(title: 'Share RoadMate', children: [ShareBlock()]);
  }
}

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const InfoSubPage(
      title: 'Disclaimer',
      children: [
        InfoBlock(
          icon: Icons.warning_amber_rounded,
          title: 'Use as a heads-up only',
          body:
              'RoadMate is community-reported, may be inaccurate or out of date, and is not official NHVR data. Always follow roadside signage, authorised directions, and official information.',
        ),
        InfoBlock(
          icon: Icons.location_off_outlined,
          title: 'Approximate locations',
          body:
              'Site locations are approximate (geocoded at town level). Conditions and site activity may change at any time, so always drive safely, obey road rules, and follow the directions of authorised officers.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared blocks
// ---------------------------------------------------------------------------

class ShareBlock extends StatelessWidget {
  const ShareBlock({super.key, this.isWeb = kIsWeb});

  /// Overridable in widget tests (which always run on the VM).
  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    final storeLinks = storeLinksFor(
      isWeb: isWeb,
      platform: defaultTargetPlatform,
    );
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
                    'Invite another driver',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Every extra driver makes the reports fresher for everyone.',
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
                  if (storeLinks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Get the app',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    for (final link in storeLinks) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accent,
                          side: const BorderSide(color: AppTheme.border),
                        ),
                        icon: Icon(
                          link.label == 'App Store'
                              ? Icons.apple
                              : Icons.android,
                          size: 18,
                        ),
                        label: Text(link.label),
                        onPressed: () => openExternal(context, link.url),
                      ),
                    ],
                  ],
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

/// Icon square + title + body card (read-only counterpart of [InfoLinkRow]).
class InfoBlock extends StatelessWidget {
  const InfoBlock({
    super.key,
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
