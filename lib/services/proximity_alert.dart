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
///  3. the distance is *shrinking* since the previous fix — which is how
///     "heading away" is handled for the ordinary site: no compass maths, no
///     dependence on the (often missing) direction tag.
///
/// Plus a per-site [proximityCooldown] so one site can't nag on a return trip
/// the same morning.
///
/// The one place compass maths does enter is **co-located opposite-direction
/// pairs** (Mt White, Marulan and Daroobalgie each have a Northbound and a
/// Southbound site on the same pin). There a travel heading derived from the
/// GPS fixes decides which member the driver is actually rolling toward: the
/// matching member prompts exactly as normal, and the opposite one is
/// deferred — it asks once, only inside [proximityNearRadiusKm] and only after
/// the matching member is done (answered or passed). That is "you've dealt
/// with your side — while you're at the gate, what does the other side look
/// like?", never two competing questions on approach. Lone directional sites
/// are untouched: their tag may be stale, and silencing their only prompt on
/// compass grounds could hide a blitz.
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

/// Two opposite-direction sites within this of each other are one location —
/// the two carriageways of the same road. Generous enough to keep the pins
/// paired if they're ever corrected from shared town-level geocodes to the
/// real gates, but far smaller than the gap between genuinely separate
/// stations (Wallan and Broadford, the nearest unrelated N/S pair, are 23 km
/// apart).
const double proximityPairRadiusKm = 2.0;

/// How far the device must move before the derived travel heading updates.
/// Below this, the bearing between fixes is mostly GPS jitter; above it,
/// course over ground is trustworthy. Movement accumulates from an anchor
/// fix, so a slow crawl still resolves a heading.
const double proximityHeadingMinMoveKm = 0.01;

/// The compass bearing a site's direction tag points along (northbound = 0,
/// eastbound = 90), or null when the site has no usable tag ("Both"/"N/A"
/// normalise to null upstream; anything unrecognised lands here too).
double? directionBearingDeg(String? direction) {
  switch (direction?.toLowerCase().trim()) {
    case 'northbound':
      return 0;
    case 'eastbound':
      return 90;
    case 'southbound':
      return 180;
    case 'westbound':
      return 270;
  }
  return null;
}

/// A site the driver is approaching, with its current distance.
class ProximityHit {
  const ProximityHit(this.site, this.km, {this.near = false});

  final Site site;
  final double km;

  /// True when this prompt is raised inside [proximityNearRadiusKm] — the
  /// second-chance ask after a dismissal, or the deferred ask for the opposite
  /// member of a direction pair — rather than the long-range one.
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
    this.pairRadiusKm = proximityPairRadiusKm,
    this.headingMinMoveKm = proximityHeadingMinMoveKm,
  });

  final double radiusKm;
  final double nearRadiusKm;
  final double minSpeedKmh;
  final Duration cooldown;
  final double closingMarginKm;
  final double passedMarginKm;
  final double pairRadiusKm;
  final double headingMinMoveKm;

  /// Travel course derived from the GPS fixes (degrees, 0 = north), or null
  /// until the device has moved [headingMinMoveKm] from its anchor fix. For a
  /// vehicle this *is* the device's GPS heading — the platform's
  /// `Position.heading` is the same course over ground, but with per-platform
  /// invalid markers (-1, 0, NaN) and no web support, while deriving it here
  /// keeps the logic pure and testable. Kept through stops: a parked truck
  /// hasn't turned, and 10 m of movement corrects it if it has.
  double? get headingDeg => _headingDeg;
  double? _headingDeg;
  double? _headingAnchorLat;
  double? _headingAnchorLng;

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
    _updateHeading(lat, lng);
    // Built only when a directional site needs it (and a heading exists), so
    // fleets without direction tags never pay the pairing scan.
    Map<String, Site>? partners;
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

      // The opposite-direction member of a co-located pair: the driver is
      // rolling toward the other carriageway's site, so the long-range ask
      // belongs to that member alone. This one waits until that conversation
      // is over (answered or passed) and then asks exactly once, only with the
      // pair in sight — where the other side of the road is something the
      // driver can actually see.
      final ownBearing = directionBearingDeg(site.direction);
      final heading = _headingDeg;
      if (ownBearing != null && heading != null) {
        final partner = (partners ??= _oppositePartners(sites))[site.id];
        if (partner != null && angleDiffDeg(heading, ownBearing) > 90.0) {
          if (track.nearPrompted || km > nearRadiusKm) continue;
          final partnerTrack = _tracks[partner.id];
          final partnerDone =
              partnerTrack != null &&
              (partnerTrack.answered || partnerTrack.passed);
          if (!partnerDone || isInCooldown(site.id, now)) continue;
          // No speed, closing or history gate here — the moment is "just
          // dealt with your own side, still at the gate", which is usually
          // slow and often already pulling away from a shared pin.
          if (best == null || km < best.km) {
            best = ProximityHit(site, km, near: true);
          }
          continue;
        }
      }

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

  /// Folds one fix into the derived travel heading. The bearing is measured
  /// from the last anchor fix and the anchor moves only on real displacement,
  /// so jitter while parked neither updates the heading nor poisons it.
  void _updateHeading(double lat, double lng) {
    final aLat = _headingAnchorLat;
    final aLng = _headingAnchorLng;
    if (aLat != null && aLng != null) {
      if (distanceKm(aLat, aLng, lat, lng) < headingMinMoveKm) return;
      _headingDeg = bearingDeg(aLat, aLng, lat, lng);
    }
    _headingAnchorLat = lat;
    _headingAnchorLng = lng;
  }

  /// For each directional site, its opposite-direction twin within
  /// [pairRadiusKm] (nearest wins) — the "same location, other carriageway"
  /// pairs the heading rule applies to. Lone directional sites stay unpaired
  /// and prompt as normal.
  Map<String, Site> _oppositePartners(Iterable<Site> sites) {
    final directional = [
      for (final s in sites)
        if (s.lat != null &&
            s.lng != null &&
            directionBearingDeg(s.direction) != null)
          s,
    ];
    final partners = <String, Site>{};
    for (final s in directional) {
      final bearing = directionBearingDeg(s.direction)!;
      Site? partner;
      double? partnerKm;
      for (final o in directional) {
        if (o.id == s.id) continue;
        if (angleDiffDeg(bearing, directionBearingDeg(o.direction)!) != 180.0) {
          continue;
        }
        final km = distanceKm(s.lat!, s.lng!, o.lat!, o.lng!);
        if (km > pairRadiusKm) continue;
        if (partnerKm == null || km < partnerKm) {
          partnerKm = km;
          partner = o;
        }
      }
      if (partner != null) partners[s.id] = partner;
    }
    return partners;
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
    _headingDeg = null;
    _headingAnchorLat = null;
    _headingAnchorLng = null;
  }
}
