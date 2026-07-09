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
      bottomNavigationBar: ShellBottomBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

/// The nav bar + version footer. A separate widget so its inset handling is
/// unit-testable (issue #26).
class ShellBottomBar extends StatelessWidget {
  const ShellBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The nav bar's internal SafeArea normally absorbs the screen insets.
        // Strip the vertical ones so it lays out at its bare M3 height: bottom
        // is re-applied around the footer, which now sits lowest, and top must
        // go too — this context sits outside the Scaffold, so keeping it would
        // re-introduce the status-bar/notch inset as a huge empty band above
        // the icons (issue #26, seen on iOS).
        MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: _navigationBar(),
        ),
        ColoredBox(
          color: AppTheme.surface,
          child: SafeArea(
            top: false,
            child: const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: SizedBox(width: double.infinity, child: AppVersionLabel()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _navigationBar() {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
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
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'User',
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
