import 'package:flutter/foundation.dart';

// Web (and any platform without dart:io) fallback: Crashlytics has no web SDK,
// so these are safe no-ops that just log. Selected via the conditional import in
// error_reporter.dart so the web bundle never imports firebase_crashlytics.

void reportFlutterError(FlutterErrorDetails details) {
  debugPrint(
    'Flutter error (no crash service here): ${details.exceptionAsString()}',
  );
}

void reportError(Object error, StackTrace stack) {
  debugPrint('Error (no crash service here): $error');
}

void setCrashReportingEnabled(bool enabled) {}
