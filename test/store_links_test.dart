import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/min_version.dart';

void main() {
  group('storeLinksFor', () {
    test('web offers both stores', () {
      final links = storeLinksFor(
        isWeb: true,
        platform: TargetPlatform.linux,
      );
      expect(links, const [kPlayStoreLink, kAppStoreLink]);
    });

    test('Android offers only Google Play', () {
      final links = storeLinksFor(
        isWeb: false,
        platform: TargetPlatform.android,
      );
      expect(links, const [kPlayStoreLink]);
    });

    test('iOS offers only the App Store', () {
      final links = storeLinksFor(
        isWeb: false,
        platform: TargetPlatform.iOS,
      );
      expect(links, const [kAppStoreLink]);
    });

    test('desktop dev runs offer nothing', () {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(storeLinksFor(isWeb: false, platform: platform), isEmpty);
      }
    });
  });

  test('store URLs point at the published listings', () {
    expect(kPlayStoreUrl, contains('id=com.darumatic.roadmate'));
    expect(kAppStoreUrl, contains('id6788635496'));
    expect(kAppStoreUrl, isNot(contains('id0000000000')));
  });
}
