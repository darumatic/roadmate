import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:geolocator/geolocator.dart';

import 'permission_queue.dart';

/// Stream settings for the trip speedometer and the site-approach alert.
///
/// - **Web**: [WebSettings.maximumAge] lets the browser serve a recent cached
///   fix as the first event instead of blocking several seconds on a cold one
///   (the browser default is maximumAge: 0 — cache forbidden). Trips normally
///   start parked, so a ≤10 s-old first fix adds no meaningful distance error.
/// - **Android**: a foreground service keeps the fixes coming while the app is
///   backgrounded or the screen is off, so an approach alert still fires when
///   the driver is using maps or has the phone in a pocket. The service's
///   ongoing notification is the price of that (and is what Android requires
///   in exchange for background location *without* the
///   ACCESS_BACKGROUND_LOCATION permission and its Play review).
/// - **iOS**: `allowBackgroundLocationUpdates` plus the `location` background
///   mode does the same job; the blue status-bar indicator tells the driver
///   the app is tracking. `automotiveNavigation` stops iOS pausing updates at
///   a red light.
LocationSettings tripLocationSettings({
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  if (isWeb) {
    return WebSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      maximumAge: const Duration(seconds: 10),
    );
  }
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'RoadMate is watching the road',
        notificationText: 'Live speed, trip logging and site alerts',
        notificationChannelName: 'Live tracking',
        enableWakeLock: true,
      ),
    ),
    TargetPlatform.iOS || TargetPlatform.macOS => AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      activityType: ActivityType.automotiveNavigation,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    ),
    _ => const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    ),
  };
}

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
      // Through the queue: raised while the notification dialog is up, this
      // request comes straight back denied without ever being shown.
      perm = await permissionQueue.run(Geolocator.requestPermission);
    }
    return perm != LocationPermission.denied &&
        perm != LocationPermission.deniedForever;
  }

  @override
  Stream<Position> positions() =>
      Geolocator.getPositionStream(locationSettings: tripLocationSettings());
}
