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
///
/// Everything is tracked per **pass**: a pass starts when the driver crosses
/// into the radius and ends when they leave it again. Within one pass a site
/// gets at most two prompts — the long-range one, and (only if the first was
/// dismissed unanswered) a second-chance one from [proximityNearRadiusKm],
/// close enough that the driver can still see the gate.

/// How close a site must be before the prompt is considered. ~3 km is roughly
/// two minutes of warning at highway speed — enough to answer safely.
const double proximityRadiusKm = 3.0;

/// Second-chance range. A prompt dismissed at 3 km is asked once more here,
/// where the driver is on top of the site and can actually see its state.
const double proximityNearRadiusKm = 0.1;

/// Below this the driver is parked/crawling and is not "approaching" anything.
/// Only gates the long-range prompt: by [proximityNearRadiusKm] a truck pulling
/// into the site is slowing down, which is exactly when the answer is best.
const double proximityMinSpeedKmh = 20.0;

/// One long-range prompt per site per this long, however many times it's
/// passed. The second-chance prompt lives inside the same pass, so it is not
/// gated by this.
const Duration proximityCooldown = Duration(hours: 2);

/// How much closer the site must be than at the previous fix to count as
/// approaching. A small margin absorbs GPS jitter while stationary traffic
/// crawls (a fix wobbling by metres must not read as "closing").
const double proximityClosingMarginKm = 0.02;

/// How far the driver must pull away from their closest point to the site
/// before it counts as behind them. Bigger than [proximityClosingMarginKm] so
/// a jittery fix at the gate doesn't read as "passed" while queueing to enter.
const double proximityPassedMarginKm = 0.15;

/// A site the driver is approaching, with its current distance.
class ProximityHit {
  const ProximityHit(this.site, this.km, {this.near = false});

  final Site site;
  final double km;

  /// True when this is the second-chance prompt raised inside
  /// [proximityNearRadiusKm], rather than the long-range one.
  final bool near;
}

/// Per-site state for the current pass through a site's radius.
class _Approach {
  /// Distance at the previous fix — what makes the "closing" test possible.
  double? lastKm;

  /// Whether the driver is currently inside the radius. The false→true edge
  /// starts a new pass and wipes the flags below.
  bool inside = false;

  /// Closest the driver has come during this pass; "passed" is measured from
  /// it, so it works whether they blow by at 100 or crawl in and out.
  double? minKm;

  /// The long-range prompt has been raised during this pass.
  bool prompted = false;

  /// The second-chance prompt has been raised (or consumed) this pass.
  bool nearPrompted = false;

  /// The driver answered — never ask about this site again this pass.
  bool answered = false;

  /// The site is behind them; the question is moot.
  bool passed = false;

  void startPass() {
    inside = true;
    minKm = null;
    prompted = false;
    nearPrompted = false;
    answered = false;
    passed = false;
  }
}

/// Stateful (but plain-Dart) tracker fed one GPS fix at a time.
///
/// It remembers the previous distance to every site — that's what makes the
/// "closing" test possible — and when each site last prompted.
class ProximityTracker {
  ProximityTracker({
    this.radiusKm = proximityRadiusKm,
    this.nearRadiusKm = proximityNearRadiusKm,
    this.minSpeedKmh = proximityMinSpeedKmh,
    this.cooldown = proximityCooldown,
    this.closingMarginKm = proximityClosingMarginKm,
    this.passedMarginKm = proximityPassedMarginKm,
  });

  final double radiusKm;
  final double nearRadiusKm;
  final double minSpeedKmh;
  final Duration cooldown;
  final double closingMarginKm;
  final double passedMarginKm;

  /// Per-pass state, keyed by site id.
  final Map<String, _Approach> _tracks = {};

  /// When each site last produced a prompt the user actually saw. Outlives the
  /// pass — that's the point of the cooldown.
  final Map<String, DateTime> _promptedAt = {};

