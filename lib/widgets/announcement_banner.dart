import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/announcement.dart';
import '../services/min_version.dart';
import '../services/notice_markup.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import 'notice_text.dart';
import 'rate_app_popup.dart';

/// Wraps the whole app (via `MaterialApp.router`'s builder, inside
/// [ProximityGate]) and shows the current admin notice: a slim banner above
/// the content — so one message reaches every user on every tab and screen —
/// or, for a rate ask ([Announcement.asksForRating]), a [RateAppPopup] floated
/// over the content behind a scrim (issue #35).
///
/// The banner is the same shape as [UpdateGate] deliberately: a [Column] that
/// steals a strip from the top rather than an overlay, so nothing can cover
/// the nav bar or a dialog. The popup is an in-tree overlay rather than a
/// dialog route for the same reason as the approach and road-name cards: this
/// gate sits above the router's Navigator, and the back button must never
/// point at a popup. With no notice (the normal case) the child renders
/// untouched and this costs a single document listener.
class AnnouncementGate extends ConsumerStatefulWidget {
  const AnnouncementGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AnnouncementGate> createState() => _AnnouncementGateState();
}

class _AnnouncementGateState extends ConsumerState<AnnouncementGate> {
  /// The notice this device has dismissed, read once at startup. Null until the
  /// store answers, which is why the banner may appear for a frame and then go —
  /// preferable to withholding an urgent notice while waiting on disk. The
  /// popup does wait ([_dismissLoaded]): it is an interruption, not news, and
  /// one flashed at a driver who already answered it would be a bug.
  String? _dismissedKey;
  bool _dismissLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    final key = await ref.read(announcementDismissStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _dismissedKey = key;
      _dismissLoaded = true;
    });
  }

  Future<void> _dismiss(Announcement announcement) async {
    // Optimistic: the notice goes now, the write follows. A failed write only
    // means the notice returns next launch.
    setState(() => _dismissedKey = announcement.dismissKey);
    await ref
        .read(announcementDismissStoreProvider)
        .save(announcement.dismissKey);
  }

  /// The rate popup and its scrim — or nothing: a rate ask shows only where
  /// there is a store to rate in (`rateUrlFor` is null on web/desktop, so web
  /// users get no rate notice at all) and only once the dismiss store has
  /// answered.
  List<Widget> _ratePopup(BuildContext context, Announcement notice) {
    final rateUrl = rateUrlFor(isWeb: kIsWeb, platform: defaultTargetPlatform);
    if (rateUrl == null || !_dismissLoaded) return const [];
    return [
      Positioned.fill(
        child: ModalBarrier(
          color: Colors.black54,
          // A tap outside is "Not now": it settles the notice too.
          onDismiss: () => _dismiss(notice),
          semanticsLabel: MaterialLocalizations.of(
            context,
          ).modalBarrierDismissLabel,
        ),
      ),
      Positioned.fill(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: RateAppPopup(
                announcement: notice,
                rateUrl: rateUrl,
                onDismiss: () => _dismiss(notice),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final announcement = ref.watch(announcementProvider).value;
    final notice =
        announcement != null &&
            announcement.isVisibleAt(
              DateTime.now(),
              dismissedKey: _dismissedKey,
            )
        ? announcement
        : null;
    // The Column/Stack is returned whatever shows: collapsing to the bare child
    // when nothing does would reparent the whole app subtree (router included)
    // and reset every screen's state each time a notice comes or goes — the
    // same reasoning as UsernameGate.
    return Column(
      children: [
        if (notice != null && !notice.asksForRating)
          AnnouncementBanner(
            announcement: notice,
            onDismiss: () => _dismiss(notice),
          ),
        Expanded(
          child: Stack(
            children: [
              widget.child,
              if (notice != null && notice.asksForRating)
                ..._ratePopup(context, notice),
            ],
          ),
        ),
      ],
    );
  }
}

/// The banner itself. Public and pumpable directly in widget tests: pass
/// [onOpenLink] there so a tapped link is recorded instead of reaching the
/// url_launcher plugin.
///
/// Rich notices ([Announcement.messageHtml], the safe subset of
/// `notice_markup.dart`) render as styled spans with tappable links
/// ([NoticeText]); plain notices render exactly as they always have. A custom
/// [Announcement.color] replaces the severity background, with black/white
/// text picked for contrast. Rate notices never come here — the gate floats
/// them as a [RateAppPopup] instead.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onDismiss,
    this.onOpenLink,
  });

  final Announcement announcement;
  final VoidCallback onDismiss;

  /// Where link taps go. Null (production) opens the URL in the browser /
  /// external app; tests inject a recorder.
  final ValueChanged<String>? onOpenLink;

  /// Warnings borrow the brand accent (the same orange the update banner and
  /// BLITZ use); ordinary notices stay in the card grey so they read as
  /// information, not alarm. An admin-picked colour overrides either.
  Color get _background {
    final custom = announcement.colorValue;
    if (custom != null) return Color(custom);
    return announcement.severity == AnnouncementSeverity.warning
        ? AppTheme.accent
        : AppTheme.surfaceAlt;
  }

  Color get _foreground {
    final custom = announcement.colorValue;
    if (custom != null) {
      return prefersDarkForeground(custom) ? Colors.black : Colors.white;
    }
    return announcement.severity == AnnouncementSeverity.warning
        ? Colors.white
        : AppTheme.textPrimary;
  }

  @override
  Widget build(BuildContext context) {
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
                child: NoticeText(
                  announcement: announcement,
                  onOpenLink: onOpenLink,
                  style: TextStyle(
                    color: _foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: _foreground,
                visualDensity: VisualDensity.compact,
                tooltip: 'Dismiss',
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
