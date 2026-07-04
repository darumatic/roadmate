import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/trip_stats.dart';

// Fixed start; 0.01 deg of latitude is ~1.1119 km (haversine, R=6371).
final _t0 = DateTime(2026, 7, 4, 8, 0, 0);

TripSample _sample(
  double lat,
  double lng,
  Duration since, {
  double? speedMps,
}) => TripSample(
  lat: lat,
  lng: lng,
  timestamp: _t0.add(since),
  speedMps: speedMps,
);

/// Folds a sequence of samples through the accumulator.
TripStats _fold(List<TripSample> samples) {
  var stats = const TripStats.initial();
  for (final s in samples) {
    stats = stats.addSample(s);
  }
  return stats;
}

void main() {
  group('TripStats.initial', () {
    test('is empty and safe to read before any sample', () {
      const stats = TripStats.initial();
      expect(stats.hasStarted, isFalse);
      expect(stats.distanceKm, 0);
      expect(stats.maxSpeedKmh, 0);
      expect(stats.currentSpeedKmh, 0);
      expect(stats.duration, Duration.zero);
      expect(stats.avgSpeedKmh, 0); // zero-duration guard
    });
  });

  group('addSample', () {
    test('first sample seeds start with no distance, speed or duration', () {
      final stats = _fold([_sample(-33.0, 151.0, Duration.zero, speedMps: 5)]);
      expect(stats.hasStarted, isTrue);
      expect(stats.distanceKm, 0);
      expect(stats.maxSpeedKmh, 0);
      expect(stats.currentSpeedKmh, 0);
      expect(stats.duration, Duration.zero);
      expect(stats.avgSpeedKmh, 0);
    });

    test('accumulates leg distance between consecutive fixes', () {
      final stats = _fold([
        _sample(-33.00, 151.0, Duration.zero),
        _sample(-33.01, 151.0, const Duration(seconds: 60)),
        _sample(-33.02, 151.0, const Duration(seconds: 120)),
      ]);
      expect(stats.distanceKm, closeTo(2.224, 0.02));
    });

    test('duration spans first to most recent fix', () {
      final stats = _fold([
        _sample(-33.0, 151.0, Duration.zero),
        _sample(-33.01, 151.0, const Duration(seconds: 90)),
      ]);
      expect(stats.duration, const Duration(seconds: 90));
    });

    test('max speed uses GPS speed; current tracks the latest reading', () {
      final stats = _fold([
        _sample(-33.00, 151.0, Duration.zero, speedMps: 0),
        _sample(-33.01, 151.0, const Duration(seconds: 60), speedMps: 25), // 90
        _sample(-33.02, 151.0, const Duration(seconds: 120), speedMps: 10), // 36
      ]);
      expect(stats.maxSpeedKmh, closeTo(90, 0.01));
      expect(stats.currentSpeedKmh, closeTo(36, 0.01));
    });

    test('derives speed from distance and time when GPS speed is absent', () {
      // 0.01 deg (~1.1119 km) in 60 s -> ~66.7 km/h.
      final stats = _fold([
        _sample(-33.00, 151.0, Duration.zero),
        _sample(-33.01, 151.0, const Duration(seconds: 60)),
      ]);
      expect(stats.currentSpeedKmh, closeTo(66.7, 0.5));
      expect(stats.maxSpeedKmh, closeTo(66.7, 0.5));
    });

    test('implausible GPS spikes are ignored for max speed', () {
      final stats = _fold([
        _sample(-33.00, 151.0, Duration.zero, speedMps: 0),
        _sample(-33.01, 151.0, const Duration(seconds: 60), speedMps: 25), // 90
        _sample(
          -33.02,
          151.0,
          const Duration(seconds: 120),
          speedMps: 100,
        ), // 360 km/h spike
      ]);
      expect(stats.maxSpeedKmh, closeTo(90, 0.01)); // spike rejected
      expect(stats.currentSpeedKmh, closeTo(360, 0.01)); // but shown live
    });

    test('average is total distance over total time, including stops', () {
      // Move one leg, then sit still for a second leg.
      final stats = _fold([
        _sample(-33.00, 151.0, Duration.zero),
        _sample(-33.01, 151.0, const Duration(seconds: 60)), // ~1.112 km
        _sample(-33.01, 151.0, const Duration(seconds: 120)), // stopped
      ]);
      // ~1.112 km over 120 s -> ~33.4 km/h.
      expect(stats.distanceKm, closeTo(1.112, 0.02));
      expect(stats.avgSpeedKmh, closeTo(33.4, 0.5));
    });

    test('a stationary trip reports zero speed but valid duration', () {
      final stats = _fold([
        _sample(-33.0, 151.0, Duration.zero, speedMps: 0),
        _sample(-33.0, 151.0, const Duration(seconds: 30), speedMps: 0),
      ]);
      expect(stats.distanceKm, closeTo(0, 0.001));
      expect(stats.currentSpeedKmh, 0);
      expect(stats.maxSpeedKmh, 0);
      expect(stats.avgSpeedKmh, closeTo(0, 0.001));
      expect(stats.duration, const Duration(seconds: 30));
    });
  });
}
