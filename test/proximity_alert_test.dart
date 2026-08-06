import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/services/proximity_alert.dart';

/// All fixtures sit on the 151.0 meridian so distance is pure latitude:
/// 0.01° ≈ 1.11 km. The site is at -33.00; the driver approaches from the
/// south (more negative latitudes).
Site _site(
  String id, {
  double? lat = -33.0,
  double? lng = 151.0,
  String? direction,
}) => Site(
  id: id,
  name: id,
  type: SiteType.checkingStation,
  state: AusState.nsw,
  suburb: id,
  address: '$id Rd',
  lat: lat,
  lng: lng,
  direction: direction,
);

final _now = DateTime(2026, 7, 26, 8, 0);

/// Feeds a run of latitudes in two-second steps and returns the last hit, so a
/// multi-fix approach reads as one line.
ProximityHit? _drive(
  ProximityTracker tracker,
  List<Site> sites,
  List<double> lats, {
  double speedKmh = 90,
  DateTime? start,
}) {
  ProximityHit? hit;
  var at = start ?? _now;
  for (final lat in lats) {
    hit = tracker.update(
      sites: sites,
      lat: lat,
      lng: 151.0,
      speedKmh: speedKmh,
      now: at,
    );
    at = at.add(const Duration(seconds: 2));
  }
  return hit;
}

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

    test('offers a close-range second chance after a dismissal', () {
      final tracker = ProximityTracker();
      final sites = [_site('a')];
      _drive(tracker, sites, const [-33.025, -33.02]);
      tracker.markPrompted('a', _now); // shown at ~2.2 km, then dismissed

      // Still far out: one prompt per approach, not one per fix.
      expect(_drive(tracker, sites, const [-33.015, -33.01]), isNull);

      // Inside 100 m the question is worth asking again.
      final near = _drive(tracker, sites, const [-33.0015, -33.0008]);
      expect(near, isNotNull);
      expect(near!.near, isTrue);
      expect(near.km, closeTo(0.089, 0.01));
    });

    test('the close-range second chance fires only once', () {
      final tracker = ProximityTracker();
      final sites = [_site('a')];
      _drive(tracker, sites, const [-33.025, -33.02]);
      tracker.markPrompted('a', _now);
      final near = _drive(tracker, sites, const [-33.0015, -33.0008]);
      expect(near, isNotNull);
      tracker.markPrompted('a', _now, near: true);

      expect(_drive(tracker, sites, const [-33.0004]), isNull);
    });

    test('answering silences the site for the rest of the pass', () {
      final tracker = ProximityTracker();
      final sites = [_site('a')];
      _drive(tracker, sites, const [-33.025, -33.02]);
      tracker.markPrompted('a', _now);
      tracker.markAnswered('a');

      expect(_drive(tracker, sites, const [-33.0015, -33.0008]), isNull);
    });

    test('a crawl into the site still gets the close-range prompt', () {
      final tracker = ProximityTracker();
      final sites = [_site('a')];
      _drive(tracker, sites, const [-33.025, -33.02]);
      tracker.markPrompted('a', _now);

      // Braking for the gate drops well under the moving threshold — which
      // must not swallow the one prompt the driver can actually answer.
      final near = _drive(tracker, sites, const [
        -33.0015,
        -33.0008,
      ], speedKmh: 8);
      expect(near?.near, isTrue);
    });

    test('reports the site as passed once it is behind you', () {
      final tracker = ProximityTracker();
      final sites = [_site('a')];
      _drive(tracker, sites, const [-33.025, -33.02, -33.0008]);
      expect(tracker.hasPassed('a'), isFalse);
      expect(tracker.lastKmFor('a'), closeTo(0.089, 0.01));

      // 100 m past the gate is still within GPS-wobble range of it.
      _drive(tracker, sites, const [-32.9997]);
      expect(tracker.hasPassed('a'), isFalse);

      _drive(tracker, sites, const [-32.9975]);
      expect(tracker.hasPassed('a'), isTrue);
    });

    test(
      'leaving the radius counts as passed, and re-entering is a new pass',
      () {
        final tracker = ProximityTracker(cooldown: Duration.zero);
        final sites = [_site('a')];
        _drive(tracker, sites, const [-33.025, -33.02]);
        tracker.markPrompted('a', _now);
        expect(tracker.hasPassed('a'), isFalse);

        _drive(tracker, sites, const [-33.05]); // 5.5 km out
        expect(tracker.hasPassed('a'), isTrue);

        // Turning around: a fresh approach prompts from scratch.
        final again = _drive(tracker, sites, const [-33.025, -33.02]);
        expect(again, isNotNull);
        expect(again!.near, isFalse);
        expect(tracker.hasPassed('a'), isFalse);
      },
    );

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

    test('derives the travel heading from the fixes, and reset clears it', () {
      final tracker = ProximityTracker();
      expect(tracker.headingDeg, isNull);
      _drive(tracker, [_site('a')], const [-33.025, -33.02]); // due north
      expect(tracker.headingDeg, isNotNull);
      expect(tracker.headingDeg!, closeTo(0, 0.001));
      tracker.reset();
      expect(tracker.headingDeg, isNull);
    });
  });

  group('directionBearingDeg', () {
    test('maps the four tags, case-insensitively, and rejects the rest', () {
      expect(directionBearingDeg('northbound'), 0);
      expect(directionBearingDeg('eastbound'), 90);
      expect(directionBearingDeg('southbound'), 180);
      expect(directionBearingDeg('westbound'), 270);
      expect(directionBearingDeg('Northbound '), 0);
      expect(directionBearingDeg('Both'), isNull);
      expect(directionBearingDeg('N/A'), isNull);
      expect(directionBearingDeg(null), isNull);
    });
  });

  group('direction-aware opposite pairs', () {
    // A Northbound/Southbound pair on one pin, like Mt White, Marulan and
    // Daroobalgie in the live data. The driver approaches from the south
    // (more negative latitude), i.e. travelling northbound.
    List<Site> pair() => [
      _site('n', direction: 'northbound'),
      _site('s', direction: 'southbound'),
    ];

    test('a northbound run prompts only the northbound member', () {
      final tracker = ProximityTracker();
      final sites = pair();
      final hit = _drive(tracker, sites, const [-33.025, -33.02]);
      expect(hit, isNotNull);
      expect(hit!.site.id, 'n');
      tracker.markPrompted('n', _now);

      // The southbound twin never takes over the long-range slot.
      expect(_drive(tracker, sites, const [-33.015, -33.01]), isNull);
    });

    test('the opposite member asks after an answer, only inside 100 m', () {
      final tracker = ProximityTracker();
      final sites = pair();
      expect(_drive(tracker, sites, const [-33.025, -33.02])!.site.id, 'n');
      tracker.markPrompted('n', _now);
      tracker.markAnswered('n');

      // Done with our side, but still 550 m out — too early for the other.
      expect(_drive(tracker, sites, const [-33.01, -33.005]), isNull);

      // Inside 100 m the other carriageway is in plain sight: ask once.
      final other = _drive(tracker, sites, const [-33.0008]);
      expect(other, isNotNull);
      expect(other!.site.id, 's');
      expect(other.near, isTrue);
      expect(other.km, closeTo(0.089, 0.01));
      tracker.markPrompted('s', _now, near: true);

      // Exactly once — a dismissal is not re-asked at the next fix.
      expect(_drive(tracker, sites, const [-33.0004]), isNull);
    });

    test('while our side is unanswered the opposite member stays silent', () {
      final tracker = ProximityTracker();
      final sites = pair();
      expect(_drive(tracker, sites, const [-33.025, -33.02])!.site.id, 'n');
      tracker.markPrompted('n', _now); // dismissed, not answered

      // At the gate, the second chance for OUR side outranks the other one.
      final near = _drive(tracker, sites, const [-33.0015, -33.0008]);
      expect(near!.site.id, 'n');
      expect(near.near, isTrue);
      tracker.markPrompted('n', _now, near: true); // dismissed again

      // Two dismissals is "leave me alone", not "done" — no third question.
      expect(_drive(tracker, sites, const [-33.0004]), isNull);
    });

    test('the roles flip with the direction of travel', () {
      final tracker = ProximityTracker();
      final sites = pair();
      // Approaching from the north, travelling southbound.
      final hit = _drive(tracker, sites, const [-32.975, -32.98]);
      expect(hit, isNotNull);
      expect(hit!.site.id, 's');
    });

    test('an unresolved heading leaves the pair untouched', () {
      // Forcing the heading to stay unknown: pre-heading fixes must behave
      // exactly like today — either member may prompt, closest-first wins.
      final tracker = ProximityTracker(headingMinMoveKm: 999);
      final sites = [
        _site('s', direction: 'southbound'),
        _site('n', direction: 'northbound'),
      ];
      final hit = _drive(tracker, sites, const [-33.025, -33.02]);
      expect(hit, isNotNull);
      expect(hit!.site.id, 's');
    });

    test('a lone directional site is unaffected by heading', () {
      final tracker = ProximityTracker();
      final sites = [_site('s', direction: 'southbound')];
      // Northbound driver, southbound-only site: prompts like always — the
      // tag may be stale, and there is no twin to carry the question instead.
      final hit = _drive(tracker, sites, const [-33.025, -33.02]);
      expect(hit, isNotNull);
      expect(hit!.site.id, 's');
    });

    test('opposite sites beyond the pair radius stay independent', () {
      final tracker = ProximityTracker();
      final sites = [
        _site('n', direction: 'northbound'), // at -33.0
        _site('s', lat: -33.05, direction: 'southbound'), // 5.6 km away
      ];
      // Northbound toward the southbound site: not a co-located pair, so the
      // old rules apply and it prompts on its own approach.
      final hit = _drive(tracker, sites, const [-33.075, -33.07]);
      expect(hit, isNotNull);
      expect(hit!.site.id, 's');
    });

    test('passing our side unanswered frees the opposite member', () {
      final tracker = ProximityTracker();
      // Pins offset along the road (real gates are), southbound one further
      // north, still well within the pair radius.
      final sites = [
        _site('n', direction: 'northbound'),
        _site('s', lat: -32.9964, direction: 'southbound'), // 400 m past 'n'
      ];
      expect(_drive(tracker, sites, const [-33.025, -33.02])!.site.id, 'n');
      tracker.markPrompted('n', _now);
      final near = _drive(tracker, sites, const [-33.0008]);
      expect(near!.site.id, 'n'); // second chance, dismissed too
      tracker.markPrompted('n', _now, near: true);

      // Not yet clear of 'n', and still 122+ m from 's': nothing.
      expect(_drive(tracker, sites, const [-32.999, -32.9975]), isNull);
      expect(tracker.hasPassed('n'), isTrue);

      // 'n' is behind us and 's' is in sight — its one question fires.
      final other = _drive(tracker, sites, const [-32.997]);
      expect(other, isNotNull);
      expect(other!.site.id, 's');
      expect(other.near, isTrue);
    });

  });
}
