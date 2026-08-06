import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:roadmate/features/add_site/add_site_screen.dart';
import 'package:roadmate/features/nearby/nearby_screen.dart'
    show currentPositionProvider;
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/admin_repository.dart';
import 'package:roadmate/services/auth_service.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/username_store.dart';
import 'package:roadmate/services/participation_logic.dart';
import 'package:roadmate/services/site_repository.dart';
import 'package:roadmate/widgets/site_card.dart';

class FakeSiteRepository implements SiteRepository {
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
  Stream<Set<String>> watchFavourites() => Stream.value(const {});

  @override
  Stream<ParticipationStats?> watchMyStats() => Stream.value(null);
  @override
  Stream<List<SiteReport>> watchAllRecentReports() => Stream.value(const []);
  @override
  Stream<List<Site>> watchSites() => Stream.value(const []);
}

/// Records site edits (as the exact Firestore write shape, via [siteEditData]);
/// everything else is unused here.
class FakeAdminRepository implements AdminRepository {
  final edits = <(String, Map<String, Object?>)>[];

  @override
  Future<void> updateSiteDetails(
    String siteId, {
    required String name,
    required SiteType type,
    required AusState state,
    required String suburb,
    required String address,
    required String? direction,
    required String? note,
    required double? lat,
    required double? lng,
  }) async => edits.add((
    siteId,
    siteEditData(
      name: name,
      type: type,
      state: state,
      suburb: suburb,
      address: address,
      direction: direction,
      note: note,
      lat: lat,
      lng: lng,
    ),
  ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Position _position(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 7, 26),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

const _site = Site(
  id: 'nsw-1',
  name: 'Marulan',
  type: SiteType.checkingStation,
  state: AusState.nsw,
  suburb: 'Marulan',
  address: 'Hume Hwy',
  lat: -34.71,
  lng: 149.99,
);

// Field order on the Add Site form: name, suburb, address, latitude,
// longitude.
const _latField = 3;
const _lngField = 4;

// Text-field order on the admin Edit site dialog: name, suburb, address,
// note, latitude, longitude (the dropdowns are not TextFormFields).
const _editName = 0;
const _editSuburb = 1;
const _editAddress = 2;
const _editNote = 3;
const _editLat = 4;
const _editLng = 5;

Future<void> _pumpAddSite(
  WidgetTester tester,
  FakeSiteRepository repo, {
  Position? position,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(1000, 2400));
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
        currentPositionProvider.overrideWith((ref) async => position),
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
}

Future<void> _fillRequiredFields(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'New Yard');
  await tester.enterText(find.byType(TextFormField).at(1), 'Broome');
  await tester.enterText(
    find.byType(TextFormField).at(2),
    'Great Northern Highway',
  );
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(
    find.widgetWithText(FilledButton, 'Submit site').last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Submit site').last);
  await tester.pumpAndSettle();
}

void main() {
  group('Add Site coordinates', () {
    testWidgets('captures the current fix and submits it with the site', (
      tester,
    ) async {
      final repo = FakeSiteRepository();
      await _pumpAddSite(tester, repo, position: _position(-34.7123, 149.7456));

      await _fillRequiredFields(tester);
      await tester.ensureVisible(find.text('Use my current location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();

      expect(find.text('-34.712300'), findsOneWidget);
      expect(find.text('149.745600'), findsOneWidget);

      await _submit(tester);

      final (site, approved) = repo.addedSites.single;
      expect(site.lat, closeTo(-34.7123, 1e-6));
      expect(site.lng, closeTo(149.7456, 1e-6));
      expect(approved, isFalse);
    });

    testWidgets('typed coordinates are submitted', (tester) async {
      final repo = FakeSiteRepository();
      await _pumpAddSite(tester, repo);

      await _fillRequiredFields(tester);
      await tester.enterText(find.byType(TextFormField).at(_latField), '-34.5');
      await tester.enterText(find.byType(TextFormField).at(_lngField), '149.5');
      await _submit(tester);

      expect(repo.addedSites.single.$1.lat, -34.5);
      expect(repo.addedSites.single.$1.lng, 149.5);
    });

    testWidgets('coordinates stay optional — a blank pair still submits', (
      tester,
    ) async {
      final repo = FakeSiteRepository();
      await _pumpAddSite(tester, repo);

      await _fillRequiredFields(tester);
      await _submit(tester);

      expect(repo.addedSites.single.$1.lat, isNull);
      expect(repo.addedSites.single.$1.lng, isNull);
    });

    testWidgets('half a pair is rejected rather than silently dropped', (
      tester,
    ) async {
      final repo = FakeSiteRepository();
      await _pumpAddSite(tester, repo);

      await _fillRequiredFields(tester);
      await tester.enterText(find.byType(TextFormField).at(_latField), '-34.5');
      await _submit(tester);

      expect(repo.addedSites, isEmpty);
      expect(
        find.text('Enter both latitude and longitude, or leave both blank'),
        findsOneWidget,
      );
    });

    testWidgets('an out-of-range latitude is rejected', (tester) async {
      final repo = FakeSiteRepository();
      await _pumpAddSite(tester, repo);

      await _fillRequiredFields(tester);
      await tester.enterText(find.byType(TextFormField).at(_latField), '95');
      await tester.enterText(find.byType(TextFormField).at(_lngField), '149.5');
      await _submit(tester);

      expect(repo.addedSites, isEmpty);
      expect(
        find.text('Latitude must be a number between -90.0 and 90.0'),
        findsOneWidget,
      );
    });

    testWidgets('an unavailable fix explains itself and blocks nothing', (
      tester,
    ) async {
      final repo = FakeSiteRepository();
      await _pumpAddSite(tester, repo, position: null);

      await _fillRequiredFields(tester);
      await tester.ensureVisible(find.text('Use my current location'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Location unavailable'), findsOneWidget);

      await _submit(tester);
      expect(repo.addedSites, hasLength(1));
    });
  });

  group('admin site editor', () {
    Future<FakeAdminRepository> pumpCard(
      WidgetTester tester, {
      Site site = _site,
    }) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1000, 2000));
      final admin = FakeAdminRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            siteRepositoryProvider.overrideWithValue(FakeSiteRepository()),
            adminRepositoryProvider.overrideWithValue(admin),
            currentUserRoleProvider.overrideWith(
              (ref) => Stream.value(AppUserRole.admin),
            ),
            currentPositionProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SiteCard(site: site)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return admin;
    }

    testWidgets('is admin-only', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            siteRepositoryProvider.overrideWithValue(FakeSiteRepository()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SiteCard(site: _site)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Edit site (admin)'), findsNothing);
    });

    testWidgets('prefills the current pin and saves an edit', (tester) async {
      final admin = await pumpCard(tester);

      await tester.tap(find.byTooltip('Edit site (admin)'));
      await tester.pumpAndSettle();

      expect(find.text('-34.71'), findsOneWidget);
      expect(find.text('149.99'), findsOneWidget);

      await tester.enterText(
        find.byType(TextFormField).at(_editLat),
        '-34.7205',
      );
      await tester.enterText(
        find.byType(TextFormField).at(_editLng),
        '149.9911',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // The untouched fields rode along with their prefilled values.
      final (siteId, data) = admin.edits.single;
      expect(siteId, 'nsw-1');
      expect(data['lat'], -34.7205);
      expect(data['lng'], 149.9911);
      expect(data['name'], _site.name);
      expect(data['suburb'], _site.suburb);
      expect(data['address'], _site.address);
      expect(data['type'], _site.type.jsonValue);
      expect(data['state'], _site.state.code);
      expect(find.text('Site updated'), findsOneWidget);
    });

    testWidgets('clearing both fields retracts the pin', (tester) async {
      final admin = await pumpCard(tester);

      await tester.tap(find.byTooltip('Edit site (admin)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(_editLat), '');
      await tester.enterText(find.byType(TextFormField).at(_editLng), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final (_, data) = admin.edits.single;
      expect(data['lat'], isNull);
      expect(data['lng'], isNull);
      expect(data['name'], _site.name);
    });

    testWidgets('a site missing coordinates flags itself to admins', (
      tester,
    ) async {
      await pumpCard(
        tester,
        site: Site(
          id: _site.id,
          name: _site.name,
          type: _site.type,
          state: _site.state,
          suburb: _site.suburb,
          address: _site.address,
        ),
      );
      expect(
        find.byTooltip('Edit site (admin) — location missing'),
        findsOneWidget,
      );
    });

    testWidgets('renaming the site saves the trimmed new name', (tester) async {
      final admin = await pumpCard(tester);

      await tester.tap(find.byTooltip('Edit site (admin)'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(_editName),
        '  Marulan HVSS Northbound  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final (_, data) = admin.edits.single;
      expect(data['name'], 'Marulan HVSS Northbound');
      expect(data['lat'], _site.lat);
      expect(data['lng'], _site.lng);
      expect(find.text('Site updated'), findsOneWidget);
    });

    testWidgets('every describing field is editable in one write', (
      tester,
    ) async {
      final admin = await pumpCard(tester);

      await tester.tap(find.byTooltip('Edit site (admin)'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(_editSuburb),
        '  Goulburn  ',
      );
      await tester.enterText(
        find.byType(TextFormField).at(_editAddress),
        'Hume Hwy, Goulburn NSW',
      );
      await tester.enterText(
        find.byType(TextFormField).at(_editNote),
        '  Entry required over 4.5t GVM  ',
      );

      final dialog = find.byType(AlertDialog);
      Future<void> pick(String current, String choice) async {
        await tester.ensureVisible(
          find.descendant(of: dialog, matching: find.text(current)),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: dialog, matching: find.text(current)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice).last);
        await tester.pumpAndSettle();
      }

      await pick('Checking Station', 'Weighbridge');
      await pick('NSW — New South Wales', 'VIC — Victoria');
      await pick('None / both', 'Southbound');

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final (siteId, data) = admin.edits.single;
      expect(siteId, 'nsw-1');
      expect(data['suburb'], 'Goulburn');
      expect(data['address'], 'Hume Hwy, Goulburn NSW');
      expect(data['note'], 'Entry required over 4.5t GVM');
      expect(data['type'], 'weighbridge');
      expect(data['state'], 'VIC');
      expect(data['direction'], 'southbound');
      expect(find.text('Site updated'), findsOneWidget);
    });

    testWidgets('clearing the note removes it', (tester) async {
      final admin = await pumpCard(
        tester,
        site: Site(
          id: _site.id,
          name: _site.name,
          type: _site.type,
          state: _site.state,
          suburb: _site.suburb,
          address: _site.address,
          lat: _site.lat,
          lng: _site.lng,
          note: 'Stale detail',
        ),
      );

      await tester.tap(find.byTooltip('Edit site (admin)'));
      await tester.pumpAndSettle();
      expect(find.text('Stale detail'), findsWidgets);
      await tester.enterText(find.byType(TextFormField).at(_editNote), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final (_, data) = admin.edits.single;
      expect(data['note'], isNull);
    });

    testWidgets(
      'a non-normalised stored direction opens as unset, not a crash',
      (tester) async {
        final admin = await pumpCard(
          tester,
          site: Site(
            id: _site.id,
            name: _site.name,
            type: _site.type,
            state: _site.state,
            suburb: _site.suburb,
            address: _site.address,
            direction: 'Both ways',
          ),
        );

        await tester.tap(
          find.byTooltip('Edit site (admin) — location missing'),
        );
        await tester.pumpAndSettle();
        expect(find.text('None / both'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(admin.edits.single.$2['direction'], isNull);
      },
    );

    testWidgets('a blanked name is rejected before it reaches Firestore', (
      tester,
    ) async {
      final admin = await pumpCard(tester);

      await tester.tap(find.byTooltip('Edit site (admin)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(_editName), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(admin.edits, isEmpty);
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('a blanked suburb or address is rejected too', (tester) async {
      final admin = await pumpCard(tester);

      await tester.tap(find.byTooltip('Edit site (admin)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(_editSuburb), ' ');
      await tester.enterText(find.byType(TextFormField).at(_editAddress), ' ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(admin.edits, isEmpty);
      expect(find.text('Required'), findsNWidgets(2));
    });

    testWidgets('an invalid edit is rejected before it reaches Firestore', (
      tester,
    ) async {
      final admin = await pumpCard(tester);

      await tester.tap(find.byTooltip('Edit site (admin)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(_editLat), '-34.5');
      await tester.enterText(find.byType(TextFormField).at(_editLng), '999');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(admin.edits, isEmpty);
      expect(
        find.text('Longitude must be a number between -180.0 and 180.0'),
        findsOneWidget,
      );
    });
  });
}
