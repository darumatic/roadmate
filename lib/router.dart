import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/add_site/add_site_screen.dart';
import 'features/home/home_screen.dart';
import 'features/nearby/nearby_screen.dart';
import 'features/saved/saved_screen.dart';
import 'features/state_detail/state_detail_screen.dart';
import 'widgets/app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/nearby', builder: (_, _) => const NearbyScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/saved', builder: (_, _) => const SavedScreen()),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/state/:code',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => StateDetailScreen(
        state: stateFromRouteCode(state.pathParameters['code']),
      ),
    ),
    GoRoute(
      path: '/add',
      parentNavigatorKey: _rootKey,
      builder: (_, _) => const AddSiteScreen(),
    ),
  ],
);
