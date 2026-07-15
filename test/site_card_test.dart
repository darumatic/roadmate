import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/admin_repository.dart';
import 'package:roadmate/services/auth_service.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/rate_limit.dart';
import 'package:roadmate/services/site_repository.dart';
import 'package:roadmate/widgets/site_card.dart';

/// Records calls so the widget's wiring can be asserted. Set [voteError] /
/// [reportError] to simulate the write being rejected (e.g. by the rules'
/// rate limit).
class FakeSiteRepository implements SiteRepository {
  final votes = <(String, SiteStatus)>[];
  final favourites = <String>[];
  final reports = <(String, ActivityReportType, String?, String?)>[];
  List<SiteReport> watchedReports = const [];
  Object? voteError;
  Object? reportError;

  @override
  Future<void> vote(String siteId, SiteStatus status) async {
    if (voteError != null) throw voteError!;
    votes.add((siteId, status));
  }

  @override
  Future<void> toggleFavourite(String siteId) async => favourites.add(siteId);

  @override
  Future<void> report(
    String siteId,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  }) async {
    if (reportError != null) throw reportError!;
    reports.add((siteId, activityType, activityNote, reporterName));
  }

  @override
  Future<void> addSite(Site site, {bool approved = false}) async {}

  @override
  Stream<List<Site>> watchSites() => Stream.value(const []);

  @override
  Stream<List<SiteReport>> watchReports(String siteId) =>
      Stream.value(watchedReports);

  @override
  Stream<Set<String>> watchFavourites() => Stream.value(const {});
}

/// Records site deletions; every other member is unused by the widget under
/// test, so noSuchMethod covers them.
class FakeAdminRepository implements AdminRepository {
  final deletedSites = <String>[];

