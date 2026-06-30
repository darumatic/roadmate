import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:roadmate/features/add_site/add_site_screen.dart';
import 'package:roadmate/features/favourites/favourites_screen.dart';
import 'package:roadmate/features/nearby/nearby_screen.dart';
import 'package:roadmate/features/state_detail/state_detail_screen.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/site_repository.dart';

class FeatureFakeSiteRepository implements SiteRepository {
  FeatureFakeSiteRepository({
    this.sites = const [],
    this.favourites = const {},
  });

  final List<Site> sites;
  final Set<String> favourites;
  final addedSites = <Site>[];

  @override
  Future<void> addSite(Site site) async => addedSites.add(site);

  @override
  Future<void> report(
    String siteId,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  }) async {}

  @override
  Future<void> toggleFavourite(String siteId) async {}

  @override
  Future<void> vote(String siteId, SiteStatus status) async {}

  @override
  Stream<Set<String>> watchFavourites() => Stream.value(favourites);

  @override
  Stream<List<SiteReport>> watchReports(String siteId) =>
      Stream.value(const []);

  @override
  Stream<List<Site>> watchSites() => Stream.value(sites);
}

Site _site({
  required String id,
  required String name,
  required AusState state,
  double? lat,
  double? lng,
  SiteStatus status = SiteStatus.open,
}) {
  return Site(
    id: id,
    name: name,
    type: SiteType.checkingStation,
    state: state,
    suburb: name,
    address: '$name Road',
    lat: lat,
    lng: lng,
    currentStatus: status,
  );
}

Position _position(double latitude, double longitude) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime(2026, 6, 30, 12),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget child,
  FeatureFakeSiteRepository repo,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [siteRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: child),
    ),
  );
}

Future<void> _pumpNearbyScreen(
  WidgetTester tester,
  FeatureFakeSiteRepository repo,
  Future<Position?> Function() loadPosition,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        siteRepositoryProvider.overrideWithValue(repo),
        currentPositionProvider.overrideWith((ref) => loadPosition()),
      ],
      child: const MaterialApp(home: NearbyScreen()),
    ),
  );
}

