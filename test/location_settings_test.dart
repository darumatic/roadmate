import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:roadmate/services/location_source.dart';

void main() {
  group('tripLocationSettings', () {
    test('native: navigation accuracy, every fix, no web tuning', () {
      final s = tripLocationSettings(isWeb: false);
      expect(s, isNot(isA<WebSettings>()));
      expect(s.accuracy, LocationAccuracy.bestForNavigation);
      expect(s.distanceFilter, 0);
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
