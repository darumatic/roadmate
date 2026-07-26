import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/min_version.dart';

void main() {
  group('storeLinksFor', () {
    test('web offers both stores', () {
      final links = storeLinksFor(isWeb: true, platform: TargetPlatform.linux);
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
      final links = storeLinksFor(isWeb: false, platform: TargetPlatform.iOS);
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

  group('showDonationLink', () {
    test('hidden only in the native iOS app (App Store guideline 3.1.1)', () {
      expect(
        showDonationLink(isWeb: false, platform: TargetPlatform.iOS),
        isFalse,
      );
    });

    test('web keeps donations, even in iOS Safari', () {
      expect(
        showDonationLink(isWeb: true, platform: TargetPlatform.iOS),
        isTrue,
      );
    });

    test('Android and desktop keep donations', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(showDonationLink(isWeb: false, platform: platform), isTrue);
      }
    });
  });

  test('store URLs point at the published listings', () {
    expect(kPlayStoreUrl, contains('id=com.darumatic.roadmate'));
    expect(kAppStoreUrl, contains('id6788635496'));
    expect(kAppStoreUrl, isNot(contains('id0000000000')));
  });
}
