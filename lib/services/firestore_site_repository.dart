import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';
import 'auth_service.dart';
import 'rate_limit.dart';
import 'site_repository.dart';
import 'status_logic.dart';

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

  /// Runaway-cost guard on the shared recent-reports query. At the enforced
  /// rate limit (5 actions/5min/user) this only bites under coordinated spam;
  /// ordering is newest-first, so if it ever does, the freshest reports win.
  static const int recentReportsQueryCap = 500;

  @override
  Stream<List<SiteReport>> watchAllRecentReports() {
    // The cutoff is fixed when the listener starts, so a long-lived session
    // only ever over-fetches (window grows past 10h, never shrinks below);
    // the exact 10h filter stays client-side in status_logic, as always.
    final cutoff = DateTime.now().subtract(statusFreshWindow);
    return firestore
        .collectionGroup('reports')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .orderBy('createdAt', descending: true)
        .limit(recentReportsQueryCap)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => SiteReport.fromMap(d.id, _normalise(d.data())))
              .toList(),
        );
  }

  DocumentReference<Map<String, dynamic>> _ledgerRef(String uid) => firestore
      .collection('users')
      .doc(uid)
      .collection('limits')
      .doc('actions');

  /// Commits [addOps] plus a rate-limit ledger stamp in one atomic batch
  /// (issue #15 redux — see rate_limit.dart for why this is clock-free).
  ///
  /// Tries the increment shape first (the common case inside an open window);
  /// when the server refuses it — window expired, doc missing, or count
  /// exhausted — retries once with the reset shape. A denial of both shapes
  /// means the user really is over the limit.
  Future<void> _commitWithLedgerStamp(
    String uid,
    void Function(WriteBatch batch) addOps,
  ) async {
    Future<void> attempt(LedgerShape shape) {
      // Batches are single-use; rebuild for each attempt.
      final batch = firestore.batch();
      addOps(batch);
      final ledger = _ledgerRef(uid);
      if (shape == LedgerShape.increment) {
        batch.update(
          ledger,
          ledgerIncrementPayload(
            incrementByOne: FieldValue.increment(1),
            serverTime: FieldValue.serverTimestamp(),
          ),
        );
      } else {
        batch.set(
          ledger,
          ledgerResetPayload(serverTime: FieldValue.serverTimestamp()),
        );
      }
      return batch.commit();
    }

    try {
      await attempt(LedgerShape.increment);
    } catch (e) {
      if (!shouldTryOtherShape(e)) rethrow;
      try {
        await attempt(LedgerShape.reset);
      } catch (e2) {
        if (isRulesDenial(e2)) throw const RateLimitedException();
        rethrow;
      }
    }
  }

  @override
  Future<void> vote(String siteId, SiteStatus status) async {
    final uid = await ensureSignedIn(auth);
    final reportRef = _sites.doc(siteId).collection('reports').doc();
    await _commitWithLedgerStamp(uid, (batch) {
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
    });
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

    // One atomic batch so a report never lands without its site touch.
    await _commitWithLedgerStamp(uid, (batch) {
      batch.set(_sites.doc(siteId).collection('reports').doc(), data);
      batch.update(_sites.doc(siteId), {
        'lastReportAt': FieldValue.serverTimestamp(),
      });
    });
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
