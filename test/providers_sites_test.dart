import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/site_repository.dart';

/// Hands the test both listeners' streams; nothing else is touched.
class _StreamsRepository implements SiteRepository {
  final sites = StreamController<List<Site>>();
  final reports = StreamController<List<SiteReport>>();

  @override
  Stream<List<Site>> watchSites() => sites.stream;

  @override
  Stream<List<SiteReport>> watchAllRecentReports() => reports.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `sitesProvider` derives the displayed status from two listeners (issue #48:
/// Camera Only / BGD exists only in the reports stream). These pin how it
/// behaves while the second one is late, present, or broken.
void main() {
  final reportedAt = DateTime.now().subtract(const Duration(hours: 1));
  final marulan = Site(
    id: 's1',
    name: 'Marulan',
    type: SiteType.checkingStation,
    state: AusState.nsw,
    suburb: 'Marulan',
    address: 'Hume Hwy',
    currentStatus: SiteStatus.closed,
    lastReportAt: reportedAt,
  );
  final cameraOnly = SiteReport(
    id: 'r1',
    siteId: 's1',
    createdAt: reportedAt,
    activityType: ActivityReportType.noActivity,
  );

  late _StreamsRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _StreamsRepository();
    container = ProviderContainer(
      // No automatic retry: a retry would re-listen to the single-subscription
      // test streams.
      retry: (_, _) => null,
      overrides: [siteRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    // Screens watch it for the life of the app; hold it open the same way.
    container.listen(sitesProvider, (_, _) {});
  });

  SiteStatus? shown() =>
      container.read(sitesProvider).value?.single.currentStatus;

  test('the site list never waits on the reports listener', () async {
    expect(container.read(sitesProvider).isLoading, isTrue);

    repo.sites.add([marulan]);
    await pumpEventQueue();

    // Reports have said nothing yet: Firestore holds back an empty first
    // snapshot until the server answers, which in a coverage hole is ~10 s —
    // the cached site list (and the approach prompt it feeds) must not stall.
    expect(container.read(recentReportsProvider).isLoading, isTrue);
    expect(shown(), SiteStatus.closed);
  });

  test('a Camera Only report lights the fourth status once it arrives, and a '
      'later vote takes it back', () async {
    repo.sites.add([marulan]);
    repo.reports.add([cameraOnly]);
    await pumpEventQueue();
    expect(shown(), SiteStatus.cameraOnly);

    final votedAt = DateTime.now();
    repo.reports.add([
      SiteReport(
        id: 'r2',
        siteId: 's1',
        createdAt: votedAt,
        status: SiteStatus.open,
      ),
      cameraOnly,
    ]);
    repo.sites.add([
      marulan.copyWith(currentStatus: SiteStatus.open, lastReportAt: votedAt),
    ]);
    await pumpEventQueue();
    expect(shown(), SiteStatus.open);
  });

  test('a failed reports listener falls back to the stored statuses', () async {
    repo.sites.add([marulan]);
    repo.reports.addError(StateError('index missing'));
    await pumpEventQueue();

    expect(container.read(recentReportsProvider).hasError, isTrue);
    expect(shown(), SiteStatus.closed);
  });

  // Issue #49: once the reports have loaded they decide. Marulan's site doc
  // says "closed, reported an hour ago" — but if the only report in the
  // window is a "Long queue", that hour-old touch is not a Closed vote.
  test('once the reports have loaded, a stored status with no status report '
      'behind it is Unknown', () async {
    repo.sites.add([marulan]);
    repo.reports.add([
      SiteReport(
        id: 'q1',
        siteId: 's1',
        createdAt: reportedAt,
        activityType: ActivityReportType.longQueue,
      ),
    ]);
    await pumpEventQueue();

    final shownSite = container.read(sitesProvider).value!.single;
    expect(shownSite.currentStatus, SiteStatus.unknown);
    // "reported 1h ago" still follows every report.
    expect(shownSite.lastReportAt, reportedAt);
  });

  test(
    'a reports listener that dies AFTER loading falls back too — its last '
    'list only goes stale, and would turn every newer vote Unknown',
    () async {
      repo.sites.add([marulan]);
      repo.reports.add(const []);
      await pumpEventQueue();
      expect(shown(), SiteStatus.unknown);

      repo.reports.addError(StateError('listener lost'));
      await pumpEventQueue();
      expect(shown(), SiteStatus.closed);
    },
  );

  // Issue #50: a post showed nothing until the server acknowledged it — the
  // pending report is not in the listener at all. The repository holds each
  // post in `inFlightPostsProvider` from the tap; these pin what the screens
  // are served meanwhile.
  group("the driver's own posts in flight (issue #50)", () {
    SiteReport blitzVote({DateTime? at}) => SiteReport(
      id: 'mine',
      siteId: 's1',
      createdAt: at ?? DateTime.now(),
      status: SiteStatus.blitz,
    );
    final closedVote = SiteReport(
      id: 'theirs',
      siteId: 's1',
      createdAt: reportedAt,
      status: SiteStatus.closed,
    );

    test('a vote shows at the tap, and is taken back when its write '
        'fails', () async {
      repo.sites.add([marulan]);
      repo.reports.add([closedVote]);
      await pumpEventQueue();
      expect(shown(), SiteStatus.closed);

      final write = Completer<void>();
      final posting = container
          .read(inFlightPostsProvider)
          .track(blitzVote(), () => write.future);
      await pumpEventQueue();
      // The listeners have said nothing new — and won't until the ack.
      expect(shown(), SiteStatus.blitz);

      write.completeError(StateError('rate limited'));
      await expectLater(posting, throwsStateError);
      await pumpEventQueue();
      expect(shown(), SiteStatus.closed);
    });

    test('it hands over to the delivered document without ever showing the '
        'old status in between', () async {
      repo.sites.add([marulan]);
      repo.reports.add([closedVote]);
      await pumpEventQueue();

      final statuses = <SiteStatus?>[];
      container.listen(
        sitesProvider,
        (_, next) => statuses.add(next.value?.single.currentStatus),
      );

      final write = Completer<void>();
      final posting = container
          .read(inFlightPostsProvider)
          .track(blitzVote(), () => write.future);
      await pumpEventQueue();

      // The ack: the write's future first, the listener's snapshot after it.
      write.complete();
      await posting;
      await pumpEventQueue();
      repo.reports.add([blitzVote(), closedVote]);
      await pumpEventQueue();

      expect(shown(), SiteStatus.blitz);
      expect(statuses, isNotEmpty);
      expect(statuses, everyElement(SiteStatus.blitz));
    });

    test('a post never makes the site list wait, and works while the reports '
        'are still loading', () async {
      repo.sites.add([marulan]);
      await pumpEventQueue();
      expect(container.read(recentReportsProvider).isLoading, isTrue);

      unawaited(
        container
            .read(inFlightPostsProvider)
            .track(blitzVote(), () => Completer<void>().future),
      );
      await pumpEventQueue();
      expect(shown(), SiteStatus.blitz);
    });

    test("an activity report is listed on the card at the tap — whatever "
        'state the listener is in — and exactly once after it lands', () async {
      SiteReport queue() => SiteReport(
        id: 'q-mine',
        siteId: 's1',
        createdAt: DateTime.now(),
        activityType: ActivityReportType.longQueue,
      );
      container.listen(siteReportsProvider('s1'), (_, _) {});
      List<String>? listed() => container
          .read(siteReportsProvider('s1'))
          .value
          ?.map((r) => r.id)
          .toList();

      repo.sites.add([marulan]);
      await pumpEventQueue();
      expect(listed(), isNull); // still loading, nothing of ours in flight

      final write = Completer<void>();
      final posting = container
          .read(inFlightPostsProvider)
          .track(queue(), () => write.future);
      await pumpEventQueue();
      expect(listed(), ['q-mine']);

      repo.reports.add([cameraOnly]);
      await pumpEventQueue();
      expect(listed(), ['q-mine', 'r1']);

      // Landed and delivered while the copy is still held: listed once.
      write.complete();
      await posting;
      repo.reports.add([queue(), cameraOnly]);
      await pumpEventQueue();
      expect(listed(), ['q-mine', 'r1']);

      // Another site's card is none the wiser.
      expect(container.read(siteReportsProvider('s2')).value, isEmpty);
    });

    test('a reports listener that has died still lists the post in '
        'flight', () async {
      container.listen(siteReportsProvider('s1'), (_, _) {});
      repo.sites.add([marulan]);
      repo.reports.add([cameraOnly]);
      await pumpEventQueue();
      repo.reports.addError(StateError('listener lost'));
      await pumpEventQueue();
      expect(container.read(siteReportsProvider('s1')).hasError, isTrue);

      unawaited(
        container
            .read(inFlightPostsProvider)
            .track(
              SiteReport(
                id: 'q-mine',
                siteId: 's1',
                createdAt: DateTime.now(),
                activityType: ActivityReportType.delays,
              ),
              () => Completer<void>().future,
            ),
      );
      await pumpEventQueue();

      expect(
        container.read(siteReportsProvider('s1')).value?.map((r) => r.id),
        ['q-mine'],
      );
    });
  });

  test('a failed sites listener still surfaces as an error', () async {
    repo.sites.addError(StateError('offline'));
    repo.reports.add([cameraOnly]);
    await pumpEventQueue();

    expect(container.read(sitesProvider).hasError, isTrue);
  });
}
