import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's one destructive-confirmation dialog: Cancel, plus a
/// [confirmLabel] action in [AppTheme.danger]. Resolves true only on explicit
/// confirmation — dismissing the dialog is a "no".
///
/// Every delete/remove/clear confirmation goes through here; there used to
/// be five hand-built copies with three different destructive-button
/// treatments (one of which forgot the destructive colour altogether).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(title),
      content: Text(
        message,
        style: const TextStyle(color: AppTheme.textSecondary, height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
