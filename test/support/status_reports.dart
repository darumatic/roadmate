import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';

/// The status report standing behind each site's stored status — what a real
/// vote always leaves in the recent-reports stream, since the vote batch
/// writes the report and the site doc atomically.
///
/// Since issue #49 a status is only current while such a report is inside the
/// 10h window, so a fake repository that serves a site "voted Blitz just now"
/// must serve this beside it — a fresh stored vote with nothing in the stream
/// is a world that cannot exist, and the site would rightly show as Unknown.
List<SiteReport> votesBehind(Iterable<Site> sites) => [
  for (final site in sites)
    if (site.lastReportAt != null && site.currentStatus.isStored)
      SiteReport(
        id: 'vote-${site.id}',
        siteId: site.id,
        createdAt: site.lastReportAt!,
        status: site.currentStatus,
      ),
];
