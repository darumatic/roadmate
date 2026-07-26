import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/site.dart';
import '../../services/providers.dart';
import '../../services/site_stats.dart';
import '../../theme/app_theme.dart';
import '../proximity/proximity_controller.dart';
import '../speedometer/speedometer_panel.dart';
import 'closest_sites_card.dart';
import '../speedometer/trip_controller.dart';
import '../speedometer/trip_logger_card.dart';
import '../../widgets/back_to_top.dart';
import '../../widgets/blitz_banner.dart';
import '../../widgets/load_error.dart';
import '../../widgets/state_card.dart';
import '../../widgets/status_labels.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(sitesProvider);

    return Scaffold(
      body: SafeArea(
        child: sitesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const LoadError(),
          data: (sites) {
            final byState = groupByState(sites);
            final recent = recentlyActive(sites);
            final states = visibleStates;
            return BackToTop(
              builder: (context, scrollController) => RefreshIndicator(
                onRefresh: () => refreshSiteData(ref),
                child: CustomScrollView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _topSection(context, sites, blitzSites(sites)),
                    ),
                    if (recent.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _recentlyActive(context, recent),
                      ),
                    SliverToBoxAdapter(child: _browseHeader(context)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 260,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.95,
                            ),
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final state = states[i];
                          return StateCard(
                            state: state,
                            sites: byState[state] ?? const [],
                            onTap: () => context.go('/state/${state.code}'),
                          );
                        }, childCount: states.length),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _topSection(BuildContext context, List<Site> sites, List<Site> blitz) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.5),
                  ),
                ),
                child: const Icon(
                  Icons.local_shipping,
                  color: AppTheme.accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'RoadMate - Know before you roll',
                    maxLines: 1,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const _ProximityToggle(),
              const _SoundToggle(),
            ],
          ),
          const SizedBox(height: 12),
          const SpeedometerPanel(),
          const SizedBox(height: 20),
          BlitzBanner(blitzSites: blitz),
          // Issue #7: the two closest sites live where the stats bar was.
          ClosestSitesCard(sites: sites),
          const SizedBox(height: 24),
          const TripLoggerCard(),
        ],
      ),
    );
  }

  Widget _browseHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          const Text(
            'Browse by State',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textPrimary,
              side: const BorderSide(color: AppTheme.border),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('Add Site'),
            onPressed: () => context.go('/add'),
          ),
        ],
      ),
    );
  }

  Widget _recentlyActive(BuildContext context, List<Site> recent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recently Active',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final s = recent[i];
                return GestureDetector(
                  onTap: () =>
                      context.go('/state/${s.state.code}?site=${s.id}'),
                  child: Container(
                    width: 200,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: s.currentStatus.color.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          s.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: s.currentStatus.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  statusDisplayLabel(s.currentStatus),
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: s.currentStatus.color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _relativeTime(s.lastReportAt!),
                                textAlign: TextAlign.end,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              s.state.code,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Beside the speaker: turns the site-approach prompt on/off. Enabled by
/// default; the choice persists on device.
class _ProximityToggle extends ConsumerWidget {
  const _ProximityToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(proximityEnabledProvider);
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(
        enabled ? Icons.near_me : Icons.near_me_disabled,
        color: enabled ? AppTheme.textPrimary : AppTheme.textSecondary,
      ),
      tooltip: enabled ? 'Turn off site alerts' : 'Turn on site alerts',
      onPressed: ref.read(proximityEnabledProvider.notifier).toggle,
    );
  }
}

/// Speaker icon at the top right (issue #22): mutes/unmutes the over-limit
/// alarm. Enabled by default; the choice persists on device.
class _SoundToggle extends ConsumerWidget {
  const _SoundToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(soundEnabledProvider);
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(
        enabled ? Icons.volume_up : Icons.volume_off,
        color: enabled ? AppTheme.textPrimary : AppTheme.textSecondary,
      ),
      tooltip: enabled ? 'Mute alerts' : 'Unmute alerts',
      onPressed: ref.read(soundEnabledProvider.notifier).toggle,
    );
  }
}

String _relativeTime(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
