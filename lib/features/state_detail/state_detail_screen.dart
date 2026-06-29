import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../models/site.dart';
import '../../services/providers.dart';
import '../../services/site_stats.dart';
import '../../theme/app_theme.dart';
import '../../widgets/site_card.dart';

class StateDetailScreen extends ConsumerStatefulWidget {
  const StateDetailScreen({super.key, required this.state});

  final AusState state;

  @override
  ConsumerState<StateDetailScreen> createState() => _StateDetailScreenState();
}

class _StateDetailScreenState extends ConsumerState<StateDetailScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sitesAsync = ref.watch(sitesProvider);

    return Scaffold(
      body: SafeArea(
        child: sitesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (allSites) {
            final stateSites = allSites
                .where((s) => s.state == widget.state)
                .toList();
            final filtered = searchSites(stateSites, _query);
            return Column(
              children: [
                _topBar(context, stateSites.length),
                Expanded(
                  child: filtered.isEmpty
                      ? _empty(stateSites.isEmpty)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) => SiteCard(site: filtered[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => context.go('/add'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Site'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.state.code,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${widget.state.fullName} — $count sites',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search sites...',
                    prefixIcon: Icon(
                      Icons.search,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(bool noSitesYet) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          noSitesYet
              ? 'No sites listed for ${widget.state.fullName} yet.\nBe the first to add one.'
              : 'No sites match your search.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

/// Resolve a route `:code` param to an [AusState] for the router.
AusState stateFromRouteCode(String? code) => AusState.fromCode(code ?? 'NSW');

/// Exposed for tests: convenience accessor used by the screen.
List<Site> sitesForState(List<Site> all, AusState state) =>
    all.where((s) => s.state == state).toList();
