import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/enums.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/services/report_purge.dart';
import 'package:roadmate/services/status_logic.dart';

final _now = DateTime(2026, 7, 31, 12);

SiteReport _report({
  String id = 'r1',
  SiteStatus? status,
  Duration age = Duration.zero,
  String? uid = 'spammer',
}) => SiteReport(
  id: id,
  siteId: 'nsw-1',
  createdAt: _now.subtract(age),
  status: status,
  activityType: status == null ? ActivityReportType.other : null,
  uid: uid,
);

void main() {
  group('purge window', () {
    test('reaches exactly as far back as a report stays current', () {
      // A purge that outlived the freshness window would delete history no
      // driver can see; one that fell short would leave spam on screen.
      expect(purgeWindow, statusFreshWindow);
      expect(purgeWindow, const Duration(hours: 10));
    });

    test('recount keeps the narrower status window deleteReport has used', () {
      expect(statusRecountWindow, const Duration(hours: 6));
    });
  });

  group('talliesFrom', () {
    test('counts every remaining status vote regardless of age', () {
      final tallies = talliesFrom([
        _report(id: 'a', status: SiteStatus.open),
        _report(id: 'b', status: SiteStatus.open, age: const Duration(days: 3)),
        _report(id: 'c', status: SiteStatus.blitz),
        _report(id: 'd', status: SiteStatus.closed),
        _report(id: 'e'), // activity report — not a vote
      ], now: _now);

      expect(tallies.openVotes, 2);
      expect(tallies.blitzVotes, 1);
      expect(tallies.closedVotes, 1);
    });

    test('currentStatus follows the newest vote inside the status window', () {
      final tallies = talliesFrom([
        _report(
          id: 'old',
          status: SiteStatus.blitz,
          age: const Duration(hours: 5),
        ),
        _report(
          id: 'new',
          status: SiteStatus.closed,
          age: const Duration(hours: 1),
        ),
      ], now: _now);

      expect(tallies.currentStatus, SiteStatus.closed);
    });

    test('votes older than the status window no longer set currentStatus', () {
      final tallies = talliesFrom([
        _report(
          id: 'stale',
          status: SiteStatus.blitz,
          age: const Duration(hours: 7),
        ),
      ], now: _now);

      // The vote is still counted, but the site falls back to open — the same
      // state a site holds before its first vote.
      expect(tallies.blitzVotes, 1);
      expect(tallies.currentStatus, SiteStatus.open);
    });

    test('lastReportAt is the newest survivor, activity reports included', () {
      final tallies = talliesFrom([
        _report(
          id: 'a',
          status: SiteStatus.open,
          age: const Duration(hours: 4),
        ),
        _report(id: 'b', age: const Duration(hours: 2)),
      ], now: _now);

      expect(tallies.lastReportAt, _now.subtract(const Duration(hours: 2)));
    });

    test('an emptied site reports null so the field can be deleted', () {
      final tallies = talliesFrom(const [], now: _now);

      expect(tallies.lastReportAt, isNull);
      expect(tallies.openVotes, 0);
      expect(tallies.blitzVotes, 0);
      expect(tallies.closedVotes, 0);
      expect(tallies.currentStatus, SiteStatus.open);
    });
  });

  group('groupReportIdsBySite', () {
    test('groups a cross-site purge by site, first-seen order', () {
      final grouped = groupReportIdsBySite([
        ('nsw-1', 'a'),
        ('qld-2', 'b'),
        ('nsw-1', 'c'),
      ]);

      expect(grouped.keys.toList(), ['nsw-1', 'qld-2']);
      expect(grouped['nsw-1'], ['a', 'c']);
      expect(grouped['qld-2'], ['b']);
    });

    test('drops reports whose parent site cannot be resolved', () {
      // No site means no tallies to recount and no doc path to delete — such a
      // report is skipped rather than crashing the whole purge.
      final grouped = groupReportIdsBySite([('', 'orphan'), ('nsw-1', 'a')]);

      expect(grouped.keys.toList(), ['nsw-1']);
    });

    test('is empty for a user with nothing recent', () {
      expect(groupReportIdsBySite(const []), isEmpty);
    });
  });

  group('chunked', () {
    test('splits past the batch limit and keeps every item once', () {
      final items = List.generate(1201, (i) => i);
      final chunks = chunked(items, size: firestoreBatchLimit);

      expect(chunks.map((c) => c.length).toList(), [500, 500, 201]);
      expect(chunks.expand((c) => c).toList(), items);
    });

    test('a short list stays a single batch', () {
      expect(chunked([1, 2, 3]).map((c) => c.length).toList(), [3]);
    });

    test('an exact multiple does not produce a trailing empty batch', () {
      expect(chunked([1, 2, 3, 4], size: 2).length, 2);
    });

    test('nothing to delete means no batches at all', () {
      expect(chunked(<int>[]), isEmpty);
    });
  });

  group('showBulkReportPurge', () {
    test('is offered on web only', () {
      expect(showBulkReportPurge(isWeb: true), isTrue);
      expect(showBulkReportPurge(isWeb: false), isFalse);
    });
  });
}
