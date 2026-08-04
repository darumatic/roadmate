import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/providers.dart';
import '../services/username_logic.dart';
import '../services/username_store.dart';
import '../theme/app_theme.dart';

/// Session-scoped "Not now": quiets the load-time prompt until the next
/// launch. Posting still requires a name ([ensureSignatureName]) — this only
/// stops the card from nagging a user who is just browsing.
class UsernamePromptDismissal extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final usernamePromptDismissedProvider =
    NotifierProvider<UsernamePromptDismissal, bool>(
      UsernamePromptDismissal.new,
    );

/// Wraps the app (via `MaterialApp.router`'s builder, inside [ProximityGate])
/// and floats the road-name picker over the current screen when an anonymous
/// user has no name yet. An overlay, not a dialog/route, for the same reason
/// as the proximity card: the back button must never point at a popup.
class UsernameGate extends ConsumerWidget {
  const UsernameGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    final profile = ref.watch(myProfileProvider).value;
    final dismissed = ref.watch(usernamePromptDismissedProvider);
    final show = shouldPromptForUsername(
      isAnonymousUser: user != null && user.isAnonymous,
      profileLoaded: profile != null,
      username: profile?.username,
      dismissed: dismissed,
    );
    // The Stack is always returned — collapsing to the bare child when the
    // card hides would reparent the whole app subtree (router included) and
    // reset every screen's state the moment a name is saved or dismissed.
    return Stack(
      children: [
        child,
        if (show)
          Positioned.fill(
            // This gate sits ABOVE the router's Navigator, so no Overlay
            // exists here — yet the card needs one: the dice tooltip and the
            // TextField's selection toolbar both summon popup UI through
            // Overlay.of(). Without a local Overlay, hovering the dice greyed
            // the whole app with "No Overlay widget found". Positioned.fill
            // gives it bounded constraints; empty regions stay tap-through.
            child: Overlay.wrap(
              child: Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                          const Row(
                            children: [
                              Icon(
                                Icons.badge_outlined,
                                size: 16,
                                color: AppTheme.accent,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'PICK YOUR ROAD NAME',
                                style: TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          UsernameForm(
                            // No pop here: claiming updates the profile stream and
                            // the gate simply stops matching.
                            onSaved: (_) {},
                            onDismiss: () => ref
                                .read(usernamePromptDismissedProvider.notifier)
                                .dismiss(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The picker itself — a generated name the user can reroll (dice) or edit
/// freely, saved through [usernameStoreProvider]. Shared between the
/// load-time gate card and the post-time dialog.
class UsernameForm extends ConsumerStatefulWidget {
  const UsernameForm({
    super.key,
    required this.onSaved,
    required this.onDismiss,
    this.dismissLabel = 'Not now',
    this.initialName,
  });

  final ValueChanged<String> onSaved;
  final VoidCallback onDismiss;
  final String dismissLabel;

  /// Pre-fills the field — the user's current name when editing, so a rename
  /// starts from what they have; null (first pick) starts from a fresh roll.
  final String? initialName;

  @override
  ConsumerState<UsernameForm> createState() => _UsernameFormState();
}

class _UsernameFormState extends ConsumerState<UsernameForm> {
  final _random = Random();
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialName ?? generateUsername(_random),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reroll() {
    setState(() {
      _error = null;
      _controller.text = generateUsername(_random);
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final name = await ref
          .read(usernameStoreProvider)
          .claimUsername(_controller.text);
      if (!mounted) return;
      widget.onSaved(name);
    } on UsernameInvalidException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on UsernameTakenException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save your road name — please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your reports and votes are signed with this public name. '
          'Roll the dice or type your own.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.words,
                maxLength: kUsernameMaxLength,
                decoration: InputDecoration(
                  hintText: 'Road name',
                  counterText: '',
                  errorText: _error,
                  errorMaxLines: 3,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.casino_outlined, color: AppTheme.accent),
              tooltip: 'Roll another name',
              onPressed: _saving ? null : _reroll,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _saving ? null : widget.onDismiss,
              child: Text(widget.dismissLabel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The post-time picker, for screens with a Navigator below them. Resolves to
/// the claimed name, or null when the user backs out. Pass [initialName]
/// (the current name) when editing, so the rename starts from it.
Future<String?> showUsernameDialog(
  BuildContext context, {
  String? initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(
        initialName == null ? 'Pick your road name' : 'Change your road name',
      ),
      content: UsernameForm(
        dismissLabel: 'Cancel',
        initialName: initialName,
        onSaved: (name) => Navigator.pop(dialogContext, name),
        onDismiss: () => Navigator.pop(dialogContext),
      ),
    ),
  );
}

/// The name the current user signs posts with, asking them to pick one when
/// they have none (anonymous, never chose). Null means they declined — the
/// post must not proceed. Signed-in users fall through on their displayName
/// and are never interrupted.
///
/// A synchronous provider read: [UsernameGate] wraps every screen and watches
/// [myProfileProvider], so the stream is live (and settled) long before
/// anyone reaches a post button — and callers watch [signatureNameProvider]
/// themselves as a belt-and-braces. The worst cold-start race merely shows
/// the picker to someone who already has a name; saving it again is a no-op.
Future<String?> ensureSignatureName(BuildContext context, WidgetRef ref) {
  final signature = ref.read(signatureNameProvider);
  if (signature != null) return Future.value(signature);
  return showUsernameDialog(context);
}
