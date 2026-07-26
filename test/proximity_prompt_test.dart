import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:roadmate/features/proximity/proximity_controller.dart';
import 'package:roadmate/features/proximity/proximity_prompt_card.dart';
import 'package:roadmate/features/speedometer/speedometer_panel.dart';
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
  final controller = StreamController<Position>.broadcast();

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Stream<Position> positions() => controller.stream;

  void emit(Position p) => controller.add(p);
}

class FakeAlertPlayer implements AlertPlayer {
  int overLimit = 0;
  int proximity = 0;

  @override
  Future<void> playOverLimit() async => overLimit++;

  @override
  Future<void> playProximity() async => proximity++;
}

class FakeStore implements TripHistoryStore {
  bool proximityEnabled = true;
  bool? savedProximity;

  @override
  Future<List<Trip>> all() async => const [];
  @override
  Future<void> clear() async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<int> loadLimit() async => kDefaultSpeedLimit;
  @override
  Future<bool> loadSoundEnabled() async => true;
  @override
  Future<void> save(Trip trip) async {}
  @override
  Future<void> saveLimit(int limitKmh) async {}
  @override
  Future<void> saveSoundEnabled(bool enabled) async {}
  @override
  Future<bool> loadProximityEnabled() async => proximityEnabled;
  @override
  Future<void> saveProximityEnabled(bool enabled) async =>
      savedProximity = enabled;
}

class FakeSiteRepository implements SiteRepository {
  FakeSiteRepository(this.sites);
  final List<Site> sites;
  final votes = <(String, SiteStatus)>[];
  Object? voteError;

  @override
  Future<void> vote(String siteId, SiteStatus status) async {
    if (voteError != null) throw voteError!;
    votes.add((siteId, status));
  }

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
  Stream<Set<String>> watchFavourites() => Stream.value(const {});
  @override
  Stream<List<SiteReport>> watchAllRecentReports() => Stream.value(const []);
  @override
  Stream<List<Site>> watchSites() => Stream.value(sites);
}

final _t0 = DateTime(2026, 7, 26, 8, 0);

Position _pos(double lat, {required Duration since, double speed = 25}) =>
    Position(
      latitude: lat,
      longitude: 151.0,
      timestamp: _t0.add(since),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed, // m/s — 25 m/s = 90 km/h
      speedAccuracy: 0,
    );

Site _site(String id, {DateTime? lastReportAt, SiteStatus? status}) => Site(
  id: id,
  name: '$id Checking Station',
  type: SiteType.checkingStation,
  state: AusState.nsw,
  suburb: id,
  address: '$id Rd',
  lat: -33.0,
  lng: 151.0,
  currentStatus: status ?? SiteStatus.unknown,
  lastReportAt: lastReportAt,
);

/// Mounts the speedometer (which owns the GPS stream) under the same
/// [ProximityGate] the real app wraps its router in.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeLocationSource location,
  required FakeSiteRepository repo,
  FakeAlertPlayer? alert,
  FakeStore? store,
}) async {
  addTearDown(location.controller.close);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(900, 1600));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationSourceProvider.overrideWithValue(location),
        alertPlayerProvider.overrideWithValue(alert ?? FakeAlertPlayer()),
        tripHistoryStoreProvider.overrideWithValue(store ?? FakeStore()),
        siteRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ProximityGate(
            child: SingleChildScrollView(child: SpeedometerPanel()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(ProximityGate)));
}

void main() {
  testWidgets('approaching a site raises the prompt and sounds the alert', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final alert = FakeAlertPlayer();
    final repo = FakeSiteRepository([
      _site('marulan', status: SiteStatus.blitz, lastReportAt: DateTime.now()),
    ]);
    await _pump(tester, location: loc, repo: repo, alert: alert);

    // First fix: inside the radius but with no history, so nothing yet.
    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    expect(find.textContaining('APPROACHING'), findsNothing);

    // Second fix, 500 m closer at 90 km/h.
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();

    expect(find.textContaining('APPROACHING'), findsOneWidget);
    expect(find.text('marulan Checking Station'), findsOneWidget);
    expect(find.textContaining('Reported Blitz'), findsOneWidget);
    expect(find.text("What's the status?"), findsOneWidget);
    expect(alert.proximity, 1);
  });

  testWidgets('answering the prompt votes and closes the card', (tester) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')]);
    await _pump(tester, location: loc, repo: repo);

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();
    expect(find.textContaining('APPROACHING'), findsOneWidget);

    await tester.tap(find.text('Open/Working'));
    await tester.pumpAndSettle();

    expect(repo.votes, [('marulan', SiteStatus.open)]);
    expect(find.textContaining('APPROACHING'), findsNothing);
    expect(find.textContaining('Reported Open/Working'), findsOneWidget);
  });

  testWidgets('a site with no recent report says so', (tester) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')]);
    await _pump(tester, location: loc, repo: repo);

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();

    expect(find.text('No recent reports — what do you see?'), findsOneWidget);
  });

  testWidgets('dismissing closes the card without voting', (tester) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')]);
    await _pump(tester, location: loc, repo: repo);

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(repo.votes, isEmpty);
    expect(find.textContaining('APPROACHING'), findsNothing);
  });

  testWidgets('an unanswered prompt clears itself', (tester) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')]);
    await _pump(tester, location: loc, repo: repo);

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();
    expect(find.textContaining('APPROACHING'), findsOneWidget);

    await tester.pump(proximityPromptTimeout + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('APPROACHING'), findsNothing);
  });

  testWidgets('a rejected vote still closes the card and explains itself', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')])
      ..voteError = Exception('offline');
    await _pump(tester, location: loc, repo: repo);

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();

    await tester.tap(find.text('Blitz'));
    await tester.pumpAndSettle();

    expect(find.textContaining('APPROACHING'), findsNothing);
    expect(find.textContaining('Could not submit'), findsOneWidget);
  });

  testWidgets('with the feature off no prompt appears', (tester) async {
    final loc = FakeLocationSource();
    final alert = FakeAlertPlayer();
    final repo = FakeSiteRepository([_site('marulan')]);
    final store = FakeStore()..proximityEnabled = false;
    await _pump(tester, location: loc, repo: repo, alert: alert, store: store);

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();

    expect(find.textContaining('APPROACHING'), findsNothing);
    expect(alert.proximity, 0);
  });

  testWidgets('the toggle persists the choice and clears a live prompt', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')]);
    final store = FakeStore();
    final container = await _pump(
      tester,
      location: loc,
      repo: repo,
      store: store,
    );

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();
    expect(find.textContaining('APPROACHING'), findsOneWidget);

    container.read(proximityEnabledProvider.notifier).toggle();
    await tester.pumpAndSettle();

    expect(container.read(proximityEnabledProvider), isFalse);
    expect(store.savedProximity, isFalse);
    expect(find.textContaining('APPROACHING'), findsNothing);
  });
}
