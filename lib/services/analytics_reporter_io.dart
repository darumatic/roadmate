import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

// Native (iOS/Android) usage analytics via Firebase Analytics. Chosen by the
// conditional import in analytics_reporter.dart when dart:io is available.
// No-ops safely until Firebase has been initialized (startup init is async and
// may time out — see startup_service.dart).

void setAnalyticsCollectionEnabled(bool enabled) {
  if (Firebase.apps.isEmpty) return;
  FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
}
