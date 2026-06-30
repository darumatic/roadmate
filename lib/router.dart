import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';

import 'features/add_site/add_site_screen.dart';
import 'features/home/home_screen.dart';
import 'features/info/info_screen.dart';
import 'features/nearby/nearby_screen.dart';
import 'features/favourites/favourites_screen.dart';
import 'features/state_detail/state_detail_screen.dart';
import 'widgets/app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

List<NavigatorObserver> _analyticsObservers() {
  if (Firebase.apps.isEmpty) return const [];
  return [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)];
}

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/home',
  observers: _analyticsObservers(),
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          observers: _analyticsObservers(),
          routes: [
            GoRoute(
              path: '/home',
              name: 'home',
              builder: (_, _) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          observers: _analyticsObservers(),
          routes: [
            GoRoute(
              path: '/nearby',
              name: 'nearby',
              builder: (_, _) => const NearbyScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          observers: _analyticsObservers(),
          routes: [
            GoRoute(
              path: '/favourites',
              name: 'favourites',
              builder: (_, _) => const FavouritesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          observers: _analyticsObservers(),
          routes: [
            GoRoute(
              path: '/info',
              name: 'info',
              builder: (_, _) => const InfoScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/state/:code',
      name: 'state',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => StateDetailScreen(
        state: stateFromRouteCode(state.pathParameters['code']),
      ),
    ),
    GoRoute(
      path: '/add',
      name: 'add',
      parentNavigatorKey: _rootKey,
      builder: (_, state) => AddSiteScreen(
        initialState: stateFromRouteCode(state.uri.queryParameters['state']),
      ),
    ),
  ],
);
