import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show protected, visibleForTesting;

import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';
import '../models/user_ban.dart';
import 'auth_service.dart';
import 'auth_switched_stream.dart';
import 'ban_logic.dart';
import 'fresh_window_stream.dart';
import 'in_flight_posts.dart';
import 'participation_logic.dart';
import 'post_sequencer.dart';
import 'rate_limit.dart';
import 'report_proximity.dart';
import 'site_repository.dart';
import 'status_logic.dart';

/// Firestore-backed [SiteRepository].
///
/// Collections:
///   sites/{siteId}
///   sites/{siteId}/reports/{reportId}
///   users/{uid}/favourites/{siteId}
class FirestoreSiteRepository implements SiteRepository {
  FirestoreSiteRepository({
    required this.firestore,
    required this.auth,
    required this.locate,
    required this.inFlight,
    this.listenerChecks = const Stream.empty(),
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  /// Every vote and report is held here from the tap until the listeners have
  /// it (issue #50); the app shows it from here meanwhile. Required, with no
  /// default: a repository holding posts in an instance nobody watches would
  /// compile, pass every test, and show nothing.
  final InFlightPosts inFlight;

  /// "Has the recent-reports listener gone stale?" — a steady tick plus
  /// app-resume events (`listenerChecksProvider`). Must be a broadcast stream:
  /// every [watchAllRecentReports] call subscribes. With none, the listener
  /// simply keeps the cutoff it started with.
  final Stream<void> listenerChecks;

  /// Resolves the device position for the report proximity gate, asking for
  /// permission if needed — see `report_proximity.dart`.
  final DevicePositionResolver locate;

  /// Posts take turns reaching the SDK, in tap order (issue #57).
  final _tapOrder = PostSequencer();

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
  Stream<List<SiteReport>> watchAllRecentReports() {
    // The query has to bake its cutoff in, and a connected listener never
    // pays for that: only NEW reports are billed. A full re-run does — after
    // >30 min disconnected Firestore bills the whole result again, with the
    // cutoff the listener started with, so a long-lived session re-read far
    // more than 10 hours. `freshWindowStream` swaps in a fresh cutoff at
    // exactly those moments and never otherwise (issue #51). The exact 10h
    // filter stays client-side in status_logic, as always.
    return freshWindowStream<List<SiteReport>>(
      window: statusFreshWindow,
      checks: listenerChecks,
      open: (cutoff) => firestore
          .collectionGroup('reports')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff),
          )
          .orderBy('createdAt', descending: true)
          .limit(recentReportsQueryCap)
          // Metadata changes are how the listener says it went offline (and
          // came back) — not billed, and not re-emitted downstream.
          .snapshots(includeMetadataChanges: true)
          .map(
            (snap) => WindowSnapshot(
              [
                for (final d in snap.docs)
                  SiteReport.fromMap(d.id, _normalise(d.data())),
              ],
              isFromCache: snap.metadata.isFromCache,
              dataChanged: snap.docChanges.isNotEmpty,
            ),
          ),
    );
  }

  DocumentReference<Map<String, dynamic>> _ledgerRef(String uid) => firestore
      .collection('users')
      .doc(uid)
      .collection('limits')
      .doc('actions');

  DocumentReference<Map<String, dynamic>> _statsRef(String uid) => firestore
      .collection('users')
      .doc(uid)
      .collection('stats')
      .doc('participation');

  /// Last-known participation counters, used to pick the `reporterLevel`
  /// stamped into activity reports. Fed by [watchMyStats] when that listener
  /// is live (the User tab), else by one memoized `get()` before the first
  /// report of the session, and bumped locally after each successful post.
  /// Cross-device staleness only ever costs an off-by-one cosmetic stamp.
  ParticipationStats? _lastKnownStats;
  String? _statsUid;
  bool _statsLoadAttempted = false;

  void _cacheStats(String uid, ParticipationStats? stats) {
    if (_statsUid != uid) _statsLoadAttempted = false;
    _statsUid = uid;
    _lastKnownStats = stats;
  }

  Future<ParticipationStats?> _statsForStamp(String uid) async {
    if (_statsUid != uid) {
      _lastKnownStats = null;
      _statsLoadAttempted = false;
      _statsUid = uid;
    }
    if (_lastKnownStats != null || _statsLoadAttempted) return _lastKnownStats;
    _statsLoadAttempted = true;
    try {
      final snap = await _statsRef(uid).get();
      _lastKnownStats = ParticipationStats.fromMap(snap.data() ?? const {});
    } catch (_) {
      // Gamification must never block a post — an unknown score just stamps
      // level 1 (reporterLevelToStamp's null path).
    }
    return _lastKnownStats;
  }

