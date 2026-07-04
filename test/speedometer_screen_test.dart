import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:roadmate/features/speedometer/speedometer_screen.dart';
import 'package:roadmate/services/location_source.dart';
import 'package:roadmate/services/providers.dart';

/// Fake location source: canned permission result plus a broadcast stream the
/// test drives to emit position fixes on demand.
class FakeLocationSource implements LocationSource {
  FakeLocationSource({this.granted = true});

  final bool granted;
  final controller = StreamController<Position>.broadcast();
  int ensureCalls = 0;

  @override
  Future<bool> ensurePermission() async {
    ensureCalls++;
    return granted;
  }

  @override
  Stream<Position> positions() => controller.stream;

  void emit(Position p) => controller.add(p);
}

final _t0 = DateTime(2026, 7, 4, 8, 0, 0);

Position _position(
  double lat,
  double lng, {
  required DateTime timestamp,
  double speed = 0,
}) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: timestamp,
  accuracy: 1,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
);

Future<void> _pump(WidgetTester tester, FakeLocationSource fake) async {
  addTearDown(fake.controller.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [locationSourceProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: SpeedometerScreen()),
    ),
  );
}

void main() {
  testWidgets('idle screen shows the Start Trip control', (tester) async {
    await _pump(tester, FakeLocationSource());
    expect(find.text('Start Trip'), findsOneWidget);
    expect(find.text('km/h'), findsWidgets);
  });

  testWidgets('starting a trip streams speed, max and distance', (
    tester,
  ) async {
    final fake = FakeLocationSource();
    await _pump(tester, fake);

    await tester.tap(find.text('Start Trip'));
    await tester.pumpAndSettle();
    expect(fake.ensureCalls, 1);

    // First fix seeds the start; the second (0.01 deg north, 60 s later at
    // 25 m/s) yields 90 km/h current & max and ~1.1 km distance.
    fake.emit(_position(-33.00, 151.0, timestamp: _t0, speed: 0));
    await tester.pump();
    fake.emit(
      _position(
        -33.01,
        151.0,
        timestamp: _t0.add(const Duration(seconds: 60)),
        speed: 25,
      ),
    );
    await tester.pump();

    expect(find.text('90'), findsWidgets); // current speed + MAX tile
    expect(find.text('1.1'), findsOneWidget); // DISTANCE tile
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('stopping freezes the stats and offers Reset / New Trip', (
    tester,
  ) async {
    final fake = FakeLocationSource();
    await _pump(tester, fake);

    await tester.tap(find.text('Start Trip'));
    await tester.pumpAndSettle();
    fake.emit(_position(-33.00, 151.0, timestamp: _t0, speed: 0));
    await tester.pump();
    fake.emit(
      _position(
        -33.01,
        151.0,
        timestamp: _t0.add(const Duration(seconds: 60)),
        speed: 25,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('New Trip'), findsOneWidget);
    expect(find.text('1.1'), findsOneWidget); // stats retained after stop
  });

  testWidgets('denied permission shows the location-needed message', (
    tester,
  ) async {
    await _pump(tester, FakeLocationSource(granted: false));

    await tester.tap(find.text('Start Trip'));
    await tester.pumpAndSettle();

    expect(find.text('Location needed'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });
}
