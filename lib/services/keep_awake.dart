import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Whether the screen wakelock should be held for [state]. Only a visible,
/// foreground app holds it — the OS/browser releases the lock when the app
/// hides anyway, so it must be re-requested on resume.
bool shouldHoldWakelock(AppLifecycleState state) =>
    state == AppLifecycleState.resumed;

typedef WakelockToggle = Future<void> Function();

/// Keeps the screen awake while the app is in the foreground, on web and
/// native (issue #14 — drivers glance at the app with dirty hands; it must
/// not lock mid-run). Best-effort: a missing or failing wakelock plugin must
/// never break the app.
class KeepAwake {
  KeepAwake({WakelockToggle? enable, WakelockToggle? disable})
    : _enable = enable ?? WakelockPlus.enable,
      _disable = disable ?? WakelockPlus.disable;

  final WakelockToggle _enable;
  final WakelockToggle _disable;
  bool _held = false;

  /// Acquires or releases the wakelock; repeat calls with the same target
  /// are no-ops.
  Future<void> apply(bool hold) async {
    if (hold == _held) return;
    _held = hold;
    try {
      await (hold ? _enable() : _disable());
    } catch (e) {
      // Keeping the screen awake is a nicety, not a requirement.
      debugPrint('RoadMate: wakelock toggle failed: $e');
    }
  }

  Future<void> onLifecycle(AppLifecycleState state) =>
      apply(shouldHoldWakelock(state));
}

final keepAwakeProvider = Provider<KeepAwake>((ref) => KeepAwake());

/// Hooks [KeepAwake] into the tree: acquires the wakelock when mounted,
/// re-acquires on resume (browsers drop the Screen Wake Lock when the tab
/// hides), and releases on dispose.
class KeepAwakeScope extends ConsumerStatefulWidget {
  const KeepAwakeScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<KeepAwakeScope> createState() => _KeepAwakeScopeState();
}

class _KeepAwakeScopeState extends ConsumerState<KeepAwakeScope>
    with WidgetsBindingObserver {
  late final KeepAwake _keepAwake;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keepAwake = ref.read(keepAwakeProvider);
    _keepAwake.apply(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _keepAwake.onLifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keepAwake.apply(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
