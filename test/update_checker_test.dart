import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/update_checker.dart';
import 'package:roadmate/version.dart';
import 'package:roadmate/widgets/update_banner.dart';

/// A checker whose first check reports an update — for widget tests.
class ForcedUpdateChecker extends UpdateChecker {
  @override
  bool build() {
    super.build();
    return true;
  }
}

ProviderContainer _container({
  required Future<String?> Function() fetcher,
  Future<void> Function()? reloader,
}) {
  final container = ProviderContainer(
    overrides: [
      updateProbeProvider.overrideWithValue((
        fetchRemoteVersion: fetcher,
        reloadApp: reloader ?? () async {},
      )),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('isUpdateAvailable', () {
    test('false when the remote version is unknown', () {
      expect(isUpdateAvailable(current: '1.0.0', remote: null), isFalse);
      expect(isUpdateAvailable(current: '1.0.0', remote: ''), isFalse);
    });

    test('false when the deployed version matches this build', () {
      expect(isUpdateAvailable(current: '1.0.0', remote: '1.0.0'), isFalse);
    });

    test('true on any difference — upgrade or rollback', () {
      expect(isUpdateAvailable(current: '1.0.0', remote: '1.0.1'), isTrue);
      expect(isUpdateAvailable(current: '1.0.1', remote: '1.0.0'), isTrue);
    });
  });

  group('UpdateChecker', () {
    test('flips to true when the deployed version differs, and stays true', () async {
      var calls = 0;
      final container = _container(
        fetcher: () async {
          calls++;
          return '$appVersion-new';
        },
      );
      final checker = container.read(updateCheckerProvider.notifier);

      expect(container.read(updateCheckerProvider), isFalse);
      await checker.checkNow();
      expect(container.read(updateCheckerProvider), isTrue);

      // Once known, further checks are skipped.
      await checker.checkNow();
      expect(calls, 1);
      expect(container.read(updateCheckerProvider), isTrue);
    });

    test('stays false while the deployed version matches', () async {
      final container = _container(fetcher: () async => appVersion);
      final checker = container.read(updateCheckerProvider.notifier);

      await checker.checkNow();
      expect(container.read(updateCheckerProvider), isFalse);
    });

    test('a failing probe never throws or flips the state', () async {
      final container = _container(fetcher: () async => null);
      final checker = container.read(updateCheckerProvider.notifier);

      await checker.checkNow();
      expect(container.read(updateCheckerProvider), isFalse);
    });
  });

  group('UpdateGate', () {
    testWidgets('renders only the child while no update is known', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            updateProbeProvider.overrideWithValue((
              fetchRemoteVersion: () async => null,
              reloadApp: () async {},
            )),
          ],
          child: const MaterialApp(
            home: UpdateGate(child: Scaffold(body: Text('content'))),
          ),
        ),
      );

      expect(find.text('content'), findsOneWidget);
      expect(find.textContaining('new version'), findsNothing);
    });

    testWidgets('shows the banner and Refresh triggers the reloader', (
      tester,
    ) async {
      var reloads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            updateCheckerProvider.overrideWith(ForcedUpdateChecker.new),
            updateProbeProvider.overrideWithValue((
              fetchRemoteVersion: () async => null,
              reloadApp: () async => reloads++,
            )),
          ],
          child: const MaterialApp(
            home: UpdateGate(child: Scaffold(body: Text('content'))),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('content'), findsOneWidget);
      expect(
        find.text('A new version of RoadMate is available.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Refresh'));
      await tester.pump();
      expect(reloads, 1);
    });
  });
}
