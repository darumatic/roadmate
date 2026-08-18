import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import '../../widgets/screen_title.dart';
import '../../widgets/async_body.dart';
import '../../widgets/empty_state.dart';
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
        child: asyncBody(sitesAsync, (sites) {
          final favourites = sites
              .where((s) => favouriteIds.contains(s.id))
              .toList();
          return RefreshIndicator(
            onRefresh: () => refreshSiteData(ref),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverScreenTitle('Favourites'),
                if (favourites.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.star_border,
                      title: 'No favourites yet',
                      body: 'Tap the star on any site to keep it here.',
                    ),
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
        }),
      ),
    );
  }
}
