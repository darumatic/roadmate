// Firebase Analytics on native (iOS/Android), no-op on web — resolved at
// compile time. Web usage is already measured by the gtag snippet in
// web/index.html (same GA property), so enabling the plugin there too would
// double-count sessions against the same measurement ID.
import 'analytics_reporter_stub.dart'
    if (dart.library.io) 'analytics_reporter_io.dart'
    as analytics;

/// Whether usage analytics should collect for this build. Pure and
/// Firebase-free so it can be unit-tested (see the repo's pure-logic
/// convention). Off in debug builds to keep developer sessions out of the
/// production property.
bool shouldCollectAnalytics({required bool isDebug}) => !isDebug;

/// Toggles Firebase Analytics collection on the platforms that have it.
/// Called once Firebase is ready (see `startup_service.dart`).
class AnalyticsReporter {
  const AnalyticsReporter();

  /// Enables/disables analytics collection (native only; no-op on web).
  void setCollectionEnabled(bool enabled) =>
      analytics.setAnalyticsCollectionEnabled(enabled);
}
