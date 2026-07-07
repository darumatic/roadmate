import 'package:firebase_core/firebase_core.dart';

/// Client-side cooldowns between actions on the *same site* by the *same
/// user* (issue #15). These MUST match the `duration.value(...)` literals in
/// the `limits/{uid}` rules in `firestore.rules` — the rules are the real
/// enforcement; these drive the friendly UX (disabled buttons + message).
const Duration kVoteCooldown = Duration(minutes: 5);
const Duration kReportCooldown = Duration(minutes: 2);

/// Whether [error] is the security-rules rejection a rate-limited write gets.
/// (Rules deny the whole batch, which surfaces as permission-denied.)
bool isRateLimited(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

/// Time left before the user may act again, or null when free to act.
Duration? cooldownRemaining({
  required DateTime? lastActionAt,
  required DateTime now,
  required Duration cooldown,
}) {
  if (lastActionAt == null) return null;
  final end = lastActionAt.add(cooldown);
  return end.isAfter(now) ? end.difference(now) : null;
}

/// User-facing cooldown explanation, e.g.
/// "You've voted on this site recently — try again in 4 minutes."
String cooldownMessage(Duration remaining, {required bool isVote}) {
  final action = isVote ? 'voted on' : 'reported activity on';
  return "You've $action this site recently — try again in "
      '${_approx(remaining)}.';
}

String _approx(Duration remaining) {
  if (remaining.inSeconds <= 60) return 'about a minute';
  final minutes = (remaining.inSeconds / 60).ceil();
  return '$minutes minutes';
}
