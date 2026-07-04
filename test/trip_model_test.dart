import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/trip.dart';

void main() {
  group('Trip', () {
    test('round-trips through toMap / fromMap', () {
      final trip = Trip(
        id: 'trip-1',
        startedAt: DateTime(2026, 7, 4, 9, 33),
        duration: const Duration(minutes: 3, seconds: 10),
        distanceKm: 5.03,
        maxSpeedKmh: 104,
        avgSpeedKmh: 94,
      );

      final restored = Trip.fromMap(trip.toMap());

      expect(restored.id, 'trip-1');
      expect(restored.startedAt, DateTime(2026, 7, 4, 9, 33));
      expect(restored.duration, const Duration(minutes: 3, seconds: 10));
      expect(restored.distanceKm, closeTo(5.03, 0.001));
      expect(restored.maxSpeedKmh, closeTo(104, 0.001));
      expect(restored.avgSpeedKmh, closeTo(94, 0.001));
    });

    test('fromMap tolerates missing/malformed fields', () {
      final trip = Trip.fromMap({'id': 'x'});
      expect(trip.id, 'x');
      expect(trip.duration, Duration.zero);
      expect(trip.distanceKm, 0);
      expect(trip.maxSpeedKmh, 0);
      expect(trip.avgSpeedKmh, 0);
    });
  });
}
