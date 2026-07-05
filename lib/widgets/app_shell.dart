import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import 'app_version_label.dart';

/// Bottom-navigation scaffold wrapping the Home / Nearby / Favourites tabs. Uses
/// go_router's [StatefulNavigationShell] so each tab keeps its own state. The
/// app version renders as a slim footer under the nav bar, on every tab.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The nav bar normally absorbs the bottom safe-area inset; strip it
          // here and re-apply it around the footer, which now sits lowest.
          MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: _navigationBar(),
          ),
          ColoredBox(
            color: AppTheme.surface,
            child: SafeArea(
              top: false,
              child: const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: AppVersionLabel(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navigationBar() {
    return NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (i) => navigationShell.goBranch(
        i,
        initialLocation: i == navigationShell.currentIndex,
      ),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.near_me_outlined),
          selectedIcon: Icon(Icons.near_me),
          label: 'Nearby',
        ),
        NavigationDestination(
          icon: Icon(Icons.star_border),
          selectedIcon: Icon(Icons.star),
          label: 'Favourites',
        ),
        NavigationDestination(
          icon: Icon(Icons.info_outline),
          selectedIcon: Icon(Icons.info),
          label: 'Info',
        ),
      ],
    );
  }
}
