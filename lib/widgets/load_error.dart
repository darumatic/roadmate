import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LoadError extends StatelessWidget {
  const LoadError({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.accent),
            SizedBox(height: 14),
            Text(
              'RoadMate is temporarily unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'This can happen if the service is offline, the network is unavailable, or usage limits have been reached. Please try again later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
