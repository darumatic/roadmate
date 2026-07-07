import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:roadmate/features/nearby/nearby_screen.dart'
    show currentPositionProvider;
import 'package:roadmate/features/home/closest_sites_card.dart';
import 'package:roadmate/features/speedometer/speedometer_panel.dart';
import 'package:roadmate/features/speedometer/trip_controller.dart';
import 'package:roadmate/features/speedometer/trip_logger_card.dart';
import 'package:roadmate/features/speedometer/trip_tile.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/models/trip.dart';
import 'package:roadmate/services/alert_player.dart';
import 'package:roadmate/services/location_source.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/site_repository.dart';
import 'package:roadmate/services/trip_history_store.dart';

class FakeLocationSource implements LocationSource {
  FakeLocationSource({this.granted = true});
  final bool granted;
  final controller = StreamController<Position>.broadcast();

  @override
  Future<bool> ensurePermission() async => granted;

  @override
  Stream<Position> positions() => controller.stream;

  void emit(Position p) => controller.add(p);
}

/// A [LocationSource] whose stream-cancel future never completes — mirrors a
/// platform where the geolocator plugin hangs on cancel (the "stop button
/// does nothing" bug).
class HangingCancelLocationSource implements LocationSource {
  // Single-subscription so onCancel's never-completing future is honoured.
  final controller = StreamController<Position>(
    onCancel: () => Completer<void>().future,
  );

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Stream<Position> positions() => controller.stream;

  void emit(Position p) => controller.add(p);
}

/// A [TripHistoryStore] whose writes always fail.
class ThrowingTripStore extends FakeTripStore {
  @override
  Future<void> save(Trip trip) async => throw Exception('storage unavailable');
}

class FakeAlertPlayer implements AlertPlayer {
  int calls = 0;
  @override
  Future<void> playOverLimit() async => calls++;
}

class FakeTripStore implements TripHistoryStore {
  FakeTripStore({this.initialLimit = 100});
  final int initialLimit;
  final List<Trip> saved = [];
  int? savedLimit;

  @override
  Future<void> save(Trip trip) async => saved.add(trip);

  @override
  Future<List<Trip>> all() async => List.of(saved);

  @override
  Future<void> delete(String id) async =>
      saved.removeWhere((t) => t.id == id);

  @override
  Future<void> clear() async => saved.clear();

  @override
  Future<int> loadLimit() async => savedLimit ?? initialLimit;

  @override
  Future<void> saveLimit(int limitKmh) async => savedLimit = limitKmh;
}

class FakeSites implements SiteRepository {
  FakeSites(this.sites);
  final List<Site> sites;
  @override
  Future<void> addSite(Site site, {bool approved = false}) async {}
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
  Stream<Set<String>> watchFavourites() => Stream.value(const {});
  @override
  Stream<List<SiteReport>> watchReports(String siteId) => Stream.value(const []);
  @override
  Stream<List<Site>> watchSites() => Stream.value(sites);
}

final _t0 = DateTime(2026, 7, 4, 9, 0, 0);

Position _pos(
  double lat,
  double lng, {
  required Duration since,
  double speed = 0,
}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: _t0.add(since),
  accuracy: 1,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
);

Site _site(String id, String name, {double? lat, double? lng}) => Site(
  id: id,
  name: name,
  type: SiteType.checkingStation,
  state: AusState.nsw,
  suburb: name,
  address: '$name Rd',
  lat: lat,
  lng: lng,
  currentStatus: SiteStatus.open,
);

