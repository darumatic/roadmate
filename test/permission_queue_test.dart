import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/permission_queue.dart';

void main() {
  group('PermissionQueue', () {
    test(
      'a queued request does not start until the one before it finishes',
      () async {
        final queue = PermissionQueue();
        final first = Completer<String>();
        var secondStarted = false;

        final firstResult = queue.run(() => first.future);
        final secondResult = queue.run(() async {
          secondStarted = true;
          return 'location';
        });

        // The notification dialog is still on screen: the location request must
        // not have been raised yet, or Android cancels it unseen.
        await Future<void>.delayed(Duration.zero);
        expect(secondStarted, isFalse);

        first.complete('notifications');
        expect(await firstResult, 'notifications');
        expect(await secondResult, 'location');
        expect(secondStarted, isTrue);
      },
    );

    test('requests run in the order they were queued', () async {
      final queue = PermissionQueue();
      final order = <int>[];

      final futures = [
        for (var i = 0; i < 4; i++)
          queue.run(() async {
            await Future<void>.delayed(Duration(milliseconds: (4 - i) * 5));
            order.add(i);
            return i;
          }),
      ];

      expect(await Future.wait(futures), [0, 1, 2, 3]);
      expect(order, [0, 1, 2, 3]);
    });

    test(
      'a failing request surfaces to its caller and does not wedge the queue',
      () async {
        final queue = PermissionQueue();

        final failed = queue.run<void>(
          () async => throw StateError('plugin gone'),
        );
        final after = queue.run(() async => 'still runs');

        await expectLater(failed, throwsStateError);
        expect(await after, 'still runs');
      },
    );

    test('an idle queue runs the next request immediately', () async {
      final queue = PermissionQueue();
      expect(await queue.run(() async => 'granted'), 'granted');
      expect(await queue.run(() async => 'granted again'), 'granted again');
    });
  });
}
