import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/status_logic.dart';

SiteReport _report(SiteStatus status, DateTime at) =>
    SiteReport(id: 'x', siteId: 's1', createdAt: at, status: status);

SiteReport _activity(String id, DateTime at) => SiteReport(
  id: id,
  siteId: 's1',
  createdAt: at,
  activityType: ActivityReportType.longQueue,
);

void main() {
  final now = DateTime(2026, 6, 29, 12);

  test('the freshness window is the 10-hour rule (issue #21)', () {
    expect(statusFreshWindow, const Duration(hours: 10));
  });

  group('effectiveStatus (issue #21)', () {
    test('keeps a status reported within the last 10 hours', () {
      expect(
        effectiveStatus(
          SiteStatus.blitz,
          now.subtract(const Duration(hours: 9, minutes: 59)),
          now: now,
        ),
        SiteStatus.blitz,
      );
    });

    test('goes unknown once the last report is over 10 hours old', () {
      expect(
        effectiveStatus(
          SiteStatus.blitz,
          now.subtract(const Duration(hours: 10, minutes: 1)),
          now: now,
        ),
        SiteStatus.unknown,
      );
    });

    test('a site never reported is unknown', () {
      expect(
        effectiveStatus(SiteStatus.open, null, now: now),
        SiteStatus.unknown,
      );
    });

    test('withEffectiveStatus maps a whole site list', () {
      final sites = [
        Site(
          id: 'fresh',
          name: 'Fresh',
          type: SiteType.weighbridge,
          state: AusState.nsw,
          suburb: 'A',
          address: 'A Rd',
          currentStatus: SiteStatus.closed,
          lastReportAt: now.subtract(const Duration(hours: 1)),
        ),
        Site(
          id: 'stale',
          name: 'Stale',
          type: SiteType.weighbridge,
          state: AusState.nsw,
          suburb: 'B',
          address: 'B Rd',
          currentStatus: SiteStatus.blitz,
          lastReportAt: now.subtract(const Duration(hours: 11)),
        ),
        Site(
          id: 'never',
          name: 'Never',
          type: SiteType.weighbridge,
          state: AusState.nsw,
          suburb: 'C',
          address: 'C Rd',
          currentStatus: SiteStatus.open,
        ),
      ];
      final mapped = withEffectiveStatus(sites, now: now);
      expect(mapped.map((s) => s.currentStatus), [
        SiteStatus.closed,
        SiteStatus.unknown,
        SiteStatus.unknown,
      ]);
      // Everything else is untouched.
      expect(mapped.map((s) => s.id), ['fresh', 'stale', 'never']);
    });
  });

  // Issue #48: Camera Only / BGD has no stored form — shipped builds read an
  // unknown status string as OPEN — so it travels as the legacy activity
  // report and is derived back into a status here, from the reports stream.
  group('Camera Only / BGD is derived from the reports (issue #48)', () {
    Site site({
      String id = 's1',
      SiteStatus stored = SiteStatus.closed,
      DateTime? lastReportAt,
    }) => Site(
      id: id,
      name: 'Marulan',
      type: SiteType.checkingStation,
      state: AusState.nsw,
      suburb: 'Marulan',
      address: 'Hume Hwy',
      currentStatus: stored,
      lastReportAt: lastReportAt,
    );

    SiteReport camera(
      DateTime at, {
      ActivityReportType type = ActivityReportType.noActivity,
      String siteId = 's1',
    }) =>
        SiteReport(id: 'c', siteId: siteId, createdAt: at, activityType: type);

    SiteStatus display(Site s, List<SiteReport> reports) => withEffectiveStatus(
      [s],
      recentReports: reports,
      now: now,
    ).single.currentStatus;

    DateTime ago(int hours, [int minutes = 0]) =>
        now.subtract(Duration(hours: hours, minutes: minutes));

    test('a press is stored as the legacy Camera Only activity report', () {
      expect(cameraOnlyWireType, ActivityReportType.noActivity);
      expect(cameraOnlyWireType.wire, 'Camera Only');
    });

    test('reportedStatusOf: a vote says its status, Camera Only and BGD say '
        'the fourth, other activity says nothing', () {
      expect(
        reportedStatusOf(_report(SiteStatus.blitz, now)),
        SiteStatus.blitz,
      );
      expect(reportedStatusOf(camera(now)), SiteStatus.cameraOnly);
      expect(
        reportedStatusOf(camera(now, type: ActivityReportType.defectChecks)),
        SiteStatus.cameraOnly,
      );
      expect(reportedStatusOf(_activity('q', now)), isNull);
    });

    test('lights when the newest status-bearing report is Camera Only', () {
      final s = site(lastReportAt: ago(1));
      expect(display(s, [camera(ago(1))]), SiteStatus.cameraOnly);
    });

    test("an old build's BGD report lights it too", () {
      final s = site(lastReportAt: ago(1));
      expect(
        display(s, [camera(ago(1), type: ActivityReportType.defectChecks)]),
        SiteStatus.cameraOnly,
      );
    });

    test('a later vote supersedes it — even one cast from an old build', () {
      final s = site(stored: SiteStatus.open, lastReportAt: ago(1));
      expect(
        display(s, [_report(SiteStatus.open, ago(1)), camera(ago(3))]),
        SiteStatus.open,
      );
    });

    test('it supersedes an earlier vote: Closed is no longer the status', () {
      final s = site(lastReportAt: ago(1));
      expect(
        display(s, [camera(ago(1)), _report(SiteStatus.closed, ago(2))]),
        SiteStatus.cameraOnly,
      );
    });

    test('the newest report wins whatever order the stream delivers them', () {
      final s = site(lastReportAt: ago(1));
      expect(
        display(s, [_report(SiteStatus.closed, ago(2)), camera(ago(1))]),
        SiteStatus.cameraOnly,
      );
    });

    test('other activity after it leaves it standing', () {
      final s = site(lastReportAt: ago(0, 30));
      expect(
        display(s, [_activity('q', ago(0, 30)), camera(ago(2))]),
        SiteStatus.cameraOnly,
      );
    });

    test('a Camera Only report past the 10h window is ignored', () {
      final s = site(lastReportAt: ago(10, 1));
      expect(display(s, [camera(ago(10, 1))]), SiteStatus.unknown);
    });

    test("another site's Camera Only report changes nothing here", () {
      final s = site(lastReportAt: ago(1));
      expect(display(s, [camera(ago(1), siteId: 'other')]), SiteStatus.closed);
    });

    test('the report proves its own freshness: it lights even when the site '
        'doc carries no lastReportAt, and lifts it for "reported Xm ago"', () {
      final at = ago(1);
      final shown = withEffectiveStatus(
        [site()],
        recentReports: [camera(at)],
        now: now,
      ).single;
      expect(shown.currentStatus, SiteStatus.cameraOnly);
      expect(shown.lastReportAt, at);
    });

    test('a later touch on the site doc is kept over the report time', () {
      final touched = ago(0, 5);
      final shown = withEffectiveStatus(
        [site(lastReportAt: touched)],
        recentReports: [camera(ago(1))],
        now: now,
      ).single;
      expect(shown.lastReportAt, touched);
    });

    test('with no reports it is exactly the stored-status rule old builds '
        'apply — a loading or failed stream fails soft', () {
      final sites = [
        site(id: 'fresh', lastReportAt: ago(1)),
        site(id: 'stale', stored: SiteStatus.blitz, lastReportAt: ago(11)),
      ];
      expect(withEffectiveStatus(sites, now: now).map((s) => s.currentStatus), [
        SiteStatus.closed,
        SiteStatus.unknown,
      ]);
    });

    test('latestStatusReports keeps one newest status-bearing report per '
        'site', () {
      final latest = latestStatusReports([
        _activity('q', ago(0, 10)),
        camera(ago(1)),
        _report(SiteStatus.open, ago(2)),
        camera(ago(3), siteId: 's2'),
        camera(ago(11), siteId: 's3'),
      ], now: now);
      expect(latest.keys, unorderedEquals(['s1', 's2']));
      expect(latest['s1']!.createdAt, ago(1));
    });
  });

  group('recentActivityReports', () {
    test('keeps fresh activity reports and drops expired ones', () {
      final reports = [
        _activity('fresh', now.subtract(const Duration(hours: 9, minutes: 59))),
        _activity('stale', now.subtract(const Duration(hours: 10, minutes: 1))),
      ];
      expect(recentActivityReports(reports, now: now).map((r) => r.id), [
        'fresh',
      ]);
    });

    test('drops status-only reports even when recent', () {
      final reports = [
        _report(SiteStatus.open, now.subtract(const Duration(minutes: 5))),
        _activity('a', now.subtract(const Duration(minutes: 5))),
      ];
      expect(recentActivityReports(reports, now: now).map((r) => r.id), ['a']);
    });

    test('empty when every activity report has expired', () {
      final reports = [
        _activity('a', now.subtract(const Duration(hours: 11))),
        _activity('b', now.subtract(const Duration(days: 2))),
      ];
      expect(recentActivityReports(reports, now: now), isEmpty);
    });

    test('respects a custom window', () {
      final reports = [_activity('a', now.subtract(const Duration(hours: 2)))];
      expect(
        recentActivityReports(
          reports,
          now: now,
          window: const Duration(hours: 1),
        ),
        isEmpty,
      );
    });
  });

  // The shared recent-reports stream: exact client-side 10h filter over the
  // server query, plus the per-site slicing every card relies on.
  group('reportsWithinWindow', () {
    final now = DateTime(2026, 6, 29, 12);

    test('keeps votes and activity reports inside the window', () {
      final reports = [
        _report(SiteStatus.blitz, now.subtract(const Duration(hours: 9))),
        _activity('a', now.subtract(const Duration(minutes: 5))),
      ];
      expect(reportsWithinWindow(reports, now: now), hasLength(2));
    });

    test('drops anything older than the window, vote or activity', () {
      final reports = [
        _report(SiteStatus.open, now.subtract(const Duration(hours: 11))),
        _activity('stale', now.subtract(const Duration(hours: 10, minutes: 1))),
        _activity('fresh', now.subtract(const Duration(hours: 9, minutes: 59))),
      ];
      expect(reportsWithinWindow(reports, now: now).map((r) => r.id), [
        'fresh',
      ]);
    });

    test('respects a custom window', () {
      final reports = [_activity('a', now.subtract(const Duration(hours: 2)))];
      expect(
        reportsWithinWindow(
          reports,
          now: now,
          window: const Duration(hours: 1),
        ),
        isEmpty,
      );
    });
  });

  group('reportsForSite', () {
    final now = DateTime(2026, 6, 29, 12);

    SiteReport at(String id, String siteId) =>
        SiteReport(id: id, siteId: siteId, createdAt: now);

    test('keeps only the requested site, preserving order', () {
      final shared = [
        at('1', 's1'),
        at('2', 's2'),
        at('3', 's1'),
        at('4', 's3'),
      ];
      expect(reportsForSite(shared, 's1').map((r) => r.id), ['1', '3']);
    });

    test('empty when the site has no reports in the shared stream', () {
      expect(reportsForSite([at('1', 's2')], 's1'), isEmpty);
    });
  });
}
