import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/trip.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/account_panel.dart';
import '../info/info_screen.dart';
import '../speedometer/trip_controller.dart';
import '../speedometer/trip_tile.dart';

/// "User" tab (issue #12 redesign, replaces the Trips tab): account sign-in,
/// help & support link, admin moderation entry, and My Trips — every saved
/// trip with per-trip delete and Clear all. The Home Trip Logger keeps
/// showing the 3 newest.
class UserScreen extends ConsumerWidget {
  const UserScreen({super.key});

  static const supportPageUrl = 'https://roadmate.club/support.html';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips =
        ref.watch(tripHistoryProvider).asData?.value ?? const <Trip>[];
    final isAnonymous =
        ref.watch(currentUserRoleProvider).value == AppUserRole.anonymous;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'User',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
              sliver: SliverToBoxAdapter(child: AccountPanel()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: InfoLinkRow(
                  icon: Icons.help_outline_rounded,
                  title: 'Help & Support',
                  subtitle: 'roadmate.club/support.html',
                  trailing: Icons.open_in_new_rounded,
                  onTap: () => openExternal(context, supportPageUrl),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.route, size: 18, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    const Text(
                      'My Trips',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (trips.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Clear all'),
                        onPressed: () => confirmClearAllTrips(context, ref),
                      ),
                  ],
                ),
              ),
            ),
            if (trips.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyTrips(),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '${trips.length} saved trip${trips.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                sliver: SliverList.separated(
                  itemCount: trips.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => TripTile(
                    trip: trips[i],
                    onDelete: () =>
                        confirmDeleteTrip(context, ref, trips[i].id),
                  ),
                ),
              ),
              if (isAnonymous)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(32, 4, 32, 24),
                    child: Text(
                      'Trips are stored on this device. Sign in to keep them.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 44, color: AppTheme.textSecondary),
            SizedBox(height: 12),
            Text(
              'No trips yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              'Start one from the Home speedometer to log it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
