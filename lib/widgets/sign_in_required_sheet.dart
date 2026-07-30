import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../services/report_eligibility.dart';
import '../theme/app_theme.dart';
import 'account_panel.dart';

/// Asks for a real account at the moment someone tries to post — a vote or an
/// activity report — instead of letting the write fail with a shrug.
///
/// Raised from the `on SignInRequiredException` arm of the existing catch
/// chains, so one path covers both the client's own pre-check and a rules
/// denial. Reuses [AccountActions] for the provider buttons, which keeps the
/// Google/Apple/PWA-redirect handling in exactly one place.
///
/// Returns true when the user became eligible to post before the sheet closed,
/// so the caller can retry what they were doing. On the **web redirect** flow
/// the page navigates away to the provider and this sheet dies with it — the
/// user lands back on the app signed in and taps again, which is why nothing
/// tries to persist the pending action across the round trip.
Future<bool> showSignInRequiredSheet(BuildContext context) async {
  final signedIn = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _SignInRequiredSheet(),
  );
  return signedIn ?? false;
}

class _SignInRequiredSheet extends ConsumerWidget {
  const _SignInRequiredSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Close as soon as a real account lands. authStateProvider is built on
    // userChanges(), so it fires when an anonymous account is *linked* to a
    // provider — the usual path here, and one authStateChanges() would miss.
    ref.listen(authStateProvider, (_, next) {
      final user = next.value;
      final eligible = canPostReports(
        signedIn: user != null,
        isAnonymous: user?.isAnonymous ?? true,
      );
      if (eligible && Navigator.canPop(context)) Navigator.pop(context, true);
    });

    final user = ref.watch(authStateProvider).value;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  color: AppTheme.accent,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  kSignInSheetTitle,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              kSignInSheetBody,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 18),
            AccountActions(user: user),
          ],
        ),
      ),
    );
  }
}