void main() {
  group('StateDetailScreen', () {
    testWidgets('filters sites by selected state and search query', (
      tester,
    ) async {
      final repo = FeatureFakeSiteRepository(
        sites: [
          _site(id: 'nsw-1', name: 'Marulan', state: AusState.nsw),
          _site(id: 'nsw-2', name: 'Eastern Creek', state: AusState.nsw),
          _site(id: 'vic-1', name: 'Euroa', state: AusState.vic),
        ],
      );

      await _pumpScreen(
        tester,
        const StateDetailScreen(state: AusState.nsw),
        repo,
      );
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.text('Marulan'), findsOneWidget);
      expect(find.text('Eastern Creek'), findsOneWidget);
      expect(find.text('Euroa'), findsNothing);

      await tester.enterText(find.byType(TextField), 'eastern');
      await tester.pumpAndSettle();

      expect(find.text('Eastern Creek'), findsOneWidget);
      expect(find.text('Marulan'), findsNothing);
    });

    testWidgets('shows empty messages for no sites and no search matches', (
      tester,
    ) async {
      final repo = FeatureFakeSiteRepository(
        sites: [_site(id: 'nsw-1', name: 'Marulan', state: AusState.nsw)],
      );

      await _pumpScreen(
        tester,
        const StateDetailScreen(state: AusState.wa),
        repo,
      );
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(
        find.text('No sites listed for Western Australia yet.'),
        findsOneWidget,
      );

      await _pumpScreen(
        tester,
        const StateDetailScreen(state: AusState.nsw),
        repo,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();

      expect(find.text('No sites match your search.'), findsOneWidget);
    });
  });

  group('AddSiteScreen', () {
    testWidgets(
      'validates required fields and submits a trimmed pending site',
      (tester) async {
        final repo = FeatureFakeSiteRepository();
        final router = GoRouter(
          initialLocation: '/add',
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const Scaffold()),
            GoRoute(path: '/add', builder: (_, _) => const AddSiteScreen()),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [siteRepositoryProvider.overrideWithValue(repo)],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        final submitButton = find
            .widgetWithText(FilledButton, 'Submit site')
            .last;
        final formList = find.byType(ListView).last;

        await tester.drag(formList, const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.tap(submitButton);
        await tester.pumpAndSettle();

        expect(find.text('Required'), findsNWidgets(3));
        expect(repo.addedSites, isEmpty);

        await tester.drag(formList, const Offset(0, 600));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).at(0),
          '  New Yard  ',
        );
        await tester.enterText(find.byType(TextFormField).at(1), '  Broome  ');
        await tester.enterText(
          find.byType(TextFormField).at(2),
          '  Great Northern Highway  ',
        );
        await tester.drag(formList, const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.tap(submitButton);
        await tester.pumpAndSettle();

        expect(repo.addedSites, hasLength(1));
        expect(repo.addedSites.single.name, 'New Yard');
        expect(repo.addedSites.single.suburb, 'Broome');
        expect(repo.addedSites.single.address, 'Great Northern Highway');
        expect(repo.addedSites.single.state, AusState.nsw);
        expect(repo.addedSites.single.type, SiteType.checkingStation);
      },
    );
  });

  group('FavouritesScreen', () {
    testWidgets('shows empty state when nothing is favourited', (tester) async {
      final repo = FeatureFakeSiteRepository(
        sites: [_site(id: 'nsw-1', name: 'Marulan', state: AusState.nsw)],
      );

      await _pumpScreen(tester, const FavouritesScreen(), repo);
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.text('No favourites yet'), findsOneWidget);
      expect(find.text('Marulan'), findsNothing);
    });

    testWidgets('shows only favourite sites', (tester) async {
      final repo = FeatureFakeSiteRepository(
        favourites: {'vic-1'},
        sites: [
          _site(id: 'nsw-1', name: 'Marulan', state: AusState.nsw),
          _site(id: 'vic-1', name: 'Euroa', state: AusState.vic),
        ],
      );

      await _pumpScreen(tester, const FavouritesScreen(), repo);
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.text('Euroa'), findsOneWidget);
      expect(find.text('Marulan'), findsNothing);
      expect(find.text('No favourites yet'), findsNothing);
    });
  });

  group('NearbyScreen', () {
    testWidgets('shows a location unavailable message', (tester) async {
      final repo = FeatureFakeSiteRepository();

      await _pumpNearbyScreen(tester, repo, () async => null);
      await tester.pumpAndSettle();

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.text('Location unavailable'), findsOneWidget);
    });

    testWidgets('shows no located sites message when sites lack coordinates', (
      tester,
    ) async {
      final repo = FeatureFakeSiteRepository(
        sites: [_site(id: 'nsw-1', name: 'Marulan', state: AusState.nsw)],
      );

      await _pumpNearbyScreen(
        tester,
        repo,
        () async => _position(-33.8688, 151.2093),
      );
      await tester.pumpAndSettle();

      expect(find.text('No located sites yet'), findsOneWidget);
    });

    testWidgets('ranks located sites and formats distance', (tester) async {
      final repo = FeatureFakeSiteRepository(
        sites: [
          _site(
            id: 'near',
            name: 'Sydney Yard',
            state: AusState.nsw,
            lat: -33.87,
            lng: 151.21,
          ),
          _site(
            id: 'far',
            name: 'Melbourne Yard',
            state: AusState.vic,
            lat: -37.81,
            lng: 144.96,
          ),
        ],
      );

      await _pumpNearbyScreen(
        tester,
        repo,
        () async => _position(-33.8688, 151.2093),
      );
      await tester.pumpAndSettle();

      final near = tester.getTopLeft(find.text('Sydney Yard'));
      final far = tester.getTopLeft(find.text('Melbourne Yard'));
      expect(near.dy, lessThan(far.dy));
      expect(find.textContaining('km away'), findsWidgets);
    });
  });
}
