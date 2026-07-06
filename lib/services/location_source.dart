import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

/// Stream settings for the trip speedometer. On web, [WebSettings.maximumAge]
/// lets the browser serve a recent cached fix as the first event instead of
/// blocking several seconds on a cold one (the browser default is
/// maximumAge: 0 — cache forbidden). Trips normally start parked, so a
/// ≤10 s-old first fix adds no meaningful distance error.
LocationSettings tripLocationSettings({bool isWeb = kIsWeb}) => isWeb
    ? WebSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        maximumAge: const Duration(seconds: 10),
      )
    : const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );

/// One-shot settings for "where am I, roughly" lookups (Nearby tab, the
/// nearest-site card). A cached fix up to 2 minutes old is fine there and
/// returns instantly on web.
LocationSettings quickFixLocationSettings({bool isWeb = kIsWeb}) => isWeb
    ? WebSettings(
        accuracy: LocationAccuracy.high,
        maximumAge: const Duration(minutes: 2),
      )
    : const LocationSettings(accuracy: LocationAccuracy.high);

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
  Stream<Position> positions() =>
      Geolocator.getPositionStream(locationSettings: tripLocationSettings());
}
