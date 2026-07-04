/// Pure decision for the over-limit warning: whether to sound the alert *now*.
/// Kept out of the render/stream path so the beep logic is unit-tested and the
/// controller just acts on the boolean.
///
/// Returns true when [speedKmh] exceeds [limitKmh] (by more than [tolerance])
/// AND either this is the first reading over the limit ([lastAlertAt] is null)
/// or at least [repeat] has elapsed since the last alert. Returns false when no
/// limit is set or the driver is within tolerance — which also lets the caller
/// clear [lastAlertAt] so the next breach re-triggers immediately (rising edge).
bool shouldAlert({
  required double speedKmh,
  required int? limitKmh,
  required DateTime now,
  DateTime? lastAlertAt,
  double tolerance = 2.0,
  Duration repeat = const Duration(seconds: 10),
}) {
  if (limitKmh == null || limitKmh <= 0) return false;
  if (speedKmh <= limitKmh + tolerance) return false;
  if (lastAlertAt == null) return true;
  return now.difference(lastAlertAt) >= repeat;
}

/// Whether [speedKmh] is over [limitKmh] (used to colour the speed readout).
bool isOverLimit(double speedKmh, int? limitKmh, {double tolerance = 2.0}) {
  if (limitKmh == null || limitKmh <= 0) return false;
  return speedKmh > limitKmh + tolerance;
}

/// Formats a speed as a zero-padded 3-digit string like the design mock
/// (`089`, `094`, `110`). Clamps negatives to 0 and caps display at `999`.
String pad3(double kmh) {
  final v = kmh.isNaN ? 0 : kmh.round().clamp(0, 999);
  return v.toString().padLeft(3, '0');
}
