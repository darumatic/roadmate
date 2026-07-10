// Web (and any platform without dart:io) fallback: web usage is measured by
// the gtag snippet in web/index.html, not the firebase_analytics plugin, so
// this is a safe no-op. Selected via the conditional import in
// analytics_reporter.dart so the web bundle never touches firebase_analytics.

void setAnalyticsCollectionEnabled(bool enabled) {}
