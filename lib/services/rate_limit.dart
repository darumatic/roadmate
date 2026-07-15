import 'package:firebase_core/firebase_core.dart';

/// Client side of the global per-user rate limit (issue #15 redux):
/// 5 actions (votes + activity reports combined) per 5 minutes, enforced by
/// the `users/{uid}/limits/actions` rules in `firestore.rules`.
///
/// Deliberately clock-free: the 2026-07-07 rollback happened because the
/// client picked the ledger's reset-vs-increment branch with the device
/// clock, and clock skew produced false rejections. Now every time judgment
/// lives server-side (`request.time`); the client only chooses a write shape
/// and, when the server denies it, retries once with the other shape. No
/// `DateTime` may ever appear in this file.

/// Display/documentation copies of the enforced values — the authoritative
/// numbers are the `5` and `duration.value(5, 'm')` in `firestore.rules`
/// (isLedgerReset/isLedgerIncrement) and MUST stay in sync with these.
const int kMaxActionsPerWindow = 5;
const Duration kRateLimitWindow = Duration(minutes: 5);

const String kRateLimitMessage =
    'Easy there — 5 actions per 5 minutes. Try again soon.';

/// The server refused both ledger shapes: the user really has spent all
/// [kMaxActionsPerWindow] actions inside the current window.
class RateLimitedException implements Exception {
  const RateLimitedException();

  @override
  String toString() => kRateLimitMessage;
}

/// The two ledger write shapes the rules accept.
enum LedgerShape {
  /// Add one action to the open window (rules: count == old+1 && <= 5,
  /// window still active). Never touches windowStart.
  increment,

  /// Start a fresh window (rules: create, or update once the old window has
  /// expired).
  reset,
}

/// Ledger payload for [LedgerShape.increment]. The Firebase sentinel values
/// are injected so this stays testable without Firestore:
/// [incrementByOne] must be `FieldValue.increment(1)` and [serverTime]
/// `FieldValue.serverTimestamp()` in production. `windowStart` is
/// deliberately absent — an increment must never move the window.
Map<String, Object> ledgerIncrementPayload({
  required Object incrementByOne,
  required Object serverTime,
}) {
  return {'count': incrementByOne, 'lastActionAt': serverTime};
}

/// Ledger payload for [LedgerShape.reset]: a fresh window of one action,
/// timestamped entirely by the server.
Map<String, Object> ledgerResetPayload({required Object serverTime}) {
  return {'count': 1, 'windowStart': serverTime, 'lastActionAt': serverTime};
}

/// Whether a failed commit should be retried with the other ledger shape.
/// `permission-denied`: the rules rejected this shape (window state didn't
/// match). `not-found`: an increment `update()` ran before the ledger doc
/// ever existed — the batch fails on the missing-doc precondition, not on
/// the rules.
bool shouldTryOtherShape(Object error) {
  return error is FirebaseException &&
      (error.code == 'permission-denied' || error.code == 'not-found');
}

/// Whether a failure is a rules denial. After both shapes have been tried,
/// a denial means genuinely rate-limited (anything else — offline, missing
/// doc — is not the limit speaking).
bool isRulesDenial(Object error) {
  return error is FirebaseException && error.code == 'permission-denied';
}
