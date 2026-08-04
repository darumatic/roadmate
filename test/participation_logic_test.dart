import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/participation_logic.dart';

void main() {
  group('points math', () {
    test('a vote is 5 points, a report is 10', () {
      expect(const ParticipationStats(votes: 1).points, kPointsPerVote);
      expect(const ParticipationStats(reports: 1).points, kPointsPerReport);
      expect(const ParticipationStats(votes: 3, reports: 2).points, 35);
      expect(const ParticipationStats().points, 0);
    });

    test('after() bumps exactly the acted counter', () {
      const stats = ParticipationStats(votes: 2, reports: 7, sitesAdded: 1);
      final voted = stats.after(ParticipationAction.vote);
      expect((voted.votes, voted.reports, voted.sitesAdded), (3, 7, 1));
      final reported = stats.after(ParticipationAction.report);
      expect(
        (reported.votes, reported.reports, reported.sitesAdded),
        (2, 8, 1),
      );
      final added = stats.after(ParticipationAction.addSite);
      expect((added.votes, added.reports, added.sitesAdded), (2, 7, 2));
    });

    test('adding a site earns no points but counts as an action', () {
      const stats = ParticipationStats(votes: 1, sitesAdded: 3);
      expect(stats.points, kPointsPerVote);
      expect(stats.actions, 4);
    });

    test('fromMap tolerates missing and numeric fields', () {
      expect(ParticipationStats.fromMap(const {}).points, 0);
      final stats = ParticipationStats.fromMap(const {
        'votes': 4,
        'reports': 1.0, // Firestore numbers can decode as double on web
      });
      expect((stats.votes, stats.reports, stats.sitesAdded), (4, 1, 0));
      // 0.1.59 docs have no sitesAdded key at all.
      final withSites = ParticipationStats.fromMap(const {'sitesAdded': 2});
      expect(withSites.sitesAdded, 2);
    });
  });

  group('level ladder', () {
    test(
      'is monotonically ascending from 0 with 1-based contiguous indexes',
      () {
        expect(kLevels.first.minPoints, 0);
        for (var i = 0; i < kLevels.length; i++) {
          expect(kLevels[i].index1, i + 1);
          if (i > 0) {
            expect(kLevels[i].minPoints, greaterThan(kLevels[i - 1].minPoints));
          }
        }
      },
    );

    test(
      'levelForPoints picks the highest reached rung, exact boundaries in',
      () {
        expect(levelForPoints(0).title, 'Rookie');
        expect(levelForPoints(49).title, 'Rookie');
        expect(levelForPoints(50).title, 'Local Runner');
        expect(levelForPoints(2499).title, 'Road Train Boss');
        expect(levelForPoints(2500).title, 'Outback Legend');
        expect(levelForPoints(1000000).title, 'Outback Legend');
      },
    );

    test('levelForIndex round-trips every rung and rejects out-of-range', () {
      for (final level in kLevels) {
        expect(levelForIndex(level.index1), same(level));
      }
      expect(levelForIndex(null), isNull);
      expect(levelForIndex(0), isNull);
      expect(levelForIndex(kLevels.length + 1), isNull);
    });

    test('nextLevelForPoints and progress behave across the ladder', () {
      expect(nextLevelForPoints(0)!.title, 'Local Runner');
      expect(nextLevelForPoints(50)!.title, 'Highway Regular');
      expect(nextLevelForPoints(2500), isNull);

      expect(progressToNextLevel(0), 0);
      expect(progressToNextLevel(25), 0.5);
      expect(progressToNextLevel(100), 0.5); // halfway 50 -> 150
      expect(progressToNextLevel(2500), 1.0); // top rung reads full
      expect(progressToNextLevel(9999), 1.0);
    });
  });

  group('reporterLevel stamp', () {
    test('counts the action being committed', () {
      // 9 votes = 45 pts; this 10th vote crosses the 50-pt rung.
      const nine = ParticipationStats(votes: 9);
      expect(reporterLevelToStamp(nine, ParticipationAction.vote), 2);
      expect(reporterLevelToStamp(nine, ParticipationAction.report), 2);
    });

    test('unknown stats degrade to level 1 — never blocks a post', () {
      expect(reporterLevelToStamp(null, ParticipationAction.vote), 1);
      expect(reporterLevelToStamp(null, ParticipationAction.report), 1);
    });
  });

  group('stats payload (sentinels injected, rate_limit.dart pattern)', () {
    test('vote bumps votes and always carries every counter', () {
      final payload = statsIncrementPayload(
        ParticipationAction.vote,
        plusOne: 'INC1',
        plusZero: 'INC0',
        serverTime: 'ST',
      );
      expect(payload, {
        'votes': 'INC1',
        'reports': 'INC0',
        'sitesAdded': 'INC0',
        'updatedAt': 'ST',
      });
    });

    test('report and addSite mirror the vote shape', () {
      final report = statsIncrementPayload(
        ParticipationAction.report,
        plusOne: 'INC1',
        plusZero: 'INC0',
        serverTime: 'ST',
      );
      expect(report, {
        'votes': 'INC0',
        'reports': 'INC1',
        'sitesAdded': 'INC0',
        'updatedAt': 'ST',
      });
      final addSite = statsIncrementPayload(
        ParticipationAction.addSite,
        plusOne: 'INC1',
        plusZero: 'INC0',
        serverTime: 'ST',
      );
      expect(addSite, {
        'votes': 'INC0',
        'reports': 'INC0',
        'sitesAdded': 'INC1',
        'updatedAt': 'ST',
      });
    });
  });

  test('formatPoints groups thousands', () {
    expect(formatPoints(0), '0');
    expect(formatPoints(999), '999');
    expect(formatPoints(1000), '1,000');
    expect(formatPoints(1240), '1,240');
    expect(formatPoints(1234567), '1,234,567');
  });

  group('badges', () {
    test('zero actions unlocks nothing', () {
      expect(badgesFor(const ParticipationStats()), isEmpty);
    });

    test('thresholds unlock exactly on the boundary', () {
      final ids = badgesFor(
        const ParticipationStats(votes: 10, reports: 1),
      ).map((b) => b.id);
      expect(ids, ['firstVote', 'firstReport', 'spotter']);
    });

    test('one added site unlocks Trailblazer, approval not required', () {
      expect(
        badgesFor(const ParticipationStats()).map((b) => b.id),
        isNot(contains('trailblazer')),
      );
      expect(
        badgesFor(const ParticipationStats(sitesAdded: 1)).map((b) => b.id),
        ['trailblazer'],
      );
    });

    test('century club counts votes and reports combined', () {
      expect(
        badgesFor(
          const ParticipationStats(votes: 60, reports: 40),
        ).map((b) => b.id),
        contains('centuryClub'),
      );
      expect(
        badgesFor(
          const ParticipationStats(votes: 60, reports: 39),
        ).map((b) => b.id),
        isNot(contains('centuryClub')),
      );
    });
  });
}
