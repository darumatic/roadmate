/// A completed, saved trip summary (produced by "Stop & Save Trip"). Persisted
/// locally on the device — see `TripHistoryStore`. Pure/serialisable so it can
/// be unit-tested without storage.
class Trip {
  const Trip({
    required this.id,
    required this.startedAt,
    required this.duration,
    required this.distanceKm,
    required this.maxSpeedKmh,
    required this.avgSpeedKmh,
  });

  final String id;
  final DateTime startedAt;
  final Duration duration;
  final double distanceKm;
  final double maxSpeedKmh;
  final double avgSpeedKmh;

  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      id: map['id'] as String,
      startedAt:
          DateTime.tryParse(map['startedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      duration: Duration(seconds: (map['durationSeconds'] as num?)?.toInt() ?? 0),
      distanceKm: (map['distanceKm'] as num?)?.toDouble() ?? 0,
      maxSpeedKmh: (map['maxSpeedKmh'] as num?)?.toDouble() ?? 0,
      avgSpeedKmh: (map['avgSpeedKmh'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startedAt': startedAt.toIso8601String(),
      'durationSeconds': duration.inSeconds,
      'distanceKm': distanceKm,
      'maxSpeedKmh': maxSpeedKmh,
      'avgSpeedKmh': avgSpeedKmh,
    };
  }
}
