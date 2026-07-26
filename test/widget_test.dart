import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/app.dart';
import 'package:roadmate/features/admin/admin_screen.dart';
import 'package:roadmate/features/info/info_screen.dart';
import 'package:roadmate/features/home/home_screen.dart';
import 'package:roadmate/models/admin_report.dart';
import 'package:roadmate/router.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/auth_service.dart';
import 'package:roadmate/services/min_version.dart';
import 'package:roadmate/services/site_repository.dart';
import 'package:roadmate/services/site_stats.dart';
import 'package:roadmate/services/startup_service.dart';
import 'package:roadmate/version.dart';
import 'package:roadmate/widgets/account_panel.dart';
import 'package:roadmate/widgets/load_error.dart';
import 'package:roadmate/widgets/state_card.dart';
import 'package:roadmate/widgets/status_badge.dart';

class FakeSiteRepository implements SiteRepository {
  FakeSiteRepository(this.sites);

  final List<Site> sites;

  @override
  Stream<List<Site>> watchSites() => Stream.value(sites);

  @override
  Stream<List<SiteReport>> watchAllRecentReports() => Stream.value(const []);

  @override
  Future<void> vote(String siteId, SiteStatus status) async {}

  @override
  Future<void> report(
    String siteId,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  }) async {}

  @override
  Future<void> addSite(Site site, {bool approved = false}) async {}

  @override
  Stream<Set<String>> watchFavourites() => Stream.value(const {});

  @override
  Future<void> toggleFavourite(String siteId) async {}
}