  @override
  Future<void> deleteSite(String siteId) async => deletedSites.add(siteId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _site = Site(
  id: 'nsw-1',
  name: 'Marulan',
  type: SiteType.checkingStation,
  state: AusState.nsw,
  suburb: 'Marulan',
  address: 'Hume Hwy',
  currentStatus: SiteStatus.closed, // so the open vote button is unambiguous
);

Site _siteWithLastReport(DateTime lastReportAt) =>
    _site.copyWith(lastReportAt: lastReportAt);

Future<void> _pump(
  WidgetTester tester,
  FakeSiteRepository repo, {
  Site site = _site,
  FakeAdminRepository? adminRepo,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        siteRepositoryProvider.overrideWithValue(repo),
        // A non-null adminRepo pumps the card as a signed-in admin.
        if (adminRepo != null) ...[
          currentUserRoleProvider.overrideWith(
            (ref) => Stream.value(AppUserRole.admin),
          ),
          adminRepositoryProvider.overrideWithValue(adminRepo),
        ],
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SiteCard(site: site)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping a vote button records a vote', (tester) async {
    final repo = FakeSiteRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open/Working'));
    await tester.pump();

    expect(repo.votes, [('nsw-1', SiteStatus.open)]);
  });

  // Issue #21: a stale site shows Unknown — badge grey, no button selected,
  // and Unknown itself is never offered as a vote.
  testWidgets('unknown status greys all vote buttons and is not votable', (
    tester,
  ) async {
    final repo = FakeSiteRepository();
    await _pump(
      tester,
      repo,
      site: _site.copyWith(currentStatus: SiteStatus.unknown),
    );
    await tester.pumpAndSettle();

    // The status badge reads Unknown…
    expect(find.text('Unknown'), findsOneWidget);
    // …but there are only the three real vote buttons, none highlighted.
    expect(find.text('Open/Working'), findsOneWidget);
    expect(find.text('Blitz'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
    final greyed = tester
        .widgetList<Text>(
          find.byWidgetPredicate(
            (w) =>
                w is Text &&
                const ['Open/Working', 'Blitz', 'Closed'].contains(w.data),
          ),
        )
        .map((t) => t.style?.color);
    expect(greyed, everyElement(const Color(0xFF9A9AA2))); // all grey
  });

  testWidgets('tapping the star toggles favourite', (tester) async {
    final repo = FakeSiteRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pump();

    expect(repo.favourites, ['nsw-1']);
  });

  testWidgets('shows recent report time in top-right when present', (
    tester,
  ) async {
    final repo = FakeSiteRepository();
    final site = _siteWithLastReport(
      DateTime.now().subtract(const Duration(minutes: 20)),
    );
    await _pump(tester, repo, site: site);
    await tester.pumpAndSettle();

    expect(find.text('reported 20m ago'), findsOneWidget);
  });

  testWidgets('hides recent report time when no report exists', (tester) async {
    final repo = FakeSiteRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    expect(find.textContaining('reported '), findsNothing);
  });

  testWidgets('submitting an activity report records category, note and name', (
    tester,
  ) async {
    final repo = FakeSiteRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delays'));
    await tester.enterText(
      find.byType(TextField).at(0),
      'Northbound back to the ramp',
    );
    await tester.enterText(find.byType(TextField).at(1), 'Sam');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(repo.reports, [
      (
        'nsw-1',
        ActivityReportType.delays,
        'Northbound back to the ramp',
        'Sam',
      ),
    ]);
  });

  testWidgets('shows latest five categorized activity reports', (tester) async {
    final repo = FakeSiteRepository()
      ..watchedReports = [
        SiteReport(
          id: '1',
          siteId: 'nsw-1',
          createdAt: DateTime.now(),
          activityType: ActivityReportType.longQueue,
          reporterName: 'Alex',
        ),
        SiteReport(
          id: '2',
          siteId: 'nsw-1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
          activityType: ActivityReportType.policePresent,
          activityNote: 'Two cars on site',
        ),
        SiteReport(
          id: 'old',
          siteId: 'nsw-1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
          activityNote: 'Old report shape',
        ),
        SiteReport(
          id: '3',
          siteId: 'nsw-1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
          activityType: ActivityReportType.noActivity,
        ),
        SiteReport(
          id: '4',
          siteId: 'nsw-1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
          activityType: ActivityReportType.defectChecks,
        ),
        SiteReport(
          id: '5',
          siteId: 'nsw-1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
          activityType: ActivityReportType.delays,
        ),
        SiteReport(
          id: '6',
          siteId: 'nsw-1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 50)),
          activityType: ActivityReportType.other,
        ),
      ];
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    expect(find.text('Recent reports'), findsOneWidget);
    expect(find.text('Long queue'), findsOneWidget);
    expect(find.text('Police present'), findsOneWidget);
    expect(find.text('Camera Only'), findsOneWidget);
    expect(find.text('BGD'), findsOneWidget);
    expect(find.text('Delays'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
    expect(find.text('Old report shape'), findsNothing);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Anonymous'), findsNWidgets(4));
  });

  testWidgets('activity reports expire from the card after 10 hours', (
    tester,
  ) async {
    final repo = FakeSiteRepository()
      ..watchedReports = [
        SiteReport(
          id: 'fresh',
          siteId: 'nsw-1',
          createdAt: DateTime.now().subtract(const Duration(hours: 9)),
          activityType: ActivityReportType.longQueue,
        ),
        SiteReport(
          id: 'stale',
          siteId: 'nsw-1',
          createdAt: DateTime.now().subtract(const Duration(hours: 11)),
          activityType: ActivityReportType.policePresent,
        ),
      ];
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    // Only two reports, so take(5) keeps both — absence proves the 10h filter.
    expect(find.text('Long queue'), findsOneWidget);
    expect(find.text('Police present'), findsNothing);
  });

  testWidgets('Recent reports section hides when every report has expired', (
    tester,
  ) async {
    final repo = FakeSiteRepository()
      ..watchedReports = [
        SiteReport(
          id: 'stale',
          siteId: 'nsw-1',
          createdAt: DateTime.now().subtract(const Duration(hours: 11)),
          activityType: ActivityReportType.longQueue,
        ),
      ];
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    expect(find.text('Recent reports'), findsNothing);
    expect(find.text('Long queue'), findsNothing);
  });

  testWidgets('remove-site X is hidden from regular users', (tester) async {
    final repo = FakeSiteRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Remove site (admin)'), findsNothing);
  });

  testWidgets('admin sees the X and confirming removes the site', (
    tester,
  ) async {
    final repo = FakeSiteRepository();
    final adminRepo = FakeAdminRepository();
    await _pump(tester, repo, adminRepo: adminRepo);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove site (admin)'));
    await tester.pumpAndSettle();

    expect(find.text('Remove site?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(adminRepo.deletedSites, ['nsw-1']);
  });

  testWidgets('cancelling the remove-site warning deletes nothing', (
    tester,
  ) async {
    final repo = FakeSiteRepository();
    final adminRepo = FakeAdminRepository();
    await _pump(tester, repo, adminRepo: adminRepo);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remove site (admin)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(adminRepo.deletedSites, isEmpty);
    expect(find.text('Remove site?'), findsNothing);
  });

  testWidgets(
    'repeat votes are not blocked client-side (undo a mis-tap works)',
    (tester) async {
      final repo = FakeSiteRepository();
      await _pump(tester, repo);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open/Working'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blitz'));
      await tester.pump();

      expect(repo.votes, [
        ('nsw-1', SiteStatus.open),
        ('nsw-1', SiteStatus.blitz),
      ]);
    },
  );

  testWidgets('vote failures show a friendly error, never a crash', (
    tester,
  ) async {
    final repo = FakeSiteRepository()..voteError = Exception('offline');
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open/Working'));
    await tester.pump();

    expect(repo.votes, isEmpty);
    expect(find.textContaining('Could not submit'), findsOneWidget);
  });

  testWidgets('report failures show a friendly error, never a crash', (
    tester,
  ) async {
    final repo = FakeSiteRepository()..reportError = Exception('offline');
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(repo.reports, isEmpty);
    expect(find.textContaining('Could not submit'), findsOneWidget);
  });

  // Issue #15 redux: hitting the 5-actions/5-minutes limit gets its own
  // explanation, not the generic failure text.
  testWidgets('rate-limited vote shows the cooldown message', (tester) async {
    final repo = FakeSiteRepository()..voteError = const RateLimitedException();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open/Working'));
    await tester.pump();

    expect(find.text(kRateLimitMessage), findsOneWidget);
    expect(find.textContaining('Could not submit'), findsNothing);
  });

  testWidgets('rate-limited report shows the cooldown message', (
    tester,
  ) async {
    final repo = FakeSiteRepository()
      ..reportError = const RateLimitedException();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.text(kRateLimitMessage), findsOneWidget);
    expect(find.textContaining('Could not submit'), findsNothing);
  });
}