Future<void> _pump(
  WidgetTester tester, {
  required FakeLocationSource location,
  FakeAlertPlayer? alert,
  FakeTripStore? store,
  List<Site> sites = const [],
  Position? nearestPosition,
}) async {
  addTearDown(location.controller.close);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(1200, 3000));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationSourceProvider.overrideWithValue(location),
        alertPlayerProvider.overrideWithValue(alert ?? FakeAlertPlayer()),
        tripHistoryStoreProvider.overrideWithValue(store ?? FakeTripStore()),
        siteRepositoryProvider.overrideWithValue(FakeSites(sites)),
        currentPositionProvider.overrideWith((ref) async => nearestPosition),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [SpeedometerPanel(), TripLoggerCard()],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('speedo is live from app open; a trip only adds recording', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    await _pump(tester, location: loc);

    // GPS starts with the app (issue #9): speed shows before any trip.
    loc.emit(_pos(-33.00, 151.0, since: Duration.zero, speed: 0));
    await tester.pump();
    loc.emit(
      _pos(-33.01, 151.0, since: const Duration(seconds: 60), speed: 25),
    ); // 90 km/h
    await tester.pump();

    expect(find.text('090'), findsOneWidget); // live speed, zero-padded
    expect(find.text('GPS active'), findsOneWidget);
    expect(find.text('Start New Trip'), findsOneWidget);
    expect(find.text('Trip in progress'), findsNothing);
    expect(find.text('Tracking'), findsNothing);

    await tester.tap(find.text('Start New Trip'));
    await tester.pumpAndSettle();

    expect(find.text('Trip in progress'), findsOneWidget);
    expect(find.text('Stop & Save Trip'), findsOneWidget);
    expect(find.text('Tracking'), findsOneWidget);
  });

  testWidgets('denied location shows the retry card and GPS idle', (
    tester,
  ) async {
    await _pump(tester, location: FakeLocationSource(granted: false));

    expect(find.textContaining('Location access is needed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('GPS idle'), findsOneWidget);
  });

  testWidgets('exceeding the limit alerts even without a recording trip', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final alert = FakeAlertPlayer();
    await _pump(
      tester,
      location: loc,
      alert: alert,
      store: FakeTripStore(initialLimit: 60),
    );

    // No trip started — the warning still fires (issue #6).
    loc.emit(_pos(-33.00, 151.0, since: Duration.zero, speed: 0));
    await tester.pump();
    loc.emit(
      _pos(-33.01, 151.0, since: const Duration(seconds: 60), speed: 30),
    ); // 108 km/h > 60
    await tester.pump();

    expect(alert.calls, greaterThanOrEqualTo(1));
    final speedText = tester.widget<Text>(find.text('108'));
    expect(speedText.style?.color, const Color(0xFFEF4444)); // over-limit red
  });

  // Plain test: reset must re-baseline only the average, never the trip (#9).
  test('resetAvg re-baselines the average without touching the trip', () async {
    final loc = FakeLocationSource();
    final store = FakeTripStore();
    final container = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithValue(loc),
        alertPlayerProvider.overrideWithValue(FakeAlertPlayer()),
        tripHistoryStoreProvider.overrideWithValue(store),
        siteRepositoryProvider.overrideWithValue(FakeSites(const [])),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(loc.controller.close);

    final controller = container.read(tripControllerProvider.notifier);
    await controller.startTrip();
    loc.emit(_pos(-33.00, 151.0, since: Duration.zero, speed: 0));
    await Future<void>.delayed(Duration.zero);
    loc.emit(
      _pos(-33.01, 151.0, since: const Duration(seconds: 60), speed: 25),
    );
    await Future<void>.delayed(Duration.zero);

    var s = container.read(tripControllerProvider);
    expect(s.avgStats.distanceKm, greaterThan(1.0));
    expect(s.tripStats!.distanceKm, greaterThan(1.0));

    controller.resetAvg();
    s = container.read(tripControllerProvider);
    expect(s.avgStats.hasStarted, isFalse); // average re-baselined
    expect(s.isRecording, isTrue); // trip untouched
    expect(s.tripStats!.distanceKm, greaterThan(1.0));

    await controller.stopAndSave();
    expect(store.saved.single.distanceKm, greaterThan(1.0));
    // GPS keeps running after the trip ends.
    expect(container.read(tripControllerProvider).gps, GpsStatus.active);
  });

  // Plain test (not testWidgets): drives the controller directly so stream
  // events flush on the real event loop — no fake-async timer to advance.
  test('Stop & Save persists the trip then returns to idle', () async {
    final loc = FakeLocationSource();
    final store = FakeTripStore();
    final container = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithValue(loc),
        alertPlayerProvider.overrideWithValue(FakeAlertPlayer()),
        tripHistoryStoreProvider.overrideWithValue(store),
        siteRepositoryProvider.overrideWithValue(FakeSites(const [])),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(loc.controller.close);

    // The history list starts empty and refreshes once the trip is saved.
    expect(await container.read(tripHistoryProvider.future), isEmpty);

    final controller = container.read(tripControllerProvider.notifier);
    await controller.startTrip();
    loc.emit(_pos(-33.00, 151.0, since: Duration.zero, speed: 0));
    await Future<void>.delayed(Duration.zero);
    loc.emit(
      _pos(-33.01, 151.0, since: const Duration(seconds: 60), speed: 25),
    );
    await Future<void>.delayed(Duration.zero);

    await controller.stopAndSave();

    expect(store.saved, hasLength(1));
    expect(store.saved.first.distanceKm, greaterThan(1.0));
    expect(store.saved.first.maxSpeedKmh, greaterThan(80));
    expect(container.read(tripControllerProvider).isRecording, isFalse);
    expect(await container.read(tripHistoryProvider.future), hasLength(1));
  });

  test('a trip stopped before any GPS fix is still saved', () async {
    final loc = FakeLocationSource();
    final store = FakeTripStore();
    final container = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithValue(loc),
        alertPlayerProvider.overrideWithValue(FakeAlertPlayer()),
        tripHistoryStoreProvider.overrideWithValue(store),
        siteRepositoryProvider.overrideWithValue(FakeSites(const [])),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(loc.controller.close);

    final controller = container.read(tripControllerProvider.notifier);
    await controller.startTrip();
    // No fixes emitted — e.g. stopped indoors before the first GPS fix.
    await controller.stopAndSave();

    expect(store.saved, hasLength(1));
    expect(store.saved.first.distanceKm, 0);
    expect(store.saved.first.maxSpeedKmh, 0);
    expect(
      store.saved.first.duration,
      greaterThanOrEqualTo(Duration.zero),
    ); // wall-clock fallback
    expect(container.read(tripControllerProvider).isRecording, isFalse);
  });

  test('stop returns to idle and saves even if the GPS cancel hangs', () async {
    final loc = HangingCancelLocationSource();
    final store = FakeTripStore();
    final container = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithValue(loc),
        alertPlayerProvider.overrideWithValue(FakeAlertPlayer()),
        tripHistoryStoreProvider.overrideWithValue(store),
        siteRepositoryProvider.overrideWithValue(FakeSites(const [])),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(tripControllerProvider.notifier);
    await controller.startTrip();
    loc.emit(_pos(-33.00, 151.0, since: Duration.zero, speed: 0));
    await Future<void>.delayed(Duration.zero);
    loc.emit(
      _pos(-33.01, 151.0, since: const Duration(seconds: 60), speed: 25),
    );
    await Future<void>.delayed(Duration.zero);

    await controller.stopAndSave().timeout(const Duration(seconds: 1));

    expect(container.read(tripControllerProvider).isRecording, isFalse);
    expect(store.saved, hasLength(1));
  });

  test('stop returns to idle and logs when saving the trip fails', () async {
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = originalDebugPrint);

    final loc = FakeLocationSource();
    final container = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithValue(loc),
        alertPlayerProvider.overrideWithValue(FakeAlertPlayer()),
        tripHistoryStoreProvider.overrideWithValue(ThrowingTripStore()),
        siteRepositoryProvider.overrideWithValue(FakeSites(const [])),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(loc.controller.close);

    final controller = container.read(tripControllerProvider.notifier);
    await controller.startTrip();
    loc.emit(_pos(-33.00, 151.0, since: Duration.zero, speed: 0));
    await Future<void>.delayed(Duration.zero);
    loc.emit(
      _pos(-33.01, 151.0, since: const Duration(seconds: 60), speed: 25),
    );
    await Future<void>.delayed(Duration.zero);

    await controller.stopAndSave();

    expect(container.read(tripControllerProvider).isRecording, isFalse);
    // The failure must not be swallowed invisibly (a silent catch hid a
    // broken web build): it leaves a console trace.
    expect(
      logs.where((m) => m.contains('failed to save trip')),
      isNotEmpty,
    );
  });

  testWidgets('closest-sites card ranks the two nearest sites (issue #7)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationSourceProvider.overrideWithValue(FakeLocationSource()),
          alertPlayerProvider.overrideWithValue(FakeAlertPlayer()),
          tripHistoryStoreProvider.overrideWithValue(FakeTripStore()),
          currentPositionProvider.overrideWith(
            (ref) async => _pos(-34.70, 150.0, since: Duration.zero),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ClosestSitesCard(
              sites: [
                _site('far', 'Euroa', lat: -36.75, lng: 145.57),
                _site(
                  'near',
                  'Marulan Checking Station North',
                  lat: -34.72,
                  lng: 150.0,
                ),
                _site('mid', 'Mount White', lat: -33.4, lng: 151.2),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CLOSEST SITES'), findsOneWidget);
    // Two nearest shown; the farthest of the three is dropped.
    expect(find.text('Marulan Checking Station North'), findsOneWidget);
    expect(find.text('Mount White'), findsOneWidget);
    expect(find.text('Euroa'), findsNothing);
    expect(find.textContaining('km away'), findsNWidgets(2));
    expect(find.text('OPEN'), findsNWidgets(2));

    // Dispose to cancel the 1-minute fallback refresh timer.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saved trips render under the Trip Logger and delete works', (
    tester,
  ) async {
    final store = FakeTripStore()
      ..saved.addAll([
        Trip(
          id: 'a',
          startedAt: DateTime(2026, 7, 5, 14, 27),
          duration: const Duration(minutes: 8, seconds: 30),
          distanceKm: 12.5,
          maxSpeedKmh: 92,
          avgSpeedKmh: 61,
        ),
        Trip(
          id: 'b',
          startedAt: DateTime(2026, 7, 4, 9, 0),
          duration: const Duration(seconds: 45),
          distanceKm: 0.4,
          maxSpeedKmh: 38,
          avgSpeedKmh: 20,
        ),
      ]);
    await _pump(tester, location: FakeLocationSource(), store: store);

    expect(find.text('2 saved trips'), findsOneWidget);
    expect(find.text('Sun, 5 Jul'), findsOneWidget);
    expect(find.text('Sat, 4 Jul'), findsOneWidget);
    // Each saved trip shows distance, average speed and elapsed time.
    expect(find.text('2:27 pm → 2:35 pm'), findsOneWidget);
    expect(find.text('12.50 km'), findsOneWidget);
    expect(find.text('avg 61 km/h'), findsOneWidget);
    expect(find.text('8m 30s'), findsOneWidget);
    expect(find.text('45s'), findsOneWidget);
    expect(find.text('92 km/h'), findsNothing); // top speed no longer shown

    // Deleting asks for confirmation first; cancelling keeps the trip.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete Trip'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('2 saved trips'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('1 saved trip'), findsOneWidget);
    expect(store.saved.map((t) => t.id), ['b']);
  });

  testWidgets('idle with no trips shows the empty state', (tester) async {
    await _pump(tester, location: FakeLocationSource());

    expect(find.text('Start New Trip'), findsOneWidget);
    expect(find.text('Records distance, speed & duration'), findsOneWidget);
    expect(find.text('No trips yet — start one above'), findsOneWidget);
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('Home shows only the 3 newest trips with a View all link', (
    tester,
  ) async {
    final store = FakeTripStore()
      ..saved.addAll([
        for (var i = 0; i < 5; i++)
          Trip(
            id: 'trip-$i',
            startedAt: DateTime(2026, 7, 5 - i, 9),
            duration: const Duration(minutes: 5),
            distanceKm: 1.0 + i,
            maxSpeedKmh: 80,
            avgSpeedKmh: 60,
          ),
      ]);
    await _pump(tester, location: FakeLocationSource(), store: store);

    expect(find.text('5 saved trips'), findsOneWidget);
    expect(find.byType(TripTile), findsNWidgets(3));
    expect(find.text('View all (5)'), findsOneWidget);
  });

  testWidgets('Clear all deletes every trip only after confirmation', (
    tester,
  ) async {
    final store = FakeTripStore()
      ..saved.addAll([
        Trip(
          id: 'a',
          startedAt: DateTime(2026, 7, 5, 14, 27),
          duration: const Duration(minutes: 8),
          distanceKm: 12.5,
          maxSpeedKmh: 92,
          avgSpeedKmh: 61,
        ),
        Trip(
          id: 'b',
          startedAt: DateTime(2026, 7, 4, 9, 0),
          duration: const Duration(minutes: 2),
          distanceKm: 0.4,
          maxSpeedKmh: 38,
          avgSpeedKmh: 20,
        ),
      ]);
    await _pump(tester, location: FakeLocationSource(), store: store);

    // Cancelling keeps everything.
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all trips?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('2 saved trips'), findsOneWidget);
    expect(store.saved, hasLength(2));

    // Confirming clears the list and hides the trip-history UI.
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all'));
    await tester.pumpAndSettle();
    expect(store.saved, isEmpty);
    expect(find.textContaining('saved trip'), findsNothing);
    expect(find.text('Clear all'), findsNothing);
  });

  testWidgets('limit steppers adjust and persist the speed limit', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final store = FakeTripStore(initialLimit: 100);
    await _pump(tester, location: loc, store: store);

    expect(find.text('100'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.add));
    await tester.pump();

    expect(find.text('101'), findsOneWidget);
    expect(store.savedLimit, 101);
  });
}
