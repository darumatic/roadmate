import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/site.dart';
import '../models/site_report.dart';
import '../models/admin_report.dart';
import '../models/user_ban.dart';
import 'admin_repository.dart';
import 'alert_player.dart';
import 'announcement.dart';
import 'announcement_dismiss_store.dart';
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

  final location = ref.watch(locationSourceProvider);
  return FirestoreSiteRepository(
    firestore: FirebaseFirestore.instance,
    auth: ref.watch(firebaseAuthProvider),
    // The proximity gate's position source — adapted here so the repository
    // stays geolocator-free (see `report_proximity.dart`).
    locate: () async {
      final position = await location.currentPosition();
      if (position == null) return null;
      return (lat: position.latitude, lng: position.longitude);
    },
  );
});

final statusLogicProvider = Provider<StatusLogic>((ref) => const StatusLogic());

/// Whether this build is the web app. A provider rather than a bare [kIsWeb]
/// read so widget tests can pump the web-only admin surface (and assert it
/// stays hidden in the native builds) without a real browser.
final isWebProvider = Provider<bool>((ref) => kIsWeb);

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

/// Remembers the last admin notice this device dismissed.
final announcementDismissStoreProvider = Provider<AnnouncementDismissStore>(
  (ref) => const PrefsAnnouncementDismissStore(),
);

/// The live admin broadcast, or null when there is nothing to say.
///
/// One document listener (`announcements/current`) — the cheapest read shape
/// there is, and the reason this isn't a query. Reads are public in the rules so
/// it works for anonymous users. Like the forced-update gate it **fails
/// silently**: a stream error yields no value and the banner consumer treats
/// that as "no notice", so a broken listener can never wedge a banner on screen.
final announcementProvider = StreamProvider<Announcement?>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value(null);
  return FirebaseFirestore.instance
      .doc('announcements/current')
      .snapshots()
      .map((snap) {
        final data = snap.data();
        if (data == null) return null;
        return Announcement.fromMap(
          data.map((key, value) {
            if (value is Timestamp) {
              return MapEntry(key, value.toDate().toIso8601String());
            }
            return MapEntry(key, value);
          }),
        );
      })
      .handleError((Object _) {});
});

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

/// Every ban, for the admin Bans tab. Admin-only by the rules, so this is
/// only ever subscribed from that screen — never at app start.
final bansProvider = StreamProvider<List<UserBan>>((ref) {
  return ref.watch(adminRepositoryProvider).watchBans();
});
