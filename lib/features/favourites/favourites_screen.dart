import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/load_error.dart';
import '../../widgets/site_card.dart';

/// Lists the sites the user has starred. Favourite IDs sync via the anonymous uid.
class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(sitesProvider);
    final favouriteIds = ref.watch(favouriteSiteIdsProvider).value ?? const {};

    return Scaffold(
      body: SafeArea(
        child: sitesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const LoadError(),
          data: (sites) {
            final favourites = sites
                .where((s) => favouriteIds.contains(s.id))
                .toList();
            return RefreshIndicator(
              onRefresh: () => _refreshFavourites(ref),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        'Favourites',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (favourites.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyFavourites(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      sliver: SliverList.separated(
                        itemCount: favourites.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => SiteCard(site: favourites[i]),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

Future<void> _refreshFavourites(WidgetRef ref) async {
  ref.invalidate(sitesProvider);
  ref.invalidate(favouriteSiteIdsProvider);
  await Future.wait([
    ref.read(sitesProvider.future),
    ref.read(favouriteSiteIdsProvider.future),
  ]);
}

class _EmptyFavourites extends StatelessWidget {
  const _EmptyFavourites();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border, size: 48, color: AppTheme.textSecondary),
            SizedBox(height: 12),
            Text(
              'No favourites yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Tap the star on any site to keep it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
