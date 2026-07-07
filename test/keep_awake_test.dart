import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/keep_awake.dart';

void main() {
  group('shouldHoldWakelock', () {
    test('holds only while resumed (visible foreground)', () {
      expect(shouldHoldWakelock(AppLifecycleState.resumed), isTrue);
      expect(shouldHoldWakelock(AppLifecycleState.inactive), isFalse);
      expect(shouldHoldWakelock(AppLifecycleState.hidden), isFalse);
      expect(shouldHoldWakelock(AppLifecycleState.paused), isFalse);
      expect(shouldHoldWakelock(AppLifecycleState.detached), isFalse);
    });
  });

  group('KeepAwake', () {
    test('apply acquires and releases, deduping repeat calls', () async {
      final calls = <String>[];
      final keepAwake = KeepAwake(
        enable: () async => calls.add('on'),
        disable: () async => calls.add('off'),
      );

      await keepAwake.apply(true);
      await keepAwake.apply(true); // no-op — already held
      await keepAwake.apply(false);
      await keepAwake.apply(false); // no-op — already released

      expect(calls, ['on', 'off']);
    });

    test('lifecycle pause releases and resume re-acquires', () async {
      final calls = <String>[];
      final keepAwake = KeepAwake(
        enable: () async => calls.add('on'),
        disable: () async => calls.add('off'),
      );

      await keepAwake.onLifecycle(AppLifecycleState.resumed);
      await keepAwake.onLifecycle(AppLifecycleState.inactive);
      await keepAwake.onLifecycle(AppLifecycleState.paused); // dedup
      await keepAwake.onLifecycle(AppLifecycleState.resumed);

      expect(calls, ['on', 'off', 'on']);
    });

    test('a failing wakelock plugin never throws', () async {
      final keepAwake = KeepAwake(
        enable: () async => throw Exception('no plugin'),
        disable: () async => throw Exception('no plugin'),
      );

      await keepAwake.apply(true);
      await keepAwake.apply(false);
    });
  });

  testWidgets(
    'KeepAwakeScope acquires on mount, follows lifecycle, releases on dispose',
    (tester) async {
      final calls = <String>[];
      final keepAwake = KeepAwake(
        enable: () async => calls.add('on'),
        disable: () async => calls.add('off'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [keepAwakeProvider.overrideWithValue(keepAwake)],
          child: const KeepAwakeScope(child: SizedBox()),
        ),
      );
      expect(calls, ['on']);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(calls, ['on', 'off']);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, ['on', 'off', 'on']);

      await tester.pumpWidget(const SizedBox());
      expect(calls, ['on', 'off', 'on', 'off']);
    },
  );
}
