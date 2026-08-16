import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/announcement.dart';
import '../services/min_version.dart';
import '../services/notice_markup.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';

/// Wraps the whole app (via `MaterialApp.router`'s builder, alongside
/// [UpdateGate]) and puts the current admin notice in a slim banner above the
/// content — so one message reaches every user on every tab and screen.
///
/// Same shape as [UpdateGate] deliberately: a [Column] that steals a strip from
/// the top rather than an overlay, so nothing can cover the nav bar or a
/// dialog. With no notice (the normal case) the child is returned untouched and
/// this costs a single document listener.
class AnnouncementGate extends ConsumerStatefulWidget {
  const AnnouncementGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AnnouncementGate> createState() => _AnnouncementGateState();
}

class _AnnouncementGateState extends ConsumerState<AnnouncementGate> {
  /// The notice this device has dismissed, read once at startup. Null until the
  /// store answers, which is why the banner may appear for a frame and then go —
  /// preferable to withholding an urgent notice while waiting on disk.
  String? _dismissedKey;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    final key = await ref.read(announcementDismissStoreProvider).load();
    if (mounted) setState(() => _dismissedKey = key);
  }

  Future<void> _dismiss(Announcement announcement) async {
    // Optimistic: the banner goes now, the write follows. A failed write only
    // means the notice returns next launch.
    setState(() => _dismissedKey = announcement.dismissKey);
    await ref
        .read(announcementDismissStoreProvider)
        .save(announcement.dismissKey);
  }

  @override
  Widget build(BuildContext context) {
    final announcement = ref.watch(announcementProvider).value;
    // Where this runtime could be rated — null on web/desktop, so a rate
    // notice is not shown at all there (nothing to rate, no button to press).
    final rateUrl = rateUrlFor(isWeb: kIsWeb, platform: defaultTargetPlatform);
    final visible =
        announcement != null &&
        announcement.isVisibleAt(DateTime.now(), dismissedKey: _dismissedKey) &&
        (!announcement.asksForRating || rateUrl != null);
    if (!visible) return widget.child;
    return Column(
      children: [
        AnnouncementBanner(
          announcement: announcement,
          rateUrl: rateUrl,
          onDismiss: () => _dismiss(announcement),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// The banner itself. Public and pumpable directly in widget tests: pass
/// [onOpenLink] there so a tapped link is recorded instead of reaching the
/// url_launcher plugin.
///
/// Rich notices ([Announcement.messageHtml], the safe subset of
/// `notice_markup.dart`) render as styled spans with tappable links; plain
/// notices render exactly as they always have. A custom [Announcement.color]
/// replaces the severity background, with black/white text picked for
/// contrast.
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onDismiss,
    this.rateUrl,
    this.onOpenLink,
  });

  final Announcement announcement;
  final VoidCallback onDismiss;

  /// The store-review URL the Rate button opens when [announcement] asks for a
  /// rating. The gate passes the running platform's own store (`rateUrlFor`);
  /// the admin preview passes a stand-in so the button is visible while
  /// composing. Null means no button — the caller decides, never this widget.
  final String? rateUrl;

  /// Where link taps go. Null (production) opens the URL in the browser /
  /// external app; tests inject a recorder.
  final ValueChanged<String>? onOpenLink;

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  /// Recognizers backing the current build's link spans — replaced wholesale
  /// each build and disposed with the state, as [TextSpan.recognizer] requires.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _open(String url) {
    final handler = widget.onOpenLink;
    if (handler != null) {
      handler(url);
      return;
    }
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// Warnings borrow the brand accent (the same orange the update banner and
  /// BLITZ use); ordinary notices stay in the card grey so they read as
  /// information, not alarm. An admin-picked colour overrides either.
  Color get _background {
    final custom = widget.announcement.colorValue;
    if (custom != null) return Color(custom);
    return widget.announcement.severity == AnnouncementSeverity.warning
        ? AppTheme.accent
        : AppTheme.surfaceAlt;
  }

  Color get _foreground {
    final custom = widget.announcement.colorValue;
    if (custom != null) {
      return prefersDarkForeground(custom) ? Colors.black : Colors.white;
    }
    return widget.announcement.severity == AnnouncementSeverity.warning
        ? Colors.white
        : AppTheme.textPrimary;
  }

  /// The message as spans: plain notices stay a single [Text]; rich ones map
  /// each parsed [NoticeSpan] onto the base style, links underlined and wired
  /// to [_open].
  Widget _message(TextStyle base) {
    final html = widget.announcement.messageHtml;
    if (html == null) return Text(widget.announcement.message, style: base);
    _disposeRecognizers();
    final spans = <TextSpan>[];
    for (final span in parseNoticeMarkup(html)) {
      TapGestureRecognizer? recognizer;
      final link = span.linkUrl;
      if (link != null) {
        recognizer = TapGestureRecognizer()..onTap = () => _open(link);
        _recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: span.text,
          recognizer: recognizer,
          style: TextStyle(
            // The base is already w600; bold steps up from there.
            fontWeight: span.bold ? FontWeight.w800 : null,
            fontStyle: span.italic ? FontStyle.italic : null,
            decoration: (span.underline || link != null)
                ? TextDecoration.underline
                : null,
            color: span.color != null ? Color(span.color!) : null,
          ),
        ),
      );
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }

  /// The specialised store CTA of a rate notice: inverted colours so it stands
  /// out on any banner background, opening whichever store [widget.rateUrl]
  /// points at (Play on Android, the App Store rating sheet on iOS).
  Widget _rateButton(String url) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: () => _open(url),
          icon: const Icon(Icons.star_rounded, size: 16),
          label: const Text('Rate RoadMate'),
          style: FilledButton.styleFrom(
            backgroundColor: _foreground,
            foregroundColor: _background,
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcement;
    final rateUrl = announcement.asksForRating ? widget.rateUrl : null;
    return Material(
      color: _background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 14, top: 6, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                announcement.severity == AnnouncementSeverity.warning
                    ? Icons.warning_amber_rounded
                    : Icons.campaign_outlined,
                color: _foreground,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _message(
                      TextStyle(
                        color: _foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (rateUrl != null) _rateButton(rateUrl),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: _foreground,
                visualDensity: VisualDensity.compact,
                tooltip: 'Dismiss',
                onPressed: widget.onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
