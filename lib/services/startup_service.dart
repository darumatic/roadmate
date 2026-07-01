import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';
import 'auth_service.dart';
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
