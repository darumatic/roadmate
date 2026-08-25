import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/announcement.dart';
import 'package:roadmate/services/announcement_dismiss_store.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/theme/app_theme.dart';
import 'package:roadmate/widgets/announcement_banner.dart';
import 'package:roadmate/widgets/rate_app_popup.dart';

/// In-memory [AnnouncementDismissStore] — test-only, so it lives here rather
/// than in lib/ (unlike MemoryUsernameStore, which backs a production
/// Firebase-less fallback).
class MemoryAnnouncementDismissStore implements AnnouncementDismissStore {
  MemoryAnnouncementDismissStore([this.dismissKey]);

  String? dismissKey;

  @override
  Future<String?> load() async => dismissKey;

  @override
  Future<void> save(String key) async => dismissKey = key;
}

/// A store still reading from disk: answers only when the test says so.
class PendingDismissStore extends MemoryAnnouncementDismissStore {
  final answer = Completer<String?>();

  @override
  Future<String?> load() => answer.future;
}

void main() {
  final published = DateTime.utc(2026, 7, 30, 9);

  Announcement notice({
    String message = 'Signing in is now required to report.',
    String? messageHtml,
    String? color,
    AnnouncementSeverity severity = AnnouncementSeverity.info,
    String? cta,
    DateTime? expiresAt,
  }) {
    return Announcement(
      message: message,
      messageHtml: messageHtml,
      color: color,
      severity: severity,
      cta: cta,
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

  /// The rate popup alone, outside the gate, with the store and any link tap
  /// recorded rather than launched and every answer counted.
  Widget popup(
    Announcement announcement, {
    required ValueChanged<String> onOpenLink,
    required VoidCallback onDismiss,
  }) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: RateAppPopup(
            announcement: announcement,
            rateUrl: 'https://store.example/rate',
            onDismiss: onDismiss,
            onOpenLink: onOpenLink,
          ),
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
    // The popup belongs to the rate CTA alone, never to an ordinary notice.
    expect(find.byType(RateAppPopup), findsNothing);
  });

  testWidgets('no notice leaves the app untouched', (tester) async {
    await tester.pumpWidget(gate(null, MemoryAnnouncementDismissStore()));
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementBanner), findsNothing);
    expect(find.byType(RateAppPopup), findsNothing);
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

  testWidgets('the rate popup opens the store and closes on Rate', (
    tester,
  ) async {
    String? opened;
    var answered = 0;
    await tester.pumpWidget(
      popup(
        notice(
          message: 'Enjoy the app? Would you mind rating us?',
          cta: kAnnouncementCtaRate,
        ),
        onOpenLink: (url) => opened = url,
        onDismiss: () => answered++,
      ),
    );

    // The shape of the ask: the plea, five stars, the store button, a way out.
    expect(
      find.text('Enjoy the app? Would you mind rating us?'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
    expect(find.text('Not now'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Rate RoadMate'));
    expect(opened, 'https://store.example/rate');
    // Rating settles the notice: the popup must not be waiting on return.
    expect(answered, 1);
  });

  testWidgets('the stars are a shortcut to the store', (tester) async {
    String? opened;
    var answered = 0;
    await tester.pumpWidget(
      popup(
        notice(cta: kAnnouncementCtaRate),
        onOpenLink: (url) => opened = url,
        onDismiss: () => answered++,
      ),
    );

    await tester.tap(find.byIcon(Icons.star_rounded).at(2));
    expect(opened, 'https://store.example/rate');
    expect(answered, 1);
  });

  testWidgets('Not now closes the popup without opening the store', (
    tester,
  ) async {
    String? opened;
    var answered = 0;
    await tester.pumpWidget(
      popup(
        notice(cta: kAnnouncementCtaRate),
        onOpenLink: (url) => opened = url,
        onDismiss: () => answered++,
      ),
    );

    await tester.tap(find.text('Not now'));
    expect(opened, isNull);
    expect(answered, 1);
  });

  testWidgets('a rich rate notice renders its markup in the popup', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      popup(
        notice(
          message: 'Loving RoadMate? Tell us',
          messageHtml:
              '<b>Loving RoadMate?</b> <a href="https://x.io/why">Tell us</a>',
          cta: kAnnouncementCtaRate,
        ),
        onOpenLink: (url) => opened = url,
        onDismiss: () {},
      ),
    );

    expect(
      find.textContaining('Loving RoadMate? Tell us', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('<b>', findRichText: true), findsNothing);

    await tester.tapOnText(find.textRange.ofSubstring('Tell us'));
    expect(opened, 'https://x.io/why');
  });

  testWidgets(
    'through the gate, Android gets a rate notice as a popup over the app',
    (tester) async {
      // flutter test reports TargetPlatform.android, so the gate resolves the
      // Play listing — the same path a phone takes.
      await tester.pumpWidget(
        gate(
          notice(cta: kAnnouncementCtaRate),
          MemoryAnnouncementDismissStore(),
        ),
      );
      await tester.pumpAndSettle();

      // A popup behind a scrim, not a strip: the app stays underneath. (The
      // scrim is looked up inside the gate — the test's page route has one
      // of its own.)
      expect(find.byType(RateAppPopup), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AnnouncementGate),
          matching: find.byType(ModalBarrier),
        ),
        findsOneWidget,
      );
      expect(find.byType(AnnouncementBanner), findsNothing);
      expect(find.text('Rate RoadMate'), findsOneWidget);
      expect(find.text('app'), findsOneWidget);
    },
  );

  testWidgets('through the gate, Not now closes the popup and remembers it', (
    tester,
  ) async {
    final store = MemoryAnnouncementDismissStore();
    final announcement = notice(cta: kAnnouncementCtaRate);
    await tester.pumpWidget(gate(announcement, store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.byType(RateAppPopup), findsNothing);
    expect(find.text('app'), findsOneWidget);
    // Remembered like a closed banner: only an admin re-publish asks again.
    expect(store.dismissKey, announcement.dismissKey);
  });

  testWidgets('a tap outside the popup is Not now', (tester) async {
    final store = MemoryAnnouncementDismissStore();
    final announcement = notice(cta: kAnnouncementCtaRate);
    await tester.pumpWidget(gate(announcement, store));
    await tester.pumpAndSettle();

    // The corner is scrim: the card sits in the middle of the screen.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.byType(RateAppPopup), findsNothing);
    expect(store.dismissKey, announcement.dismissKey);
  });

  testWidgets('a rate notice already answered on this device never pops up', (
    tester,
  ) async {
    final announcement = notice(cta: kAnnouncementCtaRate);
    await tester.pumpWidget(
      gate(
        announcement,
        MemoryAnnouncementDismissStore(announcement.dismissKey),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RateAppPopup), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('the popup waits for the dismiss store to answer', (
    tester,
  ) async {
    final store = PendingDismissStore();
    await tester.pumpWidget(gate(notice(cta: kAnnouncementCtaRate), store));
    await tester.pumpAndSettle();

    // An interruption must not flash at a driver who already answered it, so
    // the popup holds until the store says whether they did.
    expect(find.byType(RateAppPopup), findsNothing);
    expect(find.text('app'), findsOneWidget);

    store.answer.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(RateAppPopup), findsOneWidget);
  });

  testWidgets('the banner does not wait for the dismiss store', (tester) async {
    // News goes up at once — a frame of an already-read notice beats
    // withholding an urgent one while the store reads from disk.
    await tester.pumpWidget(gate(notice(), PendingDismissStore()));
    await tester.pumpAndSettle();

    expect(find.byType(AnnouncementBanner), findsOneWidget);
  });

  testWidgets('a rate notice is hidden entirely where there is no store', (
    tester,
  ) async {
    // Desktop stands in for "no store to rate in" (web's kIsWeb cannot be
    // faked in a VM test; rateUrlFor's own test covers it). Reset in the body,
    // not addTearDown — the binding checks debug variables before teardowns.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    await tester.pumpWidget(
      gate(notice(cta: kAnnouncementCtaRate), MemoryAnnouncementDismissStore()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RateAppPopup), findsNothing);
    expect(find.byType(AnnouncementBanner), findsNothing);
    expect(find.text('app'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('an ordinary notice still shows where there is no store', (
    tester,
  ) async {
    // Only the rate CTA hides on an unratable platform — never the message.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    await tester.pumpWidget(gate(notice(), MemoryAnnouncementDismissStore()));
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementBanner), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
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
