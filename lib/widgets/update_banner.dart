import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/update_checker.dart';
import '../theme/app_theme.dart';

/// Wraps the whole app (via MaterialApp.router's builder) and slides a slim
/// banner in above the content when a newer build has been deployed
/// (web only — the checker never fires on native). Refresh clears the service
/// worker + caches and reloads onto the new build in one step.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Web maps tab visibility to the lifecycle: re-check on refocus, which is
    // exactly when a driver comes back to a long-open tab.
    if (state == AppLifecycleState.resumed) {
      ref.read(updateCheckerProvider.notifier).checkNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final updateAvailable = ref.watch(updateCheckerProvider);
    if (!updateAvailable) return widget.child;
    return Column(
      children: [
        const _UpdateBanner(),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _UpdateBanner extends ConsumerWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppTheme.accent,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              const Icon(
                Icons.system_update_alt,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'A new version of RoadMate is available.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => ref.read(updateProbeProvider).reloadApp(),
                child: const Text(
                  'Refresh',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
