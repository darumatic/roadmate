import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:roadmate/app.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/router.dart';
import 'package:roadmate/services/location_source.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/startup_service.dart';
import 'package:roadmate/services/username_store.dart';
import 'package:roadmate/widgets/site_card.dart';
import 'package:roadmate/widgets/status_badge.dart';

/// Deterministic web smoke suite driven by `scripts/verify_web.sh` (and the
/// Visual Verification gate of every Web Release) in real headless Chrome.
/// Firebase is never
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

  testWidgets('web smoke: home, info hub, share store buttons, state detail, '
      'Camera Only / BGD press, activity is not a status', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStartupProvider.overrideWith((ref) => Future.value()),
          locationSourceProvider.overrideWithValue(_DeniedLocationSource()),
          // A driver who already picked a road name, so posting goes straight
          // through instead of opening the name picker.
          usernameStoreProvider.overrideWithValue(
            MemoryUsernameStore(
              initialProfile: const UserProfile(
                isAnonymous: true,
                username: 'Smoke Test',
              ),
            ),
          ),
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
    // Cards are addressed by site id from here on: the list is lazy, so a
    // positional finder quietly starts meaning another card once scrolling
    // disposes the ones above it.
    Finder cardOf(String id) =>
        find.byWidgetPredicate((w) => w is SiteCard && w.site.id == id);
    String idAt(int index) =>
        tester.widget<SiteCard>(find.byType(SiteCard).at(index)).site.id;
    final firstId = idAt(0);
    final queueId = idAt(1);
    final firstCard = cardOf(firstId);
    final mapsIcon = find
        .descendant(
          of: firstCard,
          matching: find.byIcon(Icons.directions_outlined),
        )
        .first;
    final cardBox = tester.getRect(firstCard);
    expect(tester.getCenter(mapsIcon).dx, lessThan(cardBox.center.dx));
    await binding.takeScreenshot('04-state-nsw');

    // The fourth status (issue #48): every card carries the blue button, under
    // the row of three and directly above Report activity.
    final cameraButtons = find.byKey(cameraOnlyVoteKey);
    expect(
      cameraButtons,
      findsNWidgets(find.byType(SiteCard).evaluate().length),
    );
    final cameraButton = find.descendant(
      of: firstCard,
      matching: cameraButtons,
    );
    Finder inFirstCard(String text) =>
        find.descendant(of: firstCard, matching: find.text(text));
    expect(
      tester.getRect(cameraButton).top,
      greaterThan(tester.getRect(inFirstCard('Blitz')).bottom),
    );
    expect(
      tester.getRect(cameraButton).bottom,
      lessThan(tester.getRect(inFirstCard('Report activity')).top),
    );

    // Pressing it is the whole pipeline in one go, safely in memory: the
    // press is stored as a plain 'Camera Only' activity report (no status is
    // ever written), the site list re-derives the status from the reports
    // stream, and the card turns — badge blue, button lit.
    StatusBadge badgeOf(Finder card) => tester.widget<StatusBadge>(
      find.descendant(of: card, matching: find.byType(StatusBadge)),
    );
    expect(badgeOf(firstCard).status, SiteStatus.unknown);
    await tester.ensureVisible(cameraButton);
    await tester.pumpAndSettle();
    await tester.tap(cameraButton);
    await tester.pumpAndSettle();

    expect(badgeOf(firstCard).status, SiteStatus.cameraOnly);
    // It is a status, so — like Open, Blitz and Closed — it lights the button
    // and adds NO row under Recent reports (issue #52); "reported just now"
    // is what says when.
    expect(
      find.descendant(of: firstCard, matching: find.text('Recent reports')),
      findsNothing,
    );
    expect(
      find.descendant(of: firstCard, matching: find.text('Camera Only')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: firstCard,
        matching: find.textContaining('reported '),
      ),
      findsOneWidget,
    );
    expect(find.text('Reported Camera Only / BGD — thanks!'), findsOneWidget);
    await binding.takeScreenshot('05-camera-only');

    // Issue #49: an activity report is not a status report. Filing "Long
    // queue" on a site nobody has voted on touches its lastReportAt — which
    // under the stored rule made it display its stored status, Open/Working,
    // as if someone had just said so. It must stay Unknown, while "reported
    // just now" and the Recent reports row still show the report.
    final queueCard = cardOf(queueId);
    expect(badgeOf(queueCard).status, SiteStatus.unknown);
    final reportButton = find.descendant(
      of: queueCard,
      matching: find.text('Report activity'),
    );
    await tester.ensureVisible(reportButton);
    await tester.pumpAndSettle();
    await tester.tap(reportButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit')); // "Long queue" is preselected
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: queueCard, matching: find.text('Long queue')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: queueCard,
        matching: find.textContaining('reported '),
      ),
      findsOneWidget,
    );
    expect(badgeOf(queueCard).status, SiteStatus.unknown);

    // The same, from the list every screen consumes — the first card may have
    // scrolled out of the lazy list by now, its site has not.
    final shown = {
      for (final site in ProviderScope.containerOf(
        tester.element(queueCard),
      ).read(sitesProvider).value!)
        site.id: site,
    };
    expect(shown[queueId]!.currentStatus, SiteStatus.unknown);
    expect(shown[queueId]!.lastReportAt, isNotNull);
    // ...while Camera Only / BGD, which IS a status, still stands.
    expect(shown[firstId]!.currentStatus, SiteStatus.cameraOnly);
    await binding.takeScreenshot('06-queue-is-not-a-status');
  });
}
