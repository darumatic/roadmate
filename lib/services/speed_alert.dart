/// Pure decision for the over-limit warning: whether to sound the alert *now*.
/// Kept out of the render/stream path so the beep logic is unit-tested and the
/// controller just acts on the boolean.
///
/// Returns true when [speedKmh] has reached [limitKmh] + [tolerance] — the
/// beep starts the instant the driver hits 1 km/h over the limit (issue #19)
/// AND either this is the first reading over the limit ([lastAlertAt] is null)
/// or at least [repeat] has elapsed since the last alert. Returns false when no
/// limit is set or the driver is within tolerance — which also lets the caller
/// clear [lastAlertAt] so the next breach re-triggers immediately (rising edge).
bool shouldAlert({
  required double speedKmh,
  required int? limitKmh,
  required DateTime now,
  DateTime? lastAlertAt,
  // Warn once the driver is 1 km/h past the limit (issues #11, #19).
  double tolerance = 1.0,
  // Beep every second while the driver stays over the limit (issue #6).
  Duration repeat = const Duration(seconds: 1),
}) {
  if (limitKmh == null || limitKmh <= 0) return false;
  if (speedKmh < limitKmh + tolerance) return false;
  if (lastAlertAt == null) return true;
  return now.difference(lastAlertAt) >= repeat;
}

/// Whether [speedKmh] is over [limitKmh] (used to colour the speed readout).
/// Same threshold as [shouldAlert]: at limit+[tolerance] the readout turns red
/// exactly when the beep starts (issue #19).
bool isOverLimit(double speedKmh, int? limitKmh, {double tolerance = 1.0}) {
  if (limitKmh == null || limitKmh <= 0) return false;
  return speedKmh >= limitKmh + tolerance;
}

/// Formats a speed as a zero-padded 3-digit string like the design mock
/// (`089`, `094`, `110`). Clamps negatives to 0 and caps display at `999`.
String pad3(double kmh) {
  final v = kmh.isNaN ? 0 : kmh.round().clamp(0, 999);
  return v.toString().padLeft(3, '0');
}
