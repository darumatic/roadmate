import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AccountPanel extends ConsumerStatefulWidget {
  const AccountPanel({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends ConsumerState<AccountPanel> {
  String? _busyProvider;

  @override
  Widget build(BuildContext context) {
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
            const AdminEntryLink(),
            const SizedBox(height: 12),
            if (user == null || user.isAnonymous)
              _ProviderButton(
                icon: Icons.g_mobiledata_rounded,
                label: 'Sign in with Google',
                busy: _busyProvider == 'google',
                onPressed: () => _signIn(
                  'google',
                  () => ref.read(authControllerProvider).signInWithGoogle(),
                ),
              )
            else
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.border),
                ),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Sign out'),
                onPressed: _busyProvider == null ? _signOut : null,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _signIn(
    String provider,
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
            credential == null ? 'Taking you to Google sign-in…' : 'Signed in',
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

class _ProviderButton extends StatelessWidget {
  const _ProviderButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textPrimary,
        side: const BorderSide(color: AppTheme.border),
      ),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(label),
      onPressed: busy ? null : onPressed,
    );
  }
}
