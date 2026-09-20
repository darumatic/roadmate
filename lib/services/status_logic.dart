import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';

/// Pure status-derivation logic, deliberately free of Firebase/Flutter so it
/// can be unit-tested in isolation.

/// How long a report keeps a site's status "current" (issue #21): past this,
/// the site falls back to [SiteStatus.unknown].
const Duration statusFreshWindow = Duration(hours: 10);

/// The **stored rule** — all a build can do with the site doc alone, and what
/// every shipped build does: the stored (denormalised) status counts while
/// [lastReportAt] is inside [window] (issue #21), else [SiteStatus.unknown].
/// `lastReportAt` moves on ANY report, so this can't tell a fresh vote from a
/// fresh "Long queue"; [withEffectiveStatus] uses it only as the fallback.
SiteStatus effectiveStatus(
  SiteStatus reported,
  DateTime? lastReportAt, {
  required DateTime now,
  Duration window = statusFreshWindow,
}) {
  if (lastReportAt == null || now.difference(lastReportAt) > window) {
    return SiteStatus.unknown;
  }
  return reported;
}

/// What a Camera Only / BGD press (issue #48) is stored as: the legacy
/// 'Camera Only' activity report. The status has no stored form — every
/// shipped build parses an unknown status string as OPEN, and shipped phones
/// can't be hot-updated — so it rides on a document old builds already list
/// as a report, and [reportedStatusOf] turns it back into a status here.
const ActivityReportType cameraOnlyWireType = ActivityReportType.noActivity;

/// The status a report asserts, or null when it asserts none: a vote's own
/// status, or Camera Only / BGD for the two activity types that mean it. Both
/// count — whoever posted them, from whatever build — so an old build's
/// 'Camera Only' or 'BGD' report lights the fourth status for everyone who
/// can see it.
SiteStatus? reportedStatusOf(SiteReport report) {
  final voted = report.status;
  if (voted != null) return voted;
  return (report.activityType?.meansCameraOnly ?? false)
      ? SiteStatus.cameraOnly
      : null;
}

/// Each site's newest status-bearing report inside [window], keyed by site id.
/// Compares `createdAt` explicitly rather than trusting the stream's order.
Map<String, SiteReport> latestStatusReports(
  Iterable<SiteReport> reports, {
  required DateTime now,
  Duration window = statusFreshWindow,
}) {
  final cutoff = now.subtract(window);
  final latest = <String, SiteReport>{};
  for (final r in reports) {
    if (reportedStatusOf(r) == null || !r.createdAt.isAfter(cutoff)) continue;
    final seen = latest[r.siteId];
    if (seen == null || r.createdAt.isAfter(seen.createdAt)) {
      latest[r.siteId] = r;
    }
  }
  return latest;
}

/// Runaway-cost guard on the shared recent-reports query: every client reads
/// the whole window when its listener starts, so without a cap a flood of
/// spam would cost every app start as many reads as there are spam reports —
/// and the project has no billing account, so past the daily quota Firestore
/// stops serving reads altogether. The query is newest-first, so the freshest
/// reports win; a list this long may be missing the older end of the window —
/// see [withEffectiveStatus] for what that costs and what still works.
///
/// 1,000 is ~12x the busiest 10-hour window the app has seen (79 reports).
/// The nightly backup warns via ntfy long before it is reached
/// (`REPORT_VOLUME_ALERT` in scripts/backup_firestore.py — half this value;
/// test/backup_firestore_test.dart keeps the two in step).
const int recentReportsQueryCap = 1000;

