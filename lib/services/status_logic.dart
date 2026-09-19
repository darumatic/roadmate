import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';

/// Pure status-derivation logic, deliberately free of Firebase/Flutter so it
/// can be unit-tested in isolation.

/// How long a report keeps a site's status "current" (issue #21): past this,
/// the site falls back to [SiteStatus.unknown].
const Duration statusFreshWindow = Duration(hours: 10);

/// The status a site should display, given its stored (denormalised) status
/// and when it was last reported (issue #21): a site with no report, or whose
/// latest report is older than [window], shows [SiteStatus.unknown].
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

/// The site list every screen consumes: each [Site.currentStatus] becomes the
/// status to *display*.
///
/// Stored statuses go through [effectiveStatus], so stale ones render as
/// Unknown. On top of that, a site whose newest status-bearing report in
/// [recentReports] says Camera Only / BGD displays that — so a later
/// Open/Blitz/Closed vote (even from an old build) supersedes it, and an admin
/// removing or re-typing the report reverts it with no counter to fix. The
/// report proves its own freshness, so the override doesn't consult the site's
/// `lastReportAt`; it only lifts it, for the "reported Xm ago" lines.
///
/// With no [recentReports] (the stream still loading, or failed) this is
/// exactly the stored-status rule old builds apply — it fails soft.
List<Site> withEffectiveStatus(
  List<Site> sites, {
  Iterable<SiteReport> recentReports = const [],
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final latest = latestStatusReports(recentReports, now: at);
  return [for (final s in sites) _withDisplayStatus(s, latest[s.id], at)];
}

Site _withDisplayStatus(Site site, SiteReport? latest, DateTime now) {
  if (latest != null && reportedStatusOf(latest) == SiteStatus.cameraOnly) {
    final touched = site.lastReportAt;
    return site.copyWith(
      currentStatus: SiteStatus.cameraOnly,
      lastReportAt: touched != null && touched.isAfter(latest.createdAt)
          ? touched
          : latest.createdAt,
    );
  }
  return site.copyWith(
    currentStatus: effectiveStatus(
      site.currentStatus,
      site.lastReportAt,
      now: now,
    ),
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
