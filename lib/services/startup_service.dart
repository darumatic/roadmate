import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase_options.dart';
import 'auth_service.dart';
import 'seed_service.dart';

/// Initializes Firebase and the anonymous user identity before the routed app
/// reads Firestore-backed providers.
final appStartupProvider = FutureProvider<void>((ref) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  await ensureSignedIn(FirebaseAuth.instance);

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
