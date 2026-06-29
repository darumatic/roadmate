import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/seed_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Device-based identity for votes/reports/saves (no login wall).
  await ensureSignedIn(FirebaseAuth.instance);
  // One-time seed of the authoritative NHVR sites; no-op once populated.
  final seeder = SeedService(FirebaseFirestore.instance);
  await seeder.ensureSeeded();
  // Backfill geocoded coordinates onto sites seeded before they existed.
  await seeder.ensureCoordinates();

  runApp(const ProviderScope(child: RoadMateApp()));
}
