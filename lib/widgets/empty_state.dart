import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one full-height empty/placeholder state: icon, title, explanation.
///
/// Five screens used to hand-build this same column with four different icon
/// sizes and two title weights for one visual concept; the differences were
/// accidents, not design. (The Trip Logger card's compact inline one-liner is
/// a different concept and deliberately not this widget.)
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.iconColor = AppTheme.textSecondary,
  });

  final IconData icon;
  final String title;
  final String body;

  /// [AppTheme.accent] for attention states (admin queues, load errors);
  /// the default grey for neutral "nothing here yet" screens.
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: iconColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
