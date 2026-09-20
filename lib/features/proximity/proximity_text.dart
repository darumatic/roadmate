import '../../models/enums.dart';
import '../../models/site.dart';
import '../../services/relative_time.dart';
import '../../widgets/status_labels.dart';

export '../../services/relative_time.dart' show relativeTime;

/// The one line of context shown under the site name — on the in-app card and
/// as the body of the background notification, so both say the same thing.
///
/// The 10-hour freshness rule has already collapsed a site with no recent
/// status report to Unknown by the time it reaches here (see
/// `withEffectiveStatus`), so "no recent reports" is exactly what an Unknown
/// status means.
///
/// The time quoted is the STATUS report's ([Site.statusReportedAt]), not the
/// site's latest report of any kind: "Reported Closed 5m ago" would be a lie
/// when Closed was voted three hours ago and the 5 minutes belong to someone's
/// "Long queue".
String approachStatusLine(Site site, {DateTime? now}) {
  final reportedAt = site.statusReportedAt ?? site.lastReportAt;
  if (site.currentStatus == SiteStatus.unknown || reportedAt == null) {
    return 'No recent reports — what do you see?';
  }
  final label = statusDisplayLabel(site.currentStatus);
  return 'Reported $label ${relativeTime(reportedAt, now: now)}';
}
