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
import 'package:roadmate/services/providers.dart';

const _purgeLabel = "Remove this user's reports";

class FakeAdminRepository implements AdminRepository {
  final purged = <String>[];
  int removedCount = 3;
  Object? purgeError;

  @override
  Future<int> deleteRecentReportsByUser(
    String uid, {
    Duration window = const Duration(hours: 10),
    DateTime? now,
  }) async {
    if (purgeError != null) throw purgeError!;
    purged.add(uid);
    return removedCount;
  }

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
  bool isWeb = true,
  List<AdminReport> reports = const [],
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(900, 1600));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(repo),
        isWebProvider.overrideWithValue(isWeb),
        currentUserRoleProvider.overrideWith(
          (ref) => Stream.value(AppUserRole.admin),
        ),
        pendingSitesProvider.overrideWith(
          (ref) => Stream.value(const <Site>[]),
        ),
        recentAdminReportsProvider.overrideWith((ref) => Stream.value(reports)),
        bansProvider.overrideWith((ref) => Stream.value(const <UserBan>[])),
      ],
      child: const MaterialApp(home: AdminScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openActivityTab(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(Tab, 'Activity'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an admin purges a spammer\'s recent reports from the web', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pumpAdmin(tester, repo: repo, reports: [_report()]);
    await _openActivityTab(tester);

    await tester.tap(find.text(_purgeLabel));
    await tester.pumpAndSettle();

    // Destructive and irreversible, so it always asks first.
    expect(find.text("Remove this user's reports?"), findsOneWidget);
    expect(find.textContaining('last 10 hours'), findsOneWidget);
    expect(repo.purged, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Remove reports'));
    await tester.pumpAndSettle();

    expect(repo.purged, ['spammer']);
    expect(find.text('Removed 3 reports'), findsOneWidget);
  });

  testWidgets('backing out of the dialog removes nothing', (tester) async {
    final repo = FakeAdminRepository();
    await _pumpAdmin(tester, repo: repo, reports: [_report()]);
    await _openActivityTab(tester);

    await tester.tap(find.text(_purgeLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repo.purged, isEmpty);
  });

  testWidgets('the removed count is singular for one report', (tester) async {
    final repo = FakeAdminRepository()..removedCount = 1;
    await _pumpAdmin(tester, repo: repo, reports: [_report()]);
    await _openActivityTab(tester);

    await tester.tap(find.text(_purgeLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove reports'));
    await tester.pumpAndSettle();

    expect(find.text('Removed 1 report'), findsOneWidget);
  });

  testWidgets('a user who posted nothing recent reports zero removed', (
    tester,
  ) async {
    final repo = FakeAdminRepository()..removedCount = 0;
    await _pumpAdmin(tester, repo: repo, reports: [_report()]);
    await _openActivityTab(tester);

    await tester.tap(find.text(_purgeLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove reports'));
    await tester.pumpAndSettle();

    expect(find.text('Removed 0 reports'), findsOneWidget);
  });

  testWidgets('the purge action is hidden outside the web build', (
    tester,
  ) async {
    // Shipped Android/iOS builds cannot be rolled back, so the most
    // destructive admin tool ships on web only. Banning stays everywhere.
    final repo = FakeAdminRepository();
    await _pumpAdmin(tester, repo: repo, isWeb: false, reports: [_report()]);
    await _openActivityTab(tester);

    expect(find.text(_purgeLabel), findsNothing);
    expect(find.text('Ban this user'), findsOneWidget);
  });

  testWidgets('a report without a uid offers no purge', (tester) async {
    final repo = FakeAdminRepository();
    await _pumpAdmin(tester, repo: repo, reports: [_report(uid: null)]);
    await _openActivityTab(tester);

    expect(find.text(_purgeLabel), findsNothing);
  });

  testWidgets('a failed purge surfaces the error', (tester) async {
    final repo = FakeAdminRepository()..purgeError = Exception('denied');
    await _pumpAdmin(tester, repo: repo, reports: [_report()]);
    await _openActivityTab(tester);

    await tester.tap(find.text(_purgeLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove reports'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not remove reports'), findsOneWidget);
  });
}
