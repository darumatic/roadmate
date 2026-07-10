import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

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

  test('Analytics advertising-ID collection is disabled', () {
    expect(
      manifest,
      contains('android:name="google_analytics_adid_collection_enabled"'),
    );
  });
}
