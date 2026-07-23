import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../version.dart';
import 'update_checker.dart';
import 'version_logic.dart';

/// Forced-update gate: the Firestore doc `config/app` carries a `minVersion`;
/// builds below it render a blocking update screen instead of the app.
/// The doc is edited only in the Firebase console (rules deny client writes)
/// and a live snapshot means flipping it takes effect in running apps without
/// a restart. Everything fails OPEN — no config doc, offline, parse errors —
/// so the gate can never brick the app by accident.
///
/// Limitation (recorded in specs.md): only builds that ship this gate obey
/// it. Older builds are eventually retired by the strict rules phase of the
/// rate limit (issue #15).

const String kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.darumatic.roadmate';

const String kAppStoreUrl =
    'https://apps.apple.com/us/app/roadmate-australia/id6788635496';

/// A store listing offered on the Share page's "Get the app" section.
class StoreLink {
  const StoreLink({required this.label, required this.url});

  final String label;
  final String url;
}

const StoreLink kPlayStoreLink = StoreLink(
  label: 'Google Play',
  url: kPlayStoreUrl,
);
const StoreLink kAppStoreLink = StoreLink(
  label: 'App Store',
  url: kAppStoreUrl,
);

/// Store listings to offer for a given runtime: both on web, only the
/// matching store inside the native apps, none elsewhere (desktop dev runs).
List<StoreLink> storeLinksFor({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return const [kPlayStoreLink, kAppStoreLink];
  switch (platform) {
    case TargetPlatform.android:
      return const [kPlayStoreLink];
    case TargetPlatform.iOS:
      return const [kAppStoreLink];
    default:
      return const [];
  }
}

/// Whether the "Support the app" (Buy Me a Coffee) donation UI may be shown.
/// Hidden in the native iOS app: App Store guideline 3.1.1 forbids external
/// donation mechanisms (rejection of 0.1.38). Android and web keep it.
bool showDonationLink({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return isWeb || platform != TargetPlatform.iOS;
}

/// True while this build is below the remotely-configured minimum version.
final forceUpdateProvider = StreamProvider<bool>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value(false);
  return FirebaseFirestore.instance
      .doc('config/app')
      .snapshots()
      .map(
        (snap) => isBelowMinimum(
          current: appVersion,
          minimum: snap.data()?['minVersion'] as String?,
        ),
      )
      // Swallow stream errors: the provider then reports no value and the
      // gate's `.value ?? false` consumer stays open.
      .handleError((Object _) {});
});

/// What the update button does — store page on mobile, hard reload on web.
/// A provider so widget tests can override it.
final storeOpenerProvider = Provider<Future<void> Function()>((ref) {
  if (kIsWeb) return ref.watch(updateProbeProvider).reloadApp;
  return () async {
    final url = defaultTargetPlatform == TargetPlatform.iOS
        ? kAppStoreUrl
        : kPlayStoreUrl;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  };
});
