/// Participation points, levels and badges — the purely virtual rewards for
/// community activity (status votes and activity reports).
///
/// Everything here is derived client-side from the two counters stored in
/// `users/{uid}/stats/participation` (`votes`, `reports`). There is no stored
/// `points` field on purpose: points are a pure function of the counters, so
/// the rules only ever have to validate "+1 to one counter" and never any
/// arithmetic. Level names, thresholds and badge definitions can all change
/// in a client release without touching data or rules.
///
/// Pure Dart, no Flutter/Firebase imports — the icon for each level lives in
/// `widgets/level_badge.dart`. Firestore sentinels are injected into the
/// payload builders (same pattern as `rate_limit.dart`).
library;

/// Points awarded per action. Display/documentation values — the counters in
/// Firestore stay raw so these can be re-balanced freely later.
const int kPointsPerVote = 5;
const int kPointsPerReport = 10;

/// The participation actions tracked today. Votes and reports earn points;
/// adding a site earns the Trailblazer badge only — credited at *submission*
/// time (a self-action, like the others), deliberately not at approval:
/// approvals also happen straight in the Firebase console, where no client
/// code runs to hand out the credit. Points for *approved* submissions
/// remain a phase-2 idea.
enum ParticipationAction { vote, report, addSite }

/// The user's raw participation counters, mirroring the
/// `users/{uid}/stats/participation` doc.
class ParticipationStats {
  const ParticipationStats({
    this.votes = 0,
    this.reports = 0,
    this.sitesAdded = 0,
  });

  final int votes;
  final int reports;
  final int sitesAdded;

  int get actions => votes + reports + sitesAdded;
  int get points => votes * kPointsPerVote + reports * kPointsPerReport;

  ParticipationStats after(ParticipationAction action) {
    return ParticipationStats(
      votes: votes + (action == ParticipationAction.vote ? 1 : 0),
      reports: reports + (action == ParticipationAction.report ? 1 : 0),
      sitesAdded: sitesAdded + (action == ParticipationAction.addSite ? 1 : 0),
    );
  }

