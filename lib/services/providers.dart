import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
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
import 'fresh_window_stream.dart';
import 'in_flight_posts.dart';
import 'local_seed_repository.dart';
import 'location_source.dart';
import 'participation_logic.dart';
import 'proximity_notifier.dart';
import 'refresh_logic.dart';
import 'site_repository.dart';
import 'status_logic.dart';
import 'trip_history_store.dart';
import 'username_store.dart';

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
    listenerChecks: ref.watch(listenerChecksProvider),
    inFlight: ref.watch(inFlightPostsProvider),
    // The proximity gate's position source — adapted here so the repository
    // stays geolocator-free (see `report_proximity.dart`).
    locate: () async {
      final position = await location.currentPosition();
      if (position == null) return null;
      return (lat: position.latitude, lng: position.longitude);
    },
  );
});

/// "Has a time-windowed listener gone stale?" — what `freshWindowStream` is
/// asked, on a steady one-minute tick and the moment the app comes back to the
/// foreground (a returning browser tab counts). The tick is how a freeze is
/// noticed at all — a suspended process ticks nothing, so the first tick after
/// waking sees the whole gap; the resume event makes that check immediate,
/// before the SDK has reconnected and re-sent the stale query. Broadcast,
/// because every `watchAllRecentReports()` call subscribes.
final listenerChecksProvider = Provider<Stream<void>>((ref) {
  final checks = StreamController<void>.broadcast();
  final tick = Timer.periodic(listenerCheckInterval, (_) => checks.add(null));
  final lifecycle = AppLifecycleListener(onResume: () => checks.add(null));
  ref.onDispose(() {
    tick.cancel();
    lifecycle.dispose();
    checks.close();
  });
  return checks.stream;
});

/// Where the repository holds this device's votes and reports from the tap
/// until the listeners have them (issue #50 — see `in_flight_posts.dart`).
final inFlightPostsProvider = Provider<InFlightPosts>((ref) {
  final posts = InFlightPosts();
  ref.onDispose(posts.dispose);
  return posts;
});

/// Those posts, as [sitesProvider] and [siteReportsProvider] lay them over
/// what the listeners deliver. A plain list, never loading: it is local state,
/// and the feedback it exists for must not wait on anything.
final inFlightReportsProvider =
    NotifierProvider<InFlightReportsNotifier, List<SiteReport>>(
      InFlightReportsNotifier.new,
    );

class InFlightReportsNotifier extends Notifier<List<SiteReport>> {
  @override
  List<SiteReport> build() {
    final posts = ref.watch(inFlightPostsProvider);
    final changes = posts.changes.listen((held) => state = held);
    ref.onDispose(changes.cancel);
    return posts.current;
  }
}

/// Road-name storage (see `username_store.dart`). Firestore in production;
/// the in-memory store keeps tests and Firebase-less runs prompt-free.
final usernameStoreProvider = Provider<UsernameStore>((ref) {
  if (Firebase.apps.isEmpty) return MemoryUsernameStore();
  return FirestoreUsernameStore(
    firestore: FirebaseFirestore.instance,
    auth: ref.watch(firebaseAuthProvider),
  );
});

/// The current user's profile (road name + provider displayName). One cheap
/// single-doc listener on `users/{uid}`; fail-soft (errors surface as null)
/// so a broken stream can never wedge the road-name prompt on screen.
final myProfileProvider = StreamProvider<UserProfile?>((ref) {
  return ref.watch(usernameStoreProvider).watchProfile();
});

/// What posts are signed with right now: road name, else (signed-in only)
/// the provider displayName, else null — meaning posting paths must ask the
/// user to pick a name first (`ensureSignatureName`).
final signatureNameProvider = Provider<String?>((ref) {
  return ref.watch(myProfileProvider).value?.signature;
});

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

/// The site documents exactly as stored. Only [sitesProvider] and
/// [refreshSiteData] should read this — screens want the display statuses.
final storedSitesProvider = StreamProvider<List<Site>>((ref) {
  return ref.watch(siteRepositoryProvider).watchSites();
});

