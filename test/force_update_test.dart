import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/app.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/min_version.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/site_repository.dart';
import 'package:roadmate/services/startup_service.dart';
import 'package:roadmate/widgets/force_update_screen.dart';

class _FakeSiteRepository implements SiteRepository {
  @override
  Stream<List<Site>> watchSites() => Stream.value(const []);

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

Widget _app({required bool forced, Future<void> Function()? opener}) {
  return ProviderScope(
    overrides: [
      appStartupProvider.overrideWith((ref) => Future.value()),
      siteRepositoryProvider.overrideWithValue(_FakeSiteRepository()),
      forceUpdateProvider.overrideWith((ref) => Stream.value(forced)),
      if (opener != null) storeOpenerProvider.overrideWithValue(opener),
    ],
    child: const RoadMateApp(),
  );
}

void main() {
  testWidgets('below-minimum build blocks the whole app', (tester) async {
    await tester.pumpWidget(_app(forced: true));
    await tester.pumpAndSettle();

    expect(find.byType(ForceUpdateScreen), findsOneWidget);
    expect(find.text('Update required'), findsOneWidget);
    // The router never mounts: no bottom navigation anywhere.
    expect(find.byType(NavigationDestination), findsNothing);
  });

  testWidgets('the update button fires the store opener', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _app(
        forced: true,
        opener: () async {
          opened++;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('an up-to-date build renders the normal app', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(forced: false));
    await tester.pumpAndSettle();

    expect(find.byType(ForceUpdateScreen), findsNothing);
    expect(find.byType(NavigationDestination), findsWidgets);
  });
}
