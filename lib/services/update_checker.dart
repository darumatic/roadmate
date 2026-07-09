import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../version.dart';
// Real probe on web; a null/no-op stub on native, where the app stores own
// updates. Resolved at compile time so the native bundles never touch JS.
import 'update_probe_stub.dart'
    if (dart.library.js_interop) 'update_probe_web.dart'
    as probe;

/// How often the web app polls /version.json for a newer deploy. The banner
/// also re-checks whenever the tab regains focus (see UpdateGate).
const Duration kUpdatePollInterval = Duration(minutes: 5);

/// Whether the deployed version differs from the one baked into this build.
/// Plain inequality, not semver: the server is the source of truth, so a
/// rollback should prompt a refresh too.
bool isUpdateAvailable({required String current, String? remote}) =>
    remote != null && remote.isNotEmpty && remote != current;

typedef RemoteVersionFetcher = Future<String?> Function();
typedef AppReloader = Future<void> Function();

/// The platform probe (fetch deployed version / hard-reload). The single
/// override point for tests.
final updateProbeProvider =
    Provider<
      ({RemoteVersionFetcher fetchRemoteVersion, AppReloader reloadApp})
    >(
      (ref) => (
        fetchRemoteVersion: probe.fetchRemoteVersion,
        reloadApp: probe.reloadApp,
      ),
    );

/// True once a newer build has been deployed than the one running. Polls
/// every [kUpdatePollInterval]; sticky once true. Fetch failures (offline,
/// transient) are swallowed by the probe — an update check must never break
/// the app.
class UpdateChecker extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    _timer = Timer.periodic(kUpdatePollInterval, (_) => checkNow());
    return false;
  }

  Future<void> checkNow() async {
    if (state) return; // already known — nothing to re-check
    final remote = await ref.read(updateProbeProvider).fetchRemoteVersion();
    if (isUpdateAvailable(current: appVersion, remote: remote)) {
      state = true;
    }
  }
}

final updateCheckerProvider = NotifierProvider<UpdateChecker, bool>(
  UpdateChecker.new,
);
