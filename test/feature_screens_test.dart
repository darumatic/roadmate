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
import 'package:roadmate/services/auth_service.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/username_store.dart';
import 'package:roadmate/services/participation_logic.dart';
import 'package:roadmate/services/site_repository.dart';
import 'package:roadmate/widgets/site_card.dart';

class FeatureFakeSiteRepository implements SiteRepository {
  FeatureFakeSiteRepository({
    this.sites = const [],
    this.favourites = const {},
  });

  final List<Site> sites;
  final Set<String> favourites;
  final addedSites = <(Site, bool)>[];

  @override
  Future<void> addSite(
    Site site, {
    bool approved = false,
    String? submitterName,
  }) async => addedSites.add((site, approved));

  @override
  Future<void> report(
    Site site,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  }) async {}

  @override
  Future<void> toggleFavourite(String siteId) async {}

  @override
  Future<void> vote(
    Site site,
    SiteStatus status, {
    String? reporterName,
  }) async {}

  @override
  Stream<Set<String>> watchFavourites() => Stream.value(favourites);

  @override
  Stream<ParticipationStats?> watchMyStats() => Stream.value(null);

  @override
  Stream<List<SiteReport>> watchAllRecentReports() => Stream.value(const []);

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
      overrides: [
        siteRepositoryProvider.overrideWithValue(repo),
        myProfileProvider.overrideWith(
          (ref) => Stream.value(
            const UserProfile(isAnonymous: true, username: 'Test Driver'),
          ),
        ),
      ],
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

    testWidgets('lists the state\'s sites alphabetically (issue #36)', (
      tester,
    ) async {
      // Tall enough that every card is built, not just the visible prefix.
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(900, 1600));

      // Repository order is newest-first, not alphabetical.
      final repo = FeatureFakeSiteRepository(
        sites: [
          _site(id: 'nsw-1', name: 'Marulan', state: AusState.nsw),
          _site(id: 'nsw-2', name: 'eastern creek', state: AusState.nsw),
          _site(id: 'nsw-3', name: 'Bulahdelah', state: AusState.nsw),
        ],
      );

      await _pumpScreen(
        tester,
        const StateDetailScreen(state: AusState.nsw),
        repo,
      );
      await tester.pumpAndSettle();

      final cards = tester.widgetList<SiteCard>(find.byType(SiteCard)).toList();
      expect(cards.map((c) => c.site.name), [
        'Bulahdelah',
        'eastern creek',
        'Marulan',
      ]);
    });

    testWidgets('pins and highlights the tapped site (issue #10)', (
      tester,
    ) async {
      final repo = FeatureFakeSiteRepository(
        sites: [
          _site(id: 'nsw-1', name: 'Marulan', state: AusState.nsw),
          _site(id: 'nsw-2', name: 'Eastern Creek', state: AusState.nsw),
          _site(id: 'nsw-3', name: 'Mount White', state: AusState.nsw),
        ],
      );

      await _pumpScreen(
        tester,
        const StateDetailScreen(state: AusState.nsw, highlightSiteId: 'nsw-3'),
        repo,
      );
      await tester.pumpAndSettle();

      // The tapped site renders first and is the highlighted card.
      final cards = tester.widgetList<SiteCard>(find.byType(SiteCard)).toList();
      expect(cards.first.site.id, 'nsw-3');
      expect(cards.first.highlighted, isTrue);
      expect(cards.where((c) => c.highlighted), hasLength(1));
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

    testWidgets('Add Site action opens the submission form for the state', (
      tester,
    ) async {
      final repo = FeatureFakeSiteRepository(
        sites: [_site(id: 'wa-1', name: 'Northam', state: AusState.wa)],
      );
      final router = GoRouter(
        initialLocation: '/state/WA',
        routes: [
          GoRoute(
            path: '/state/:code',
            builder: (_, state) => StateDetailScreen(
              state: stateFromRouteCode(state.pathParameters['code']),
            ),
          ),
          GoRoute(
            path: '/add',
            builder: (_, state) => AddSiteScreen(
              initialState: stateFromRouteCode(
                state.uri.queryParameters['state'],
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            siteRepositoryProvider.overrideWithValue(repo),
            myProfileProvider.overrideWith(
              (ref) => Stream.value(
                const UserProfile(isAnonymous: true, username: 'Test Driver'),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Add Site'));
      await tester.pumpAndSettle();

      expect(find.text('Site name'), findsOneWidget);
      expect(find.text('WA — Western Australia'), findsOneWidget);
    });
  });

  group('AddSiteScreen', () {
    testWidgets(
      'validates required fields and submits a trimmed pending site',
      (tester) async {
        // Tall surface so every field-level error is on screen at once — the
        // form grew a coordinates section.
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(const Size(1000, 2400));
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
            overrides: [
              siteRepositoryProvider.overrideWithValue(repo),
              myProfileProvider.overrideWith(
                (ref) => Stream.value(
                  const UserProfile(isAnonymous: true, username: 'Test Driver'),
                ),
              ),
            ],
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
        final (site, approved) = repo.addedSites.single;
        expect(site.name, 'New Yard');
        expect(site.suburb, 'Broome');
        expect(site.address, 'Great Northern Highway');
        expect(site.state, AusState.nsw);
        expect(site.type, SiteType.checkingStation);
        expect(approved, isFalse); // community submissions stay pending
      },
    );

    testWidgets('direction dropdown offers all four bounds and submits '
        'the selection', (tester) async {
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
          overrides: [
            siteRepositoryProvider.overrideWithValue(repo),
            myProfileProvider.overrideWith(
              (ref) => Stream.value(
                const UserProfile(isAnonymous: true, username: 'Test Driver'),
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'East Yard');
      await tester.enterText(find.byType(TextFormField).at(1), 'Orange');
      await tester.enterText(find.byType(TextFormField).at(2), 'Mitchell Hwy');

      final formList = find.byType(ListView).last;
      await tester.drag(formList, const Offset(0, -600));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      for (final option in [
        'Northbound',
        'Southbound',
        'Eastbound',
        'Westbound',
      ]) {
        expect(find.text(option), findsWidgets);
      }
      await tester.tap(find.text('Eastbound').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Submit site').last);
      await tester.pumpAndSettle();

      expect(repo.addedSites, hasLength(1));
      final (site, _) = repo.addedSites.single;
      expect(site.direction, 'eastbound');
    });

    testWidgets('an admin publishes the site immediately (approved)', (
      tester,
    ) async {
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
          overrides: [
            siteRepositoryProvider.overrideWithValue(repo),
            myProfileProvider.overrideWith(
              (ref) => Stream.value(
                const UserProfile(isAnonymous: true, username: 'Test Driver'),
              ),
            ),
            currentUserRoleProvider.overrideWith(
              (ref) => Stream.value(AppUserRole.admin),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('published immediately, without review'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'Admin Yard');
      await tester.enterText(find.byType(TextFormField).at(1), 'Broome');
      await tester.enterText(find.byType(TextFormField).at(2), 'Hwy 1');
      // The submit button sits below the fold (the ListView builds lazily).
      final formList = find.byType(ListView).last;
      await tester.drag(formList, const Offset(0, -600));
      await tester.pumpAndSettle();

      final publishButton = find.widgetWithText(FilledButton, 'Publish site');
      expect(publishButton, findsOneWidget);
      await tester.tap(publishButton.last);
      await tester.pumpAndSettle();

      expect(repo.addedSites, hasLength(1));
      final (site, approved) = repo.addedSites.single;
      expect(site.name, 'Admin Yard');
      expect(approved, isTrue);
      expect(find.text('Site published — it is live now.'), findsOneWidget);
    });
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
