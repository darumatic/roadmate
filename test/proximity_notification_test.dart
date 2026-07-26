import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:roadmate/features/proximity/proximity_controller.dart';
import 'package:roadmate/features/proximity/proximity_prompt_card.dart';
import 'package:roadmate/features/proximity/proximity_text.dart';
import 'package:roadmate/features/speedometer/speedometer_panel.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/proximity_notifier.dart';

import 'proximity_prompt_test.dart'
    show FakeAlertPlayer, FakeLocationSource, FakeSiteRepository, FakeStore;

class RecordingNotifier implements ProximityNotifier {
  final shown = <(String, String, double, String)>[];
  int cancels = 0;
  void Function(ProximityAnswer)? onAnswer;

  @override
  Future<void> initialise(void Function(ProximityAnswer) onAnswer) async {
    this.onAnswer = onAnswer;
  }

  @override
  Future<void> showApproach({
    required String siteId,
    required String siteName,
    required double km,
    required String body,
  }) async => shown.add((siteId, siteName, km, body));

  @override
  Future<void> cancel() async => cancels++;
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
      speed: speed,
      speedAccuracy: 0,
    );

Site _site({SiteStatus status = SiteStatus.unknown, DateTime? lastReportAt}) =>
    Site(
      id: 'marulan',
      name: 'Marulan',
      type: SiteType.checkingStation,
      state: AusState.nsw,
      suburb: 'Marulan',
      address: 'Hume Hwy',
      lat: -33.0,
      lng: 151.0,
      currentStatus: status,
      lastReportAt: lastReportAt,
    );

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeLocationSource location,
  required FakeSiteRepository repo,
  required RecordingNotifier notifier,
  FakeAlertPlayer? alert,
}) async {
  addTearDown(location.controller.close);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(900, 1600));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationSourceProvider.overrideWithValue(location),
        alertPlayerProvider.overrideWithValue(alert ?? FakeAlertPlayer()),
        tripHistoryStoreProvider.overrideWithValue(FakeStore()),
        siteRepositoryProvider.overrideWithValue(repo),
        proximityNotifierProvider.overrideWithValue(notifier),
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

/// Drives two fixes past the site so a prompt is raised.
Future<void> _approach(WidgetTester tester, FakeLocationSource loc) async {
  loc.emit(_pos(-33.025, since: Duration.zero));
  await tester.pump();
  loc.emit(_pos(-33.02, since: const Duration(seconds: 20)));
  await tester.pump();
}

