/// Point-to-point (average speed) camera expected travel times.
///
/// Pure Dart (no Flutter imports) so it stays fast to unit-test. The data
/// ships as `assets/camera_times.csv` (Route, Segment, Distance_km,
/// Slow_zone_km, Slow_zone_speed_kph, Expected_Time, Expected_Seconds);
/// [parseCameraTimesCsv] turns it into routes and [groupCorridors] pairs the
/// two directions of each run into one corridor for the UI.
library;

/// One camera-to-camera leg of a route.
class CameraLeg {
  const CameraLeg({
    required this.from,
    required this.to,
    required this.distanceKm,
    required this.expectedSeconds,
    this.slowZoneKm,
    this.slowZoneSpeedKph,
  });

  final String from;
  final String to;
  final int distanceKm;

  /// Minimum legal travel time between the two camera points.
  final int expectedSeconds;

  /// Reduced-speed stretch inside the leg, when the source data has one.
  final int? slowZoneKm;
  final int? slowZoneSpeedKph;

  String get title => '$from → $to';
}

/// One direction of a run, e.g. "Sydney - Melbourne".
class CameraRoute {
  const CameraRoute({
    required this.origin,
    required this.destination,
    required this.legs,
    this.variant,
  });

  final String origin;
  final String destination;

  /// Highway variant when a city pair has more than one run
  /// (e.g. "Coast" vs "New England").
  final String? variant;
  final List<CameraLeg> legs;

  String get title => '$origin → $destination';

  int get totalKm => legs.fold(0, (sum, l) => sum + l.distanceKm);
  int get totalSeconds => legs.fold(0, (sum, l) => sum + l.expectedSeconds);

  /// The legs inside [range], in run order.
  List<CameraLeg> legsIn(LegRange range) =>
      legs.sublist(range.start, range.end + 1);

  int rangeKm(LegRange range) =>
      legsIn(range).fold(0, (sum, l) => sum + l.distanceKm);

  int rangeSeconds(LegRange range) =>
      legsIn(range).fold(0, (sum, l) => sum + l.expectedSeconds);

  /// "Marulan → Gundagai" for the selected stretch.
  String rangeTitle(LegRange range) =>
      '${legs[range.start].from} → ${legs[range.end].to}';
}

/// An inclusive range of consecutive leg indexes — the partial-run selection.
class LegRange {
  const LegRange(this.start, this.end);

  final int start;
  final int end;

  bool contains(int index) => index >= start && index <= end;
  bool get isSingle => start == end;
  int get length => end - start + 1;
}

/// Next selection after tapping leg [tapped]: first tap starts a range, a tap
/// outside extends it to the tapped leg, a tap inside restarts from that leg,
/// and re-tapping a lone selected leg clears it. Selections therefore stay
/// consecutive by construction.
LegRange? nextLegSelection(LegRange? current, int tapped) {
  if (current == null) return LegRange(tapped, tapped);
  if (tapped < current.start) return LegRange(tapped, current.end);
  if (tapped > current.end) return LegRange(current.start, tapped);
  if (current.isSingle) return null;
  return LegRange(tapped, tapped);
}

/// Seconds left before passing the end camera is legal (0 = clear to pass:
/// the elapsed time already meets the expected minimum).
int legalWaitSeconds({
  required int expectedSeconds,
  required int elapsedSeconds,
}) => (expectedSeconds - elapsedSeconds).clamp(0, expectedSeconds);

/// The highest whole-trip average that still passes the cameras.
double maxLegalAvgKmh({
  required int distanceKm,
  required int expectedSeconds,
}) => expectedSeconds <= 0 ? 0 : distanceKm / (expectedSeconds / 3600);

/// Average speed over a timing session, or null when it can't be computed
/// (no time elapsed, or the odometer baseline was reset mid-session).
double? sessionAvgKmh({required double distanceKm, required Duration elapsed}) {
  final hours = elapsed.inMicroseconds / Duration.microsecondsPerHour;
  if (hours <= 0 || distanceKm < 0) return null;
  return distanceKm / hours;
}

/// A city pair (plus variant): both directions of the same run.
class CameraCorridor {
  const CameraCorridor({required this.directions});

  /// 1–2 routes in CSV order (forward first).
  final List<CameraRoute> directions;

  CameraRoute get forward => directions.first;

  String get title {
    final f = forward;
    final variant = f.variant == null ? '' : ' (${f.variant})';
    return '${f.origin} ↔ ${f.destination}$variant';
  }

  /// URL-safe id, e.g. "sydney-brisbane-coast".
  String get slug {
    final f = forward;
    final raw = [
      f.origin,
      f.destination,
      if (f.variant != null) f.variant!,
    ].join(' ');
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

/// Parses the bundled CSV into routes (one per direction, CSV order kept).
///
/// The file is trusted build-time data: no quoting/escaping is used, so a
/// plain comma split is safe. Malformed lines throw [FormatException] to
/// fail tests loudly rather than silently dropping legs.
List<CameraRoute> parseCameraTimesCsv(String csv) {
  final lines = csv
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return const [];

  // Keyed by route name, insertion-ordered so CSV order is preserved.
  final legsByRoute = <String, List<CameraLeg>>{};
  for (final line in lines.skip(1)) {
    final cells = line.split(',');
    if (cells.length != 7) {
      throw FormatException('Bad camera-times row: $line');
    }
    final segment = cells[1].split(' - ');
    if (segment.length != 2) {
      throw FormatException('Bad segment name: ${cells[1]}');
    }
    legsByRoute
        .putIfAbsent(cells[0], () => [])
        .add(
          CameraLeg(
            from: segment[0],
            to: segment[1],
            distanceKm: int.parse(cells[2]),
            slowZoneKm: cells[3].isEmpty ? null : int.parse(cells[3]),
            slowZoneSpeedKph: cells[4].isEmpty ? null : int.parse(cells[4]),
            expectedSeconds: int.parse(cells[6]),
          ),
        );
  }

  return [
    for (final entry in legsByRoute.entries)
      _routeFromName(entry.key, entry.value),
  ];
}

CameraRoute _routeFromName(String name, List<CameraLeg> legs) {
  var base = name;
  String? variant;
  final variantMatch = RegExp(r'^(.*?)\s*\((.+)\)$').firstMatch(name);
  if (variantMatch != null) {
    base = variantMatch.group(1)!;
    variant = variantMatch.group(2);
  }
  final ends = base.split(' - ');
  if (ends.length != 2) {
    throw FormatException('Bad route name: $name');
  }
  return CameraRoute(
    origin: ends[0],
    destination: ends[1],
    variant: variant,
    legs: legs,
  );
}

/// Pairs the two directions of each run (same city pair + variant) into a
/// corridor, keeping CSV order for both corridors and directions.
List<CameraCorridor> groupCorridors(List<CameraRoute> routes) {
  final byKey = <String, List<CameraRoute>>{};
  for (final route in routes) {
    final cities = [route.origin, route.destination]..sort();
    final key = '${cities.join('|')}|${route.variant ?? ''}';
    byKey.putIfAbsent(key, () => []).add(route);
  }
  return [
    for (final directions in byKey.values)
      CameraCorridor(directions: directions),
  ];
}

/// "3276 → 54m 36s", "9900 → 2h 45m", "540 → 9m" (zero trailing units drop).
String formatCameraDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final parts = [
    if (h > 0) '${h}h',
    if (m > 0 || (h > 0 && s > 0)) '${m}m',
    if (s > 0) '${s}s',
  ];
  return parts.isEmpty ? '0m' : parts.join(' ');
}