  /// Folds one GPS fix in and returns the site to prompt for, or null.
  ///
  /// Always call this for every fix, even while a prompt is on screen: the
  /// distance history has to stay current or the next "closing" test compares
  /// against a stale sample, and [hasPassed] would never fire. Callers that
  /// choose not to show the returned hit simply don't call [markPrompted], so
  /// the site stays eligible.
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
      final track = _tracks.putIfAbsent(site.id, _Approach.new);
      final previousKm = track.lastKm;
      track.lastKm = km;

      if (km > radiusKm) {
        // Out of range entirely. Leaving the radius ends the pass — and counts
        // as passed, so a prompt still on screen for it can be retired.
        if (track.inside) {
          track.inside = false;
          track.passed = true;
        }
        continue;
      }
      // Crossing in from beyond the radius: a fresh pass, fresh prompts. A
      // pass that has been open since before the cooldown expired is stale
      // (parked in range all morning, or GPS dropped out for hours) and starts
      // over too, so the site can't be silenced forever by one old prompt.
      if (!track.inside || (track.prompted && !isInCooldown(site.id, now))) {
        track.startPass();
      }

      final minKm = track.minKm;
      if (minKm == null || km < minKm) track.minKm = km;
      if (km - track.minKm! > passedMarginKm) track.passed = true;

      if (track.passed || track.answered) continue;
      // First fix for this site (app just opened, or it just entered the
      // radius from beyond it): no history, so "closing" is unknowable. The
      // next fix a second later decides.
      if (previousKm == null) continue;
      if (previousKm - km < closingMarginKm) continue;

      final bool near;
      if (!track.prompted) {
        if (speedKmh < minSpeedKmh) continue;
        final promptedAt = _promptedAt[site.id];
        if (promptedAt != null && now.difference(promptedAt) < cooldown) {
          continue;
        }
        near = false;
      } else if (!track.nearPrompted && km <= nearRadiusKm) {
        // The long-range prompt came and went unanswered — ask once more now
        // that the site is in sight. No speed or cooldown gate: this is the
        // same approach the driver already agreed to be asked about.
        near = true;
      } else {
        continue;
      }

      // Closest qualifying site wins — that's the one the driver reaches first.
      if (best == null || km < best.km) {
        best = ProximityHit(site, km, near: near);
      }
    }
    return best;
  }

  /// Records that [siteId] prompted at [now], starting its [cooldown]. Pass
  /// `near: true` for the second-chance prompt, which spends the one retry
  /// this pass gets rather than the long-range slot.
  void markPrompted(String siteId, DateTime now, {bool near = false}) {
    _promptedAt[siteId] = now;
    final track = _tracks.putIfAbsent(siteId, _Approach.new);
    if (near) {
      track.nearPrompted = true;
    } else {
      track.prompted = true;
    }
  }

  /// Records that the driver answered for [siteId] — no second chance, they've
  /// already told us what's there.
  void markAnswered(String siteId) {
    _tracks.putIfAbsent(siteId, _Approach.new).answered = true;
  }

  /// Whether the driver has rolled past [siteId] (or left its radius) during
  /// the current pass. Drives retiring a prompt that is no longer answerable.
  bool hasPassed(String siteId) => _tracks[siteId]?.passed ?? false;

  /// Distance to [siteId] at the last fix, or null if it hasn't been seen —
  /// lets a live prompt keep counting down instead of freezing at 3 km.
  double? lastKmFor(String siteId) => _tracks[siteId]?.lastKm;

  /// Whether [siteId] is inside its cooldown at [now] (test/debug helper).
  bool isInCooldown(String siteId, DateTime now) {
    final at = _promptedAt[siteId];
    return at != null && now.difference(at) < cooldown;
  }

  /// Forgets all history — used when the GPS stream restarts, so a fix from a
  /// different part of the country can't be compared against the old one.
  void reset() {
    _tracks.clear();
    _promptedAt.clear();
  }
}