void main() {
  group('notification text', () {
    test('title carries the site and how far ahead it is', () {
      expect(
        proximityNotificationTitle('Marulan', 2.42),
        'Marulan · 2.4 km ahead',
      );
      expect(
        proximityNotificationTitle('Marulan', 0.4),
        'Marulan · 400 m ahead',
      );
    });

    test('body reports the live status or asks for one', () {
      final now = DateTime(2026, 7, 26, 9, 0);
      expect(
        approachStatusLine(
          _site(
            status: SiteStatus.blitz,
            lastReportAt: now.subtract(const Duration(minutes: 20)),
          ),
          now: now,
        ),
        'Reported Blitz 20m ago',
      );
      expect(
        approachStatusLine(_site(), now: now),
        'No recent reports — what do you see?',
      );
    });

    test('action ids map to the vote they cast', () {
      expect(statusFromActionId('vote_open'), SiteStatus.open);
      expect(statusFromActionId('vote_blitz'), SiteStatus.blitz);
      expect(statusFromActionId('vote_closed'), SiteStatus.closed);
      // A plain tap on the notification body carries no action.
      expect(statusFromActionId(null), isNull);
      expect(statusFromActionId('something_else'), isNull);
    });
  });

  group('background behaviour', () {
    testWidgets('off screen, the approach becomes a notification, not a beep', (
      tester,
    ) async {
      final loc = FakeLocationSource();
      final alert = FakeAlertPlayer();
      final notifier = RecordingNotifier();
      final repo = FakeSiteRepository([
        _site(status: SiteStatus.blitz, lastReportAt: DateTime.now()),
      ]);
      final container = await _pump(
        tester,
        location: loc,
        repo: repo,
        notifier: notifier,
        alert: alert,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await _approach(tester, loc);

      expect(notifier.shown, hasLength(1));
      final (siteId, siteName, km, body) = notifier.shown.single;
      expect(siteId, 'marulan');
      expect(siteName, 'Marulan');
      expect(km, closeTo(2.22, 0.1));
      expect(body, startsWith('Reported Blitz'));
      // No sound: nobody is looking, and the notification makes its own noise.
      expect(alert.proximity, 0);
      // The prompt is still pending, waiting on screen for the driver.
      expect(container.read(proximityControllerProvider), isNotNull);
    });

    testWidgets('returning to the app shows the card and clears the '
        'notification', (tester) async {
      final loc = FakeLocationSource();
      final notifier = RecordingNotifier();
      final repo = FakeSiteRepository([_site()]);
      await _pump(tester, location: loc, repo: repo, notifier: notifier);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await _approach(tester, loc);
      expect(notifier.shown, hasLength(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(notifier.cancels, greaterThan(0));
      expect(find.textContaining('APPROACHING'), findsOneWidget);
    });

    testWidgets('a prompt raised in the background does not expire unseen', (
      tester,
    ) async {
      final loc = FakeLocationSource();
      final notifier = RecordingNotifier();
      final repo = FakeSiteRepository([_site()]);
      final container = await _pump(
        tester,
        location: loc,
        repo: repo,
        notifier: notifier,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await _approach(tester, loc);

      // Well past the on-screen timeout, but the app was never on screen.
      await tester.pump(proximityPromptTimeout * 3);
      expect(container.read(proximityControllerProvider), isNotNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.textContaining('APPROACHING'), findsOneWidget);

      // The countdown starts from the moment they came back.
      await tester.pump(proximityPromptTimeout + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.textContaining('APPROACHING'), findsNothing);
    });

    testWidgets('a vote action on the notification casts the vote', (
      tester,
    ) async {
      final loc = FakeLocationSource();
      final notifier = RecordingNotifier();
      final repo = FakeSiteRepository([_site()]);
      final container = await _pump(
        tester,
        location: loc,
        repo: repo,
        notifier: notifier,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await _approach(tester, loc);

      notifier.onAnswer!(
        const ProximityAnswer(siteId: 'marulan', status: SiteStatus.blitz),
      );
      await tester.pumpAndSettle();

      expect(repo.votes, [('marulan', SiteStatus.blitz)]);
      // Answered — nothing left pending, and the notification is gone.
      expect(container.read(proximityControllerProvider), isNull);
      expect(notifier.cancels, greaterThan(0));
    });

    testWidgets('tapping the notification body leaves the card to answer', (
      tester,
    ) async {
      final loc = FakeLocationSource();
      final notifier = RecordingNotifier();
      final repo = FakeSiteRepository([_site()]);
      final container = await _pump(
        tester,
        location: loc,
        repo: repo,
        notifier: notifier,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await _approach(tester, loc);

      notifier.onAnswer!(const ProximityAnswer(siteId: 'marulan'));
      await tester.pumpAndSettle();

      expect(repo.votes, isEmpty);
      expect(container.read(proximityControllerProvider), isNotNull);
    });

    testWidgets('a failed notification vote is swallowed, not crashed on', (
      tester,
    ) async {
      final loc = FakeLocationSource();
      final notifier = RecordingNotifier();
      final repo = FakeSiteRepository([_site()])
        ..voteError = Exception('offline');
      await _pump(tester, location: loc, repo: repo, notifier: notifier);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await _approach(tester, loc);

      notifier.onAnswer!(
        const ProximityAnswer(siteId: 'marulan', status: SiteStatus.open),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('answering in the app clears any notification', (tester) async {
      final loc = FakeLocationSource();
      final notifier = RecordingNotifier();
      final repo = FakeSiteRepository([_site()]);
      await _pump(tester, location: loc, repo: repo, notifier: notifier);

      await _approach(tester, loc);
      final before = notifier.cancels;
      await tester.tap(find.text('Open/Working'));
      await tester.pumpAndSettle();

      expect(repo.votes, [('marulan', SiteStatus.open)]);
      expect(notifier.cancels, greaterThan(before));
    });
  });
}
