import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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
import 'package:roadmate/services/auth_service.dart';
import 'package:roadmate/services/location_source.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/proximity_notifier.dart';
import 'package:roadmate/services/participation_logic.dart';
import 'package:roadmate/services/site_repository.dart';
import 'package:roadmate/services/trip_history_store.dart';

class FakeLocationSource implements LocationSource {
  final controller = StreamController<Position>.broadcast();

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Stream<Position> positions() => controller.stream;

  @override
  Future<Position?> currentPosition() async => null;

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
  Future<void> vote(
    Site site,
    SiteStatus status, {
    String? reporterName,
  }) async {
    if (voteError != null) throw voteError!;
    votes.add((site.id, status));
  }

  @override
  Future<void> addSite(
    Site site, {
    bool approved = false,
    String? submitterName,
  }) async {}
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
  Stream<Set<String>> watchFavourites() => Stream.value(const {});

  @override
  Stream<ParticipationStats?> watchMyStats() => Stream.value(null);
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

/// Just enough User for the auth overrides: all anyone asks is whether the
/// session is anonymous.
class FakeUser implements User {
  FakeUser({this.anonymous = false});

  final bool anonymous;

  @override
  bool get isAnonymous => anonymous;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Just enough FirebaseAuth for the provider override: the restored session.
class FakeFirebaseAuth implements FirebaseAuth {
  FakeFirebaseAuth(this.current);

  final User? current;

  @override
  User? get currentUser => current;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Mounts the speedometer (which owns the GPS stream) under the same
/// [ProximityGate] the real app wraps its router in.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeLocationSource location,
  required FakeSiteRepository repo,
  FakeAlertPlayer? alert,
  FakeStore? store,
  // Posting is account-free (the proximity gate is what guards it), but the
  // auth providers still need a session to hand out.
  User? user,
}) async {
  final signedInUser = user ?? FakeUser();
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
        firebaseAuthProvider.overrideWithValue(FakeFirebaseAuth(signedInUser)),
        authStateProvider.overrideWith((ref) => Stream.value(signedInUser)),
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

  testWidgets('an unanswered prompt stays put, counting down the distance', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')]);
    await _pump(tester, location: loc, repo: repo);

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();
    expect(find.textContaining('2.2 km ahead'), findsOneWidget);

    // Minutes of driving later it is still there — nothing but the driver (or
    // the site going behind them) takes it off screen.
    await tester.pump(const Duration(minutes: 5));
    loc.emit(_pos(-33.008, since: const Duration(minutes: 5)));
    await tester.pump();
    await tester.pump(); // the fix lands, then the card redraws
    expect(find.textContaining('890 m ahead'), findsOneWidget);
  });

  testWidgets('the prompt retires itself once the site is behind you', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')]);
    await _pump(tester, location: loc, repo: repo);

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();
    loc.emit(_pos(-33.0008, since: const Duration(minutes: 1)));
    await tester.pump();
    expect(find.textContaining('APPROACHING'), findsOneWidget);

    // Past the gate and pulling away: the question is moot.
    loc.emit(_pos(-32.9975, since: const Duration(minutes: 2)));
    await tester.pump();
    expect(find.textContaining('APPROACHING'), findsNothing);
    expect(repo.votes, isEmpty);
  });

  testWidgets('a dismissed prompt asks once more from close range', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final alert = FakeAlertPlayer();
    final repo = FakeSiteRepository([_site('marulan')]);
    await _pump(tester, location: loc, repo: repo, alert: alert);

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('APPROACHING'), findsNothing);

    // Halfway there: still quiet.
    loc.emit(_pos(-33.01, since: const Duration(minutes: 1)));
    await tester.pump();
    expect(find.textContaining('APPROACHING'), findsNothing);

    // Inside 100 m, with the site in sight, it asks again — once.
    loc.emit(_pos(-33.0015, since: const Duration(minutes: 2)));
    await tester.pump();
    loc.emit(_pos(-33.0008, since: const Duration(seconds: 122)));
    await tester.pump();
    await tester.pump(); // the fix lands, then the card redraws
    expect(find.textContaining('89 m ahead'), findsOneWidget);
    expect(alert.proximity, 2);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    loc.emit(_pos(-33.0004, since: const Duration(seconds: 124)));
    await tester.pump();
    expect(find.textContaining('APPROACHING'), findsNothing);
  });

  testWidgets('an answered prompt is not asked again from close range', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')]);
    await _pump(tester, location: loc, repo: repo);

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();
    await tester.tap(find.text('Closed'));
    await tester.pumpAndSettle();
    expect(repo.votes, [('marulan', SiteStatus.closed)]);

    loc.emit(_pos(-33.0015, since: const Duration(minutes: 2)));
    await tester.pump();
    loc.emit(_pos(-33.0008, since: const Duration(seconds: 122)));
    await tester.pump();

    expect(find.textContaining('APPROACHING'), findsNothing);
    expect(repo.votes, hasLength(1));
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

  // Posting is account-free: the prompt only exists because GPS put the
  // truck within the report radius, so an anonymous answer goes straight in.
  testWidgets('an anonymous driver votes straight from the prompt', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')]);
    await _pump(
      tester,
      location: loc,
      repo: repo,
      user: FakeUser(anonymous: true),
    );

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();

    await tester.tap(find.text('Blitz'));
    await tester.pumpAndSettle();

    expect(repo.votes, [('marulan', SiteStatus.blitz)]);
    expect(find.textContaining('APPROACHING'), findsNothing);
    expect(find.textContaining('Reported Blitz'), findsOneWidget);
  });

  testWidgets('an anonymous answer from the notification is applied', (
    tester,
  ) async {
    final loc = FakeLocationSource();
    final repo = FakeSiteRepository([_site('marulan')]);
    final container = await _pump(
      tester,
      location: loc,
      repo: repo,
      user: FakeUser(anonymous: true),
    );

    loc.emit(_pos(-33.025, since: Duration.zero));
    await tester.pump();
    loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
    await tester.pump();
    expect(find.textContaining('APPROACHING'), findsOneWidget);

    await container
        .read(proximityControllerProvider.notifier)
        .answerFromNotification(
          const ProximityAnswer(siteId: 'marulan', status: SiteStatus.blitz),
        );
    await tester.pumpAndSettle();

    expect(repo.votes, [('marulan', SiteStatus.blitz)]);
    expect(find.textContaining('APPROACHING'), findsNothing);
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
