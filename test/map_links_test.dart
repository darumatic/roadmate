import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/map_links.dart';

void main() {
  const lat = -34.75;
  const lng = 149.9926;
  const name = 'Marulan Heavy Vehicle Safety Station (Southbound)';
  const address = 'Hume Hwy, Marulan NSW';

  group('mapsUri', () {
    test('web opens Google Maps at the pin, whatever the platform', () {
      for (final platform in TargetPlatform.values) {
        final uri = mapsUri(
          isWeb: true,
          platform: platform,
          lat: lat,
          lng: lng,
          name: name,
          address: address,
        );
        expect(uri.scheme, 'https');
        expect(uri.host, 'www.google.com');
        expect(uri.path, '/maps/search/');
        expect(uri.queryParameters, {'api': '1', 'query': '$lat,$lng'});
      }
    });

    test('web without a pin searches Google Maps for the address', () {
      final uri = mapsUri(
        isWeb: true,
        platform: TargetPlatform.iOS,
        name: name,
        address: address,
      );
      expect(uri.host, 'www.google.com');
      expect(uri.queryParameters['query'], address);
    });

    test('Android opens the native maps app via geo: with a labelled pin', () {
      final uri = mapsUri(
        isWeb: false,
        platform: TargetPlatform.android,
        lat: lat,
        lng: lng,
        name: name,
        address: address,
      );
      expect(
        uri.toString(),
        'geo:$lat,$lng?q=$lat,$lng'
        '(Marulan%20Heavy%20Vehicle%20Safety%20Station%20(Southbound))',
      );
    });

    test('Android without a pin searches the maps app for the address', () {
      final uri = mapsUri(
        isWeb: false,
        platform: TargetPlatform.android,
        name: name,
        address: address,
      );
      expect(uri.toString(), 'geo:0,0?q=Hume%20Hwy%2C%20Marulan%20NSW');
    });

    test('iOS opens Apple Maps at the pin, labelled with the name', () {
      final uri = mapsUri(
        isWeb: false,
        platform: TargetPlatform.iOS,
        lat: lat,
        lng: lng,
        name: name,
        address: address,
      );
      expect(uri.host, 'maps.apple.com');
      expect(uri.queryParameters, {'ll': '$lat,$lng', 'q': name});
    });

    test('iOS without a pin searches Apple Maps for the address', () {
      final uri = mapsUri(
        isWeb: false,
        platform: TargetPlatform.iOS,
        name: name,
        address: address,
      );
      expect(uri.host, 'maps.apple.com');
      expect(uri.queryParameters, {'q': address});
    });

    test('desktop dev runs fall back to Google Maps in the browser', () {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        final uri = mapsUri(
          isWeb: false,
          platform: platform,
          lat: lat,
          lng: lng,
          name: name,
          address: address,
        );
        expect(uri.host, 'www.google.com');
      }
    });

    test('a half-geocoded site is treated as having no pin', () {
      final uri = mapsUri(
        isWeb: false,
        platform: TargetPlatform.android,
        lat: lat,
        name: name,
        address: address,
      );
      expect(uri.toString(), startsWith('geo:0,0?q='));
    });
  });
}
