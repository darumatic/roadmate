import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/announcement.dart';
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
    final visible =
        announcement != null &&
        announcement.isVisibleAt(DateTime.now(), dismissedKey: _dismissedKey);
    if (!visible) return widget.child;
    return Column(
      children: [
        AnnouncementBanner(
          announcement: announcement,
          onDismiss: () => _dismiss(announcement),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// The banner itself. Public and dependency-free so it can be pumped directly
/// in widget tests.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onDismiss,
  });

  final Announcement announcement;
  final VoidCallback onDismiss;

  /// Warnings borrow the brand accent (the same orange the update banner and
  /// BLITZ use); ordinary notices stay in the card grey so they read as
  /// information, not alarm.
  Color get _background => announcement.severity == AnnouncementSeverity.warning
      ? AppTheme.accent
      : AppTheme.surfaceAlt;

  Color get _foreground => announcement.severity == AnnouncementSeverity.warning
      ? Colors.white
      : AppTheme.textPrimary;

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
                child: Text(
                  announcement.message,
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
