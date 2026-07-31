import '../models/enums.dart';
import '../models/site_report.dart';

/// Pure logic behind the admin's report removals — deliberately free of
/// Firebase/Flutter so it can be unit-tested in isolation.

/// How far back an admin purge reaches: the same window a report stays
/// "current" for, so removing a spammer's reports clears exactly what drivers
/// can still see. Older reports are already invisible in every client and are
/// left alone as history.
const Duration purgeWindow = Duration(hours: 10);

/// Firestore's hard limit on writes in one batch. Purges chunk below it, since
/// a spammer can easily leave more than 500 reports behind.
const int firestoreBatchLimit = 500;

/// How recent a status vote must be to still set a site's stored
/// `currentStatus` when tallies are recounted. Narrower than [purgeWindow] on
/// purpose — it is the window `deleteReport` has always used, and clients
/// re-check freshness themselves via `statusFreshWindow`.
const Duration statusRecountWindow = Duration(hours: 6);

/// A site's denormalised counters, recomputed from the reports that survive a
/// removal. Writing absolute values (rather than decrementing) means a purge
/// that is retried after a partial failure still lands on the right numbers.
class SiteTallies {
  const SiteTallies({
    required this.openVotes,
    required this.blitzVotes,
    required this.closedVotes,
    required this.currentStatus,
    required this.lastReportAt,
  });

  final int openVotes;
  final int blitzVotes;
  final int closedVotes;
  final SiteStatus currentStatus;

  /// Null when nothing is left under the site — the caller deletes the field.
  final DateTime? lastReportAt;
}

/// Recounts a site's tallies from the reports remaining after a removal.
///
/// A site whose recent status votes were all removed falls back to
/// [SiteStatus.open], matching what the site doc holds before its first vote.
SiteTallies talliesFrom(
  Iterable<SiteReport> remaining, {
  required DateTime now,
  Duration statusWindow = statusRecountWindow,
}) {
  final counts = {
    SiteStatus.open: 0,
    SiteStatus.blitz: 0,
    SiteStatus.closed: 0,
  };
  DateTime? lastReportAt;
  var currentStatus = SiteStatus.open;
  DateTime? currentStatusAt;
  final cutoff = now.subtract(statusWindow);

  for (final report in remaining) {
    if (lastReportAt == null || report.createdAt.isAfter(lastReportAt)) {
      lastReportAt = report.createdAt;
    }
    final status = report.status;
    if (status == null) continue;
    counts[status] = counts[status]! + 1;
    if (report.createdAt.isAfter(cutoff) &&
        (currentStatusAt == null ||
            report.createdAt.isAfter(currentStatusAt))) {
      currentStatus = status;
      currentStatusAt = report.createdAt;
    }
  }

  return SiteTallies(
    openVotes: counts[SiteStatus.open]!,
    blitzVotes: counts[SiteStatus.blitz]!,
    closedVotes: counts[SiteStatus.closed]!,
    currentStatus: currentStatus,
    lastReportAt: lastReportAt,
  );
}

/// Groups a flat list of `(siteId, reportId)` pairs by site, preserving the
/// order each site was first seen. A purge spans however many sites the user
/// posted to, and each site's tallies are rewritten once.
Map<String, List<String>> groupReportIdsBySite(
  Iterable<(String siteId, String reportId)> reports,
) {
  final grouped = <String, List<String>>{};
  for (final (siteId, reportId) in reports) {
    if (siteId.isEmpty) continue;
    grouped.putIfAbsent(siteId, () => <String>[]).add(reportId);
  }
  return grouped;
}

/// Splits [items] into batches of at most [size].
List<List<T>> chunked<T>(List<T> items, {int size = firestoreBatchLimit}) {
  assert(size > 0);
  return [
    for (var i = 0; i < items.length; i += size)
      items.sublist(i, i + size > items.length ? items.length : i + size),
  ];
}

/// Whether the bulk "remove this user's recent reports" action is offered.
///
/// Web only. It is the most destructive tool in the admin surface, and the web
/// build is the one that can be rolled back within minutes — shipped Android
/// and iOS builds sit on users' phones for months with no way to withdraw a
/// mistake. Single-report removal and bans stay available everywhere.
bool showBulkReportPurge({required bool isWeb}) => isWeb;
