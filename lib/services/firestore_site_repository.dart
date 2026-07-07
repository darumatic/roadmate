import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';
import 'auth_service.dart';
import 'site_repository.dart';

/// Firestore-backed [SiteRepository].
///
/// Collections:
///   sites/{siteId}
///   sites/{siteId}/reports/{reportId}
///   users/{uid}/favourites/{siteId}
class FirestoreSiteRepository implements SiteRepository {
  FirestoreSiteRepository({required this.firestore, required this.auth});

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  CollectionReference<Map<String, dynamic>> get _sites =>
      firestore.collection('sites');

  /// Firestore returns [Timestamp]s; convert them to ISO strings so the
  /// Firebase-agnostic model parsers can read them.
  Map<String, dynamic> _normalise(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.toDate().toIso8601String());
      }
      return MapEntry(key, value);
    });
  }

  @override
  Stream<List<Site>> watchSites() {
    return _sites
        .where('approved', isEqualTo: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => Site.fromMap(d.id, _normalise(d.data())))
              .toList(),
        );
  }

  @override
  Stream<List<SiteReport>> watchReports(String siteId) {
    return _sites
        .doc(siteId)
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => SiteReport.fromMap(d.id, _normalise(d.data())))
              .toList(),
        );
  }

  /// The per-user rate-limit ledger doc (issue #15). Vote/report batches must
  /// stamp it with the server time — the rules verify the stamp via getAfter()
  /// and reject the whole batch when the previous stamp is inside the cooldown.
  DocumentReference<Map<String, dynamic>> _limitsRef(String siteId, String uid) =>
      _sites.doc(siteId).collection('limits').doc(uid);

  @override
  Future<void> vote(String siteId, SiteStatus status) async {
    final uid = await ensureSignedIn(auth);
    final reportRef = _sites.doc(siteId).collection('reports').doc();
    final batch = firestore.batch();
    batch.set(reportRef, {
      'siteId': siteId,
      'status': status.name,
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_sites.doc(siteId), {
      '${status.name}Votes': FieldValue.increment(1),
      'currentStatus': status.name,
      'lastReportAt': FieldValue.serverTimestamp(),
    });
    batch.set(_limitsRef(siteId, uid), {
      'lastVoteAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Future<void> report(
    String siteId,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  }) async {
    final uid = await ensureSignedIn(auth);
    final data = <String, dynamic>{
      'siteId': siteId,
      'activityType': activityType.wire,
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final note = activityNote?.trim();
    final name = reporterName?.trim();
    if (note != null && note.isNotEmpty) data['activityNote'] = note;
    if (name != null && name.isNotEmpty) data['reporterName'] = name;

    // One atomic batch: the rules tie the report + touch to the rate-limit
    // ledger stamp with getAfter(), which only sees same-batch writes.
    final batch = firestore.batch();
    batch.set(_sites.doc(siteId).collection('reports').doc(), data);
    batch.update(_sites.doc(siteId), {
      'lastReportAt': FieldValue.serverTimestamp(),
    });
    batch.set(_limitsRef(siteId, uid), {
      'lastReportAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Future<void> addSite(Site site, {bool approved = false}) async {
    final uid = await ensureSignedIn(auth);
    final ref = site.id.isEmpty ? _sites.doc() : _sites.doc(site.id);
    await ref.set({
      ...site.toMap(),
      // Pending moderation unless an admin publishes directly (issue #16;
      // the rules reject approved == true from non-admins).
      'approved': approved,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      if (approved) 'approvedAt': FieldValue.serverTimestamp(),
      if (approved) 'approvedBy': uid,
    });
  }

  @override
  Stream<Set<String>> watchFavourites() {
    return auth.authStateChanges().asyncExpand((user) {
      final uid = user?.uid;
      if (uid == null) return Stream.value(const <String>{});
      return firestore
          .collection('users')
          .doc(uid)
          .collection('favourites')
          .snapshots()
          .map((snap) => snap.docs.map((d) => d.id).toSet());
    });
  }

  @override
  Future<void> toggleFavourite(String siteId) async {
    final uid = await ensureSignedIn(auth);
    final ref = firestore
        .collection('users')
        .doc(uid)
        .collection('favourites')
        .doc(siteId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
    } else {
      await ref.set({'favouritedAt': FieldValue.serverTimestamp()});
    }
  }
}
