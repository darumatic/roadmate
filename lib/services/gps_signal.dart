/// How healthy the GPS feed actually is, as opposed to whether the app merely
/// subscribed to it.
///
/// The speedometer used to show a confident green "GPS active" the moment the
/// position stream was subscribed — even when not a single fix ever arrived
/// (parked indoors, or the stream erroring out). The driver then sees a
/// perfectly still speedo/odometer with no clue why, which is exactly the
/// 0.1.47 report. Pure/Flutter-free so it unit-tests without a device.
enum GpsSignal {
  /// The stream isn't running (nothing has asked for it yet).
  off,

  /// Location permission was refused, or location services are off.
  denied,

  /// Subscribed, but no fix has landed yet — normal for the first seconds, and
  /// indefinite indoors.
  acquiring,

  /// At least one fix has arrived and the stream is healthy.
  live,

  /// The stream errored (GPS dropout, service toggled off mid-drive).
  lost,
}

/// Derives the signal from what the trip controller knows. Deliberately based
/// on facts that arrive as state changes (a fix, an error) rather than on a
/// timer, so the UI never has to poll to stay truthful.
GpsSignal gpsSignal({
  required bool subscribed,
  required bool denied,
  required bool hasFix,
  bool errored = false,
}) {
  if (denied) return GpsSignal.denied;
  if (!subscribed) return GpsSignal.off;
  // An error that a later fix has already recovered from isn't worth showing.
  if (errored) return GpsSignal.lost;
  return hasFix ? GpsSignal.live : GpsSignal.acquiring;
}

/// The one-line status shown under the speedometer.
String gpsSignalLabel(GpsSignal signal) => switch (signal) {
  GpsSignal.off => 'GPS idle',
  GpsSignal.denied => 'GPS idle',
  GpsSignal.acquiring => 'Waiting for GPS fix…',
  GpsSignal.live => 'GPS active',
  GpsSignal.lost => 'No GPS signal',
};