void main() {
  testWidgets('RoadMateApp shows startup loading while initializing', (
    tester,
  ) async {
    final startup = Completer<void>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStartupProvider.overrideWith((ref) => startup.future)],
        child: const RoadMateApp(),
      ),
    );

    expect(find.text('RoadMate AU'), findsOneWidget);
    expect(find.text('Know before you roll.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('StatusBadge renders its label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StatusBadge(SiteStatus.blitz))),
    );
    expect(find.text('Blitz'), findsOneWidget);
  });

  testWidgets('Info hub lists the seven sections (issue #12)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: InfoScreen()));

    expect(find.text('Info'), findsOneWidget);
    for (final row in [
      'Useful Links',
      'About RoadMate',
      'Credits',
      'Support the app',
      'Contact / Support',
      'Share RoadMate',
      'Disclaimer',
    ]) {
      expect(find.text(row), findsOneWidget);
    }
    // Account moved to the User tab (issue #12 redesign).
    expect(find.text('Account'), findsNothing);
  });

  testWidgets('Info hub hides Support the app in the native iOS app', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Native iOS: no external donation link (App Store guideline 3.1.1).
    await tester.pumpWidget(
      const MaterialApp(
        home: InfoScreen(isWeb: false, platform: TargetPlatform.iOS),
      ),
    );
    expect(find.text('Support the app'), findsNothing);

    // Android app and web keep it.
    await tester.pumpWidget(
      const MaterialApp(
        home: InfoScreen(isWeb: false, platform: TargetPlatform.android),
      ),
    );
    expect(find.text('Support the app'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: InfoScreen(isWeb: true, platform: TargetPlatform.iOS),
      ),
    );
    expect(find.text('Support the app'), findsOneWidget);
  });

  testWidgets('Info sub-pages render their content', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    expect(
      find.text('Built by truck drivers, for truck drivers'),
      findsOneWidget,
    );
    expect(find.text('Community-powered'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: CreditsPage()));
    expect(find.text('Leandro Pervieux'), findsOneWidget);
    expect(find.text('Adrian Deccico'), findsOneWidget);
    expect(find.text('Darumatic'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SupportPage()));
    expect(find.text('Keep RoadMate rolling'), findsOneWidget);
    expect(find.text('Buy me a coffee'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: UsefulLinksPage()));
    expect(find.text('NHVR — Road Access'), findsOneWidget);
    expect(find.text('TasALERT'), findsOneWidget);
    expect(
      find.byType(InfoLinkRow),
      findsNWidgets(UsefulLinksPage.links.length),
    );

    await tester.pumpWidget(const MaterialApp(home: SharePage()));
    expect(find.text('Invite another driver'), findsOneWidget);
    expect(find.text(InfoScreen.shareUrl), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: ContactPage()));
    expect(find.textContaining('info@roadmate.club'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: DisclaimerPage()));
    expect(find.text('Use as a heads-up only'), findsOneWidget);
    expect(find.text('Approximate locations'), findsOneWidget);
  });

  test('share text sends web, App Store and Play Store links', () {
    expect(InfoScreen.shareText, contains('Web: ${InfoScreen.shareUrl}'));
    expect(InfoScreen.shareText, contains('iPhone: $kAppStoreUrl'));
    expect(InfoScreen.shareText, contains('Android: $kPlayStoreUrl'));
  });

  testWidgets('Share page store buttons follow the platform', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Web build: both stores on offer.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ShareBlock(isWeb: true))),
    );
    expect(find.text('Get the app'), findsOneWidget);
    expect(find.text('Google Play'), findsOneWidget);
    expect(find.text('App Store'), findsOneWidget);

    // Android app: Google Play only.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ShareBlock())),
    );
    expect(find.text('Google Play'), findsOneWidget);
    expect(find.text('App Store'), findsNothing);

    // iOS app: App Store only.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ShareBlock())),
    );
    expect(find.text('App Store'), findsOneWidget);
    expect(find.text('Google Play'), findsNothing);

    // Must be reset before the framework's end-of-test invariant check.
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('AdminEntryLink shows only for admins', (tester) async {
    Widget harness(AppUserRole role) => ProviderScope(
      key: ValueKey(role),
      overrides: [
        currentUserRoleProvider.overrideWith((ref) => Stream.value(role)),
      ],
      child: const MaterialApp(home: Scaffold(body: AdminEntryLink())),
    );

    await tester.pumpWidget(harness(AppUserRole.truckie));
    await tester.pumpAndSettle();
    expect(find.text('Open moderation'), findsNothing);

    await tester.pumpWidget(harness(AppUserRole.admin));
    await tester.pumpAndSettle();
    expect(find.text('Open moderation'), findsOneWidget);
  });

  testWidgets('LoadError shows a friendly temporary outage message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoadError())),
    );

    expect(find.text('RoadMate is temporarily unavailable'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });

  testWidgets('AdminScreen prompts non-admin users', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserRoleProvider.overrideWith(
            (ref) => Stream.value(AppUserRole.anonymous),
          ),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Admin sign-in required'), findsOneWidget);
    expect(find.text('Sites'), findsNothing);
  });

  testWidgets('AdminScreen shows admin tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserRoleProvider.overrideWith(
            (ref) => Stream.value(AppUserRole.admin),
          ),
          pendingSitesProvider.overrideWith((ref) => Stream.value(const [])),
          recentAdminReportsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sites'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('No pending sites'), findsOneWidget);
  });

  testWidgets('Admin Reports and Activity tabs split by report kind', (
    tester,
  ) async {
    AdminReport entry(SiteReport report) =>
        AdminReport(report: report, siteId: 'site-1', siteName: 'Marulan');
    final now = DateTime.now();
    final statusVote = entry(
      SiteReport(
        id: 'r-status',
        siteId: 'site-1',
        createdAt: now,
        status: SiteStatus.open,
      ),
    );
    final activity = entry(
      SiteReport(
        id: 'r-activity',
        siteId: 'site-1',
        createdAt: now,
        activityType: ActivityReportType.longQueue,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserRoleProvider.overrideWith(
            (ref) => Stream.value(AppUserRole.admin),
          ),
          pendingSitesProvider.overrideWith((ref) => Stream.value(const [])),
          recentAdminReportsProvider.overrideWith(
            (ref) => Stream.value([statusVote, activity]),
          ),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Reports tab shows the status vote, not the activity report.
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Status: Open'), findsOneWidget);
    expect(find.text('Long queue'), findsNothing);

    // Activity tab shows the activity report, not the status vote.
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Long queue'), findsOneWidget);
    expect(find.text('Status: Open'), findsNothing);

    // Only activity reports are editable; the status vote card on the
    // Reports tab has just the remove action.
    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('Admin edit dialog prefills the report and returns the edit', (
    tester,
  ) async {
    ({ActivityReportType type, String note})? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog(
                context: context,
                builder: (_) => const EditActivityReportDialog(
                  initialType: ActivityReportType.longQueue,
                  initialNote: 'queued to the ramp',
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Prefilled with the report's current values.
    expect(find.text('Edit activity report'), findsOneWidget);
    expect(find.text('Long queue'), findsOneWidget);
    expect(find.text('queued to the ramp'), findsOneWidget);

    // Change the type and the note, then save.
    await tester.tap(find.text('Long queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Police present').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'queued to the ramp'),
      'patrol car on the shoulder',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.type, ActivityReportType.policePresent);
    expect(result!.note, 'patrol car on the shoulder');
  });

  testWidgets('Home recently active cards show last activity timestamp', (
    tester,
  ) async {
    // Tall surface so the whole Home (speedometer panel pushes content down)
    // lays out without scrolling.
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final activeSite = Site(
      id: 'active-1',
      name: 'Marulan',
      type: SiteType.checkingStation,
      state: AusState.nsw,
      suburb: 'Marulan',
      address: 'Hume Hwy',
      currentStatus: SiteStatus.open,
      lastReportAt: DateTime.now().subtract(const Duration(minutes: 20)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          siteRepositoryProvider.overrideWithValue(
            FakeSiteRepository([activeSite]),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);

    // Issue #8: single header title, old texts gone.
    expect(find.text('RoadMate - Know before you roll'), findsOneWidget);
    expect(find.text('NHVR Sites'), findsNothing);
    expect(find.text('Know before you roll'), findsNothing);

    expect(find.text('Recently Active'), findsOneWidget);
    // Only the recently-active card shows a status label now — the
    // Open/Blitz/Closed stats bar was replaced by the closest-sites card (#7),
    // which stays hidden here (no position available).
    expect(find.text('Open/Working'), findsOneWidget);
    expect(find.text('CLOSEST SITES'), findsNothing);
    expect(find.text('OPEN'), findsNothing);
    expect(find.text('20m ago'), findsOneWidget);

    // The state search box was removed; the full grid always shows.
    expect(find.text('Search states...'), findsNothing);
    for (final state in visibleStates) {
      expect(find.text(state.code), findsWidgets);
    }
  });

  testWidgets('Home Add Site action opens the submission form', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStartupProvider.overrideWith((ref) => Future.value()),
          siteRepositoryProvider.overrideWithValue(
            FakeSiteRepository(const []),
          ),
        ],
        child: const RoadMateApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Site'));
    await tester.pumpAndSettle();

    expect(find.text('Site name'), findsOneWidget);
  });

  testWidgets('app version renders once, in the footer under the nav bar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStartupProvider.overrideWith((ref) => Future.value()),
          siteRepositoryProvider.overrideWithValue(
            FakeSiteRepository(const []),
          ),
        ],
        child: const RoadMateApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The router is a global; an earlier test may have left it off-shell.
    appRouter.go('/home');
    await tester.pumpAndSettle();

    // Footer is part of the shell, so it shows on Home…
    expect(find.text('RoadMate v$appVersion'), findsOneWidget);

    // …and stays a single copy on the Info tab (removed from the tab body).
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(find.text('RoadMate v$appVersion'), findsOneWidget);
  });

  testWidgets('User tab sits in the shell and opens account + trips', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStartupProvider.overrideWith((ref) => Future.value()),
          siteRepositoryProvider.overrideWithValue(
            FakeSiteRepository(const []),
          ),
        ],
        child: const RoadMateApp(),
      ),
    );
    await tester.pumpAndSettle();
    appRouter.go('/home');
    await tester.pumpAndSettle();

    // 5 tabs, User between Favourites and Info (issue #12 redesign).
    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();
    expect(labels, ['Home', 'Nearby', 'Favourites', 'User', 'Info']);

    await tester.tap(find.text('User'));
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('My Trips'), findsOneWidget);
    expect(find.text('No trips yet'), findsOneWidget);
  });

  testWidgets('StateCard shows code, name, site count and blitz badge', (
    tester,
  ) async {
    final sites = [
      const Site(
        id: '1',
        name: 'A',
        type: SiteType.weighbridge,
        state: AusState.vic,
        suburb: 'Euroa',
        address: 'Hume Fwy',
        lat: 0,
        lng: 0,
        currentStatus: SiteStatus.blitz,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StateCard(state: AusState.vic, sites: sites),
        ),
      ),
    );
    expect(find.text('VIC'), findsOneWidget);
    expect(find.text('Victoria'), findsOneWidget);
    expect(find.text('1 sites'), findsOneWidget);
    expect(find.text('Blitz'), findsOneWidget);
  });

  testWidgets('StateCard surfaces the Unknown status count in grey', (
    tester,
  ) async {
    Site site(String id, SiteStatus status) => Site(
      id: id,
      name: 'Site $id',
      type: SiteType.weighbridge,
      state: AusState.qld,
      suburb: 'Town',
      address: 'Bruce Hwy',
      lat: 0,
      lng: 0,
      currentStatus: status,
    );
    final sites = [
      site('1', SiteStatus.open),
      site('2', SiteStatus.unknown),
      site('3', SiteStatus.unknown),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StateCard(state: AusState.qld, sites: sites),
        ),
      ),
    );

    final openCount = tester.widget<Text>(find.text('1'));
    expect(openCount.style?.color, SiteStatus.open.color);
    final unknownCount = tester.widget<Text>(find.text('2'));
    expect(unknownCount.style?.color, SiteStatus.unknown.color);
  });
}
