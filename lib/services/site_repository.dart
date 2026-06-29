import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';

/// Abstraction over site storage so the app can run against bundled seed data
/// today and swap in a Firestore-backed implementation once Firebase is wired,
/// without touching the UI. Also keeps unit tests offline.
abstract class SiteRepository {
  /// Live stream of all (approved) sites.
  Stream<List<Site>> watchSites();

  /// Live stream of recent reports for a single site (most-recent first).
  Stream<List<SiteReport>> watchReports(String siteId);

  /// Record a status vote for a site.
  Future<void> vote(String siteId, SiteStatus status);

  /// Record an activity report for a site.
  Future<void> report(
    String siteId,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  });

  /// Submit a new (community-added) site.
  Future<void> addSite(Site site);

  /// IDs of sites the current user has favourited.
  Stream<Set<String>> watchFavourites();

  /// Toggle a site in/out of the user's favourites set.
  Future<void> toggleFavourite(String siteId);
}

/// Parse the authoritative NHVR national dataset
/// (`sites/nhvr_national_inspection_sites.json`) into a flat list of [Site].
///
/// Schema: `states -> { <CODE>: { facility_type, stations: [...] } }`. States
/// with no stations (WA/NT — non-participating) yield nothing. Pure function,
/// no Flutter dependency, so it is directly unit-testable.
List<Site> parseNhvrNationalData(Map<String, dynamic> json) {
  final states = json['states'] as Map<String, dynamic>? ?? const {};
  final sites = <Site>[];
  states.forEach((code, value) {
    final state = AusState.fromCode(code);
    final group = value as Map<String, dynamic>;
    final facilityType = group['facility_type'] as String? ?? '';
    final stations = group['stations'] as List? ?? const [];
    for (final station in stations) {
      sites.add(
        Site.fromNhvrStation(
          station as Map<String, dynamic>,
          state: state,
          facilityType: facilityType,
        ),
      );
    }
  });
  return sites;
}