/// The site list every screen consumes: each [Site.currentStatus] becomes the
/// status to *display*, and [Site.statusReportedAt] when it was reported.
///
/// **A status is current only while a status report stands behind it**
/// (issue #49): the newest Open / Blitz / Closed vote or Camera Only / BGD
/// report inside the 10h window is the site's status; with none, the site is
/// Unknown. The reports decide, not the site doc — so a later vote (even from
/// an old build) supersedes Camera Only / BGD, an admin removing or re-typing
/// a report reverts it with no counter to fix, and a "Long queue" no longer
/// brings a weeks-old Blitz back to life. That last one is what the stored
/// rule gets wrong: every activity report touches the site's `lastReportAt`,
/// the only thing [effectiveStatus] can look at, so ANY report makes the last
/// stored vote read as fresh — however old it is.
///
/// [Site.lastReportAt] keeps meaning "a report of any kind": the card's
/// "reported Xm ago" and Home's Recently Active follow every report, exactly
/// as old builds show them. It is only lifted to the status report's time
/// when the site doc lags behind it.
///
/// The stored rule remains the fallback, per site, whenever the reports can't
/// vouch for "no status report": [recentReports] is null (the stream is still
/// loading, or failed — the site list never waits on it), or it has hit
/// [recentReportsQueryCap] and may be cut short. That fallback is exactly what
/// old builds display, so it fails soft.
///
/// [inFlight] is this device's own posts the listeners can't show yet
/// (`InFlightPosts`, issue #50), laid over all of the above so a tap shows at
/// the tap. Each stands in for what its write will leave behind: it touches
/// the site's `lastReportAt` — whose pending value reads as null, which would
/// otherwise blank "reported Xm ago" and turn the stored rule Unknown until
/// the ack — and one that asserts a status IS the site's status. It outranks
/// every delivered report whatever the two clocks say, because the server
/// stamps a post when it commits, and this one has not committed yet. Kept
/// apart from [recentReports] on purpose: merged in, a lone in-flight post
/// would make a still-loading list look complete, and every other site
/// Unknown.
List<Site> withEffectiveStatus(
  List<Site> sites, {
  Iterable<SiteReport>? recentReports,
  Iterable<SiteReport> inFlight = const [],
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final reports = recentReports?.toList(growable: false);
  final latest = latestStatusReports(reports ?? const [], now: at);
  final complete = reports != null && reports.length < recentReportsQueryCap;
  // Both in posting order, so a later post replaces an earlier one for the
  // same site. The touch counts for as long as a post is held, delivered or
  // not: the two listeners answer an ack in separate snapshots, and for the
  // moment the report is in and the site doc is not, the touch reads as null.
  final touching = {
    for (final post in reportsWithinWindow(inFlight, now: at))
      post.siteId: post,
  };
  final asserting = {
    for (final post in undeliveredPosts(inFlight, reports ?? const [], now: at))
      if (reportedStatusOf(post) != null) post.siteId: post,
  };
  return [
    for (final s in sites)
      _withDisplayStatus(
        _touchedBy(s, touching[s.id]),
        asserting[s.id] ?? latest[s.id],
        at,
        reportsComplete: complete,
      ),
  ];
}

/// [site] as [post]'s write will leave it: every post touches `lastReportAt`.
Site _touchedBy(Site site, SiteReport? post) {
  if (post == null) return site;
  final touched = site.lastReportAt;
  if (touched != null && touched.isAfter(post.createdAt)) return site;
  return site.copyWith(lastReportAt: post.createdAt);
}

Site _withDisplayStatus(
  Site site,
  SiteReport? latest,
  DateTime now, {
  required bool reportsComplete,
}) {
  if (latest != null) {
    final touched = site.lastReportAt;
    return site.copyWith(
      currentStatus: reportedStatusOf(latest),
      statusReportedAt: latest.createdAt,
      lastReportAt: touched != null && touched.isAfter(latest.createdAt)
          ? touched
          : latest.createdAt,
    );
  }
  if (reportsComplete) {
    // Every report in the window is here, and none of them asserts a status:
    // whatever keeps `lastReportAt` fresh, it isn't a status report.
    return site.copyWith(currentStatus: SiteStatus.unknown);
  }
  final stored = effectiveStatus(
    site.currentStatus,
    site.lastReportAt,
    now: now,
  );
  return site.copyWith(
    currentStatus: stored,
    // The stored rule can't tell a vote from a touch; the touch is all it has.
    statusReportedAt: stored == SiteStatus.unknown ? null : site.lastReportAt,
  );
}

/// Activity reports (Long queue, Delays, …) still fresh enough to show to
/// drivers — the same 10-hour window statuses live by. Older reports are
/// hidden, never deleted: the full history stays in Firestore as the audit log
/// (the admin feed is deliberately unfiltered).
///
/// A Camera Only / BGD report is **not** listed (issue #52). On builds that
/// know the fourth status it is how that status travels (issue #48), so
/// listing it gave every press of the blue button a row of its own — five
/// taps, five "Camera Only" rows — while Open, Blitz and Closed only ever
/// light their button. The button, the badge and "reported Xm ago" already say
/// it. The exception is one that carries a note: only an old build's Report
/// dialog can write that, and a driver's own words ("gate down, officers still
/// waving trucks in") are information the status alone doesn't hold.
List<SiteReport> recentActivityReports(
  Iterable<SiteReport> reports, {
  DateTime? now,
  Duration window = statusFreshWindow,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(window);
  return reports
      .where((r) => _isListedActivity(r) && r.createdAt.isAfter(cutoff))
      .toList();
}

bool _isListedActivity(SiteReport report) {
  final type = report.activityType;
  if (type == null) return false;
  if (!type.meansCameraOnly) return true;
  return report.activityNote?.trim().isNotEmpty ?? false;
}

/// Every report (status votes and activity alike) still inside [window] —
/// the exact client-side filter over the shared recent-reports stream, whose
/// server query is only a ≥[window] cost bound fixed at subscription time.
List<SiteReport> reportsWithinWindow(
  Iterable<SiteReport> reports, {
  DateTime? now,
  Duration window = statusFreshWindow,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(window);
  return [
    for (final r in reports)
      if (r.createdAt.isAfter(cutoff)) r,
  ];
}

/// A single site's slice of the shared recent-reports stream, preserving the
/// stream's most-recent-first order.
List<SiteReport> reportsForSite(Iterable<SiteReport> reports, String siteId) {
  return [
    for (final r in reports)
      if (r.siteId == siteId) r,
  ];
}

/// The [inFlight] posts (`InFlightPosts`, issue #50) still standing in for a
/// document the listener has not [delivered], in posting order. A delivered
/// one is shadowed — matched by id, which a held post shares with the document
/// it becomes — so the real report takes over with its server time, on equal
/// terms with everyone else's, and is never listed twice. A post older than
/// [window] is dropped like any other report: a vote that has sat in the
/// offline queue all night is not a current status.
List<SiteReport> undeliveredPosts(
  Iterable<SiteReport> inFlight,
  Iterable<SiteReport> delivered, {
  DateTime? now,
  Duration window = statusFreshWindow,
}) {
  final held = reportsWithinWindow(inFlight, now: now, window: window);
  if (held.isEmpty) return held;
  final deliveredIds = {for (final r in delivered) r.id};
  return [
    for (final post in held)
      if (!deliveredIds.contains(post.id)) post,
  ];
}

/// The shared recent-reports list with this device's [inFlight] posts on top —
/// most-recent first like the stream itself, and an in-flight post is by
/// construction the newest thing there is. Feeds the cards' Recent reports,
/// so a "Long queue" is listed at the tap rather than at the ack.
List<SiteReport> withInFlightPosts(
  List<SiteReport> delivered,
  Iterable<SiteReport> inFlight, {
  DateTime? now,
}) {
  final held = undeliveredPosts(inFlight, delivered, now: now);
  return held.isEmpty ? delivered : [...held.reversed, ...delivered];
}
