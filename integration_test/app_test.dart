import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:roadmate/app.dart';
import 'package:roadmate/router.dart';
import 'package:roadmate/services/location_source.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/startup_service.dart';
import 'package:roadmate/widgets/site_card.dart';

/// Deterministic web smoke suite driven by `scripts/verify_web.sh` (and the
/// nightly-visual CI workflow) in real headless Chrome. Firebase is never
/// initialized, so `siteRepositoryProvider` falls back to the bundled
/// `LocalSeedSiteRepository` — a red run always means a code regression, not
/// changed live data. Screenshots land in build/integration_screenshots/.
class _DeniedLocationSource implements LocationSource {
  @override
  Future<bool> ensurePermission() async => false;

  @override
  Stream<Position> positions() => const Stream.empty();

  @override
  Future<Position?> currentPosition() async => null;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('web smoke: home, info hub, share store buttons, state detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStartupProvider.overrideWith((ref) => Future.value()),
          locationSourceProvider.overrideWithValue(_DeniedLocationSource()),
        ],
        child: const RoadMateApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Home: header + bottom nav render.
    expect(find.text('RoadMate Australia'), findsOneWidget);
    expect(find.text('Nearby'), findsOneWidget);
    await binding.takeScreenshot('01-home');

    // Info hub.
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(find.text('Share RoadMate'), findsOneWidget);
    expect(find.text('Disclaimer'), findsOneWidget);
    await binding.takeScreenshot('02-info-hub');

    // Share page: on real web (kIsWeb) both store buttons must show.
    await tester.ensureVisible(find.text('Share RoadMate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share RoadMate'));
    await tester.pumpAndSettle();
    expect(find.text('Invite another driver'), findsOneWidget);
    expect(find.text('Get the app'), findsOneWidget);
    expect(find.text('Google Play'), findsOneWidget);
    expect(find.text('App Store'), findsOneWidget);
    await binding.takeScreenshot('03-share');

    // State detail: seed sites render (grid tile position varies with the
    // browser window, so navigate by route; the list is lazy, so assert the
    // header count + rendered cards rather than one specific site name).
    appRouter.go('/state/NSW');
    await tester.pumpAndSettle();
    expect(find.textContaining('New South Wales —'), findsOneWidget);
    expect(find.byType(SiteCard), findsWidgets);
    // Every card's address row is an "Open in Maps" tap target, with the
    // directions icon leading the address on the left rather than trailing.
    expect(
      find.byTooltip('Open in Maps'),
      findsNWidgets(find.byType(SiteCard).evaluate().length),
    );
    final firstCard = find.byType(SiteCard).first;
    final mapsIcon = find
        .descendant(
          of: firstCard,
          matching: find.byIcon(Icons.directions_outlined),
        )
        .first;
    final cardBox = tester.getRect(firstCard);
    expect(tester.getCenter(mapsIcon).dx, lessThan(cardBox.center.dx));
    await binding.takeScreenshot('04-state-nsw');
  });
}
