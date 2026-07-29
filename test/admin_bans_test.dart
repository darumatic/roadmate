import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/features/admin/admin_screen.dart';
import 'package:roadmate/models/admin_report.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/site_report.dart';
import 'package:roadmate/models/user_ban.dart';
import 'package:roadmate/services/admin_repository.dart';
import 'package:roadmate/services/auth_service.dart';
import 'package:roadmate/services/ban_logic.dart';
import 'package:roadmate/services/providers.dart';

class FakeAdminRepository implements AdminRepository {
  final bans = <(String, BanDuration, String?)>[];
  final unbanned = <String>[];
  Object? banError;

  @override
  Future<void> banUser(
    String uid, {
    required BanDuration duration,
    String? reason,
  }) async {
    if (banError != null) throw banError!;
    bans.add((uid, duration, reason));
  }

  @override
  Future<void> unbanUser(String uid) async => unbanned.add(uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AdminReport _report({String? uid = 'spammer'}) => AdminReport(
  report: SiteReport(
    id: 'r1',
    siteId: 'nsw-1',
    createdAt: DateTime.now(),
    activityType: ActivityReportType.other,
    activityNote: 'buy cheap tyres www.spam.example',
    uid: uid,
  ),
  siteId: 'nsw-1',
  siteName: 'Marulan',
);

Future<void> _pumpAdmin(
  WidgetTester tester, {
  required FakeAdminRepository repo,
  List<AdminReport> reports = const [],
  List<UserBan> bans = const [],
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(900, 1600));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(repo),
        currentUserRoleProvider.overrideWith(
          (ref) => Stream.value(AppUserRole.admin),
        ),
        pendingSitesProvider.overrideWith(
          (ref) => Stream.value(const <Site>[]),
        ),
        recentAdminReportsProvider.overrideWith((ref) => Stream.value(reports)),
        bansProvider.overrideWith((ref) => Stream.value(bans)),
      ],
      child: const MaterialApp(home: AdminScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an admin bans a spammer for a day from their report', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pumpAdmin(tester, repo: repo, reports: [_report()]);
    await _openTab(tester, 'Activity');

    await tester.tap(find.text('Ban this user'));
    await tester.pumpAndSettle();

    // The dialog names the account and defaults to the lighter penalty.
    expect(find.text('Ban user'), findsOneWidget);
    // The uid is repeated inside the dialog — banning is irreversible enough
    // that the admin should see who they are acting on without going back.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('spammer'),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, 'vote spam');
    await tester.tap(find.widgetWithText(FilledButton, 'Ban'));
    await tester.pumpAndSettle();

    expect(repo.bans, [('spammer', BanDuration.oneDay, 'vote spam')]);
    expect(find.textContaining('User banned (1 day)'), findsOneWidget);
  });

  testWidgets('the same flow bans forever when that is chosen', (tester) async {
    final repo = FakeAdminRepository();
    await _pumpAdmin(tester, repo: repo, reports: [_report()]);
    await _openTab(tester, 'Activity');

    await tester.tap(find.text('Ban this user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forever'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ban'));
    await tester.pumpAndSettle();

    expect(repo.bans.single.$2, BanDuration.forever);
    expect(find.textContaining('User banned (Forever)'), findsOneWidget);
  });

  testWidgets('backing out of the dialog bans nobody', (tester) async {
    final repo = FakeAdminRepository();
    await _pumpAdmin(tester, repo: repo, reports: [_report()]);
    await _openTab(tester, 'Activity');

    await tester.tap(find.text('Ban this user'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.bans, isEmpty);
  });

  // Reports written before uids were recorded can't be traced to an account.
  testWidgets('a report with no uid offers no ban', (tester) async {
    final repo = FakeAdminRepository();
    await _pumpAdmin(tester, repo: repo, reports: [_report(uid: null)]);
    await _openTab(tester, 'Activity');

    expect(find.text('Remove report'), findsOneWidget);
    expect(find.text('Ban this user'), findsNothing);
  });

  testWidgets('a failed ban says so instead of pretending', (tester) async {
    final repo = FakeAdminRepository()..banError = Exception('offline');
    await _pumpAdmin(tester, repo: repo, reports: [_report()]);
    await _openTab(tester, 'Activity');

    await tester.tap(find.text('Ban this user'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ban'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not ban user'), findsOneWidget);
  });

  group('Bans tab', () {
    testWidgets('lists an active ban and lifts it', (tester) async {
      final repo = FakeAdminRepository();
      await _pumpAdmin(
        tester,
        repo: repo,
        bans: [
          UserBan(
            uid: 'spammer',
            until: DateTime.now().add(const Duration(hours: 20)),
            reason: 'vote spam',
            createdAt: DateTime.now().subtract(const Duration(hours: 4)),
            createdBy: 'admin1',
          ),
        ],
      );
      await _openTab(tester, 'Bans');

      expect(find.textContaining('Banned until'), findsOneWidget);
      expect(find.text('spammer'), findsOneWidget);
      expect(find.text('vote spam'), findsOneWidget);
      expect(find.textContaining('Banned 4h ago'), findsOneWidget);

      await tester.tap(find.text('Lift ban'));
      await tester.pumpAndSettle();

      expect(repo.unbanned, ['spammer']);
      expect(find.text('Ban lifted'), findsOneWidget);
    });

    testWidgets('a permanent ban says so, with no expiry to read', (
      tester,
    ) async {
      await _pumpAdmin(
        tester,
        repo: FakeAdminRepository(),
        bans: [UserBan(uid: 'spammer', createdAt: DateTime.now())],
      );
      await _openTab(tester, 'Bans');

      expect(find.text('Banned forever'), findsOneWidget);
      expect(find.textContaining('Banned until'), findsNothing);
    });

    // A served 1-day ban stays on the list: it is the evidence for handing out
    // a permanent one next time.
    testWidgets('an expired ban is kept, marked expired', (tester) async {
      await _pumpAdmin(
        tester,
        repo: FakeAdminRepository(),
        bans: [
          UserBan(
            uid: 'spammer',
            until: DateTime.now().subtract(const Duration(hours: 1)),
            createdAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ],
      );
      await _openTab(tester, 'Bans');

      expect(find.text('Ban expired'), findsOneWidget);
      expect(find.text('Remove record'), findsOneWidget);
    });

    testWidgets('with nobody banned it explains where bans come from', (
      tester,
    ) async {
      await _pumpAdmin(tester, repo: FakeAdminRepository());
      await _openTab(tester, 'Bans');

      expect(find.text('Nobody is banned'), findsOneWidget);
    });
  });
}
