import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/site.dart';
import 'auth_service.dart';
import 'firestore_site_repository.dart';
import 'site_repository.dart';
import 'status_logic.dart';

/// The active site backend. Firestore-backed; the single place that names a
/// concrete implementation. (The bundled-seed `LocalSeedSiteRepository` remains
/// available for offline/dev use and tests.)
final siteRepositoryProvider = Provider<SiteRepository>((ref) {
  return FirestoreSiteRepository(
    firestore: FirebaseFirestore.instance,
    auth: ref.watch(firebaseAuthProvider),
  );
});

final statusLogicProvider = Provider<StatusLogic>((ref) => const StatusLogic());

final sitesProvider = StreamProvider<List<Site>>((ref) {
  return ref.watch(siteRepositoryProvider).watchSites();
});

final savedSiteIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(siteRepositoryProvider).watchSaved();
});
