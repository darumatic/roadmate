import 'geo.dart' as geo;

/// Average speed (km/h) for [distanceKm] covered over [elapsed]. Zero when no
/// time (or negative time) has passed, so a degenerate clock can't produce an
/// infinite readout.
double avgKmhOver({required double distanceKm, required Duration elapsed}) {
  final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  if (seconds <= 0) return 0;
  return distanceKm / (seconds / 3600.0);
}

/// The running trip clock: "0m 7s", "12m 30s", "2h 5m". Counts wall-clock time
/// since the driver pressed Start — never GPS-fix time, which stands still
/// while the vehicle is parked or the sky is blocked.
String formatTripElapsed(Duration d) {
  if (d.isNegative) return '0m 0s';
  final h = d.inHours;
  if (h > 0) return '${h}h ${d.inMinutes.remainder(60)}m';
  return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
}

/// A single GPS fix fed into the trip accumulator. Kept Flutter/plugin-free so
/// the trip maths can be unit-tested without a device (see the repo's pure-logic
/// convention). [speedMps] is the platform GPS speed in metres/second when
/// available (geolocator's `Position.speed`), or null to derive speed from the
/// distance and time between consecutive fixes.
class TripSample {
  const TripSample({
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.speedMps,
  });

  final double lat;
  final double lng;
  final DateTime timestamp;
  final double? speedMps;
}

/// Immutable trip accumulator: current / max / average speed, distance and
/// duration since the trip started. Pure — [addSample] returns a new [TripStats]
/// rather than mutating, and holds only running totals (not the full point
/// history) so multi-hour trips stay bounded. Reuses [distanceKm] for leg
/// distances. Speeds are in km/h; distance in km.
class TripStats {
  const TripStats({
    this.startTime,
    this.lastTime,
    this.distanceKm = 0,
    this.maxSpeedKmh = 0,
    this.currentSpeedKmh = 0,
    this.lastLat,
    this.lastLng,
  });

  /// A fresh trip with no samples yet.
  const TripStats.initial() : this();

  /// GPS readings above this are treated as spikes and ignored for max speed
  /// (a heavy vehicle won't legitimately exceed this on Australian roads).
  static const double maxPlausibleKmh = 200.0;

  final DateTime? startTime;
  final DateTime? lastTime;
  final double distanceKm;
  final double maxSpeedKmh;
  final double currentSpeedKmh;

  /// Coordinates of the last accepted fix, used to measure the next leg.
  final double? lastLat;
  final double? lastLng;

  /// Whether any sample has been recorded.
  bool get hasStarted => startTime != null;

  /// Wall-clock time between the first and most recent fix.
  Duration get duration => (startTime == null || lastTime == null)
      ? Duration.zero
      : lastTime!.difference(startTime!);

  /// Total distance divided by total elapsed time (trip-computer average;
  /// includes time spent stopped). Zero until time has elapsed.
  double get avgSpeedKmh =>
      avgKmhOver(distanceKm: distanceKm, elapsed: duration);

  /// Folds [s] into the trip and returns the updated stats. The first sample
  /// only seeds the start position/time (no distance or speed yet).
  TripStats addSample(TripSample s) {
    if (startTime == null) {
      return TripStats(
        startTime: s.timestamp,
        lastTime: s.timestamp,
        lastLat: s.lat,
        lastLng: s.lng,
      );
    }

    final legKm = geo.distanceKm(lastLat!, lastLng!, s.lat, s.lng);
    final legSeconds =
        s.timestamp.difference(lastTime!).inMicroseconds /
        Duration.microsecondsPerSecond;

    // Instantaneous speed: prefer the GPS-reported value; otherwise derive it
    // from how far we moved since the last fix.
    double instantKmh;
    if (s.speedMps != null && s.speedMps! >= 0) {
      instantKmh = s.speedMps! * 3.6;
    } else if (legSeconds > 0) {
      instantKmh = legKm / (legSeconds / 3600.0);
    } else {
      instantKmh = 0;
    }

    final newMax = (instantKmh <= maxPlausibleKmh && instantKmh > maxSpeedKmh)
        ? instantKmh
        : maxSpeedKmh;

    return TripStats(
      startTime: startTime,
      lastTime: s.timestamp,
      distanceKm: distanceKm + legKm,
      maxSpeedKmh: newMax,
      currentSpeedKmh: instantKmh,
      lastLat: s.lat,
      lastLng: s.lng,
    );
  }
}
