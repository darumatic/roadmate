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
