import '../../models/enums.dart';
import '../../models/site.dart';
import '../../widgets/status_labels.dart';

/// The one line of context shown under the site name — on the in-app card and
/// as the body of the background notification, so both say the same thing.
///
/// The 10-hour freshness rule has already collapsed stale reports to Unknown
/// by the time a site reaches here (see `withEffectiveStatus`), so "no recent
/// reports" is exactly what an Unknown status means.
String approachStatusLine(Site site, {DateTime? now}) {
  if (site.currentStatus == SiteStatus.unknown || site.lastReportAt == null) {
    return 'No recent reports — what do you see?';
  }
  final label = statusDisplayLabel(site.currentStatus);
  return 'Reported $label ${relativeTime(site.lastReportAt!, now: now)}';
}

/// Compact "how long ago", matching the site cards.
String relativeTime(DateTime at, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
