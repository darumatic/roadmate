import 'ban_logic.dart';
import 'rate_limit.dart';
import 'report_proximity.dart';

/// Fallback for failures that carry no driver-appropriate message.
const String kPostFailedMessage = 'Could not submit — please try again.';

/// The snack text for a failed vote / activity report / site write.
///
/// One mapping shared by every posting surface. This used to be a six-branch
/// catch chain hand-copied per call site, which is exactly how a new surface
/// gets a branch wrong (wrong constant, missing mounted-guard, swallowed
/// message) without anyone noticing — the branches carry policy, so they
/// live here once, pure and tested.
String postErrorMessage(Object error) {
  if (error is TooFarException) return error.message;
  if (error is LocationRequiredException) return error.message;
  if (error is BannedException) return error.message;
  if (error is RateLimitedException) return kRateLimitMessage;
  return kPostFailedMessage;
}
