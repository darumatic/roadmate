import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/features/info/camera_timer.dart';
import 'package:roadmate/features/info/camera_times_page.dart';
import 'package:roadmate/services/camera_times.dart';
import 'package:roadmate/theme/app_theme.dart';

const _sampleCsv = '''
Route,Segment,Distance_km,Slow_zone_km,Slow_zone_speed_kph,Expected_Time,Expected_Seconds
Sydney - Melbourne,Douglas Park - Marulan,91,,,54m 36s,3276
Sydney - Melbourne,Marulan - One Tree,115,,,1h 9m 0s,4140
Melbourne - Sydney,One Tree - Marulan,115,,,1h 9m 0s,4140
Sydney - Brisbane (Coast),Mt White - Nabiac,227,16,60,2h 22m 36s,8556
''';

void main() {
  group('parseCameraTimesCsv', () {
    test('parses legs with from/to, distance and expected seconds', () {
      final routes = parseCameraTimesCsv(_sampleCsv);
      expect(routes, hasLength(3));

      final sydMel = routes.first;
      expect(sydMel.origin, 'Sydney');
      expect(sydMel.destination, 'Melbourne');
      expect(sydMel.variant, isNull);
      expect(sydMel.title, 'Sydney → Melbourne');
      expect(sydMel.legs, hasLength(2));

      final leg = sydMel.legs.first;
      expect(leg.from, 'Douglas Park');
      expect(leg.to, 'Marulan');
      expect(leg.title, 'Douglas Park → Marulan');
      expect(leg.distanceKm, 91);
      expect(leg.expectedSeconds, 3276);
      expect(leg.slowZoneKm, isNull);
      expect(leg.slowZoneSpeedKph, isNull);
    });

    test('parses highway variant and slow zones', () {
      final routes = parseCameraTimesCsv(_sampleCsv);
      final coast = routes.last;
      expect(coast.origin, 'Sydney');
      expect(coast.destination, 'Brisbane');
      expect(coast.variant, 'Coast');
      expect(coast.legs.single.slowZoneKm, 16);
      expect(coast.legs.single.slowZoneSpeedKph, 60);
    });

    test('route totals sum the legs', () {
      final sydMel = parseCameraTimesCsv(_sampleCsv).first;
      expect(sydMel.totalKm, 91 + 115);
      expect(sydMel.totalSeconds, 3276 + 4140);
    });

    test('throws on malformed rows', () {
      expect(
        () => parseCameraTimesCsv('Route,Segment\nbad,row'),
        throwsFormatException,
      );
    });
  });

  group('groupCorridors', () {
    test('pairs the two directions of a run, forward first', () {
      final corridors = groupCorridors(parseCameraTimesCsv(_sampleCsv));
      expect(corridors, hasLength(2));

      final sydMel = corridors.first;
      expect(sydMel.title, 'Sydney ↔ Melbourne');
      expect(sydMel.slug, 'sydney-melbourne');
      expect(sydMel.directions, hasLength(2));
      expect(sydMel.forward.title, 'Sydney → Melbourne');
      expect(sydMel.directions[1].title, 'Melbourne → Sydney');

      final coast = corridors.last;
      expect(coast.title, 'Sydney ↔ Brisbane (Coast)');
      expect(coast.slug, 'sydney-brisbane-coast');
      expect(coast.directions, hasLength(1));
    });
  });

  group('nextLegSelection', () {
    test('first tap starts a single-leg range', () {
      final r = nextLegSelection(null, 2)!;
      expect((r.start, r.end), (2, 2));
    });

    test('tapping outside extends the range either way', () {
      var r = nextLegSelection(const LegRange(2, 2), 4)!;
      expect((r.start, r.end), (2, 4));
      r = nextLegSelection(r, 0)!;
      expect((r.start, r.end), (0, 4));
    });

    test('tapping inside a multi-leg range restarts from that leg', () {
      final r = nextLegSelection(const LegRange(0, 4), 2)!;
      expect((r.start, r.end), (2, 2));
    });

    test('re-tapping a lone selected leg clears the selection', () {
      expect(nextLegSelection(const LegRange(3, 3), 3), isNull);
    });
  });

  group('range totals', () {
    final route = parseCameraTimesCsv(_sampleCsv).first; // Sydney - Melbourne

    test('sums distance and time over the selected legs', () {
      const range = LegRange(0, 1);
      expect(route.rangeKm(range), 91 + 115);
      expect(route.rangeSeconds(range), 3276 + 4140);
      expect(route.rangeTitle(range), 'Douglas Park → One Tree');
      expect(range.length, 2);
    });
  });

  group('time-me maths', () {
    test('legalWaitSeconds counts down and clamps at zero', () {
      expect(
        legalWaitSeconds(expectedSeconds: 3276, elapsedSeconds: 0),
        3276,
      );
      expect(
        legalWaitSeconds(expectedSeconds: 3276, elapsedSeconds: 3000),
        276,
      );
      expect(
        legalWaitSeconds(expectedSeconds: 3276, elapsedSeconds: 5000),
        0,
      );
    });

    test('maxLegalAvgKmh is distance over expected time', () {
      // 91 km in 3276 s is exactly 100 km/h.
      expect(
        maxLegalAvgKmh(distanceKm: 91, expectedSeconds: 3276),
        closeTo(100, 0.001),
      );
      expect(maxLegalAvgKmh(distanceKm: 91, expectedSeconds: 0), 0);
    });

    test('sessionAvgKmh handles zero time and reset baselines', () {
      expect(
        sessionAvgKmh(
          distanceKm: 50,
          elapsed: const Duration(minutes: 30),
        ),
        closeTo(100, 0.001),
      );
      expect(sessionAvgKmh(distanceKm: 50, elapsed: Duration.zero), isNull);
      // Odometer reset mid-session → negative distance → no average.
      expect(
        sessionAvgKmh(distanceKm: -3, elapsed: const Duration(minutes: 5)),
        isNull,
      );
    });
  });

  group('camera timer queue', () {
    test('startNext rolls through the upcoming legs, then no-ops', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final legs = parseCameraTimesCsv(_sampleCsv).first.legs; // 2 legs
      final notifier = container.read(cameraTimerProvider.notifier);

      notifier.start(
        targetTitle: 'Warm-up',
        distanceKm: 5,
        expectedSeconds: 180,
        upcoming: legs,
      );
      expect(
        container.read(cameraTimerProvider)!.nextLeg!.title,
        'Douglas Park → Marulan',
      );

      notifier.startNext();
      var session = container.read(cameraTimerProvider)!;
      expect(session.targetTitle, 'Douglas Park → Marulan');
      expect(session.distanceKm, 91);
      expect(session.expectedSeconds, 3276);
      expect(session.nextLeg!.title, 'Marulan → One Tree');

      notifier.startNext();
      session = container.read(cameraTimerProvider)!;
      expect(session.targetTitle, 'Marulan → One Tree');
      expect(session.nextLeg, isNull);

      // Nothing queued: startNext must not clear or restart the session.
      notifier.startNext();
      expect(
        container.read(cameraTimerProvider)!.targetTitle,
        'Marulan → One Tree',
      );
    });
  });

  group('formatCameraDuration', () {
    test('drops zero units and keeps camera-relevant seconds', () {
      expect(formatCameraDuration(3276), '54m 36s');
      expect(formatCameraDuration(9900), '2h 45m');
      expect(formatCameraDuration(540), '9m');
      expect(formatCameraDuration(26352), '7h 19m 12s');
      expect(formatCameraDuration(0), '0m');
    });
  });

  group('bundled asset', () {
    final csv = File('assets/camera_times.csv').readAsStringSync();

    test('parses in full: 8 corridors, both directions each', () {
      final corridors = groupCorridors(parseCameraTimesCsv(csv));
      expect(corridors, hasLength(8));
      for (final corridor in corridors) {
        expect(
          corridor.directions,
          hasLength(2),
          reason: '${corridor.title} should have both directions',
        );
        expect(corridor.slug, matches(RegExp(r'^[a-z0-9-]+$')));
        for (final direction in corridor.directions) {
          expect(direction.legs, isNotEmpty);
        }
      }
    });

    test('known corridor totals match the source data', () {
      final corridors = groupCorridors(parseCameraTimesCsv(csv));
      final sydMel = corridors.firstWhere((c) => c.slug == 'sydney-melbourne');
      expect(sydMel.forward.totalKm, 732);
      expect(sydMel.forward.totalSeconds, 26352);
    });

    test('slugs are unique (used as URL ids)', () {
      final corridors = groupCorridors(parseCameraTimesCsv(csv));
      final slugs = corridors.map((c) => c.slug).toSet();
      expect(slugs, hasLength(corridors.length));
    });

    test('town names use the corrected spellings', () {
      expect(csv, contains('Narrandera'));
      expect(csv, contains('Coonabarabran'));
      expect(csv, isNot(contains('Narranderra')));
      expect(csv, isNot(contains('Coonabarrabran')));
    });
  });

  group('camera pages', () {
    final corridors = groupCorridors(
      parseCameraTimesCsv(
        File('assets/camera_times.csv').readAsStringSync(),
      ),
    );

    Widget host(Widget child) => ProviderScope(
          child: MaterialApp(theme: AppTheme.dark, home: child),
        );

    testWidgets('hub lists every corridor with totals', (tester) async {
      await tester.pumpWidget(host(CameraTimesPage(corridors: corridors)));
      expect(find.text('Camera Times'), findsOneWidget);
      expect(find.text('Sydney ↔ Melbourne'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Melbourne ↔ Brisbane (Newell)'),
        200,
      );
      expect(find.text('Melbourne ↔ Brisbane (Newell)'), findsOneWidget);
      // Forward totals shown as the subtitle.
      expect(find.text('732 km · 7h 19m 12s'), findsOneWidget);
    });

    testWidgets('corridor page shows legs, total and direction toggle',
        (tester) async {
      await tester.pumpWidget(
        host(
          CameraCorridorPage(slug: 'sydney-melbourne', corridors: corridors),
        ),
      );
      expect(find.text('Sydney ↔ Melbourne'), findsOneWidget);
      expect(find.text('Douglas Park → Marulan'), findsOneWidget);
      expect(find.text('54m 36s'), findsOneWidget);

      // Flip direction: reverse-run legs replace the forward ones.
      await tester.tap(find.text('To Sydney'));
      await tester.pumpAndSettle();
      expect(find.text('Wallan → Table Top'), findsOneWidget);
      expect(find.text('Douglas Park → Marulan'), findsNothing);
      await tester.scrollUntilVisible(find.text('Marulan → The Nest'), 200);
      expect(find.text('Marulan → The Nest'), findsOneWidget);
    });

    testWidgets('slow zones are noted on the leg', (tester) async {
      await tester.pumpWidget(
        host(
          CameraCorridorPage(
            slug: 'sydney-brisbane-coast',
            corridors: corridors,
          ),
        ),
      );
      expect(
        find.text('227 km · incl. 16 km @ 60 km/h'),
        findsOneWidget,
      );
    });

    testWidgets('unknown slug shows a not-found message', (tester) async {
      await tester.pumpWidget(
        host(CameraCorridorPage(slug: 'nope', corridors: corridors)),
      );
      expect(find.text('Route not found'), findsOneWidget);
    });

    testWidgets('tap-to-select sums a partial run and can time it',
        (tester) async {
      await tester.pumpWidget(
        host(
          CameraCorridorPage(slug: 'sydney-melbourne', corridors: corridors),
        ),
      );
      await tester.tap(find.text('Douglas Park → Marulan'));
      await tester.pump();
      await tester.tap(find.text('Marulan → One Tree'));
      await tester.pump();

      // The summary card sums both legs: 206 km, 7416 s.
      await tester.scrollUntilVisible(
        find.text('Douglas Park → One Tree'),
        200,
      );
      expect(find.text('2 legs · 206 km · 2h 3m 36s'), findsOneWidget);

      await tester.tap(find.text('Time me'));
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 900));
      await tester.pump();
      expect(find.text('TIMING · Douglas Park → One Tree'), findsOneWidget);
      // Countdown starts at the combined expected time.
      expect(find.text('2h 3m 36s'), findsOneWidget);
    });

    testWidgets('direction flip clears the selection', (tester) async {
      await tester.pumpWidget(
        host(
          CameraCorridorPage(slug: 'sydney-melbourne', corridors: corridors),
        ),
      );
      await tester.tap(find.text('Douglas Park → Marulan'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Time me'), 300);
      expect(find.text('Time me'), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 900));
      await tester.pump();
      await tester.tap(find.text('To Sydney'));
      await tester.pumpAndSettle();
      expect(find.text('Time me'), findsNothing);
    });

    testWidgets('full-run Time me targets the whole route', (tester) async {
      await tester.pumpWidget(
        host(
          CameraCorridorPage(slug: 'sydney-melbourne', corridors: corridors),
        ),
      );
      await tester.scrollUntilVisible(find.byTooltip('Time the full run'), 300);
      await tester.tap(find.byTooltip('Time the full run'));
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1200));
      await tester.pump();
      expect(
        find.text('TIMING · Full run · Sydney → Melbourne'),
        findsOneWidget,
      );
    });

    testWidgets('per-leg Time me starts that leg and rolls to the next',
        (tester) async {
      await tester.pumpWidget(
        host(
          CameraCorridorPage(slug: 'sydney-melbourne', corridors: corridors),
        ),
      );
      await tester.tap(find.byTooltip('Time Douglas Park → Marulan'));
      await tester.pump();

      expect(find.text('TIMING · Douglas Park → Marulan'), findsOneWidget);
      expect(find.text('Next · Marulan → One Tree'), findsOneWidget);

      // Passed the camera: jump straight to timing the next stretch.
      await tester.tap(find.text('Start next'));
      await tester.pump();
      expect(find.text('TIMING · Marulan → One Tree'), findsOneWidget);
      expect(find.text('Next · One Tree → Coolac'), findsOneWidget);
    });

    testWidgets('timer flips to Clear once the expected time has elapsed',
        (tester) async {
      await tester.pumpWidget(
        host(
          CameraCorridorPage(slug: 'sydney-melbourne', corridors: corridors),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CameraCorridorPage)),
      );
      container.read(cameraTimerProvider.notifier).start(
            targetTitle: 'Douglas Park → Marulan',
            distanceKm: 91,
            expectedSeconds: 3276,
            startedAt: DateTime.now().subtract(const Duration(hours: 2)),
          );
      await tester.pump();
      expect(find.text('Clear to pass'), findsOneWidget);

      // Stop dismisses the panel.
      await tester.tap(find.byTooltip('Stop timing'));
      await tester.pump();
      expect(find.text('Clear to pass'), findsNothing);
    });
  });
}
