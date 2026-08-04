import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../services/participation_logic.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import 'level_badge.dart';

const _deleteRed = Color(0xFFEF4444);

class AccountPanel extends ConsumerWidget {
  const AccountPanel({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Firebase.apps.isEmpty) {
      return _Shell(
        icon: Icons.account_circle_outlined,
        title: 'Account',
        child: const Text(
          'Sign-in is unavailable until Firebase starts.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.35),
        ),
      );
    }

    final userAsync = ref.watch(authStateProvider);
    final roleAsync = ref.watch(currentUserRoleProvider);
    return userAsync.when(
      loading: () => const _Shell(
        icon: Icons.account_circle_outlined,
        title: 'Account',
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (error, _) => _Shell(
        icon: Icons.account_circle_outlined,
        title: 'Account',
        child: Text(
          'Could not load account: $error',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
      data: (user) => _Shell(
        icon: Icons.account_circle_outlined,
        title: 'Account',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AccountSummary(user: user, role: roleAsync.value),
            const ParticipationSummary(),
            const AdminEntryLink(),
            const SizedBox(height: 12),
            AccountActions(user: user),
          ],
        ),
      ),
    );
  }
}

/// The sign-in / sign-out / delete-account actions for [user]. Public and
/// Firebase-free so widget tests can pump it with a fake [AuthController].
class AccountActions extends ConsumerStatefulWidget {
  const AccountActions({super.key, required this.user});

  final User? user;

  @override
  ConsumerState<AccountActions> createState() => _AccountActionsState();
}

class _AccountActionsState extends ConsumerState<AccountActions> {
  String? _busyProvider;

  // Apple guideline 4.8 only applies to the iOS app; web/Android stay
  // Google-only (no Apple Services ID is configured for the web flow).
  bool get _isIosApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    if (user == null || user.isAnonymous) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isIosApp) ...[
            _ProviderButton(
              icon: Icons.apple,
              label: 'Sign in with Apple',
              filled: true,
              busy: _busyProvider == 'apple',
              onPressed: _busyProvider != null
                  ? null
                  : () => _signIn(
                      'apple',
                      'Apple',
                      () => ref.read(authControllerProvider).signInWithApple(),
                    ),
            ),
            const SizedBox(height: 8),
          ],
          _ProviderButton(
            icon: Icons.g_mobiledata_rounded,
            label: 'Sign in with Google',
            filled: _isIosApp,
            busy: _busyProvider == 'google',
            onPressed: _busyProvider != null
                ? null
                : () => _signIn(
                    'google',
                    'Google',
                    () => ref.read(authControllerProvider).signInWithGoogle(),
                  ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
            side: const BorderSide(color: AppTheme.border),
          ),
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: const Text('Sign out'),
          onPressed: _busyProvider == null ? _signOut : null,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: _deleteRed),
          icon: _busyProvider == 'delete'
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_forever_outlined, size: 18),
          label: const Text('Delete account'),
          onPressed: _busyProvider == null ? _deleteAccount : null,
        ),
      ],
    );
  }

  Future<void> _signIn(
    String provider,
    String providerLabel,
    Future<UserCredential?> Function() action,
  ) async {
    setState(() => _busyProvider = provider);
    try {
      final credential = await action();
      if (!mounted) return;
      // Null: the popup was blocked and a full-page redirect was started —
      // the browser is navigating to the provider now.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            credential == null
                ? 'Taking you to $providerLabel sign-in…'
                : 'Signed in',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = shouldFallBackToRedirect(e)
          ? 'Your browser blocked the sign-in window — please allow pop-ups '
                'for roadmate.club and try again.'
          : 'Could not sign in: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busyProvider = 'signOut');
    try {
      await ref.read(authControllerProvider).signOut();
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your sign-in, profile and favourites. '
          'Status votes and activity reports you have submitted stay in the '
          'app but are anonymised — they can no longer be linked to you. '
          'Trip logs stored on this device are not affected. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: _deleteRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyProvider = 'delete');
    try {
      await ref.read(authControllerProvider).deleteAccount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = shouldFallBackToRedirect(e)
          ? 'Your browser blocked the sign-in window needed to confirm the '
                'deletion — please allow pop-ups for roadmate.club and try '
                'again.'
          : 'Could not delete account: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.user, required this.role});

  final User? user;
  final AppUserRole? role;

  @override
  Widget build(BuildContext context) {
    final email = user?.email;
    final label = switch ((user, role)) {
      (null, _) => 'Using RoadMate anonymously.',
      (final current?, _) when current.isAnonymous =>
        'Using RoadMate anonymously.',
      (_, AppUserRole.admin) => 'Signed in as admin.',
      (_, _) => 'Signed in as truckie.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.35),
        ),
        if (email != null) ...[
          const SizedBox(height: 4),
          Text(
            email,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (user == null || user!.isAnonymous) ...[
          const SizedBox(height: 4),
          const Text(
            'Sign in to keep your trips and favourites across devices.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

/// The user's participation level: badge, title, points and progress toward
/// the next rung; taps into the Achievements page. Self-gating (watches
/// [myParticipationProvider]) and fail-silent — nothing renders while stats
/// are loading, missing or erroring, so a broken stream can never wedge the
/// account panel.
class ParticipationSummary extends ConsumerWidget {
  const ParticipationSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(myParticipationProvider).value;
    if (stats == null) return const SizedBox.shrink();

    final level = levelForPoints(stats.points);
    final next = nextLevelForPoints(stats.points);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/user/achievements'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LevelBadge(level: level),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          level.title,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${formatPoints(stats.points)} pts',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progressToNextLevel(stats.points),
                  minHeight: 4,
                  backgroundColor: AppTheme.border,
                  color: AppTheme.accent,
                ),
              ),
              if (next != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${formatPoints(next.minPoints - stats.points)} pts to '
                  '${next.title}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Link to the moderation area, rendered only when the signed-in user resolves
/// to the admin role. Self-gating (watches [currentUserRoleProvider]) so it can
/// be dropped anywhere and unit-tested in isolation.
class AdminEntryLink extends ConsumerWidget {
  const AdminEntryLink({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref.watch(currentUserRoleProvider).value == AppUserRole.admin;
    if (!isAdmin) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.accent,
            side: const BorderSide(color: AppTheme.border),
          ),
          icon: const Icon(Icons.shield_outlined, size: 18),
          label: const Text('Open moderation'),
          onPressed: () => context.push('/admin'),
        ),
      ),
    );
  }
}

/// [filled] gives the black/white look Apple's guidelines require for its
/// button; on iOS Google gets it too so neither provider reads dimmer than
/// the other. Elsewhere Google keeps the app's outlined style.
class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final spinner = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : null;
    if (filled) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          side: const BorderSide(color: AppTheme.border),
        ),
        icon: spinner ?? Icon(icon, size: 20),
        label: Text(label),
        onPressed: busy ? null : onPressed,
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textPrimary,
        side: const BorderSide(color: AppTheme.border),
      ),
      icon: spinner ?? Icon(icon, size: 18),
      label: Text(label),
      onPressed: busy ? null : onPressed,
    );
  }
}
