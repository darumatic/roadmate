import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/min_version.dart';
import '../theme/app_theme.dart';

/// Blocking screen shown when this build is older than the remotely
/// configured minimum (config/app.minVersion). Deliberately has no dismiss:
/// the only way forward is updating (or the owner lowering the minimum,
/// which un-gates running apps live).
class ForceUpdateScreen extends ConsumerWidget {
  const ForceUpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openStore = ref.watch(storeOpenerProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update_alt,
                  color: AppTheme.accent,
                  size: 40,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Update required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This version of RoadMate is no longer supported. '
                  'Update to keep reporting and seeing live site status.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => openStore(),
                  icon: const Icon(Icons.download),
                  label: Text(kIsWeb ? 'Refresh' : 'Update'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
