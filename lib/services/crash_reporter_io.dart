import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

// Native (iOS/Android) crash reporting via Firebase Crashlytics. Chosen by the
// conditional import in error_reporter.dart when dart:io is available. All calls
// no-op safely until Firebase has been initialized (startup init is async and
// may time out — see startup_service.dart), so early errors never crash on the
// reporter itself.

void reportFlutterError(FlutterErrorDetails details) {
  if (Firebase.apps.isEmpty) {
    debugPrint(
      'Flutter error before Firebase init: ${details.exceptionAsString()}',
    );
    return;
  }
  FirebaseCrashlytics.instance.recordFlutterFatalError(details);
}

void reportError(Object error, StackTrace stack) {
  if (Firebase.apps.isEmpty) {
    debugPrint('Error before Firebase init: $error');
    return;
  }
  FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
}

void setCrashReportingEnabled(bool enabled) {
  if (Firebase.apps.isEmpty) return;
  FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
}