  /// The level [action]'s stamp will carry, when that is already known — for
  /// the copy of a post shown while its write is in flight (issue #50). The
  /// row is feedback for the tap, so unlike [_statsForStamp] this never reads:
  /// unknown just means the level icon arrives with the document.
  int? _knownLevelAfter(ParticipationAction action) {
    final stats = _lastKnownStats;
    if (stats == null || _statsUid != auth.currentUser?.uid) return null;
    return reporterLevelToStamp(stats, action);
  }

  void _bumpStats(String uid, ParticipationAction action) {
    if (_statsUid != uid || _lastKnownStats == null) return;
    _lastKnownStats = _lastKnownStats!.after(action);
  }

  /// The stats write riding in every vote/report batch: exactly one counter
  /// +1, the shape `isStatsSeed`/`isStatsIncrement` in firestore.rules
  /// validate. `set(merge)` + increments covers create and update alike.
  void _stampStats(WriteBatch batch, String uid, ParticipationAction action) {
    batch.set(
      _statsRef(uid),
      statsIncrementPayload(
        action,
        plusOne: FieldValue.increment(1),
        plusZero: FieldValue.increment(0),
        serverTime: FieldValue.serverTimestamp(),
      ),
      SetOptions(merge: true),
    );
  }

  /// The user's active ban, or null. Read **only after a write was refused**:
  /// a ban is rare and the rules already enforce it, so paying a document read
  /// on every vote to pre-empt one would be backwards. On the failure path it
  /// costs one read and turns "Could not submit" into the real reason.
  ///
  /// Never throws: a lookup that itself fails (offline, rules changed) must
  /// leave the original error to speak for itself.
  Future<UserBan?> _activeBan(String uid) async {
    try {
      final snap = await firestore.collection('bans').doc(uid).get();
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      final ban = UserBan.fromMap(uid, _normalise(data));
      return ban.isActiveAt(DateTime.now()) ? ban : null;
    } catch (_) {
      return null;
    }
  }

  /// Turns a rules denial into the exception that explains it. A banned user
  /// is banned whatever else is true, so that check comes first; [orElse] is
  /// what the caller would otherwise have thrown.
  Future<Never> _explainDenial(String uid, Object orElse) async {
    final ban = await _activeBan(uid);
    if (ban != null) throw BannedException(ban.until);
    throw orElse;
  }

  /// The proximity gate — see `report_proximity.dart`. Skips the position
  /// lookup entirely for an un-geocoded site: there is nothing to measure
  /// against, so the driver isn't asked for location they don't need to give.
  ///
  /// Admins are exempt (moderation happens from the desk), but the
  /// `userRoles/{uid}` read is paid **only after a refusal** — the same
  /// discipline as [_activeBan], so an ordinary post near a site costs no
  /// extra read and an admin's remote one costs exactly one.
  Future<void> _ensureNearSite(Site site) async {
    if (site.lat == null || site.lng == null) return;
    final position = await locate();
    final decision = checkReportProximity(
      siteLat: site.lat,
      siteLng: site.lng,
      position: position,
    );
    if (decision == ReportProximity.allowed) return;
    enforceReportProximity(decision, isAdmin: await _isAdmin());
  }

