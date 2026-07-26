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
}
