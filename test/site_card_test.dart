import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/site_repository.dart';
import 'package:roadmate/widgets/site_card.dart';

/// Records calls so the widget's wiring can be asserted.
class FakeSiteRepository implements SiteRepository {
  final votes = <(String, SiteStatus)>[];
  final favourites = <String>[];
  final reports = <(String, ActivityReportType, String?, String?)>[];
  List<SiteReport> watchedReports = const [];

  @override
  Future<void> vote(String siteId, SiteStatus status) async =>
      votes.add((siteId, status));

  @override
  Future<void> toggleFavourite(String siteId) async => favourites.add(siteId);

  @override
  Future<void> report(
    String siteId,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  }) async => reports.add((siteId, activityType, activityNote, reporterName));

  @override
  Future<void> addSite(Site site) async {}

  @override
  Stream<List<Site>> watchSites() => Stream.value(const []);

  @override
  Stream<List<SiteReport>> watchReports(String siteId) =>
      Stream.value(watchedReports);

  @override
  Stream<Set<String>> watchFavourites() => Stream.value(const {});
}

const _site = Site(
  id: 'nsw-1',
  name: 'Marulan',
  type: SiteType.checkingStation,
  state: AusState.nsw,
  suburb: 'Marulan',
  address: 'Hume Hwy',
  currentStatus: SiteStatus.closed, // so the OPEN vote button is unambiguous
);

Future<void> _pump(WidgetTester tester, FakeSiteRepository repo) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [siteRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SiteCard(site: _site)),
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

    await tester.tap(find.text('OPEN'));
    await tester.pump();

    expect(repo.votes, [('nsw-1', SiteStatus.open)]);
  });

  testWidgets('tapping the star toggles favourite', (tester) async {
    final repo = FakeSiteRepository();
    await _pump(tester, repo);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_border));
    await tester.pump();

    expect(repo.favourites, ['nsw-1']);
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
    expect(find.text('No activity'), findsOneWidget);
    expect(find.text('Defect checks'), findsOneWidget);
    expect(find.text('Delays'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
    expect(find.text('Old report shape'), findsNothing);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Anonymous'), findsNWidgets(4));
  });
}
