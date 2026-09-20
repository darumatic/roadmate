import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/fresh_window_stream.dart';
import 'package:roadmate/services/providers.dart';

/// `listenerChecksProvider` is what asks the recent-reports listener "have you
/// gone stale?" (issue #51). A freeze is only noticed by the tick that follows
/// it, and only beaten to the SDK's reconnect by the resume event — so both
/// must come through, and the timer must die with the provider.
void main() {
  testWidgets('ticks once a minute and the moment the app comes back', (
    tester,
  ) async {
    final container = ProviderContainer();
    var checks = 0;
    final sub = container.read(listenerChecksProvider).listen((_) => checks++);

    await tester.pump(listenerCheckInterval);
    expect(checks, 1);
    await tester.pump(listenerCheckInterval * 3);
    expect(checks, 4);

    // Backgrounded and brought back (on the web: the tab hidden, then shown).
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(checks, 5);

    // It is a broadcast stream: every watchAllRecentReports() call subscribes.
    expect(container.read(listenerChecksProvider).isBroadcast, isTrue);

    // (Not awaited: a cancel future never completes under the fake clock.)
    unawaited(sub.cancel());
    container.dispose();
    // No timer left behind — the test binding fails the test if one is.
    await tester.pump(listenerCheckInterval * 2);
    expect(checks, 5);
  });
}
