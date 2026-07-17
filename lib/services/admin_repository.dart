import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/admin_report.dart';
import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';

/// Whether the cached site-name map already resolves every referenced site.
/// Empty ids (a report whose parent site cannot be determined) never force a
/// refetch — no fetch could resolve them anyway.
bool siteNamesCover(Map<String, String> names, Iterable<String> siteIds) {
  return siteIds.every((id) => id.isEmpty || names.containsKey(id));
}

class AdminRepository {
  AdminRepository({required this.firestore, required this.auth});

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> get _sites =>
      firestore.collection('sites');

  Map<String, dynamic> _normalise(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.toDate().toIso8601String());
      }
      return MapEntry(key, value);
    });
  }

  Stream<List<Site>> watchPendingSites() {
    return _sites
        .where('approved', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .where((doc) => doc.data()['rejected'] != true)
              .map((doc) => Site.fromMap(doc.id, _normalise(doc.data())))
              .toList(),
        );
  }

  Stream<List<AdminReport>> watchRecentReports() {
    // Site names come from one cached sites fetch per subscription (refreshed
    // only when a report references an unseen site) — the previous per-report
    // get() billed up to 100 extra reads on every snapshot.
    var siteNames = const <String, String>{};
    return firestore
        .collectionGroup('reports')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .asyncMap((snap) async {
          final siteIds = [
            for (final doc in snap.docs)
              doc.reference.parent.parent?.id ??
                  (doc.data()['siteId'] as String? ?? ''),
          ];
          if (!siteNamesCover(siteNames, siteIds)) {
            final sitesSnap = await _sites.get();
            siteNames = {
              for (final doc in sitesSnap.docs)
                doc.id: doc.data()['name'] as String? ?? doc.id,
            };
          }
          return [
            for (final (i, doc) in snap.docs.indexed)
              AdminReport(
                report: SiteReport.fromMap(doc.id, _normalise(doc.data())),
                siteId: siteIds[i],
                siteName: siteNames[siteIds[i]] ?? siteIds[i],
              ),
          ];
        });
  }

  Future<void> approveSite(String siteId) {
    return _sites.doc(siteId).update({
      'approved': true,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': _adminMarker,
      'rejected': FieldValue.delete(),
      'rejectedAt': FieldValue.delete(),
      'rejectedBy': FieldValue.delete(),
    });
  }

  Future<void> rejectSite(String siteId) {
    return _sites.doc(siteId).update({
      'rejected': true,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': _adminMarker,
    });
  }

  /// Permanently removes a site and every report and rate-limit ledger doc
  /// under it (issue #13). Admin-only per the security rules; one atomic
  /// batch so a failure never leaves orphans behind a deleted site.
  Future<void> deleteSite(String siteId) async {
    final siteRef = _sites.doc(siteId);
    final reports = await siteRef.collection('reports').get();
    final limits = await siteRef.collection('limits').get();
    final batch = firestore.batch();
    for (final doc in reports.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in limits.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(siteRef);
    await batch.commit();
  }

  Future<void> deleteReport(String siteId, String reportId) async {
    final siteRef = _sites.doc(siteId);
    final reportsRef = siteRef.collection('reports');
    final reportRef = reportsRef.doc(reportId);
    final allReports = await reportsRef.get();
    final remainingReports = allReports.docs
        .where((doc) => doc.id != reportId)
        .map((doc) => SiteReport.fromMap(doc.id, _normalise(doc.data())))
        .toList();

    final statusCounts = {
      SiteStatus.open: 0,
      SiteStatus.blitz: 0,
      SiteStatus.closed: 0,
    };
    DateTime? lastReportAt;
    SiteStatus currentStatus = SiteStatus.open;
    DateTime? currentStatusAt;
    final cutoff = DateTime.now().subtract(const Duration(hours: 6));

    for (final report in remainingReports) {
      if (lastReportAt == null || report.createdAt.isAfter(lastReportAt)) {
        lastReportAt = report.createdAt;
      }
      final status = report.status;
      if (status == null) continue;
      statusCounts[status] = statusCounts[status]! + 1;
      if (report.createdAt.isAfter(cutoff) &&
          (currentStatusAt == null ||
              report.createdAt.isAfter(currentStatusAt))) {
        currentStatus = status;
        currentStatusAt = report.createdAt;
      }
    }

    final batch = firestore.batch();
    batch.delete(reportRef);
    batch.update(siteRef, {
      'openVotes': statusCounts[SiteStatus.open],
      'blitzVotes': statusCounts[SiteStatus.blitz],
      'closedVotes': statusCounts[SiteStatus.closed],
      'currentStatus': currentStatus.name,
      if (lastReportAt == null)
        'lastReportAt': FieldValue.delete()
      else
        'lastReportAt': Timestamp.fromDate(lastReportAt),
    });
    await batch.commit();
  }

  String get _adminMarker => auth.currentUser?.uid ?? 'admin';
}
