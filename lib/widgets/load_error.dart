import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'empty_state.dart';

/// What every screen shows when its data stream errors (see `asyncBody`).
class LoadError extends StatelessWidget {
  const LoadError({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.cloud_off_outlined,
      iconColor: AppTheme.accent,
      title: 'RoadMate is temporarily unavailable',
      body:
          'This can happen if the service is offline, the network is '
          'unavailable, or usage limits have been reached. Please try '
          'again later.',
    );
  }
}
