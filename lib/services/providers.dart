import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/site.dart';
import '../models/site_report.dart';
import '../models/admin_report.dart';
import 'admin_repository.dart';
import 'alert_player.dart';
import 'auth_service.dart';
import 'firestore_site_repository.dart';
import 'local_seed_repository.dart';
import 'location_source.dart';
import 'site_repository.dart';
import 'status_logic.dart';
import 'trip_history_store.dart';

/// The active site backend. Firestore-backed; the single place that names a
/// concrete implementation. (The bundled-seed `LocalSeedSiteRepository` remains
/// available for offline/dev use and tests.)
final siteRepositoryProvider = Provider<SiteRepository>((ref) {
  if (Firebase.apps.isEmpty) {
    final repo = LocalSeedSiteRepository();
    ref.onDispose(repo.dispose);
    return repo;
  }

  return FirestoreSiteRepository(
    firestore: FirebaseFirestore.instance,
    auth: ref.watch(firebaseAuthProvider),
  );
});

final statusLogicProvider = Provider<StatusLogic>((ref) => const StatusLogic());

/// Device-location source for the trip speedometer. The single swap point;
/// tests override this with a fake that emits a controlled position stream.
final locationSourceProvider = Provider<LocationSource>(
  (ref) => const GeolocatorLocationSource(),
);

/// Plays the over-limit warning (beep + haptic). Overridden with a fake in tests.
final alertPlayerProvider = Provider<AlertPlayer>((ref) => BeepAlertPlayer());

/// On-device store for saved trips and the manual speed limit.
final tripHistoryStoreProvider = Provider<TripHistoryStore>(
  (ref) => const PrefsTripHistoryStore(),
);

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(
    firestore: FirebaseFirestore.instance,
    auth: ref.watch(firebaseAuthProvider),
  );
});

final sitesProvider = StreamProvider<List<Site>>((ref) {
  return ref.watch(siteRepositoryProvider).watchSites();
});

final favouriteSiteIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(siteRepositoryProvider).watchFavourites();
});

final siteReportsProvider = StreamProvider.family<List<SiteReport>, String>((
  ref,
  siteId,
) {
  return ref.watch(siteRepositoryProvider).watchReports(siteId);
});

final pendingSitesProvider = StreamProvider<List<Site>>((ref) {
  return ref.watch(adminRepositoryProvider).watchPendingSites();
});

final recentAdminReportsProvider = StreamProvider<List<AdminReport>>((ref) {
  return ref.watch(adminRepositoryProvider).watchRecentReports();
});
