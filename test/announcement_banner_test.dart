import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/announcement.dart';
import 'package:roadmate/services/announcement_dismiss_store.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/theme/app_theme.dart';
import 'package:roadmate/widgets/announcement_banner.dart';

void main() {
  final published = DateTime.utc(2026, 7, 30, 9);

  Announcement notice({
    String message = 'Signing in is now required to report.',
    String? messageHtml,
    String? color,
    AnnouncementSeverity severity = AnnouncementSeverity.info,
    DateTime? expiresAt,
  }) {
    return Announcement(
      message: message,
      messageHtml: messageHtml,
      color: color,
      severity: severity,
      publishedAt: published,
      expiresAt: expiresAt,
    );
  }

  /// The banner alone, outside the gate — how the rich-rendering tests pump it,
  /// with link taps recorded rather than launched.
  Widget bare(Announcement announcement, {ValueChanged<String>? onOpenLink}) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: AnnouncementBanner(
          announcement: announcement,
          onDismiss: () {},
          onOpenLink: onOpenLink,
        ),
      ),
    );
  }

  Widget gate(Announcement? announcement, AnnouncementDismissStore store) {
    return ProviderScope(
      overrides: [
        announcementProvider.overrideWith((ref) => Stream.value(announcement)),
        announcementDismissStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: AnnouncementGate(
          child: Scaffold(body: Builder(builder: (_) => const Text('app'))),
        ),
      ),
    );
  }

  testWidgets('the notice bands across the top, above the app', (tester) async {
    await tester.pumpWidget(gate(notice(), MemoryAnnouncementDismissStore()));
    await tester.pumpAndSettle();

    expect(find.text('Signing in is now required to report.'), findsOneWidget);
    expect(find.text('app'), findsOneWidget);
    // Above, not over: the banner takes a strip and the app keeps the rest.
    final bannerY = tester.getBottomLeft(find.byType(AnnouncementBanner)).dy;
    expect(bannerY, lessThanOrEqualTo(tester.getTopLeft(find.text('app')).dy));
  });

  testWidgets('no notice leaves the app untouched', (tester) async {
    await tester.pumpWidget(gate(null, MemoryAnnouncementDismissStore()));
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementBanner), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('dismissing hides the banner and remembers it', (tester) async {
    final store = MemoryAnnouncementDismissStore();
    final announcement = notice();
    await tester.pumpWidget(gate(announcement, store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementBanner), findsNothing);
    expect(store.dismissKey, announcement.dismissKey);
  });

  testWidgets('a notice already dismissed on this device never shows', (
    tester,
  ) async {
    final announcement = notice();
    final store = MemoryAnnouncementDismissStore(announcement.dismissKey);
    await tester.pumpWidget(gate(announcement, store));
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementBanner), findsNothing);
  });

  testWidgets('an expired notice never shows', (tester) async {
    await tester.pumpWidget(
      gate(
        notice(expiresAt: DateTime.utc(2020)),
        MemoryAnnouncementDismissStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementBanner), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('a warning reads louder than an info notice', (tester) async {
    await tester.pumpWidget(
      gate(
        notice(severity: AnnouncementSeverity.warning, message: 'Heads up'),
        MemoryAnnouncementDismissStore(),
      ),
    );
    await tester.pumpAndSettle();

    // .first: the banner's own Material, not the inner one the dismiss
    // IconButton brings with it.
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AnnouncementBanner),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, AppTheme.accent);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('a rich notice renders its markup and opens the tapped link', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      bare(
        notice(
          message: 'Fuel deal at BP Yass — tap here',
          messageHtml:
              '<b>Fuel deal</b> at BP Yass — '
              '<a href="https://example.com/deal">tap here</a>',
        ),
        onOpenLink: (url) => opened = url,
      ),
    );

    // The markup resolved to styled text — no tag leaks through to the user.
    expect(
      find.textContaining('Fuel deal at BP Yass', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('<b>', findRichText: true), findsNothing);

    await tester.tapOnText(find.textRange.ofSubstring('tap here'));
    expect(opened, 'https://example.com/deal');
  });

  testWidgets('a custom colour restyles the banner, foreground auto-picked', (
    tester,
  ) async {
    await tester.pumpWidget(
      bare(notice(message: 'Sponsored run', color: '#2563EB')),
    );

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(AnnouncementBanner),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, const Color(0xFF2563EB));
    // Blue is dark, so the text goes white for contrast.
    final text = tester.widget<Text>(find.text('Sponsored run'));
    expect(text.style?.color, Colors.white);
  });

  testWidgets('through the gate, a rich notice is still dismissible', (
    tester,
  ) async {
    final store = MemoryAnnouncementDismissStore();
    final announcement = notice(
      message: 'Deal — tap',
      messageHtml: 'Deal — <a href="https://x.io">tap</a>',
      color: '#16A34A',
    );
    await tester.pumpWidget(gate(announcement, store));
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementBanner), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementBanner), findsNothing);
    expect(store.dismissKey, announcement.dismissKey);
  });
}
