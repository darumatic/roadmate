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

  group('rateUrlFor', () {
    test('Android rates on Google Play', () {
      expect(
        rateUrlFor(isWeb: false, platform: TargetPlatform.android),
        kPlayStoreUrl,
      );
    });

    test('iOS lands straight on the App Store rating sheet', () {
      expect(
        rateUrlFor(isWeb: false, platform: TargetPlatform.iOS),
        kAppStoreReviewUrl,
      );
      expect(kAppStoreReviewUrl, contains('id6788635496'));
      expect(kAppStoreReviewUrl, contains('action=write-review'));
    });

    test('web has nothing to rate, even in mobile browsers', () {
      // Rate notices are hidden entirely wherever this is null.
      expect(rateUrlFor(isWeb: true, platform: TargetPlatform.iOS), isNull);
      expect(rateUrlFor(isWeb: true, platform: TargetPlatform.android), isNull);
    });

    test('desktop dev runs have nothing to rate', () {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(rateUrlFor(isWeb: false, platform: platform), isNull);
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
