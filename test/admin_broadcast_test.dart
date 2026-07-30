import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/features/admin/admin_screen.dart';
import 'package:roadmate/models/site.dart';
import 'package:roadmate/models/user_ban.dart';
import 'package:roadmate/services/admin_repository.dart';
import 'package:roadmate/services/announcement.dart';
import 'package:roadmate/services/auth_service.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/widgets/announcement_banner.dart';

typedef PublishedNotice = ({
  String message,
  AnnouncementSeverity severity,
  DateTime? expiresAt,
});

class FakeAdminRepository implements AdminRepository {
  final published = <PublishedNotice>[];
  int cleared = 0;
  Object? publishError;

  @override
  Future<void> publishAnnouncement({
    required String message,
    required AnnouncementSeverity severity,
    DateTime? expiresAt,
  }) async {
    if (publishError != null) throw publishError!;
    published.add((message: message, severity: severity, expiresAt: expiresAt));
  }

  @override
  Future<void> clearAnnouncement() async => cleared++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpNoticeTab(
  WidgetTester tester, {
  required FakeAdminRepository repo,
  Announcement? live,
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
        bansProvider.overrideWith((ref) => Stream.value(const <UserBan>[])),
        announcementProvider.overrideWith((ref) => Stream.value(live)),
      ],
      child: const MaterialApp(home: AdminScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(Tab, 'Notice'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an admin publishes a notice to everyone', (tester) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(tester, repo: repo);

    await tester.enterText(
      find.byType(TextField),
      '  Signing in is now required to report.  ',
    );
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repo.published, hasLength(1));
    // Trimmed, info by default, and up until an admin takes it down.
    expect(
      repo.published.single.message,
      'Signing in is now required to report.',
    );
    expect(repo.published.single.severity, AnnouncementSeverity.info);
    expect(repo.published.single.expiresAt, isNull);
    expect(find.text('Notice published'), findsOneWidget);
  });

  testWidgets('a warning can be set to auto-hide', (tester) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(tester, repo: repo);

    await tester.enterText(
      find.byType(TextField),
      'Blitz season starts Monday',
    );
    await tester.tap(find.text('Warning'));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repo.published.single.severity, AnnouncementSeverity.warning);
    expect(repo.published.single.expiresAt, isNotNull);
  });

  testWidgets('an empty message is refused before it reaches Firestore', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(tester, repo: repo);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repo.published, isEmpty);
    expect(find.text('Type a message first'), findsOneWidget);
  });

  testWidgets('the message field caps at the length the rules enforce', (
    tester,
  ) async {
    await _pumpNoticeTab(tester, repo: FakeAdminRepository());

    // Pins the form to isValidAnnouncement's 280-char cap: a message the rules
    // would reject must be untypeable rather than fail on submit.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLength, kAnnouncementMaxLength);
  });

  testWidgets('a live notice is previewed, editable and clearable', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(
      tester,
      repo: repo,
      live: Announcement(
        message: 'Roadworks on the Hume.',
        severity: AnnouncementSeverity.warning,
        publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    );

    // The admin sees exactly what users see, and the form is seeded for edits.
    expect(find.byType(AnnouncementBanner), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Roadworks on the Hume.',
    );
    expect(find.text('Update notice'), findsOneWidget);

    await tester.tap(find.text('Clear notice'));
    await tester.pumpAndSettle();

    expect(repo.cleared, 1);
    expect(find.text('Notice cleared'), findsOneWidget);
  });

  testWidgets('a failed publish tells the admin instead of silently dropping', (
    tester,
  ) async {
    final repo = FakeAdminRepository()..publishError = Exception('offline');
    await _pumpNoticeTab(tester, repo: repo);

    await tester.enterText(find.byType(TextField), 'Anything');
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not publish'), findsOneWidget);
  });
}
