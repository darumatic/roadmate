import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/site.dart';
import '../../services/proximity_alert.dart';
import '../../services/proximity_notifier.dart';
import '../../services/providers.dart';
import '../speedometer/trip_controller.dart';
import 'proximity_text.dart';

/// The site the driver is approaching, awaiting an answer.
class ProximityPrompt {
  const ProximityPrompt({required this.site, required this.km});

  final Site site;
  final double km;
}

/// Drives the Waze-style "you're coming up on X — what's the status?" prompt.
///
/// Fed from the one existing GPS stream (`TripController` calls [onPosition]
/// for every fix) so no second listener is opened; the decision itself is the
/// pure [ProximityTracker]. Holds at most one pending prompt: a second site
/// entering range while the driver is answering is ignored rather than
/// stacked, and stays eligible because it was never marked as prompted.
class ProximityController extends Notifier<ProximityPrompt?> {
  final ProximityTracker _tracker = ProximityTracker();
  List<Site> _sites = const [];
  bool _enabled = true;
  bool _foreground = true;

  @override
  ProximityPrompt? build() {
    // Wire up the background notification channel once, on the same trigger
    // that starts GPS. Best-effort inside the notifier itself.
    ref.read(proximityNotifierProvider).initialise(answerFromNotification);
    // `listen` rather than `watch`: this notifier must hold a live subscription
    // to the site stream (otherwise a read from the GPS callback finds an
    // unsubscribed, still-loading provider), but must NOT rebuild when the list
    // changes — a rebuild would reset `state` and yank a prompt off screen
    // every time any site's vote count ticks.
    ref.listen(sitesProvider, (_, next) {
      final sites = next.value;
      if (sites != null) _sites = sites;
    }, fireImmediately: true);
    // Same reasoning for the on/off switch, and touching it here matters:
    // the controller is built when the GPS stream starts, so the persisted
    // value has loaded well before the first fix could raise a prompt.
    ref.listen(proximityEnabledProvider, (_, next) {
      _enabled = next;
      // Switching the feature off must take any live prompt with it. Handled
      // here rather than in the switch's own controller so the dependency
      // stays one-way (that direction would be a cycle).
      if (!next) state = null;
    }, fireImmediately: true);
    return null;
  }

  /// Folds one GPS fix in, raising a prompt when a site qualifies.
  void onPosition({
    required double lat,
    required double lng,
    required double speedKmh,
  }) {
    if (_sites.isEmpty) return;
    final now = DateTime.now();
    // Runs even when a prompt is showing or the feature is off: the tracker's
    // distance history must not go stale, or the next "closing" test compares
    // against a fix from minutes and kilometres ago.
    final hit = _tracker.update(
      sites: _sites,
      lat: lat,
      lng: lng,
      speedKmh: speedKmh,
      now: now,
    );
    if (hit == null || state != null || !_enabled) return;

    _tracker.markPrompted(hit.site.id, now);
    // Set regardless of where it's announced: an unanswered prompt raised in
    // the background is exactly what the driver should find on screen when
    // they pick the phone up.
    state = ProximityPrompt(site: hit.site, km: hit.km);
    if (_foreground) {
      if (ref.read(soundEnabledProvider)) {
        // Best-effort: a missing sound must never block the prompt itself.
        ref.read(alertPlayerProvider).playProximity();
      }
    } else {
      ref
          .read(proximityNotifierProvider)
          .showApproach(
            siteId: hit.site.id,
            siteName: hit.site.name,
            km: hit.km,
            body: approachStatusLine(hit.site),
          );
    }
  }

  /// Tracks whether the app is on screen — set by [ProximityGate] from the
  /// app lifecycle. Off screen, an approach becomes a system notification
  /// instead of a card nobody would see.
  void setAppForeground(bool foreground) {
    _foreground = foreground;
    // Coming back to the app: the card takes over from the notification.
    if (foreground) ref.read(proximityNotifierProvider).cancel();
  }

  /// Applies an answer the user gave on the notification itself. A plain tap
  /// (no action) carries no status — it just brings them to the card.
  Future<void> answerFromNotification(ProximityAnswer answer) async {
    ref.read(proximityNotifierProvider).cancel();
    final status = answer.status;
    if (status == null) return;
    if (state?.site.id == answer.siteId) state = null;
    try {
      await ref.read(siteRepositoryProvider).vote(answer.siteId, status);
    } catch (e) {
      // Rate-limited or offline: the site card is a tap away and the driver
      // has already left the notification behind — never crash on it.
      debugPrint('RoadMate: notification vote failed: $e');
    }
  }

  /// Clears the pending prompt (answered, dismissed, or opened in full).
  void dismiss() {
    state = null;
    ref.read(proximityNotifierProvider).cancel();
  }

  /// Drops all approach history — used when the GPS stream restarts, so a fix
  /// from another part of the country isn't compared against the last one.
  void resetTracking() {
    _tracker.reset();
    state = null;
  }
}

final proximityControllerProvider =
    NotifierProvider<ProximityController, ProximityPrompt?>(
      ProximityController.new,
    );

/// Whether approach prompts are enabled — the `near_me` toggle beside the
/// speaker on Home. On by default; persisted on device like the speed limit
/// and the sound switch.
class ProximityEnabledController extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    try {
      state = await ref.read(tripHistoryStoreProvider).loadProximityEnabled();
    } catch (e) {
      // Storage unavailable (first launch or test harness) — keep the default.
      debugPrint('RoadMate: failed to load proximity setting: $e');
    }
  }

  void toggle() => set(!state);

  void set(bool enabled) {
    state = enabled;
    try {
      ref.read(tripHistoryStoreProvider).saveProximityEnabled(enabled);
    } catch (e) {
      // The toggle still applies this session; persistence is best-effort.
      debugPrint('RoadMate: failed to save proximity setting: $e');
    }
  }
}

final proximityEnabledProvider =
    NotifierProvider<ProximityEnabledController, bool>(
      ProximityEnabledController.new,
    );
