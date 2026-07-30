import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/admin_report.dart';
import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';
import '../models/user_ban.dart';
import 'announcement.dart';
import 'ban_logic.dart';

/// Whether the cached site-name map already resolves every referenced site.
/// Empty ids (a report whose parent site cannot be determined) never force a
/// refetch — no fetch could resolve them anyway.
bool siteNamesCover(Map<String, String> names, Iterable<String> siteIds) {
  return siteIds.every((id) => id.isEmpty || names.containsKey(id));
}

/// Field values for an admin edit of an activity report — exactly the fields
/// the security rules allow to change. The note is trimmed; a blank note maps
/// to null, which [AdminRepository.updateActivityReport] turns into a field
/// delete so the doc stays a valid activity-report shape.
Map<String, String?> activityReportEditData(
  ActivityReportType activityType,
  String? activityNote,
) {
  final note = activityNote?.trim();
  return {
    'activityType': activityType.wire,
    'activityNote': (note == null || note.isEmpty) ? null : note,
  };
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

  /// Sets (or clears) a site's map coordinates — admin-only per the security
  /// rules, which allow admins to update a site freely.
  ///
  /// Written as plain numbers, exactly the shape every shipped client already
  /// reads; passing nulls clears them, which old clients handle (they treat a
  /// site without coordinates as simply not distance-rankable).
  Future<void> updateSiteLocation(
    String siteId, {
    required double? lat,
    required double? lng,
  }) {
    return _sites.doc(siteId).update({'lat': lat, 'lng': lng});
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

  /// Edits an activity report in place (admin-only per the security rules).
  /// Only activityType/activityNote change; status votes are immutable —
  /// moderating one means [deleteReport], which recounts the site's tallies.
  Future<void> updateActivityReport(
    String siteId,
    String reportId, {
    required ActivityReportType activityType,
    String? activityNote,
  }) {
    final data = activityReportEditData(activityType, activityNote);
    return _sites.doc(siteId).collection('reports').doc(reportId).update({
      'activityType': data['activityType'],
      'activityNote': data['activityNote'] ?? FieldValue.delete(),
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

  /// Every ban ever issued, newest first — expired ones included, since the
  /// admin needs to see that a 1-day ban has already lapsed (and lift it early
  /// if they change their mind). The collection holds one doc per banned user,
  /// so it stays small enough to read whole.
  Stream<List<UserBan>> watchBans() {
    return _bans
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => UserBan.fromMap(doc.id, _normalise(doc.data())))
              .toList(),
        );
  }

  /// Bans [uid] for [duration] (issue: spam control). Writes `bans/{uid}`,
  /// which `firestore.rules` consults on every write that uid attempts.
  ///
  /// `set` rather than `update`: re-banning someone whose old ban lapsed
  /// replaces the doc outright, so a stale `until` can never survive under a
  /// new permanent ban.
  Future<void> banUser(
    String uid, {
    required BanDuration duration,
    String? reason,
  }) {
    final data = banEditData(
      duration: duration,
      now: DateTime.now(),
      reason: reason,
    );
    final until = data['until'];
    return _bans.doc(uid).set({
      if (until is DateTime) 'until': Timestamp.fromDate(until),
      if (data['reason'] != null) 'reason': data['reason'],
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _adminMarker,
    });
  }

  /// Lifts a ban — including a permanent one. Deleting the doc is what the
  /// rules read as "not banned", so this is the whole of an unban.
  Future<void> unbanUser(String uid) => _bans.doc(uid).delete();

  /// Publishes the admin notice every user sees banded across the top of the
  /// app. One fixed document, so publishing replaces whatever was there —
  /// there is only ever one current message.
  ///
  /// `set` without merge on purpose: an edit that drops the expiry must clear
  /// the old `expiresAt` rather than leave it behind.
  Future<void> publishAnnouncement({
    required String message,
    required AnnouncementSeverity severity,
    DateTime? expiresAt,
  }) {
    final data = Announcement.editData(
      message: message,
      severity: severity,
      expiresAt: expiresAt,
    );
    final expiry = data['expiresAt'];
    return _announcement.set({
      'message': data['message'],
      'severity': data['severity'],
      if (expiry is DateTime) 'expiresAt': Timestamp.fromDate(expiry),
      'publishedAt': FieldValue.serverTimestamp(),
      'publishedBy': _adminMarker,
    });
  }

  /// Takes the notice down. Deleting the doc is what clients read as "nothing
  /// to say", so this is the whole of a clear.
  Future<void> clearAnnouncement() => _announcement.delete();

  DocumentReference<Map<String, dynamic>> get _announcement =>
      firestore.doc('announcements/current');

  CollectionReference<Map<String, dynamic>> get _bans =>
      firestore.collection('bans');

  String get _adminMarker => auth.currentUser?.uid ?? 'admin';
}
