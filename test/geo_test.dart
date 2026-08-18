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

  group('bearingDeg', () {
    test('the four cardinal directions', () {
      expect(bearingDeg(-33.0, 151.0, -32.0, 151.0), closeTo(0, 0.001)); // N
      expect(bearingDeg(-33.0, 151.0, -33.0, 152.0), closeTo(90, 0.3)); // E
      expect(bearingDeg(-32.0, 151.0, -33.0, 151.0), closeTo(180, 0.001)); // S
      expect(bearingDeg(-33.0, 152.0, -33.0, 151.0), closeTo(270, 0.3)); // W
    });

    test('stays within 0–360', () {
      final b = bearingDeg(-33.0, 151.0, -32.9, 150.9); // north-west
      expect(b, greaterThan(270));
      expect(b, lessThan(360));
    });
  });

  group('angleDiffDeg', () {
    test('wraps around north', () {
      expect(angleDiffDeg(350, 10), closeTo(20, 0.001));
      expect(angleDiffDeg(10, 350), closeTo(20, 0.001));
    });

    test('opposites are 180, same is 0', () {
      expect(angleDiffDeg(0, 180), 180);
      expect(angleDiffDeg(270, 90), 180);
      expect(angleDiffDeg(90, 90), 0);
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

  group('parseCoordinate', () {
    test('parses signed decimals, ignoring surrounding whitespace', () {
      expect(parseCoordinate(' -34.7123 ', maxAbs: maxLatitude), -34.7123);
      expect(parseCoordinate('149', maxAbs: maxLongitude), 149);
    });

    test('blank, unparseable and out-of-range values are null', () {
      expect(parseCoordinate('', maxAbs: maxLatitude), isNull);
      expect(parseCoordinate(null, maxAbs: maxLatitude), isNull);
      expect(parseCoordinate('south', maxAbs: maxLatitude), isNull);
      expect(parseCoordinate('-91', maxAbs: maxLatitude), isNull);
      expect(parseCoordinate('181', maxAbs: maxLongitude), isNull);
      // 149.7 is a valid longitude but not a valid latitude.
      expect(parseCoordinate('149.7', maxAbs: maxLatitude), isNull);
    });
  });

  group('coordinate field validation', () {
    test('blank passes — coordinates are optional', () {
      expect(
        coordinateFieldError('', maxAbs: maxLatitude, label: 'Latitude'),
        isNull,
      );
    });

    test('out-of-range explains the bounds', () {
      expect(
        coordinateFieldError('95', maxAbs: maxLatitude, label: 'Latitude'),
        'Latitude must be a number between -90.0 and 90.0',
      );
    });

    test('valid input passes', () {
      expect(
        coordinateFieldError('-34.71', maxAbs: maxLatitude, label: 'Latitude'),
        isNull,
      );
    });

    test('half a pair is rejected, both or neither passes', () {
      expect(coordinatePairError('-34.7', ''), isNotNull);
      expect(coordinatePairError('', '149.7'), isNotNull);
      expect(coordinatePairError('-34.7', '149.7'), isNull);
      expect(coordinatePairError('', ''), isNull);
      expect(coordinatePairError(null, null), isNull);
    });
  });

  group('requiredFieldError', () {
    test('blank and whitespace-only are refused, content passes', () {
      expect(requiredFieldError(null), 'Required');
      expect(requiredFieldError(''), 'Required');
      expect(requiredFieldError('   '), 'Required');
      expect(requiredFieldError('Marulan'), isNull);
    });
  });

  group('kmAwayLabel', () {
    test('one decimal under 10 km, whole kilometres from 10 up', () {
      expect(kmAwayLabel(3.44), '3.4 km away');
      expect(kmAwayLabel(9.99), '10.0 km away');
      expect(kmAwayLabel(10.4), '10 km away');
      expect(kmAwayLabel(115.0), '115 km away');
    });
  });
}
