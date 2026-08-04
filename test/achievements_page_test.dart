import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/features/user/achievements_page.dart';
import 'package:roadmate/services/participation_logic.dart';
import 'package:roadmate/services/providers.dart';

Future<void> _pump(WidgetTester tester, ParticipationStats? stats) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        myParticipationProvider.overrideWith((ref) => Stream.value(stats)),
      ],
      child: const MaterialApp(home: AchievementsPage()),
    ),
  );
}

void main() {
  testWidgets('shows the level header, progress and every badge', (
    tester,
  ) async {
    // 10 votes + 1 report = 60 pts -> Local Runner; unlocks First Vote,
    // First Report and Spotter, leaving the other badges locked.
    await _pump(tester, const ParticipationStats(votes: 10, reports: 1));
    await tester.pumpAndSettle();

    expect(find.text('Achievements'), findsOneWidget);
    expect(find.text('Local Runner'), findsOneWidget);
    expect(find.text('60 pts'), findsOneWidget);
    expect(find.text('90 pts to Highway Regular'), findsOneWidget);

    for (final badge in kBadges) {
      expect(find.text(badge.title), findsOneWidget);
    }
    expect(find.byIcon(Icons.emoji_events), findsNWidgets(3));
    expect(
      find.byIcon(Icons.lock_outline_rounded),
      findsNWidgets(kBadges.length - 3),
    );
  });

  testWidgets('a fresh user is a Rookie with everything locked', (
    tester,
  ) async {
    // Null stats (stream not settled / signed out) degrade to zero counters.
    await _pump(tester, null);
    await tester.pumpAndSettle();

    expect(find.text('Rookie'), findsOneWidget);
    expect(find.text('0 pts'), findsOneWidget);
    expect(
      find.byIcon(Icons.lock_outline_rounded),
      findsNWidgets(kBadges.length),
    );
  });

  testWidgets('the top of the ladder reads as such', (tester) async {
    await _pump(tester, const ParticipationStats(votes: 300, reports: 100));
    await tester.pumpAndSettle();

    expect(find.text('Outback Legend'), findsOneWidget);
    expect(find.textContaining('Top of the ladder'), findsOneWidget);
    expect(find.textContaining('pts to'), findsNothing);
  });
}
