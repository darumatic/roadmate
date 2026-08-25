import 'package:flutter/material.dart';

import '../services/announcement.dart';
import '../theme/app_theme.dart';
import 'notice_text.dart';

/// The popup a rate notice ([Announcement.asksForRating]) opens as — a centred
/// card in the app's own style, modelled on the store-rating prompts drivers
/// know from other apps (issue #35): brand mark, the admin's plea, five stars,
/// a store button and a way out. Public and pumpable on its own: the
/// announcement gate floats it over the app behind a scrim, the admin Notice
/// tab renders it inline as the preview.
///
/// Either answer settles the notice: Rate opens the store and closes the
/// popup; Not now just closes it. Both go through [onDismiss], so the gate
/// remembers the notice as read exactly as it does a closed banner — a popup
/// that came back on every launch would be a nag, not a request.
class RateAppPopup extends StatelessWidget {
  const RateAppPopup({
    super.key,
    required this.announcement,
    required this.rateUrl,
    required this.onDismiss,
    this.onOpenLink,
  });

  final Announcement announcement;

  /// The store this runtime is rated in (`rateUrlFor`); the admin preview
  /// passes a stand-in so the popup is complete while composing on web.
  final String rateUrl;

  /// Called once the popup has been answered, either way.
  final VoidCallback onDismiss;

  /// Where the store button and any link in the message go. Null (production)
  /// opens them outside the app; tests inject a recorder.
  final ValueChanged<String>? onOpenLink;

  void _rate() {
    (onOpenLink ?? launchExternalUrl)(rateUrl);
    onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.accent, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The brand mark, as the startup screen draws it.
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.local_shipping,
                  color: AppTheme.accent,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 16),
            NoticeText(
              announcement: announcement,
              textAlign: TextAlign.center,
              onOpenLink: onOpenLink,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'A quick rating helps more drivers find RoadMate.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 14),
            // The stars are the invitation, not a picker — rating happens in
            // the store, so a tap on them goes there like the button does.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _rate,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.filled(
                    5,
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.star_rounded,
                        color: AppTheme.accent,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onPressed: _rate,
              child: const Text('Rate RoadMate'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: onDismiss,
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
