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
  String? messageHtml,
  AnnouncementSeverity severity,
  String? color,
  String? cta,
  DateTime? expiresAt,
});

class FakeAdminRepository implements AdminRepository {
  final published = <PublishedNotice>[];
  int cleared = 0;
  Object? publishError;

  @override
  Future<void> publishAnnouncement({
    required String message,
    String? messageHtml,
    required AnnouncementSeverity severity,
    String? color,
    String? cta,
    DateTime? expiresAt,
  }) async {
    if (publishError != null) throw publishError!;
    published.add((
      message: message,
      messageHtml: messageHtml,
      severity: severity,
      color: color,
      cta: cta,
      expiresAt: expiresAt,
    ));
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
  /// The message box — first field in the form (the second is the custom
  /// colour hex).
  Finder messageField() => find.byType(TextField).first;

  testWidgets('an admin publishes a notice to everyone', (tester) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(tester, repo: repo);

    await tester.enterText(
      messageField(),
      '  Signing in is now required to report.  ',
    );
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repo.published, hasLength(1));
    // Trimmed, info by default, and up until an admin takes it down. Plain
    // text writes the exact pre-rich shape: no markup, no colour.
    expect(
      repo.published.single.message,
      'Signing in is now required to report.',
    );
    expect(repo.published.single.messageHtml, isNull);
    expect(repo.published.single.color, isNull);
    expect(repo.published.single.cta, isNull);
    expect(repo.published.single.severity, AnnouncementSeverity.info);
    expect(repo.published.single.expiresAt, isNull);
    expect(find.text('Notice published'), findsOneWidget);
  });

  testWidgets('markup publishes richly with its plain text as the fallback', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(tester, repo: repo);

    await tester.enterText(
      messageField(),
      'Fuel deal at <b>BP Yass</b> — <a href="https://x.io">tap here</a>',
    );
    await tester.pumpAndSettle();

    // Typing brings up a live preview banner of the draft.
    expect(find.text('Preview'), findsOneWidget);
    expect(find.byType(AnnouncementBanner), findsOneWidget);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    final notice = repo.published.single;
    expect(
      notice.messageHtml,
      'Fuel deal at <b>BP Yass</b> — <a href="https://x.io">tap here</a>',
    );
    // What pre-rich builds will show: the same words, markup resolved away.
    expect(notice.message, 'Fuel deal at BP Yass — tap here');
  });

  testWidgets('a swatch tap publishes its colour, auto clears it', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(tester, repo: repo);

    await tester.enterText(messageField(), 'Sponsored run');
    // The hex field is the source of truth; swatches only fill it.
    await tester.enterText(find.byType(TextField).at(1), '2563EB');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repo.published.single.color, '#2563EB');

    // An unparseable colour means "auto": published without one. (The button
    // still reads Publish — the faked live stream never emits.)
    await tester.enterText(find.byType(TextField).at(1), 'nope');
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(repo.published.last.color, isNull);
  });

  testWidgets('a warning can be set to auto-hide', (tester) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(tester, repo: repo);

    await tester.enterText(messageField(), 'Blitz season starts Monday');
    await tester.tap(find.text('Warning'));
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Auto-hide after 7 days'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repo.published.single.severity, AnnouncementSeverity.warning);
    expect(repo.published.single.expiresAt, isNotNull);
  });

  testWidgets('the rate toggle prefills the plea and publishes the CTA', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(tester, repo: repo);

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Ask users to rate the app'),
    );
    await tester.pumpAndSettle();

    // An empty box is seeded with the plea, and the preview already carries
    // the specialised store button mobile users will see.
    expect(
      tester.widget<TextField>(messageField()).controller?.text,
      'Enjoy the app? Would you mind rating us?',
    );
    expect(find.text('Rate RoadMate'), findsOneWidget);

    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repo.published.single.cta, kAnnouncementCtaRate);
    expect(
      repo.published.single.message,
      'Enjoy the app? Would you mind rating us?',
    );
  });

  testWidgets('the rate toggle never overwrites a typed message', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(tester, repo: repo);

    await tester.enterText(messageField(), 'Loving the new Nearby tab?');
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Ask users to rate the app'),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(messageField()).controller?.text,
      'Loving the new Nearby tab?',
    );
  });

  testWidgets('an empty message is refused before it reaches Firestore', (
    tester,
  ) async {
    final repo = FakeAdminRepository();
    await _pumpNoticeTab(tester, repo: repo);

    await tester.enterText(messageField(), '   ');
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(repo.published, isEmpty);
    expect(find.text('Type a message first'), findsOneWidget);

    // Markup that strips to nothing is refused the same way — old builds
    // would otherwise get a blank notice.
    await tester.enterText(messageField(), '<b> </b><br>');
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
    expect(repo.published, isEmpty);
  });

  testWidgets('the message field caps at the length the rules enforce', (
    tester,
  ) async {
    await _pumpNoticeTab(tester, repo: FakeAdminRepository());

    // Pins the form to isValidAnnouncement's 480-char markup cap: a notice the
    // rules would reject must be untypeable rather than fail on submit.
    final field = tester.widget<TextField>(messageField());
    expect(field.maxLength, kAnnouncementHtmlMaxLength);
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
        cta: kAnnouncementCtaRate,
        publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    );

    // The admin sees exactly what users see — the live banner up top and the
    // seeded draft's preview below — and the form is ready for edits,
    // including the rate toggle mirroring the live CTA.
    expect(find.byType(AnnouncementBanner), findsNWidgets(2));
    expect(
      tester.widget<TextField>(messageField()).controller?.text,
      'Roadworks on the Hume.',
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Ask users to rate the app'),
          )
          .value,
      isTrue,
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

    await tester.enterText(messageField(), 'Anything');
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not publish'), findsOneWidget);
  });
}
