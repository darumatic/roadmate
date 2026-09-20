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

/// Runaway-cost guard on the shared recent-reports query. At the enforced
/// rate limit (5 actions/5min/user) it only bites under coordinated spam, and
/// the query is newest-first, so the freshest reports win. A list this long
/// may be missing the older end of the window — see [withEffectiveStatus].
const int recentReportsQueryCap = 500;

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
List<Site> withEffectiveStatus(
  List<Site> sites, {
  Iterable<SiteReport>? recentReports,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final reports = recentReports?.toList(growable: false);
  final latest = latestStatusReports(reports ?? const [], now: at);
  final complete = reports != null && reports.length < recentReportsQueryCap;
  return [
    for (final s in sites)
      _withDisplayStatus(s, latest[s.id], at, reportsComplete: complete),
  ];
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

/// Activity reports (BGD, Delays, …) still fresh enough to show to drivers —
/// the same 10-hour window statuses live by. Older reports are hidden, never
/// deleted: the full history stays in Firestore as the audit log (the admin
/// feed is deliberately unfiltered).
List<SiteReport> recentActivityReports(
  Iterable<SiteReport> reports, {
  DateTime? now,
  Duration window = statusFreshWindow,
}) {
  final cutoff = (now ?? DateTime.now()).subtract(window);
  return reports
      .where((r) => r.activityType != null && r.createdAt.isAfter(cutoff))
      .toList();
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
