import '../models/site.dart';
import 'geo.dart';

/// Pure "are we approaching a site?" logic for the Waze-style prompt, kept
/// Flutter/Firebase-free so it unit-tests like `speed_alert.dart`.
///
/// The rule is deliberately conservative — a prompt that fires while parked at
/// a servo next to a weighbridge, or after the driver has already rolled past
/// the gate, trains people to dismiss it without reading. So all three of these
/// must hold:
///
///  1. the site is within [proximityRadiusKm],
///  2. the driver is actually moving ([proximityMinSpeedKmh]), and
///  3. the distance is *shrinking* since the previous fix — which is also how
///     direction is handled: heading away never prompts, so no compass maths
///     and no dependence on the site's (often missing) direction tag.
///
/// Plus a per-site [proximityCooldown] so one site can't nag on a return trip
/// the same morning.

/// How close a site must be before the prompt is considered. ~3 km is roughly
/// two minutes of warning at highway speed — enough to answer safely.
const double proximityRadiusKm = 3.0;

/// Below this the driver is parked/crawling and is not "approaching" anything.
const double proximityMinSpeedKmh = 20.0;

/// One prompt per site per this long, however many times it's passed.
const Duration proximityCooldown = Duration(hours: 2);

/// How much closer the site must be than at the previous fix to count as
/// approaching. A small margin absorbs GPS jitter while stationary traffic
/// crawls (a fix wobbling by metres must not read as "closing").
const double proximityClosingMarginKm = 0.02;

/// A site the driver is approaching, with its current distance.
class ProximityHit {
  const ProximityHit(this.site, this.km);

  final Site site;
  final double km;
}

/// Stateful (but plain-Dart) tracker fed one GPS fix at a time.
///
/// It remembers the previous distance to every site — that's what makes the
/// "closing" test possible — and when each site last prompted.
class ProximityTracker {
  ProximityTracker({
    this.radiusKm = proximityRadiusKm,
    this.minSpeedKmh = proximityMinSpeedKmh,
    this.cooldown = proximityCooldown,
    this.closingMarginKm = proximityClosingMarginKm,
  });

  final double radiusKm;
  final double minSpeedKmh;
  final Duration cooldown;
  final double closingMarginKm;

  /// Distance to each site at the previous fix, keyed by site id.
  final Map<String, double> _lastKm = {};

  /// When each site last produced a prompt the user actually saw.
  final Map<String, DateTime> _promptedAt = {};

  /// Folds one GPS fix in and returns the site to prompt for, or null.
  ///
  /// Always call this for every fix, even while a prompt is on screen: the
  /// distance history has to stay current or the next "closing" test compares
  /// against a stale sample. Callers that choose not to show the returned hit
  /// simply don't call [markPrompted], so the site stays eligible.
  ProximityHit? update({
    required Iterable<Site> sites,
    required double lat,
    required double lng,
    required double speedKmh,
    required DateTime now,
  }) {
    ProximityHit? best;
    for (final site in sites) {
      if (site.lat == null || site.lng == null) continue;
      final km = distanceKm(lat, lng, site.lat!, site.lng!);
      final previousKm = _lastKm[site.id];
      _lastKm[site.id] = km;

      if (km > radiusKm) continue;
      if (speedKmh < minSpeedKmh) continue;
      // First fix for this site (app just opened, or it just entered the
      // radius from beyond it): no history, so "closing" is unknowable. The
      // next fix a second later decides.
      if (previousKm == null) continue;
      if (previousKm - km < closingMarginKm) continue;
      final promptedAt = _promptedAt[site.id];
      if (promptedAt != null && now.difference(promptedAt) < cooldown) continue;

      // Closest qualifying site wins — that's the one the driver reaches first.
      if (best == null || km < best.km) best = ProximityHit(site, km);
    }
    return best;
  }

  /// Records that [siteId] prompted at [now], starting its [cooldown].
  void markPrompted(String siteId, DateTime now) {
    _promptedAt[siteId] = now;
  }

  /// Whether [siteId] is inside its cooldown at [now] (test/debug helper).
  bool isInCooldown(String siteId, DateTime now) {
    final at = _promptedAt[siteId];
    return at != null && now.difference(at) < cooldown;
  }

  /// Forgets all history — used when the GPS stream restarts, so a fix from a
  /// different part of the country can't be compared against the old one.
  void reset() {
    _lastKm.clear();
    _promptedAt.clear();
  }
}
