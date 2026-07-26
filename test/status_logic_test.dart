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
  final logic = const StatusLogic(window: Duration(hours: 6));
  final now = DateTime(2026, 6, 29, 12);

  group('deriveStatus', () {
    test('defaults to unknown with no reports (issue #21)', () {
      expect(logic.deriveStatus(const [], now: now), SiteStatus.unknown);
    });

    test('uses the most recent report within the window', () {
      final reports = [
        _report(SiteStatus.open, now.subtract(const Duration(hours: 3))),
        _report(SiteStatus.blitz, now.subtract(const Duration(minutes: 30))),
        _report(SiteStatus.closed, now.subtract(const Duration(hours: 5))),
      ];
      expect(logic.deriveStatus(reports, now: now), SiteStatus.blitz);
    });

    test('reports older than the window leave the status unknown', () {
      final reports = [
        _report(SiteStatus.blitz, now.subtract(const Duration(hours: 8))),
      ];
      expect(logic.deriveStatus(reports, now: now), SiteStatus.unknown);
    });

    test('ignores activity-only reports with no status', () {
      final reports = [
        SiteReport(
          id: 'a',
          siteId: 's1',
          createdAt: now.subtract(const Duration(minutes: 5)),
          activityNote: 'Truck queue forming',
        ),
      ];
      expect(logic.deriveStatus(reports, now: now), SiteStatus.unknown);
    });

    test('the default window is the 10-hour freshness rule (issue #21)', () {
      expect(const StatusLogic().window, const Duration(hours: 10));
    });
  });

  group('isBlitzActive', () {
    test('true when a recent blitz exists', () {
      final reports = [
        _report(SiteStatus.blitz, now.subtract(const Duration(hours: 2))),
      ];
      expect(logic.isBlitzActive(reports, now: now), isTrue);
    });

    test('false when the blitz is outside the window', () {
      final reports = [
        _report(SiteStatus.blitz, now.subtract(const Duration(hours: 7))),
      ];
      expect(logic.isBlitzActive(reports, now: now), isFalse);
    });
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
