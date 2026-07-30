import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/site.dart';
import '../../services/auth_service.dart';
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

/// How much the distance must change before a live prompt is rewritten. Every
/// fix moves the number a little; redrawing the card 50 m at a time keeps it
/// honest without rebuilding it for every metre of jitter.
const double proximityPromptStepKm = 0.05;

/// Drives the Waze-style "you're coming up on X — what's the status?" prompt.
///
/// Fed from the one existing GPS stream (`TripController` calls [onPosition]
/// for every fix) so no second listener is opened; the decision itself is the
/// pure [ProximityTracker]. Holds at most one pending prompt: a second site
/// entering range while the driver is answering is ignored rather than
/// stacked, and stays eligible because it was never marked as prompted.
///
/// A raised prompt has no timer on it — it stays until the driver answers it,
/// dismisses it, or drives past the site (which [ProximityTracker.hasPassed]
/// reports, and which retires the card here).
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
    _updatePending();

    if (hit != null && state?.site.id == hit.site.id) {
      // The card for this site is already up, so the second-chance prompt has
      // nothing to add — spend it here rather than let it fire the instant the
      // driver dismisses the one they're looking at.
      _tracker.markPrompted(hit.site.id, now, near: hit.near);
      return;
    }
    if (hit == null || state != null || !_enabled) return;

    _tracker.markPrompted(hit.site.id, now, near: hit.near);
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

  /// Keeps the on-screen prompt in step with the truck: the distance counts
  /// down as the site nears, and the card retires itself once the site is
  /// behind them (the only thing that clears it besides an answer, a dismiss,
  /// or the feature being switched off).
  void _updatePending() {
    final pending = state;
    if (pending == null) return;
    if (_tracker.hasPassed(pending.site.id)) {
      dismiss();
      return;
    }
    final km = _tracker.lastKmFor(pending.site.id);
    if (km == null) return;
    if ((pending.km - km).abs() < proximityPromptStepKm) return;
    state = ProximityPrompt(site: pending.site, km: km);
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
    // Posting needs a real account and a notification has no UI to ask with,
    // so an anonymous tap is left *unanswered*: the prompt stays pending and
    // the in-app card raises the sign-in sheet when the driver next looks at
    // the app. Consuming it here would silently drop the report instead.
    //
    if (!mayPostReports(ref.read(firebaseAuthProvider))) return;
    _tracker.markAnswered(answer.siteId);
    if (state?.site.id == answer.siteId) state = null;
    try {
      await ref.read(siteRepositoryProvider).vote(answer.siteId, status);
    } catch (e) {
      // Rate-limited or offline: the site card is a tap away and the driver
      // has already left the notification behind — never crash on it.
      debugPrint('RoadMate: notification vote failed: $e');
    }
  }

  /// Clears the pending prompt without recording an answer. The site keeps its
  /// second chance: dismissing at 3 km is "not now", not "nothing to report",
  /// so it asks again from [proximityNearRadiusKm].
  void dismiss() {
    state = null;
    ref.read(proximityNotifierProvider).cancel();
  }

  /// Clears the prompt because the driver answered it — unlike [dismiss] this
  /// ends the conversation about that site for the rest of the pass.
  void markAnswered() {
    final pending = state;
    if (pending != null) _tracker.markAnswered(pending.site.id);
    dismiss();
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
