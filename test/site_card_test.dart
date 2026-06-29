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

  @override
  Future<void> vote(String siteId, SiteStatus status) async =>
      votes.add((siteId, status));

  @override
  Future<void> toggleFavourite(String siteId) async => favourites.add(siteId);

  @override
  Future<void> report(String siteId, String note) async {}

  @override
  Future<void> addSite(Site site) async {}

  @override
  Stream<List<Site>> watchSites() => Stream.value(const []);

  @override
  Stream<List<SiteReport>> watchReports(String siteId) =>
      Stream.value(const []);

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
        home: Scaffold(body: SiteCard(site: _site)),
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
}
