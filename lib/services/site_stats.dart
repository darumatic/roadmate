import '../models/enums.dart';
import '../models/site.dart';

/// Pure aggregation helpers over a list of sites, used by the Home screen.
/// Kept Flutter-free for straightforward unit testing.

/// Count of sites in each [SiteStatus] across [sites].
class StatusCounts {
  const StatusCounts({this.open = 0, this.blitz = 0, this.closed = 0});

  final int open;
  final int blitz;
  final int closed;

  int get total => open + blitz + closed;
}

/// States shown in the app, preserving the enum order used by the UI.
const visibleStates = AusState.values;

StatusCounts countByStatus(Iterable<Site> sites) {
  var open = 0, blitz = 0, closed = 0;
  for (final s in sites) {
    switch (s.currentStatus) {
      case SiteStatus.open:
        open++;
      case SiteStatus.blitz:
        blitz++;
      case SiteStatus.closed:
        closed++;
    }
  }
  return StatusCounts(open: open, blitz: blitz, closed: closed);
}

/// Group sites by their state, preserving the UI state order and including
/// visible states that currently have no sites.
Map<AusState, List<Site>> groupByState(Iterable<Site> sites) {
  final map = {for (final state in visibleStates) state: <Site>[]};
  for (final s in sites) {
    map[s.state]?.add(s);
  }
  return map;
}

/// Sites currently flagged as a blitz.
List<Site> blitzSites(Iterable<Site> sites) =>
    sites.where((s) => s.currentStatus == SiteStatus.blitz).toList();

/// Sites with the most recent community activity, newest first.
List<Site> recentlyActive(Iterable<Site> sites, {int limit = 5}) {
  final withActivity = sites.where((s) => s.lastReportAt != null).toList()
    ..sort((a, b) => b.lastReportAt!.compareTo(a.lastReportAt!));
  return withActivity.take(limit).toList();
}

/// Filter sites by a case-insensitive query over name, suburb and state.
List<Site> searchSites(Iterable<Site> sites, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return sites.toList();
  return sites.where((s) {
    return s.name.toLowerCase().contains(q) ||
        s.suburb.toLowerCase().contains(q) ||
        s.address.toLowerCase().contains(q) ||
        s.state.code.toLowerCase().contains(q) ||
        s.state.fullName.toLowerCase().contains(q);
  }).toList();
}
