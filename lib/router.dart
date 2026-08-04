import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'services/min_version.dart';

import 'features/admin/admin_screen.dart';
import 'features/add_site/add_site_screen.dart';
import 'features/home/home_screen.dart';
import 'features/info/camera_times_page.dart';
import 'features/info/info_screen.dart';
import 'features/nearby/nearby_screen.dart';
import 'features/favourites/favourites_screen.dart';
import 'features/state_detail/state_detail_screen.dart';
import 'features/user/achievements_page.dart';
import 'features/user/user_screen.dart';
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
            GoRoute(
              path: '/home',
              name: 'home',
              builder: (_, _) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/nearby',
              name: 'nearby',
              builder: (_, _) => const NearbyScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/favourites',
              name: 'favourites',
              builder: (_, _) => const FavouritesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/user',
              name: 'user',
              builder: (_, _) => const UserScreen(),
              routes: [
                GoRoute(
                  path: 'achievements',
                  builder: (_, _) => const AchievementsPage(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/info',
              name: 'info',
              builder: (_, _) => const InfoScreen(),
              routes: [
                GoRoute(
                  path: 'cameras',
                  builder: (_, _) => const CameraTimesPage(),
                  routes: [
                    GoRoute(
                      path: ':slug',
                      builder: (_, state) => CameraCorridorPage(
                        slug: state.pathParameters['slug']!,
                      ),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'links',
                  builder: (_, _) => const UsefulLinksPage(),
                ),
                GoRoute(path: 'about', builder: (_, _) => const AboutPage()),
                GoRoute(
                  path: 'credits',
                  builder: (_, _) => const CreditsPage(),
                ),
                GoRoute(
                  path: 'support',
                  // No donation page in the native iOS app (guideline 3.1.1),
                  // even via deep link.
                  redirect: (_, _) =>
                      showDonationLink(
                        isWeb: kIsWeb,
                        platform: defaultTargetPlatform,
                      )
                      ? null
                      : '/info',
                  builder: (_, _) => const SupportPage(),
                ),
                GoRoute(
                  path: 'contact',
                  builder: (_, _) => const ContactPage(),
                ),
                GoRoute(path: 'share', builder: (_, _) => const SharePage()),
                GoRoute(
                  path: 'disclaimer',
                  builder: (_, _) => const DisclaimerPage(),
                ),
              ],
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
        highlightSiteId: state.uri.queryParameters['site'],
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
    GoRoute(
      path: '/admin',
      name: 'admin',
      parentNavigatorKey: _rootKey,
      builder: (_, _) => const AdminScreen(),
    ),
  ],
);