  /// Whether the current uid is an admin, straight from `userRoles/{uid}`
  /// (readable by its owner — the same doc `currentUserRoleProvider` streams).
  /// Never throws: an unreadable role must leave the gate's own refusal to
  /// speak for itself.
  Future<bool> _isAdmin() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      final snap = await firestore.collection('userRoles').doc(uid).get();
      return snap.data()?['role'] == 'admin';
    } catch (_) {
      return false;
    }
  }

  /// Commits [addOps] plus a rate-limit ledger stamp in one atomic batch
  /// (issue #15 redux — see rate_limit.dart for why this is clock-free).
  ///
  /// Tries the increment shape first (the common case inside an open window);
  /// when the server refuses it — window expired, doc missing, or count
  /// exhausted — retries with the reset shape, and when that is denied too,
  /// with the increment once more (below). A denial of all three means the
  /// user really is over the limit.
  ///
  /// Every attempt reaches the SDK through [write], the post's place in the
  /// tap order (issue #57) — never by calling `commit()` directly.
  Future<void> _commitWithLedgerStamp(
    String uid,
    void Function(WriteBatch batch) addOps, {
    required PostWrite write,
  }) async {
    // Batches are single-use, so each attempt builds its own — and only when
    // [write] lets it out: a re-send may first have to wait for the posts
    // ahead of this one.
    Future<void> attempt(LedgerShape shape) => write(() {
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
    });

    try {
      await attempt(LedgerShape.increment);
      return;
    } catch (e) {
      if (!shouldTryOtherShape(e)) rethrow;
    }
    try {
      await attempt(LedgerShape.reset);
      return;
    } catch (e) {
      if (!isRulesDenial(e)) rethrow;
    }
    // A denied reset says the window is open — which it may be only since a
    // moment ago, opened by the post before this one (issue #57). On a slow
    // link both posts' increments are with the server before either is
    // answered: it refuses both (no window), accepts the first post's reset,
    // and refuses this one's because the window is open NOW. One more
    // increment settles it, and the server still counts: a window that really
    // is spent refuses this too.
    try {
      await attempt(LedgerShape.increment);
    } catch (e) {
      // Refused in every shape: either the window really is spent, or this
      // uid is banned and every write of theirs is being denied.
      if (isRulesDenial(e)) {
        await _explainDenial(uid, const RateLimitedException());
      }
      rethrow;
    }
  }

  @override
  Future<void> vote(
    Site site,
    SiteStatus status, {
    String? reporterName,
  }) async {
    // Camera Only / BGD has no stored form — every shipped build reads an
    // unknown status string as OPEN — so it is posted as the 'Camera Only'
    // activity report old builds already list, and derived back into a status
    // by builds that know it (status_logic.dart). Credited as the one-tap
    // vote it is, not as a 10-point report. Both checks run before any
    // Firebase call, so the routing is unit-testable without Firebase.
    if (status == SiteStatus.cameraOnly) {
      return postActivity(
        site,
        cameraOnlyWireType,
        reporterName: reporterName,
        credit: ParticipationAction.vote,
      );
    }
    if (!status.isStored) {
      throw ArgumentError.value(status, 'status', 'has no stored form');
    }
    final siteId = site.id;
    final name = storedText(reporterName);
    final reportRef = _newReportRef(siteId);
    await _post(
      SiteReport(
        id: reportRef.id,
        siteId: siteId,
        createdAt: clock.now(),
        status: status,
        reporterName: name,
      ),
      (write) async {
        final uid = await ensureSignedIn(auth);
        await _ensureNearSite(site);
        await _commitWithLedgerStamp(uid, write: write, (batch) {
          batch.set(reportRef, {
            'siteId': siteId,
            'status': status.name,
            'uid': uid,
            'createdAt': FieldValue.serverTimestamp(),
            'reporterName': ?name,
          });
          batch.update(_sites.doc(siteId), {
            '${status.name}Votes': FieldValue.increment(1),
            'currentStatus': status.name,
            'lastReportAt': FieldValue.serverTimestamp(),
          });
          _stampStats(batch, uid, ParticipationAction.vote);
        });
        _bumpStats(uid, ParticipationAction.vote);
      },
    );
  }

  /// The way every vote and report is made: [held] is shown from the tap
  /// until the listeners have it ([inFlight], issue #50), and [post] — the
  /// whole of it, sign-in and the proximity gate included — takes its turn
  /// behind the posts tapped before it ([PostSequencer], issue #57). [post]
  /// hands its [PostWrite] on to [_commitWithLedgerStamp].
  Future<void> _post(
    SiteReport held,
    Future<void> Function(PostWrite write) post,
  ) => inFlight.track(held, () => _tapOrder.run(post));

  /// The reference a post's report document will be written to. Allocated
  /// once per post and **outside** [_commitWithLedgerStamp]'s retry, so both
  /// ledger shapes write the same document: the copy held in [inFlight] hands
  /// over to the listener's document by this id (issue #50), and the first
  /// post of every rate-limit window is exactly the one that retries. The id
  /// is generated on the device — no round trip.
  DocumentReference<Map<String, dynamic>> _newReportRef(String siteId) =>
      _sites.doc(siteId).collection('reports').doc();

  @override
  Future<void> report(
    Site site,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
  }) {
    return postActivity(
      site,
      activityType,
      activityNote: activityNote,
      reporterName: reporterName,
      credit: ParticipationAction.report,
    );
  }

  /// Posts an activity report: the report doc plus the site's `lastReportAt`
  /// touch, in one batch. Shared by [report] and by a Camera Only / BGD press
  /// ([vote]), which is this very write — the only difference is [credit],
  /// the participation counter the author earns (a private doc no other
  /// client reads), so what every other build sees is identical.
  @protected
  @visibleForTesting
  Future<void> postActivity(
    Site site,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
    required ParticipationAction credit,
  }) async {
    final siteId = site.id;
    final reportRef = _newReportRef(siteId);
    await _post(
      SiteReport(
        id: reportRef.id,
        siteId: siteId,
        createdAt: clock.now(),
        activityType: activityType,
        activityNote: storedText(activityNote),
        reporterName: storedText(reporterName),
        reporterLevel: _knownLevelAfter(credit),
      ),
      (write) async {
        final uid = await ensureSignedIn(auth);
        await _ensureNearSite(site);
        final data = activityReportPayload(
          siteId: siteId,
          uid: uid,
          type: activityType,
          note: activityNote,
          reporterName: reporterName,
          reporterLevel: reporterLevelToStamp(
            await _statsForStamp(uid),
            credit,
          ),
          serverTime: FieldValue.serverTimestamp(),
        );

        // One atomic batch so a report never lands without its site touch.
        await _commitWithLedgerStamp(uid, write: write, (batch) {
          batch.set(reportRef, data);
          batch.update(_sites.doc(siteId), {
            'lastReportAt': FieldValue.serverTimestamp(),
          });
          _stampStats(batch, uid, credit);
        });
        _bumpStats(uid, credit);
      },
    );
  }

  @override
  Future<void> addSite(
    Site site, {
    bool approved = false,
    String? submitterName,
  }) async {
    final uid = await ensureSignedIn(auth);
    final name = storedText(submitterName);
    final ref = site.id.isEmpty ? _sites.doc() : _sites.doc(site.id);
    try {
      // One batch: the submission plus its sitesAdded credit (Trailblazer
      // badge — earned at submission, deliberately not at approval, which
      // can also happen in the Firebase console where no client code runs).
      // No ledger stamp here: the 5/5min cap covers votes/reports only.
      final batch = firestore.batch();
      batch.set(ref, {
        ...site.toMap(),
        // Pending moderation unless an admin publishes directly (issue #16;
        // the rules reject approved == true from non-admins).
        'approved': approved,
        'createdBy': uid,
        'createdByName': ?name,
        'createdAt': FieldValue.serverTimestamp(),
        if (approved) 'approvedAt': FieldValue.serverTimestamp(),
        if (approved) 'approvedBy': uid,
      });
      _stampStats(batch, uid, ParticipationAction.addSite);
      await batch.commit();
      _bumpStats(uid, ParticipationAction.addSite);
    } catch (e) {
      // A denial here is almost always a ban (the shape is validated
      // client-side first); anything else surfaces unchanged.
      if (isRulesDenial(e)) await _explainDenial(uid, e);
      rethrow;
    }
  }

  // Both auth-scoped watchers go through authSwitchedStream: the old
  // asyncExpand shape queued a sign-in/out forever behind the previous
  // identity's never-completing listener (an account switch kept showing the
  // old user's favourites/stats until restart) and never recovered from a
  // terminal listener error — the same wedge as the 0.1.74 nickname bug.

  @override
  Stream<ParticipationStats?> watchMyStats() {
    return authSwitchedStream<String, ParticipationStats?>(
      authUsers: auth.authStateChanges().map((user) => user?.uid),
      sourceOf: (uid) => _statsRef(uid).snapshots().map((snap) {
        final stats = ParticipationStats.fromMap(snap.data() ?? const {});
        // Keep the reporterLevel stamp fresh while the listener is live.
        _cacheStats(uid, stats);
        return stats;
      }),
      signedOutValue: null,
    );
  }

  @override
  Stream<Set<String>> watchFavourites() {
    return authSwitchedStream<String, Set<String>>(
      authUsers: auth.authStateChanges().map((user) => user?.uid),
      sourceOf: (uid) => firestore
          .collection('users')
          .doc(uid)
          .collection('favourites')
          .snapshots()
          .map((snap) => snap.docs.map((d) => d.id).toSet()),
      signedOutValue: const <String>{},
    );
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
    // Un-favouriting stays open to banned users: the rules only close the
    // create/update side, so nobody is stuck with a starred site they can't
    // remove (and account deletion keeps working).
    if (snap.exists) {
      await ref.delete();
      return;
    }
    try {
      await ref.set({'favouritedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      if (isRulesDenial(e)) await _explainDenial(uid, e);
      rethrow;
    }
  }
}
