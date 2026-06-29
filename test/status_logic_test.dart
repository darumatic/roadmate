import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/status_logic.dart';

SiteReport _report(SiteStatus status, DateTime at) =>
    SiteReport(id: 'x', siteId: 's1', createdAt: at, status: status);

void main() {
  final logic = const StatusLogic(window: Duration(hours: 6));
  final now = DateTime(2026, 6, 29, 12);

  group('deriveStatus', () {
    test('defaults to open with no reports', () {
      expect(logic.deriveStatus(const [], now: now), SiteStatus.open);
    });

    test('uses the most recent report within the window', () {
      final reports = [
        _report(SiteStatus.open, now.subtract(const Duration(hours: 3))),
        _report(SiteStatus.blitz, now.subtract(const Duration(minutes: 30))),
        _report(SiteStatus.closed, now.subtract(const Duration(hours: 5))),
      ];
      expect(logic.deriveStatus(reports, now: now), SiteStatus.blitz);
    });

    test('ignores reports older than the window', () {
      final reports = [
        _report(SiteStatus.blitz, now.subtract(const Duration(hours: 8))),
      ];
      expect(logic.deriveStatus(reports, now: now), SiteStatus.open);
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
      expect(logic.deriveStatus(reports, now: now), SiteStatus.open);
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
}
