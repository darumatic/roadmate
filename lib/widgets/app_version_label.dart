import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../version.dart';

/// Muted, centered app-version footer shown at the bottom of the Info tab.
///
/// Firebase-free so it can be pumped in isolation in widget tests.
class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'RoadMate v$appVersion',
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
    );
  }
}
