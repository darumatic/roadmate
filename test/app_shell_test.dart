import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/theme/app_theme.dart';
import 'package:roadmate/widgets/app_shell.dart';

void main() {
  // Issue #26: on iOS the nav bar rendered ~60pt of empty space above the
  // icons. The bar is built outside the Scaffold, so its internal SafeArea saw
  // the raw screen insets — the notch/status-bar top padding must be stripped
  // along with the bottom one (which the version footer re-applies below).
  testWidgets('nav bar ignores screen insets and keeps its bare M3 height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          // iPhone-like insets: 59pt notch on top, 34pt home bar below.
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 59, bottom: 34),
            viewPadding: EdgeInsets.only(top: 59, bottom: 34),
          ),
          child: Scaffold(
            bottomNavigationBar: ShellBottomBar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Bare Material 3 NavigationBar height — no inset leaked inside.
    expect(tester.getSize(find.byType(NavigationBar)).height, 80);

    // All five destinations render.
    for (final label in ['Home', 'Nearby', 'Favourites', 'User', 'Info']) {
      expect(find.text(label), findsOneWidget);
    }
    // The version footer still honours the bottom inset (sits lowest).
    expect(find.textContaining('RoadMate v'), findsOneWidget);
  });
}
