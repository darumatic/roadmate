import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/admin_report.dart';
import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';

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
    return firestore
        .collectionGroup('reports')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .asyncMap((snap) async {
          final reports = <AdminReport>[];
          for (final doc in snap.docs) {
            final siteId =
                doc.reference.parent.parent?.id ??
                (doc.data()['siteId'] as String? ?? '');
            final siteSnap = siteId.isEmpty
                ? null
                : await _sites.doc(siteId).get();
            final siteName = siteSnap?.data()?['name'] as String? ?? siteId;
            reports.add(
              AdminReport(
                report: SiteReport.fromMap(doc.id, _normalise(doc.data())),
                siteId: siteId,
                siteName: siteName,
              ),
            );
          }
          return reports;
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
