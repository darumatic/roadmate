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
import 'package:roadmate/services/report_proximity.dart';
import 'package:roadmate/services/participation_logic.dart';
import 'package:roadmate/services/site_repository.dart';
import 'package:roadmate/services/username_logic.dart';
import 'package:roadmate/services/username_store.dart';
import 'package:roadmate/widgets/level_badge.dart';
import 'package:roadmate/widgets/site_card.dart';

/// Records calls so the widget's wiring can be asserted. Set [voteError] /
/// [reportError] to simulate the write being rejected (e.g. by the rules'
/// rate limit or the proximity gate).
class FakeSiteRepository implements SiteRepository {
  final votes = <(String, SiteStatus, String?)>[];
  final favourites = <String>[];
  final reports = <(String, ActivityReportType, String?, String?)>[];
  List<SiteReport> watchedReports = const [];
  Object? voteError;
  Object? reportError;

  @override
  Future<void> vote(
    Site site,
    SiteStatus status, {
    String? reporterName,
  }) async {
    final error = voteError;
    if (error != null) throw error;
    votes.add((site.id, status, reporterName));
  }

  @override
  Future<void> toggleFavourite(String siteId) async => favourites.add(siteId);

  @override
  Future<void> report(
    Site site,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  }) async {
    final error = reportError;
    if (error != null) throw error;
    reports.add((site.id, activityType, activityNote, reporterName));
  }

  @override
  Future<void> addSite(
    Site site, {
    bool approved = false,
    String? submitterName,
  }) async {}

  @override
  Stream<List<Site>> watchSites() => Stream.value(const []);

  @override
  Stream<List<SiteReport>> watchAllRecentReports() =>
      Stream.value(watchedReports);

  @override
  Stream<Set<String>> watchFavourites() => Stream.value(const {});

  @override
  Stream<ParticipationStats?> watchMyStats() => Stream.value(null);
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
  // Posting is signed, so most tests pump as a user who already picked a
  // road name; hasRoadName: false exercises the pick-a-name prompt instead.
  bool hasRoadName = true,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        siteRepositoryProvider.overrideWithValue(repo),
        if (hasRoadName)
          myProfileProvider.overrideWith(
            (ref) => Stream.value(
              const UserProfile(isAnonymous: true, username: 'Test Driver'),
            ),
          ),
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
    await tester.pumpAndSettle();

    expect(repo.votes, [('nsw-1', SiteStatus.open, 'Test Driver')]);
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

  testWidgets('submitting an activity report records category, note and the '
      'road name it is signed with', (tester) async {
    final repo = FakeSiteRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report activity'));
    await tester.pumpAndSettle();

    // The dialog says what name the report will carry — no free-text field.
    expect(find.text('Posting as Test Driver'), findsOneWidget);

    await tester.tap(find.text('Delays'));
    await tester.enterText(
      find.byType(TextField),
      'Northbound back to the ramp',
    );
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(repo.reports, [
      (
        'nsw-1',
        ActivityReportType.delays,
        'Northbound back to the ramp',
        'Test Driver',
      ),
    ]);
  });

  // Posting is signed: a user with no road name yet is asked to pick one
  // right at the point of posting, and the post proceeds with it.
  group('road-name requirement on posting', () {
    testWidgets('voting without a road name opens the picker, and saving '
        'signs the vote', (tester) async {
      final repo = FakeSiteRepository();
      await _pump(tester, repo, hasRoadName: false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open/Working'));
      await tester.pumpAndSettle();

      expect(find.text('Pick your road name'), findsOneWidget);
      expect(repo.votes, isEmpty);

      await tester.enterText(find.byType(TextField), 'Big Rig Bob');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Pick your road name'), findsNothing);
      expect(repo.votes, [('nsw-1', SiteStatus.open, 'Big Rig Bob')]);
    });

    testWidgets('declining the picker abandons the vote with an explanation', (
      tester,
    ) async {
      final repo = FakeSiteRepository();
      await _pump(tester, repo, hasRoadName: false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open/Working'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.votes, isEmpty);
      expect(find.text(kRoadNameRequiredMessage), findsOneWidget);
    });

    testWidgets('an invalid typed name shows the reason and blocks saving', (
      tester,
    ) async {
      final repo = FakeSiteRepository();
      await _pump(tester, repo, hasRoadName: false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open/Working'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '!!');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.votes, isEmpty);
      expect(find.text('Pick your road name'), findsOneWidget);
      expect(find.text(validateUsername('!!')!), findsOneWidget);
    });

    testWidgets('a taken name shows the taken message', (tester) async {
      final repo = FakeSiteRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            siteRepositoryProvider.overrideWithValue(repo),
            usernameStoreProvider.overrideWithValue(
              MemoryUsernameStore(takenNames: {'Big Rig Bob'}),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SiteCard(site: _site)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open/Working'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'big rig bob');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.votes, isEmpty);
      expect(find.textContaining('already taken'), findsOneWidget);
    });
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
        // The repository stream is now shared across all sites — another
        // site's report must never leak onto this card.
        SiteReport(
          id: 'other-site',
          siteId: 'qld-9',
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          activityType: ActivityReportType.delays,
          reporterName: 'Zoe',
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
    expect(find.text('Zoe'), findsNothing); // qld-9's report stays off nsw-1
  });

  testWidgets('a report row shows the level icon only when stamped', (
    tester,
  ) async {
    final repo = FakeSiteRepository()
      ..watchedReports = [
        SiteReport(
          id: 'stamped',
          siteId: 'nsw-1',
          createdAt: DateTime.now(),
          activityType: ActivityReportType.longQueue,
          reporterName: 'Alex',
          reporterLevel: 3, // Highway Regular
        ),
        // Written by an older client — no reporterLevel, no icon.
        SiteReport(
          id: 'legacy',
          siteId: 'nsw-1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
          activityType: ActivityReportType.delays,
          reporterName: 'Sam',
        ),
      ];
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Highway Regular'), findsOneWidget);
    // Exactly one marker across both rows: the legacy row renders nothing.
    expect(
      find.descendant(
        of: find.byType(ReporterLevelIcon),
        matching: find.byType(Icon),
      ),
      findsOneWidget,
    );
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
      await tester.pumpAndSettle();

      expect(repo.votes, [
        ('nsw-1', SiteStatus.open, 'Test Driver'),
        ('nsw-1', SiteStatus.blitz, 'Test Driver'),
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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    expect(find.text(kRateLimitMessage), findsOneWidget);
    expect(find.textContaining('Could not submit'), findsNothing);
  });

  testWidgets('rate-limited report shows the cooldown message', (tester) async {
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

  // Reports are trusted because they come from the road: the repository
  // refuses a write from outside the 3 km radius (TooFarException) or with no
  // position at all (LocationRequiredException), and each refusal gets its
  // own explanation — never the generic failure text.
  group('proximity gate on posting', () {
    testWidgets('a vote from too far away shows the distance message', (
      tester,
    ) async {
      final repo = FakeSiteRepository()..voteError = const TooFarException();
      await _pump(tester, repo);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open/Working'));
      await tester.pumpAndSettle();

      expect(repo.votes, isEmpty);
      expect(find.text(kTooFarToReportMessage), findsOneWidget);
      expect(find.textContaining('Could not submit'), findsNothing);
      expect(find.text(kRateLimitMessage), findsNothing);
    });

    testWidgets('a vote without a device position asks for location', (
      tester,
    ) async {
      final repo = FakeSiteRepository()
        ..voteError = const LocationRequiredException();
      await _pump(tester, repo);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open/Working'));
      await tester.pumpAndSettle();

      expect(repo.votes, isEmpty);
      expect(find.text(kLocationRequiredMessage), findsOneWidget);
      expect(find.textContaining('Could not submit'), findsNothing);
    });

    testWidgets('an activity report from too far away shows the distance '
        'message', (tester) async {
      final repo = FakeSiteRepository()..reportError = const TooFarException();
      await _pump(tester, repo);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(repo.reports, isEmpty);
      expect(find.text(kTooFarToReportMessage), findsOneWidget);
      expect(find.textContaining('Could not submit'), findsNothing);
    });

    testWidgets('an activity report without a device position asks for '
        'location', (tester) async {
      final repo = FakeSiteRepository()
        ..reportError = const LocationRequiredException();
      await _pump(tester, repo);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(repo.reports, isEmpty);
      expect(find.text(kLocationRequiredMessage), findsOneWidget);
      expect(find.textContaining('Could not submit'), findsNothing);
    });
  });
}
