/// Client side of "report from the road, not from the couch" (trust control).
///
/// Reports and status votes are believed because they come from someone who
/// can see the site. So posting no longer needs an account of any kind —
/// anonymous sessions post like everyone else — but it does need the device to
/// be **within [reportRadiusKm] of the site**, the same 3 km at which the
/// approach prompt starts asking "what's the status?". Browsing, Nearby,
/// favourites and Add Site remain ungated (Add Site submissions are pending
/// until moderated, so spam is already contained there).
///
/// The check is client-side only: Firestore rules cannot verify a GPS fix, so
/// (as with the status freshness windows) the behaviour lives in client logic
/// and the rules stay accepting of every shipped write shape.
///
/// Deliberately Flutter- and Firebase-free (like `status_logic.dart` and
/// `ban_logic.dart`) so the rule is unit-testable without a Firebase app. The
/// repository is the single enforcement point — `FirestoreSiteRepository`
/// checks this before writing, so no UI path can leak a doomed request.
library;

import 'geo.dart';
import 'proximity_alert.dart';

/// How close the device must be for a report to be accepted. Locked to the
/// approach-prompt radius on purpose: the app must never *ask* for a status it
/// would then refuse to accept.
const double reportRadiusKm = proximityRadiusKm;

/// A device fix, provider-agnostic so this library never imports geolocator.
typedef DevicePosition = ({double lat, double lng});

/// Resolves the device's current position, asking for location permission if
/// needed. Null means unavailable: services off, permission denied, or no fix.
typedef DevicePositionResolver = Future<DevicePosition?> Function();

/// The three ways a proximity check can land.
enum ReportProximity {
  /// Close enough — or the site has no coordinates, which means there is
  /// nothing to measure against. Un-geocoded sites stay reportable: refusing
  /// them would make a site nobody can pin unreportable forever.
  allowed,

  /// The device fix is outside [reportRadiusKm].
  tooFar,

  /// The site has coordinates but the device position is unknown.
  needsLocation,
}

/// Decides whether a report from ([position]) about a site at
/// ([siteLat], [siteLng]) is acceptable. Pure — unit-tested.
ReportProximity checkReportProximity({
  required double? siteLat,
  required double? siteLng,
  required DevicePosition? position,
  double radiusKm = reportRadiusKm,
}) {
  if (siteLat == null || siteLng == null) return ReportProximity.allowed;
  if (position == null) return ReportProximity.needsLocation;
  final km = distanceKm(position.lat, position.lng, siteLat, siteLng);
  return km <= radiusKm ? ReportProximity.allowed : ReportProximity.tooFar;
}

/// Snack/exception text for a refusal for distance.
final String kTooFarToReportMessage =
    'Too far away — reports are accepted within '
    '${reportRadiusKm.toStringAsFixed(0)} km of the site.';

/// Snack/exception text when the device position is unknown. The permission
/// prompt itself has already been raised by the time this is shown, so it
/// reads as "and here is why we asked".
final String kLocationRequiredMessage =
    'Turn on location to report — reports are accepted within '
    '${reportRadiusKm.toStringAsFixed(0)} km of the site.';

/// The write was refused because the device is outside [reportRadiusKm] — as
/// opposed to being banned ([BannedException] in `ban_logic.dart`) or too
/// quick ([RateLimitedException] in `rate_limit.dart`).
class TooFarException implements Exception {
  const TooFarException();

  String get message => kTooFarToReportMessage;

  @override
  String toString() => message;
}

/// The write was refused because the device position could not be resolved
/// (location off, permission denied, or no fix in time).
class LocationRequiredException implements Exception {
  const LocationRequiredException();

  String get message => kLocationRequiredMessage;

  @override
  String toString() => message;
}
