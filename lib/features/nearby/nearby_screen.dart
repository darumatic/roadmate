import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/geo.dart';
import '../../services/location_source.dart';
import '../../services/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_title.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/load_error.dart';
import '../../widgets/site_card.dart';

/// Resolves the device location (or null if unavailable/denied).
final currentPositionProvider = FutureProvider<Position?>((ref) async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.deniedForever) {
    return null;
  }
  // Web: accept a recent cached fix (returns instantly) instead of blocking
  // on a cold one — see quickFixLocationSettings.
  return Geolocator.getCurrentPosition(
    locationSettings: quickFixLocationSettings(),
  );
});

/// Nearby tab: sites ranked by distance from the user. Requires sites to have
/// coordinates (geocoded) and location permission.
class NearbyScreen extends ConsumerWidget {
  const NearbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posAsync = ref.watch(currentPositionProvider);
    final sitesAsync = ref.watch(sitesProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refreshNearby(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverScreenTitle('Nearby'),
              ...switch ((posAsync, sitesAsync)) {
                (AsyncLoading(), _) || (_, AsyncLoading()) => [
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                (AsyncData(value: final pos), AsyncData(value: final sites))
                    when pos != null =>
                  _results(
                    context,
                    nearestSites(sites, pos.latitude, pos.longitude),
                  ),
                (AsyncData(value: null), _) => [
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.location_off_outlined,
                      title: 'Location unavailable',
                      body:
                          'Enable location access to see sites ranked by distance.',
                    ),
                  ),
                ],
                _ => [
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: LoadError(),
                  ),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _results(BuildContext context, List<SiteDistance> ranked) {
    if (ranked.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.explore_off_outlined,
            title: 'No located sites yet',
            body:
                'Sites need map coordinates to appear here. Coordinates are being added.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        sliver: SliverList.separated(
          itemCount: ranked.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final r = ranked[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    kmAwayLabel(r.km),
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SiteCard(site: r.site),
              ],
            );
          },
        ),
      ),
    ];
  }
}

Future<void> _refreshNearby(WidgetRef ref) async {
  // The device position genuinely goes stale, so a pull re-reads it; the
  // Firestore streams are live and handled by refreshSiteData's error-only
  // restart rule.
  ref.invalidate(currentPositionProvider);
  await Future.wait([
    ref.read(currentPositionProvider.future),
    refreshSiteData(ref),
  ]);
}
