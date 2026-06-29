import '../models/enums.dart';
import '../models/site_report.dart';

/// Pure status-derivation logic, deliberately free of Firebase/Flutter so it
/// can be unit-tested in isolation.
///
/// Displayed status of a site = the status of the most recent report within
/// [window]. If there are no recent status reports, the site is treated as
/// [SiteStatus.open] (no news = open road).
class StatusLogic {
  const StatusLogic({this.window = const Duration(hours: 6)});

  /// How far back a report still counts as "current".
  final Duration window;

  /// Derive the live status from a site's reports, relative to [now].
  SiteStatus deriveStatus(List<SiteReport> reports, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final recent = _recentStatusReports(reports, at);
    if (recent.isEmpty) return SiteStatus.open;
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
