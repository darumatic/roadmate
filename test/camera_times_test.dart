import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });

  group('camera pages', () {
    final corridors = groupCorridors(
      parseCameraTimesCsv(
        File('assets/camera_times.csv').readAsStringSync(),
      ),
    );

    Widget host(Widget child) => MaterialApp(
          theme: AppTheme.dark,
          home: child,
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
  });
}
