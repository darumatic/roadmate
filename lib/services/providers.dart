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
import 'proximity_notifier.dart';
import 'refresh_logic.dart';
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

/// Raises the system notification for a site approach while the app is in the
/// background. Overridden with a recorder in tests.
final proximityNotifierProvider = Provider<ProximityNotifier>(
  (ref) => LocalProximityNotifier(),
);

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
  // Statuses go grey/Unknown once the last report is >10h old (issue #21);
  // applied here so every consumer of the site list gets the same rule.
  return ref
      .watch(siteRepositoryProvider)
      .watchSites()
      .map(withEffectiveStatus);
});

final favouriteSiteIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(siteRepositoryProvider).watchFavourites();
});

/// One shared Firestore listener for every report inside the 10h freshness
/// window, across all sites. Replaces the old per-visible-card query, which
/// billed up to 20 reads per site per session; the window is time-bounded
/// (not count-bounded), so a busy day can never push a site's reports out.
final recentReportsProvider = StreamProvider<List<SiteReport>>((ref) {
  return ref.watch(siteRepositoryProvider).watchAllRecentReports();
});

/// A single site's slice of [recentReportsProvider] — the same AsyncValue
/// shape SiteCard has always consumed, now derived client-side instead of
/// opening one Firestore query per site.
final siteReportsProvider =
    Provider.family<AsyncValue<List<SiteReport>>, String>((ref, siteId) {
      return ref
          .watch(recentReportsProvider)
          .whenData((reports) => reportsForSite(reports, siteId));
    });

/// Shared pull-to-refresh for the Firestore-backed streams: a healthy
/// snapshot listener is already live, so it is only restarted after an error
/// (retry); restarting a working one would re-bill its whole result set.
Future<void> refreshSiteData(WidgetRef ref) async {
  for (final provider in [
    sitesProvider,
    recentReportsProvider,
    favouriteSiteIdsProvider,
  ]) {
    if (shouldRestartOnRefresh(ref.read(provider))) {
      ref.invalidate(provider);
    }
  }
  await ref.read(sitesProvider.future);
}

final pendingSitesProvider = StreamProvider<List<Site>>((ref) {
  return ref.watch(adminRepositoryProvider).watchPendingSites();
});

final recentAdminReportsProvider = StreamProvider<List<AdminReport>>((ref) {
  return ref.watch(adminRepositoryProvider).watchRecentReports();
});
