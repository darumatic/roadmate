import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/firestore_site_repository.dart';
import 'package:roadmate/services/local_seed_repository.dart';
import 'package:roadmate/services/participation_logic.dart';

/// Any contact with Firebase fails the test: the routing under test must be
/// decided before the first Firebase call.
class _UntouchableFirestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Firestore touched: ${invocation.memberName}');
}

class _UntouchableAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Auth touched: ${invocation.memberName}');
}

typedef _Post = (
  String siteId,
  ActivityReportType type,
  String? note,
  String? name,
  ParticipationAction credit,
);

/// Records what would have been posted as an activity report.
class _RecordingRepository extends FirestoreSiteRepository {
  _RecordingRepository()
    : super(
        firestore: _UntouchableFirestore(),
        auth: _UntouchableAuth(),
        locate: () async => null,
      );

  final posts = <_Post>[];

  @override
  Future<void> postActivity(
    Site site,
    ActivityReportType activityType, {
    String? activityNote,
    String? reporterName,
    required ParticipationAction credit,
  }) async {
    posts.add((site.id, activityType, activityNote, reporterName, credit));
  }
}

const _site = Site(
  id: 'nsw-1',
  name: 'Marulan',
  type: SiteType.checkingStation,
  state: AusState.nsw,
  suburb: 'Marulan',
  address: 'Hume Hwy',
);

/// Issue #48: Camera Only / BGD has no stored form (every shipped build reads
/// an unknown status string as OPEN), so a press must leave as the legacy
/// 'Camera Only' activity report and never as a vote.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirestoreSiteRepository', () {
    test('a Camera Only / BGD press is posted as the Camera Only activity '
        'report, credited as a vote', () async {
      final repo = _RecordingRepository();
      await repo.vote(_site, SiteStatus.cameraOnly, reporterName: 'Dusty');
      expect(repo.posts, [
        (
          'nsw-1',
          ActivityReportType.noActivity,
          null,
          'Dusty',
          ParticipationAction.vote,
        ),
      ]);
    });

    test('an ordinary activity report is credited as a report', () async {
      final repo = _RecordingRepository();
      await repo.report(
        _site,
        ActivityReportType.delays,
        activityNote: 'queue',
        reporterName: 'Dusty',
      );
      expect(repo.posts, [
        (
          'nsw-1',
          ActivityReportType.delays,
          'queue',
          'Dusty',
          ParticipationAction.report,
        ),
      ]);
    });

    test('Unknown is refused before anything reaches Firebase', () async {
      final repo = _RecordingRepository();
      await expectLater(
        repo.vote(_site, SiteStatus.unknown),
        throwsArgumentError,
      );
      expect(repo.posts, isEmpty);
    });

    test('a stored status is NOT routed to the activity path', () async {
      final repo = _RecordingRepository();
      // It heads for the real vote batch — i.e. straight into Firebase,
      // which the untouchable fakes turn into a StateError.
      await expectLater(
        repo.vote(_site, SiteStatus.closed),
        throwsA(isA<StateError>()),
      );
      expect(repo.posts, isEmpty);
    });
  });

  group('LocalSeedSiteRepository', () {
    late LocalSeedSiteRepository repo;
    late Site site;

    setUp(() async {
      repo = LocalSeedSiteRepository();
      addTearDown(repo.dispose);
      site = (await repo.watchSites().first).first;
    });

    test('a Camera Only / BGD press is recorded as the Camera Only activity '
        'report: the stored status is untouched, lastReportAt is', () async {
      await repo.vote(site, SiteStatus.cameraOnly, reporterName: ' Dusty ');

      final report = (await repo.watchAllRecentReports().first).single;
      expect(report.siteId, site.id);
      expect(report.status, isNull);
      expect(report.activityType, ActivityReportType.noActivity);
      expect(report.reporterName, 'Dusty');

      final stored = (await repo.watchSites().first).firstWhere(
        (s) => s.id == site.id,
      );
      expect(stored.currentStatus, site.currentStatus);
      expect(stored.currentStatus.isStored, isTrue);
      expect(stored.lastReportAt, isNotNull);
      expect(
        [stored.openVotes, stored.blitzVotes, stored.closedVotes],
        [site.openVotes, site.blitzVotes, site.closedVotes],
      );

      // One tap, like the other three statuses — 5 points, not a report's 10.
      final stats = await repo.watchMyStats().first;
      expect((stats!.votes, stats.reports), (1, 0));
    });

    test(
      'an activity report touches lastReportAt, as Firestore does',
      () async {
        expect(site.lastReportAt, isNull);
        await repo.report(site, ActivityReportType.delays);
        final stored = (await repo.watchSites().first).firstWhere(
          (s) => s.id == site.id,
        );
        expect(stored.lastReportAt, isNotNull);
        final stats = await repo.watchMyStats().first;
        expect((stats!.votes, stats.reports), (0, 1));
      },
    );

    test('Unknown is refused', () {
      expect(repo.vote(site, SiteStatus.unknown), throwsArgumentError);
    });

    test('subscribing both streams together loads the seed once', () async {
      final fresh = LocalSeedSiteRepository();
      addTearDown(fresh.dispose);
      final both = await Future.wait([
        fresh.watchSites().first,
        fresh.watchAllRecentReports().first,
      ]);
      expect(both[0], isNotEmpty);
      expect(both[1], isEmpty);
    });
  });
}
