import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/services/proximity_alert.dart';

/// All fixtures sit on the 151.0 meridian so distance is pure latitude:
/// 0.01° ≈ 1.11 km. The site is at -33.00; the driver approaches from the
/// south (more negative latitudes).
Site _site(String id, {double? lat = -33.0, double? lng = 151.0}) => Site(
  id: id,
  name: id,
  type: SiteType.checkingStation,
  state: AusState.nsw,
  suburb: id,
  address: '$id Rd',
  lat: lat,
  lng: lng,
);

final _now = DateTime(2026, 7, 26, 8, 0);

void main() {
  group('ProximityTracker', () {
    test('never prompts on the first fix — closing is unknowable', () {
      final tracker = ProximityTracker();
      final hit = tracker.update(
        sites: [_site('a')],
        lat: -33.02, // 2.2 km out, well inside the radius
        lng: 151.0,
        speedKmh: 90,
        now: _now,
      );
      expect(hit, isNull);
    });

    test('prompts on the next fix once inside the radius and closing', () {
      final tracker = ProximityTracker();
      final sites = [_site('a')];
      tracker.update(
        sites: sites,
        lat: -33.025,
        lng: 151.0,
        speedKmh: 90,
        now: _now,
      );
      final hit = tracker.update(
        sites: sites,
        lat: -33.02,
        lng: 151.0,
        speedKmh: 90,
        now: _now.add(const Duration(seconds: 2)),
      );
      expect(hit, isNotNull);
      expect(hit!.site.id, 'a');
      expect(hit.km, closeTo(2.22, 0.1));
    });

    test('stays silent while parked next to a site', () {
      final tracker = ProximityTracker();
      final sites = [_site('a')];
      tracker.update(
        sites: sites,
        lat: -33.005,
        lng: 151.0,
        speedKmh: 0,
        now: _now,
      );
      final hit = tracker.update(
        sites: sites,
        lat: -33.004, // drifting closer, but stationary
        lng: 151.0,
        speedKmh: 3,
        now: _now.add(const Duration(seconds: 2)),
      );
      expect(hit, isNull);
    });

    test('stays silent once the site is behind you (distance growing)', () {
      final tracker = ProximityTracker();
      final sites = [_site('a')];
      tracker.update(
        sites: sites,
        lat: -32.99,
        lng: 151.0,
        speedKmh: 90,
        now: _now,
      );
      final hit = tracker.update(
        sites: sites,
        lat: -32.98, // heading away
        lng: 151.0,
        speedKmh: 90,
        now: _now.add(const Duration(seconds: 2)),
      );
      expect(hit, isNull);
    });

    test('stays silent outside the radius even when closing fast', () {
      final tracker = ProximityTracker();
      final sites = [_site('a')];
      tracker.update(
        sites: sites,
        lat: -33.10,
        lng: 151.0,
        speedKmh: 100,
        now: _now,
      );
      final hit = tracker.update(
        sites: sites,
        lat: -33.08, // 8.9 km out — still beyond the 3 km radius
        lng: 151.0,
        speedKmh: 100,
        now: _now.add(const Duration(seconds: 2)),
      );
      expect(hit, isNull);
    });

    test('ignores GPS jitter smaller than the closing margin', () {
      final tracker = ProximityTracker(closingMarginKm: 0.02);
      final sites = [_site('a')];
      tracker.update(
        sites: sites,
        lat: -33.02,
        lng: 151.0,
        speedKmh: 90,
        now: _now,
      );
      final hit = tracker.update(
        sites: sites,
        lat: -33.01995, // ~5 m closer: noise, not approach
        lng: 151.0,
        speedKmh: 90,
        now: _now.add(const Duration(seconds: 1)),
      );
      expect(hit, isNull);
    });

    test('skips sites without coordinates', () {
      final tracker = ProximityTracker();
      final sites = [_site('nocoords', lat: null, lng: null)];
      tracker.update(
        sites: sites,
        lat: -33.025,
        lng: 151.0,
        speedKmh: 90,
        now: _now,
      );
      final hit = tracker.update(
        sites: sites,
        lat: -33.02,
        lng: 151.0,
        speedKmh: 90,
        now: _now.add(const Duration(seconds: 2)),
      );
      expect(hit, isNull);
    });

    test('picks the closest of several qualifying sites', () {
      final tracker = ProximityTracker();
      final sites = [
        _site('far', lat: -33.0), // ~2.2 km at the second fix
        _site('near', lat: -33.01), // ~1.1 km at the second fix
      ];
      tracker.update(
        sites: sites,
        lat: -33.025,
        lng: 151.0,
        speedKmh: 90,
        now: _now,
      );
      final hit = tracker.update(
        sites: sites,
        lat: -33.02,
        lng: 151.0,
        speedKmh: 90,
        now: _now.add(const Duration(seconds: 2)),
      );
      expect(hit!.site.id, 'near');
    });

    test('one prompt per site per cooldown, then eligible again', () {
      final tracker = ProximityTracker(cooldown: const Duration(hours: 2));
      final sites = [_site('a')];

      tracker.update(
        sites: sites,
        lat: -33.025,
        lng: 151.0,
        speedKmh: 90,
        now: _now,
      );
      final first = tracker.update(
        sites: sites,
        lat: -33.02,
        lng: 151.0,
        speedKmh: 90,
        now: _now.add(const Duration(seconds: 2)),
      );
      expect(first, isNotNull);
      tracker.markPrompted('a', _now.add(const Duration(seconds: 2)));

      // Same approach a few minutes later: suppressed.
      final within = tracker.update(
        sites: sites,
        lat: -33.015,
        lng: 151.0,
        speedKmh: 90,
        now: _now.add(const Duration(minutes: 5)),
      );
      expect(within, isNull);
      expect(
        tracker.isInCooldown('a', _now.add(const Duration(minutes: 5))),
        isTrue,
      );

      // Return trip after the cooldown: prompts again.
      final later = _now.add(const Duration(hours: 3));
      tracker.update(
        sites: sites,
        lat: -33.025,
        lng: 151.0,
        speedKmh: 90,
        now: later,
      );
      final again = tracker.update(
        sites: sites,
        lat: -33.02,
        lng: 151.0,
        speedKmh: 90,
        now: later.add(const Duration(seconds: 2)),
      );
      expect(again, isNotNull);
    });

    test('reset drops the distance history so the next fix cannot prompt', () {
      final tracker = ProximityTracker();
      final sites = [_site('a')];
      tracker.update(
        sites: sites,
        lat: -33.025,
        lng: 151.0,
        speedKmh: 90,
        now: _now,
      );
      tracker.reset();
      final hit = tracker.update(
        sites: sites,
        lat: -33.02,
        lng: 151.0,
        speedKmh: 90,
        now: _now.add(const Duration(seconds: 2)),
      );
      expect(hit, isNull);
    });
  });
}
