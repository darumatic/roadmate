/// Serialises the app's platform permission requests.
///
/// Android hands an **empty `grantResults`** — an instant, silent denial the
/// driver never sees — to any permission request raised while another
/// permission dialog is already on screen. On a fresh install RoadMate asks for
/// two at once: notifications (the approach notifier, wired up by
/// `ProximityGate`) and location (the speedometer's GPS stream), both on the
/// first frame. Whichever lost that race was cancelled before its dialog could
/// open, and because a denial is sticky the driver was left on "GPS idle" with
/// no location prompt ever shown.
///
/// Requests queued here run one at a time, in arrival order, so the second
/// dialog only opens once the first has been answered.
class PermissionQueue {
  Future<void> _tail = Future<void>.value();

  /// Runs [request] after every request queued before it has settled, and
  /// returns its result (or rethrows its error) to the caller.
  Future<T> run<T>(Future<T> Function() request) {
    final result = _tail.then((_) => request());
    // The chain must survive a failure: a plugin that throws must not wedge
    // every later permission behind a broken future.
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

/// The single queue every runtime permission request in the app goes through.
final PermissionQueue permissionQueue = PermissionQueue();
