import 'package:flutter/foundation.dart';

// Crashlytics on native, no-op logging on web — resolved at compile time so the
// web bundle never imports firebase_crashlytics (which has no web SDK).
import 'crash_reporter_stub.dart'
    if (dart.library.io) 'crash_reporter_io.dart'
    as crash;

/// Whether a caught framework error is worth forwarding to the crash service.
/// Pure and Firebase-free so it can be unit-tested (see the repo's pure-logic
/// convention). `silent` errors are diagnostics-only and are dropped.
bool shouldReport(FlutterErrorDetails details) => !details.silent;

/// Installs as the app's global error handlers (see `main.dart`) and forwards
/// uncaught errors to the platform crash reporter.
class ErrorReporter {
  const ErrorReporter();

  /// Handler for [FlutterError.onError]. Preserves the default console output,
  /// then reports non-silent errors.
  void recordFlutterError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (!shouldReport(details)) return;
    crash.reportFlutterError(details);
  }

  /// Handler for [PlatformDispatcher.instance.onError]. Returns `true` to mark
  /// the error as handled.
  bool recordError(Object error, StackTrace stack) {
    crash.reportError(error, stack);
    return true;
  }

  /// Enables/disables crash collection (native only). Called once Firebase is
  /// ready; disabled in debug to avoid noisy uploads while developing.
  void setCollectionEnabled(bool enabled) =>
      crash.setCrashReportingEnabled(enabled);
}