/// The site list every screen consumes, with each status resolved to the one
/// to display (`withEffectiveStatus`): a site's status is its newest *status
/// report* inside the 10h window — an Open/Blitz/Closed vote or a Camera Only
/// / BGD report (issue #48), which exists only in the reports stream — and
/// Unknown when there is none (issues #21, #49). Applied here so every
/// consumer gets one rule.
///
/// A plain provider over the two listeners rather than a combined stream, so
/// each Firestore listener stays single and shared — rebuilding a stream
/// provider on every report would re-subscribe (and re-bill) the whole site
/// list.
///
/// It deliberately **never waits on the reports**: their query is new every
/// session, and Firestore holds back an empty first snapshot until the server
/// answers (up to ~10 s in a coverage hole), which would stall the cached site
/// list and the approach prompt it feeds. While they load — or if they fail —
/// the stored statuses show, exactly what old builds display anyway.
///
/// The driver's own posts in flight are laid over both (issue #50), so a tap
/// shows at the tap instead of at the server's acknowledgement.
final sitesProvider = Provider<AsyncValue<List<Site>>>((ref) {
  final stored = ref.watch(storedSitesProvider);
  final reports = ref.watch(recentReportsProvider);
  final inFlight = ref.watch(inFlightReportsProvider);
  return stored.whenData(
    (sites) => withEffectiveStatus(
      sites,
      // null = "the reports can't vouch for anything yet": still loading, or
      // failed (a dead listener's last list only goes stale, and would turn
      // every newer vote Unknown). Both fall back to the stored statuses.
      recentReports: reports.hasError ? null : reports.value,
      inFlight: inFlight,
    ),
  );
});

final favouriteSiteIdsProvider = StreamProvider<Set<String>>((ref) {
  return ref.watch(siteRepositoryProvider).watchFavourites();
});

/// The current user's participation counters (points/levels/badges derive
/// client-side in participation_logic.dart). One single-doc listener whose
/// only writer is the user themself; first subscribed from the User tab.
/// Fails silent: consumers render nothing on null/error, so a broken stream
/// can never wedge the account panel. Not part of [refreshSiteData].
final myParticipationProvider = StreamProvider<ParticipationStats?>((ref) {
  return ref.watch(siteRepositoryProvider).watchMyStats();
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
/// opening one Firestore query per site. The driver's own posts in flight are
/// listed on top (issue #50), whatever state the listener is in: a "Long
/// queue" is on the card at the tap, not at the acknowledgement.
final siteReportsProvider =
    Provider.family<AsyncValue<List<SiteReport>>, String>((ref, siteId) {
      final inFlight = ref.watch(inFlightReportsProvider);
      List<SiteReport> forSite(List<SiteReport> delivered) =>
          reportsForSite(withInFlightPosts(delivered, inFlight), siteId);
      final listed = ref.watch(recentReportsProvider).whenData(forSite);
      // Loading, or failed (`whenData` keeps no value through an error, even
      // one that had loaded): the listener has nothing to list, the driver
      // still does.
      if (!listed.hasValue && inFlight.any((post) => post.siteId == siteId)) {
        return AsyncData(forSite(const []));
      }
      return listed;
    });

/// Shared pull-to-refresh for the Firestore-backed streams: a healthy
/// snapshot listener is already live, so it is only restarted after an error
/// (retry); restarting a working one would re-bill its whole result set.
Future<void> refreshSiteData(WidgetRef ref) async {
  // The listeners themselves — [sitesProvider] is derived from the first two
  // and follows them; invalidating it would restart nothing.
  for (final provider in [
    storedSitesProvider,
    recentReportsProvider,
    favouriteSiteIdsProvider,
  ]) {
    if (shouldRestartOnRefresh(ref.read(provider))) {
      ref.invalidate(provider);
    }
  }
  await ref.read(storedSitesProvider.future);
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
