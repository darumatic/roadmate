import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/enums.dart';
import '../../services/providers.dart';
import '../../services/rate_limit.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_labels.dart';
import 'proximity_controller.dart';
import 'proximity_text.dart';

/// How long the prompt stays up before dismissing itself. At 100 km/h the
/// 3 km trigger radius is ~110 s from the gate, so an unanswered card clears
/// well before the driver arrives instead of sitting over the app all day.
const Duration proximityPromptTimeout = Duration(seconds: 45);

/// Wraps the app (via `MaterialApp.router`'s builder, inside [UpdateGate]) and
/// floats the approach prompt over the current screen.
///
/// An overlay rather than a route or dialog on purpose: it must appear from
/// any tab without disturbing navigation, and a driver tapping through the app
/// must never find the back button pointed at a popup.
class ProximityGate extends ConsumerStatefulWidget {
  const ProximityGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ProximityGate> createState() => _ProximityGateState();
}

class _ProximityGateState extends ConsumerState<ProximityGate>
    with WidgetsBindingObserver {
  Timer? _timeout;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Off screen, an approach is announced as a system notification instead —
  /// see [ProximityController.setAppForeground].
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    ref
        .read(proximityControllerProvider.notifier)
        .setAppForeground(_foreground);
    // Returning to the app starts the card's countdown from now: a prompt
    // raised in the background must not expire unseen.
    if (_foreground) _restartTimeout(ref.read(proximityControllerProvider));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeout?.cancel();
    super.dispose();
  }

  void _restartTimeout(ProximityPrompt? prompt) {
    _timeout?.cancel();
    // No countdown while the app is off screen — the notification is doing the
    // talking, and its lifetime is the system's business.
    if (prompt == null || !_foreground) return;
    _timeout = Timer(proximityPromptTimeout, () {
      if (mounted) ref.read(proximityControllerProvider.notifier).dismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ProximityPrompt?>(
      proximityControllerProvider,
      (_, next) => _restartTimeout(next),
    );
    final prompt = ref.watch(proximityControllerProvider);

    return Stack(
      children: [
        widget.child,
        if (prompt != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: ProximityPromptCard(
                prompt: prompt,
                onDismiss: () =>
                    ref.read(proximityControllerProvider.notifier).dismiss(),
              ),
            ),
          ),
      ],
    );
  }
}

/// The card itself — split out from the gate so widget tests can drive it
/// directly, and so the layout is reusable if it ever moves.
class ProximityPromptCard extends ConsumerWidget {
  const ProximityPromptCard({
    super.key,
    required this.prompt,
    required this.onDismiss,
  });

  final ProximityPrompt prompt;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final site = prompt.site;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.near_me_outlined,
                  size: 16,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'APPROACHING · ${_distanceLabel(prompt.km)}',
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              site.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              approachStatusLine(site),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "What's the status?",
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final status in SiteStatus.votable) ...[
                  if (status != SiteStatus.votable.first)
                    const SizedBox(width: 8),
                  Expanded(
                    child: _AnswerButton(
                      status: status,
                      onTap: () => _vote(context, ref, status),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Casts the vote and closes the card. The card goes first: a driver must
  /// never be left staring at an unresponsive popup while a write retries.
  Future<void> _vote(
    BuildContext context,
    WidgetRef ref,
    SiteStatus status,
  ) async {
    onDismiss();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(siteRepositoryProvider).vote(prompt.site.id, status);
      _snack(messenger, 'Reported ${statusDisplayLabel(status)} — thanks!');
    } on RateLimitedException {
      _snack(messenger, kRateLimitMessage);
    } catch (e) {
      _snack(messenger, 'Could not submit — please try again.');
    }
  }

  void _snack(ScaffoldMessengerState? messenger, String msg) {
    messenger
      ?..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }
}

String _distanceLabel(double km) => km < 1
    ? '${(km * 1000).round()} m ahead'
    : '${km.toStringAsFixed(1)} km ahead';

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({required this.status, required this.onTap});

  final SiteStatus status;
  final VoidCallback onTap;

  IconData get _icon => switch (status) {
    SiteStatus.open => Icons.check_circle_outline,
    SiteStatus.blitz => Icons.warning_amber_rounded,
    SiteStatus.closed => Icons.cancel_outlined,
    SiteStatus.unknown => Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Taller than the card buttons: this one is tapped at speed.
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: status.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: status.color.withValues(alpha: 0.8)),
        ),
        child: Column(
          children: [
            Icon(_icon, size: 20, color: status.color),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                statusDisplayLabel(status),
                maxLines: 1,
                style: TextStyle(
                  color: status.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
