import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/gps_signal.dart';

void main() {
  test('nothing subscribed is idle; a refused permission is idle too', () {
    expect(
      gpsSignal(subscribed: false, denied: false, hasFix: false),
      GpsSignal.off,
    );
    expect(
      gpsSignal(subscribed: false, denied: true, hasFix: false),
      GpsSignal.denied,
    );
    expect(gpsSignalLabel(GpsSignal.off), 'GPS idle');
  });

  // The 0.1.47 report: subscribed but not one fix ever arrived, while the badge
  // claimed "GPS active" over a completely still readout.
  test('subscribed with no fix yet reads as waiting, not active', () {
    final signal = gpsSignal(subscribed: true, denied: false, hasFix: false);
    expect(signal, GpsSignal.acquiring);
    expect(gpsSignalLabel(signal), 'Waiting for GPS fix…');
  });

  test('a fix makes it live', () {
    expect(
      gpsSignal(subscribed: true, denied: false, hasFix: true),
      GpsSignal.live,
    );
    expect(gpsSignalLabel(GpsSignal.live), 'GPS active');
  });

  test('a stream error is surfaced, and a later fix clears it', () {
    expect(
      gpsSignal(subscribed: true, denied: false, hasFix: true, errored: true),
      GpsSignal.lost,
    );
    expect(gpsSignalLabel(GpsSignal.lost), 'No GPS signal');
    // The controller clears `errored` on the next fix, which returns us here.
    expect(
      gpsSignal(subscribed: true, denied: false, hasFix: true),
      GpsSignal.live,
    );
  });
}
