import 'dart:math' as math;

import '../models/site.dart';

/// Great-circle distance in kilometres between two lat/lng points (haversine).
/// Pure function — unit-tested.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLng = _toRad(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRad(double deg) => deg * math.pi / 180.0;

/// Initial great-circle bearing in degrees (0 = north, 90 = east) travelling
/// from point 1 toward point 2. Pure function — unit-tested.
double bearingDeg(double lat1, double lng1, double lat2, double lng2) {
  final phi1 = _toRad(lat1);
  final phi2 = _toRad(lat2);
  final dLng = _toRad(lng2 - lng1);
  final y = math.sin(dLng) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLng);
  return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
}

/// Smallest absolute difference between two bearings, in degrees (0–180).
double angleDiffDeg(double a, double b) {
  final d = (a - b) % 360.0; // Dart % is non-negative for a positive divisor
  return d > 180.0 ? 360.0 - d : d;
}

const double maxLatitude = 90.0;
const double maxLongitude = 180.0;

/// Parses a typed coordinate, returning null for blank, unparseable or
/// out-of-range input. Pure — shared by Add Site and the admin location
/// editor so both accept exactly the same things.
double? parseCoordinate(String? raw, {required double maxAbs}) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || value.isNaN || value.abs() > maxAbs) return null;
  return value;
}

/// Validation message for a form field that must not be blank. The one
/// implementation of the "Required" rule — Add Site and the admin site editor
/// used to each spell it inline.
String? requiredFieldError(String? raw) =>
    (raw == null || raw.trim().isEmpty) ? 'Required' : null;

/// "12 km away" / "3.4 km away" — whole kilometres from 10 up, one decimal
/// below. Shared by Nearby and the Home closest-sites card so the two rows
/// can never disagree on rounding.
String kmAwayLabel(double km) =>
    '${km.toStringAsFixed(km < 10 ? 1 : 0)} km away';

/// Validation message for one coordinate field, or null when acceptable.
/// **Blank is acceptable**: coordinates are optional — a site without them is
/// simply absent from Nearby and never raises an approach prompt.
String? coordinateFieldError(
  String? raw, {
  required double maxAbs,
  required String label,
}) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  if (parseCoordinate(text, maxAbs: maxAbs) == null) {
    return '$label must be a number between ${-maxAbs} and $maxAbs';
  }
  return null;
}

/// Validation message for the lat/lng pair. Half a coordinate is useless —
/// it would silently drop the site out of every distance calculation — so
/// both are required together or not at all.
String? coordinatePairError(String? lat, String? lng) {
  final hasLat = (lat?.trim() ?? '').isNotEmpty;
  final hasLng = (lng?.trim() ?? '').isNotEmpty;
  if (hasLat == hasLng) return null;
  return 'Enter both latitude and longitude, or leave both blank';
}

/// A site paired with its distance from a reference point.
class SiteDistance {
  const SiteDistance(this.site, this.km);
  final Site site;
  final double km;
}

/// Rank sites by distance from ([lat], [lng]). Sites without coordinates are
/// excluded (the authoritative NHVR dataset has none until geocoded). Pure —
/// unit-tested.
List<SiteDistance> nearestSites(
  Iterable<Site> sites,
  double lat,
  double lng, {
  int? limit,
}) {
  final ranked =
      sites
          .where((s) => s.lat != null && s.lng != null)
          .map((s) => SiteDistance(s, distanceKm(lat, lng, s.lat!, s.lng!)))
          .toList()
        ..sort((a, b) => a.km.compareTo(b.km));
  return limit == null ? ranked : ranked.take(limit).toList();
}