  factory ParticipationStats.fromMap(Map<String, dynamic> map) {
    return ParticipationStats(
      votes: (map['votes'] as num?)?.toInt() ?? 0,
      reports: (map['reports'] as num?)?.toInt() ?? 0,
      sitesAdded: (map['sitesAdded'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One rung of the ladder. [index1] is 1-based and is what gets denormalized
/// into report docs as `reporterLevel` — an int so re-flavouring the titles
/// never touches stored data.
class ParticipationLevel {
  const ParticipationLevel({
    required this.index1,
    required this.title,
    required this.minPoints,
  });

  final int index1;
  final String title;
  final int minPoints;
}

/// The ladder, ascending. Thresholds are owner-tweakable; the rules only cap
/// `reporterLevel` at a loose 99, so adding rungs never needs a rules deploy.
const List<ParticipationLevel> kLevels = [
  ParticipationLevel(index1: 1, title: 'Rookie', minPoints: 0),
  ParticipationLevel(index1: 2, title: 'Local Runner', minPoints: 50),
  ParticipationLevel(index1: 3, title: 'Highway Regular', minPoints: 150),
  ParticipationLevel(index1: 4, title: 'Interstate Pro', minPoints: 400),
  ParticipationLevel(index1: 5, title: 'Road Train Boss', minPoints: 1000),
  ParticipationLevel(index1: 6, title: 'Outback Legend', minPoints: 2500),
];

/// The highest rung whose threshold [points] has reached.
ParticipationLevel levelForPoints(int points) {
  var level = kLevels.first;
  for (final rung in kLevels) {
    if (points >= rung.minPoints) level = rung;
  }
  return level;
}

/// The rung shown for a stored `reporterLevel` index, or null when the value
/// is absent/out of range (e.g. a doc written by a newer client with more
/// rungs than this build knows — show nothing rather than lie).
ParticipationLevel? levelForIndex(int? index1) {
  if (index1 == null || index1 < 1 || index1 > kLevels.length) return null;
  return kLevels[index1 - 1];
}

/// The next rung above [points], or null at the top of the ladder.
ParticipationLevel? nextLevelForPoints(int points) {
  for (final rung in kLevels) {
    if (rung.minPoints > points) return rung;
  }
  return null;
}

/// Progress from the current rung's threshold toward the next, 0..1.
/// 1.0 at the top of the ladder (the bar reads full, not empty).
double progressToNextLevel(int points) {
  final current = levelForPoints(points);
  final next = nextLevelForPoints(points);
  if (next == null) return 1.0;
  final span = next.minPoints - current.minPoints;
  return (points - current.minPoints) / span;
}

/// The `reporterLevel` to stamp on a report being written right now: the
/// level the author holds *after* this action. [lastKnown] may be stale or
/// null (first-ever post, fetch failed) — gamification must never block a
/// post, so null degrades to level 1.
int reporterLevelToStamp(
  ParticipationStats? lastKnown,
  ParticipationAction action,
) {
  final stats = (lastKnown ?? const ParticipationStats()).after(action);
  return levelForPoints(stats.points).index1;
}

/// Payload for the stats write committed in the same batch as every vote,
/// activity report and site submission (`set` with merge). Sentinels are
/// injected so this stays testable without Firestore: [plusOne]/[plusZero]
/// must be `FieldValue.increment(1)`/`increment(0)` and [serverTime]
/// `FieldValue.serverTimestamp()` in production. Every counter always
/// appears — `increment(0)` on the untouched ones — so the create shape
/// carries the full key set `isStatsSeed` validates in firestore.rules.
Map<String, Object> statsIncrementPayload(
  ParticipationAction action, {
  required Object plusOne,
  required Object plusZero,
  required Object serverTime,
}) {
  return {
    'votes': action == ParticipationAction.vote ? plusOne : plusZero,
    'reports': action == ParticipationAction.report ? plusOne : plusZero,
    'sitesAdded': action == ParticipationAction.addSite ? plusOne : plusZero,
    'updatedAt': serverTime,
  };
}

/// "12,345" — thousands-separated points for display.
String formatPoints(int points) {
  final digits = points.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Which counter a badge watches.
enum BadgeMetric { votes, reports, sitesAdded, actions }

/// A badge is a threshold on one counter — derived entirely from
/// [ParticipationStats], zero extra storage.
class ParticipationBadge {
  const ParticipationBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.metric,
    required this.threshold,
  });

  final String id;
  final String title;
  final String description;
  final BadgeMetric metric;
  final int threshold;

  bool unlockedBy(ParticipationStats stats) {
    final value = switch (metric) {
      BadgeMetric.votes => stats.votes,
      BadgeMetric.reports => stats.reports,
      BadgeMetric.sitesAdded => stats.sitesAdded,
      BadgeMetric.actions => stats.actions,
    };
    return value >= threshold;
  }
}

const List<ParticipationBadge> kBadges = [
  ParticipationBadge(
    id: 'firstVote',
    title: 'First Vote',
    description: 'Cast your first status vote',
    metric: BadgeMetric.votes,
    threshold: 1,
  ),
  ParticipationBadge(
    id: 'firstReport',
    title: 'First Report',
    description: 'Post your first activity report',
    metric: BadgeMetric.reports,
    threshold: 1,
  ),
  ParticipationBadge(
    id: 'spotter',
    title: 'Spotter',
    description: '10 status votes',
    metric: BadgeMetric.votes,
    threshold: 10,
  ),
  ParticipationBadge(
    id: 'informer',
    title: 'Informer',
    description: '10 activity reports',
    metric: BadgeMetric.reports,
    threshold: 10,
  ),
  ParticipationBadge(
    id: 'eagleEye',
    title: 'Eagle Eye',
    description: '50 status votes',
    metric: BadgeMetric.votes,
    threshold: 50,
  ),
  ParticipationBadge(
    id: 'convoyCaptain',
    title: 'Convoy Captain',
    description: '50 activity reports',
    metric: BadgeMetric.reports,
    threshold: 50,
  ),
  ParticipationBadge(
    id: 'trailblazer',
    title: 'Trailblazer',
    description: 'Add a site to the map',
    metric: BadgeMetric.sitesAdded,
    threshold: 1,
  ),
  ParticipationBadge(
    id: 'centuryClub',
    title: 'Century Club',
    description: '100 total actions',
    metric: BadgeMetric.actions,
    threshold: 100,
  ),
];

/// The badges [stats] has unlocked, in [kBadges] order.
List<ParticipationBadge> badgesFor(ParticipationStats stats) {
  return kBadges.where((b) => b.unlockedBy(stats)).toList();
}
