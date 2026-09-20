import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';
import 'participation_logic.dart';
import 'site_repository.dart';
import 'status_logic.dart';

/// In-memory [SiteRepository] backed by the bundled seed JSON. Used for local
/// development, demos and tests; replaced by a Firestore implementation in a
/// later phase. Writes are kept in memory only.
class LocalSeedSiteRepository implements SiteRepository {
  LocalSeedSiteRepository({
    this.assetPath = 'sites/nhvr_national_inspection_sites.json',
  });

  final String assetPath;

  final _sites = <Site>[];
  final _reports = <String, List<SiteReport>>{};
  final _favourites = <String>{};
  Future<void>? _loading;
  int _seq = 0;
  var _stats = const ParticipationStats();

  final _sitesController = StreamController<List<Site>>.broadcast();
  final _favouritesController = StreamController<Set<String>>.broadcast();
  final _allReportsController = StreamController<List<SiteReport>>.broadcast();
  final _statsController = StreamController<ParticipationStats?>.broadcast();

  /// Memoized: the site list and the recent-reports stream are subscribed
  /// together at startup (the displayed status is derived from both), and a
  /// second concurrent load would clear the list under the first.
  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    _sites
      ..clear()
      ..addAll(parseNhvrNationalData(json));
  }

  @override
  Stream<List<Site>> watchSites() async* {
    await _ensureLoaded();
    yield List.unmodifiable(_sites);
    yield* _sitesController.stream;
  }

  @override
  Stream<List<SiteReport>> watchAllRecentReports() async* {
    await _ensureLoaded();
    yield _recentReportsSnapshot();
    yield* _allReportsController.stream;
  }

  List<SiteReport> _recentReportsSnapshot() {
    final recent = reportsWithinWindow(_reports.values.expand((l) => l))
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(recent);
  }

  @override
  Future<void> vote(
    Site site,
    SiteStatus status, {
    String? reporterName,
  }) async {
    // Same routing as FirestoreSiteRepository.vote: Camera Only / BGD has no
    // stored form and travels as the 'Camera Only' activity report.
    if (status == SiteStatus.cameraOnly) {
      return _postActivity(
        site,
        cameraOnlyWireType,
        reporterName: reporterName,
        credit: ParticipationAction.vote,
      );
    }
    if (!status.isStored) {
      throw ArgumentError.value(status, 'status', 'has no stored form');
    }
    await _ensureLoaded();
    final siteId = site.id;
    _addReport(
      SiteReport(
        id: 'r${_seq++}',
        siteId: siteId,
        createdAt: DateTime.now(),
        status: status,
        reporterName: storedText(reporterName),
      ),
    );
    final i = _sites.indexWhere((s) => s.id == siteId);
    if (i != -1) {
      final s = _sites[i];
      _sites[i] = s.copyWith(
        currentStatus: status,
        lastReportAt: DateTime.now(),
        openVotes: s.openVotes + (status == SiteStatus.open ? 1 : 0),
        blitzVotes: s.blitzVotes + (status == SiteStatus.blitz ? 1 : 0),
        closedVotes: s.closedVotes + (status == SiteStatus.closed ? 1 : 0),
      );
      _sitesController.add(List.unmodifiable(_sites));
    }
    _recordAction(ParticipationAction.vote);
  }

  @override
  Future<void> report(
    Site site,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  }) {
    return _postActivity(
      site,
      activityType,
      activityNote: activityNote,
      reporterName: reporterName,
      credit: ParticipationAction.report,
    );
  }

  /// In-memory twin of `FirestoreSiteRepository.postActivity`: the report
  /// plus the site's `lastReportAt` touch, never its status.
  Future<void> _postActivity(
    Site site,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
    required ParticipationAction credit,
  }) async {
    await _ensureLoaded();
    final now = DateTime.now();
    _addReport(
      SiteReport(
        id: 'r${_seq++}',
        siteId: site.id,
        createdAt: now,
        activityType: activityType,
        activityNote: storedText(activityNote),
        reporterName: storedText(reporterName),
        reporterLevel: reporterLevelToStamp(_stats, credit),
      ),
    );
    final i = _sites.indexWhere((s) => s.id == site.id);
    if (i != -1) {
      _sites[i] = _sites[i].copyWith(lastReportAt: now);
      _sitesController.add(List.unmodifiable(_sites));
    }
    _recordAction(credit);
  }

  @override
  Future<void> addSite(
    Site site, {
    bool approved = false,
    String? submitterName,
  }) async {
    await _ensureLoaded();
    _sites.add(site);
    _sitesController.add(List.unmodifiable(_sites));
    _recordAction(ParticipationAction.addSite);
  }

  @override
  Stream<ParticipationStats?> watchMyStats() async* {
    yield _stats;
    yield* _statsController.stream;
  }

  void _recordAction(ParticipationAction action) {
    _stats = _stats.after(action);
    _statsController.add(_stats);
  }

  @override
  Stream<Set<String>> watchFavourites() async* {
    yield Set.unmodifiable(_favourites);
    yield* _favouritesController.stream;
  }

  @override
  Future<void> toggleFavourite(String siteId) async {
    if (!_favourites.add(siteId)) _favourites.remove(siteId);
    _favouritesController.add(Set.unmodifiable(_favourites));
  }

  void _addReport(SiteReport report) {
    final list = _reports.putIfAbsent(report.siteId, () => <SiteReport>[]);
    list.insert(0, report);
    _allReportsController.add(_recentReportsSnapshot());
  }

  void dispose() {
    _sitesController.close();
    _favouritesController.close();
    _allReportsController.close();
    _statsController.close();
  }
}
