import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/geo.dart';
import '../../services/providers.dart';
import '../../theme/app_theme.dart';
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
  return Geolocator.getCurrentPosition();
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
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Nearby',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
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
                    child: _Message(
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
                    child: _Message(
                      icon: Icons.error_outline,
                      title: 'Something went wrong',
                      body: 'Could not determine nearby sites.',
                    ),
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
          child: _Message(
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
                    '${r.km.toStringAsFixed(r.km < 10 ? 1 : 0)} km away',
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
  ref.invalidate(currentPositionProvider);
  ref.invalidate(sitesProvider);
  await Future.wait([
    ref.read(currentPositionProvider.future),
    ref.read(sitesProvider.future),
  ]);
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
