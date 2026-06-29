import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/services/geo.dart';

Site _site(String id, double? lat, double? lng) => Site(
  id: id,
  name: id,
  type: SiteType.weighbridge,
  state: AusState.nsw,
  suburb: 'x',
  address: 'x',
  lat: lat,
  lng: lng,
);

void main() {
  group('distanceKm', () {
    test('same point is zero', () {
      expect(distanceKm(-33.8, 151.2, -33.8, 151.2), closeTo(0, 0.001));
    });

    test('Sydney to Melbourne is ~714 km', () {
      // Sydney (-33.8688,151.2093) -> Melbourne (-37.8136,144.9631)
      final d = distanceKm(-33.8688, 151.2093, -37.8136, 144.9631);
      expect(d, closeTo(714, 15));
    });
  });

  group('nearestSites', () {
    test('sorts by distance and excludes sites without coordinates', () {
      final sites = [
        _site('far', -37.81, 144.96), // Melbourne
        _site('near', -33.87, 151.21), // ~Sydney
        _site('nocoord', null, null),
      ];
      final ranked = nearestSites(sites, -33.8688, 151.2093); // Sydney
      expect(ranked.map((r) => r.site.id), ['near', 'far']);
      expect(ranked.any((r) => r.site.id == 'nocoord'), isFalse);
    });

    test('respects limit', () {
      final sites = [
        _site('a', -33.87, 151.21),
        _site('b', -34.0, 151.0),
        _site('c', -35.0, 150.0),
      ];
      expect(nearestSites(sites, -33.8688, 151.2093, limit: 2).length, 2);
    });
  });
}
