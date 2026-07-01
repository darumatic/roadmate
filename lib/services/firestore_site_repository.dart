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
      'activityType': activityType.name,
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final note = activityNote?.trim();
    final name = reporterName?.trim();
    if (note != null && note.isNotEmpty) data['activityNote'] = note;
    if (name != null && name.isNotEmpty) data['reporterName'] = name;

    await _sites.doc(siteId).collection('reports').add(data);
    await _sites.doc(siteId).update({
      'lastReportAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> addSite(Site site) async {
    final uid = await ensureSignedIn(auth);
    final ref = site.id.isEmpty ? _sites.doc() : _sites.doc(site.id);
    await ref.set({
      ...site.toMap(),
      'approved': false, // pending moderation before it becomes visible
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
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
