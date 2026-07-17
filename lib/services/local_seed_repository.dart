import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';
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
  bool _loaded = false;
  int _seq = 0;

  final _sitesController = StreamController<List<Site>>.broadcast();
  final _favouritesController = StreamController<Set<String>>.broadcast();
  final _allReportsController = StreamController<List<SiteReport>>.broadcast();

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    _sites
      ..clear()
      ..addAll(parseNhvrNationalData(json));
    _loaded = true;
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
  Future<void> vote(String siteId, SiteStatus status) async {
    await _ensureLoaded();
    _addReport(
      SiteReport(
        id: 'r${_seq++}',
        siteId: siteId,
        createdAt: DateTime.now(),
        status: status,
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
  }

  @override
  Future<void> report(
    String siteId,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  }) async {
    await _ensureLoaded();
    _addReport(
      SiteReport(
        id: 'r${_seq++}',
        siteId: siteId,
        createdAt: DateTime.now(),
        activityType: activityType,
        activityNote: activityNote?.trim().isEmpty ?? true
            ? null
            : activityNote!.trim(),
        reporterName: reporterName?.trim().isEmpty ?? true
            ? null
            : reporterName!.trim(),
      ),
    );
  }

  @override
  Future<void> addSite(Site site, {bool approved = false}) async {
    await _ensureLoaded();
    _sites.add(site);
    _sitesController.add(List.unmodifiable(_sites));
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
  }
}
