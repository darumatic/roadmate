import 'package:geolocator/geolocator.dart';

/// Injectable device-location dependency for the trip speedometer. Behind this
/// abstraction (mirroring the `SiteRepository` pattern) so screens and the trip
/// controller never touch the Geolocator plugin directly — widget tests override
/// the provider with a fake that emits a controlled stream.
abstract class LocationSource {
  /// Ensures location services are on and foreground permission is granted,
  /// prompting the user if needed. Returns `false` if unavailable or denied.
  Future<bool> ensurePermission();

  /// A continuous stream of position fixes (each carries `speed` in m/s).
  Stream<Position> positions();
}

/// Production [LocationSource] backed by `geolocator`. Permission gating mirrors
/// `currentPositionProvider` in the Nearby screen; the stream is tuned for
/// navigation-grade speed with updates on every fix (`distanceFilter: 0`).
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm != LocationPermission.denied &&
        perm != LocationPermission.deniedForever;
  }

  @override
  Stream<Position> positions() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    ),
  );
}
