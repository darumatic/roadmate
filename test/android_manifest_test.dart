import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('AD_ID permission is stripped from the merged manifest', () {
    // firebase_analytics pulls in com.google.android.gms.permission.AD_ID by
    // default, but the Play Console declaration says the app doesn't use the
    // advertising ID — Play rejects the release if the permission sneaks back
    // in. The tools:node="remove" rule keeps it out of the merged manifest.
    expect(
      manifest,
      contains(
        '<uses-permission android:name="com.google.android.gms.permission.AD_ID" '
        'tools:node="remove"/>',
      ),
    );
    expect(
      manifest,
      contains('xmlns:tools="http://schemas.android.com/tools"'),
    );
  });

  test('background site alerts declare the foreground-service permissions', () {
    // Without these the location foreground service fails to start on Android
    // 14+, and background approach alerts silently stop working — the app
    // would keep running with no error the user could see.
    expect(
      manifest,
      contains('android:name="android.permission.FOREGROUND_SERVICE"'),
    );
    expect(
      manifest,
      contains('android:name="android.permission.FOREGROUND_SERVICE_LOCATION"'),
    );
    expect(manifest, contains('android:name="android.permission.WAKE_LOCK"'));
    expect(
      manifest,
      contains('android:name="android.permission.POST_NOTIFICATIONS"'),
    );
  });

  test('background location is granted by the service, not by permission', () {
    // ACCESS_BACKGROUND_LOCATION triggers a Play Console review and a much
    // scarier permission prompt; the location-typed foreground service covers
    // this app's need. Keep it out.
    expect(
      manifest,
      isNot(contains('android.permission.ACCESS_BACKGROUND_LOCATION')),
    );
  });

  test('Analytics advertising-ID collection is disabled', () {
    expect(
      manifest,
      contains('android:name="google_analytics_adid_collection_enabled"'),
    );
  });

  group('release build config', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    test(
      'core library desugaring is enabled for flutter_local_notifications',
      () {
        // flutter_local_notifications (the off-screen site-approach alert) needs
        // java.time desugared. Without these two lines *every* Android release
        // build fails with "requires core library desugaring to be enabled" —
        // and nothing else in the suite catches it, because the failure only
        // surfaces at `flutter build appbundle`, never at `flutter test`.
        expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
        expect(
          gradle,
          contains(
            'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:',
          ),
        );
      },
    );
  });
}
