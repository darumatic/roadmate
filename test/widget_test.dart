import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/app.dart';
import 'package:roadmate/features/admin/admin_screen.dart';
import 'package:roadmate/features/info/info_screen.dart';
import 'package:roadmate/features/home/home_screen.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/auth_service.dart';
import 'package:roadmate/services/site_repository.dart';
import 'package:roadmate/services/startup_service.dart';
import 'package:roadmate/widgets/load_error.dart';
import 'package:roadmate/widgets/state_card.dart';
import 'package:roadmate/widgets/status_badge.dart';

class FakeSiteRepository implements SiteRepository {
  FakeSiteRepository(this.sites);

  final List<Site> sites;

  @override
  Stream<List<Site>> watchSites() => Stream.value(sites);

  @override
  Stream<List<SiteReport>> watchReports(String siteId) =>
      Stream.value(const []);

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
  Future<void> addSite(Site site) async {}

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

  testWidgets('InfoScreen shows disclaimer and about content', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: InfoScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Use as a heads-up only'), findsOneWidget);
    expect(find.text('About RoadMate'), findsOneWidget);
    expect(
      find.textContaining('Built by Leandro Pervieux and Adrian Deccico.'),
      findsOneWidget,
    );
    expect(find.text('Share RoadMate'), findsWidgets);
    expect(find.text(InfoScreen.shareUrl), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.textContaining('Sign-in is unavailable'), findsOneWidget);
    // Admin entry is hidden for non-admins.
    expect(find.text('Open moderation'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Support'), findsOneWidget);
    expect(find.textContaining('info@roadmate.club'), findsOneWidget);
    expect(find.text('Report activity data'), findsNothing);
    expect(find.text('Donations'), findsNothing);
  });

  testWidgets('InfoScreen shows the admin entry for admins', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserRoleProvider.overrideWith(
            (ref) => Stream.value(AppUserRole.admin),
          ),
        ],
        child: const MaterialApp(home: InfoScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Admin'), findsOneWidget);
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
    expect(find.text('No pending sites'), findsOneWidget);
  });

  testWidgets('Home recently active cards show last activity timestamp', (
    tester,
  ) async {
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
    expect(find.text('Recently Active'), findsOneWidget);
    expect(find.text('Open/Working'), findsNWidgets(2));
    expect(find.text('OPEN'), findsNothing);
    expect(find.text('20m ago'), findsOneWidget);
  });

  testWidgets('Home Add Site action opens the submission form', (tester) async {
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
}
