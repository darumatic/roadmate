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

/// Maps every site's [Site.currentStatus] through [effectiveStatus], so stale
/// statuses render as Unknown everywhere the site list is consumed.
List<Site> withEffectiveStatus(List<Site> sites, {DateTime? now}) {
  final at = now ?? DateTime.now();
  return [
    for (final s in sites)
      s.copyWith(
        currentStatus: effectiveStatus(
          s.currentStatus,
          s.lastReportAt,
          now: at,
        ),
      ),
  ];
}

/// Displayed status of a site = the status of the most recent report within
/// [window]. If there are no recent status reports, the site's live status is
/// [SiteStatus.unknown] (issue #21).
class StatusLogic {
  const StatusLogic({this.window = statusFreshWindow});

  /// How far back a report still counts as "current".
  final Duration window;

  /// Derive the live status from a site's reports, relative to [now].
  SiteStatus deriveStatus(List<SiteReport> reports, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final recent = _recentStatusReports(reports, at);
    if (recent.isEmpty) return SiteStatus.unknown;
    recent.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return recent.first.status!;
  }

  /// Whether a blitz has been reported within [window] of [now].
  bool isBlitzActive(List<SiteReport> reports, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return _recentStatusReports(
      reports,
      at,
    ).any((r) => r.status == SiteStatus.blitz);
  }

  List<SiteReport> _recentStatusReports(List<SiteReport> reports, DateTime at) {
    final cutoff = at.subtract(window);
    return reports
        .where((r) => r.status != null && r.createdAt.isAfter(cutoff))
        .toList();
  }
}
