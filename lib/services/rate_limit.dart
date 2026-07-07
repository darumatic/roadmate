import 'package:firebase_core/firebase_core.dart';

/// Server-enforced rate limit (issue #15): up to [kMaxActionsPerWindow]
/// actions — votes and activity reports combined — per user per site within
/// each [kActionWindow], so a mis-tap can be corrected immediately but a spam
/// loop cannot run. These MUST match the `limits/{uid}` rules in
/// `firestore.rules` (5 actions / 5 minutes). Validation is server-side only;
/// the client just translates the rejection into a friendly message.
const Duration kActionWindow = Duration(minutes: 5);
const int kMaxActionsPerWindow = 5;

/// Whether [error] is the security-rules rejection a rate-limited write gets.
/// (Rules deny the whole batch, which surfaces as permission-denied.)
bool isRateLimited(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

/// User-facing explanation for a rate-limited write.
const String rateLimitMessage =
    "You've made several changes to this site just now — "
    'please try again in a few minutes.';

/// The ledger transition for one more action: start a new window if the
/// current one has ended, otherwise count within it. Pure, mirrored exactly
/// by the rules (which verify the transition server-side).
({bool resetWindow, int count}) nextLedger({
  required DateTime? windowStart,
  required int count,
  required DateTime now,
}) {
  final expired =
      windowStart == null || now.isAfter(windowStart.add(kActionWindow));
  return (resetWindow: expired, count: expired ? 1 : count + 1);
}
