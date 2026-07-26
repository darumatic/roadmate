import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:roadmate/services/location_source.dart';

void main() {
  group('tripLocationSettings', () {
    test('native: navigation accuracy, every fix, no web tuning', () {
      final s = tripLocationSettings(
        isWeb: false,
        platform: TargetPlatform.linux,
      );
      expect(s, isNot(isA<WebSettings>()));
      expect(s.accuracy, LocationAccuracy.bestForNavigation);
      expect(s.distanceFilter, 0);
    });

    test(
      'android: a foreground service keeps site alerts alive off screen',
      () {
        final s = tripLocationSettings(
          isWeb: false,
          platform: TargetPlatform.android,
        );
        expect(s, isA<AndroidSettings>());
        final config = (s as AndroidSettings).foregroundNotificationConfig;
        expect(config, isNotNull);
        // Without the wake lock Android batches fixes until the device wakes,
        // which would deliver an approach alert well past the site.
        expect(config!.enableWakeLock, isTrue);
        expect(config.notificationTitle, isNotEmpty);
        expect(config.notificationText, isNotEmpty);
      },
    );

    test('ios: background updates on, auto-pause off', () {
      final s = tripLocationSettings(
        isWeb: false,
        platform: TargetPlatform.iOS,
      );
      expect(s, isA<AppleSettings>());
      final apple = s as AppleSettings;
      expect(apple.allowBackgroundLocationUpdates, isTrue);
      expect(apple.showBackgroundLocationIndicator, isTrue);
      // iOS otherwise pauses updates when it decides you've stopped — at a
      // red light 2 km short of a weighbridge, that's the wrong call.
      expect(apple.pauseLocationUpdatesAutomatically, isFalse);
      expect(apple.activityType, ActivityType.automotiveNavigation);
    });

    test('web: allows a <=10s cached fix so the stream starts fast', () {
      final s = tripLocationSettings(isWeb: true);
      expect(s, isA<WebSettings>());
      expect(s.accuracy, LocationAccuracy.bestForNavigation);
      expect(s.distanceFilter, 0);
      expect((s as WebSettings).maximumAge, const Duration(seconds: 10));
    });
  });

  group('quickFixLocationSettings', () {
    test('native: plain high-accuracy one-shot', () {
      final s = quickFixLocationSettings(isWeb: false);
      expect(s, isNot(isA<WebSettings>()));
      expect(s.accuracy, LocationAccuracy.high);
    });

    test('web: accepts a cached fix up to 2 minutes old', () {
      final s = quickFixLocationSettings(isWeb: true);
      expect(s, isA<WebSettings>());
      expect((s as WebSettings).maximumAge, const Duration(minutes: 2));
    });
  });
}
