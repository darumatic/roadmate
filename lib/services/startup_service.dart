import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';
import 'analytics_reporter.dart';
import 'auth_service.dart';
import 'error_reporter.dart';
import 'seed_service.dart';

/// Initializes Firebase before the routed app reads Firestore-backed providers.
/// If Firebase is slow or unavailable, startup continues with the bundled seed
/// repository so the app does not remain on the loading screen indefinitely.
final appStartupProvider = FutureProvider<void>((ref) async {
  var firebaseReady = Firebase.apps.isNotEmpty;
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 8));
      firebaseReady = true;
    } catch (_) {
      firebaseReady = false;
    }
  }

  if (!firebaseReady) return;

  // Native provider sign-in must round-trip through roadmate.club like web
  // does, not the default firebaseapp.com auth handler.
  final authDomain = nativeCustomAuthDomain(isWeb: kIsWeb);
  if (authDomain != null) {
    FirebaseAuth.instance.customAuthDomain = authDomain;
  }

  // Enable crash reporting now that Firebase is up (native only; no-op on web).
  // Off in debug builds to avoid noisy uploads while developing.
  const ErrorReporter().setCollectionEnabled(!kDebugMode);

  // Usage analytics (native only; web is measured by the gtag snippet in
  // web/index.html — see analytics_reporter.dart).
  const AnalyticsReporter().setCollectionEnabled(
    shouldCollectAnalytics(isDebug: kDebugMode),
  );

  // Finish a pending redirect sign-in (web: popup was blocked and we came
  // back from the provider) before the anonymous fallback kicks in.
  unawaited(ref.read(authControllerProvider).completeRedirectSignIn());

  unawaited(ensureSignedIn(FirebaseAuth.instance).catchError((_) => ''));

  unawaited(_runSeedMaintenance());
});

Future<void> _runSeedMaintenance() async {
  try {
    final seeder = SeedService(FirebaseFirestore.instance);
    await seeder.ensureSeeded();
    await seeder.ensureCoordinates();
  } catch (_) {
    // Production startup should not fail because bootstrap maintenance is blocked.
  }
}
