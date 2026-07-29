import 'package:intl/intl.dart';

/// Client side of admin bans (spam control).
///
/// A ban is one document at `bans/{uid}`, written only by admins and enforced
/// by `firestore.rules`: while it is active the uid may not write anything —
/// votes, activity reports, new sites, favourites, profile syncs. Reading is
/// untouched, so a banned spammer still gets the map, the speedo and their
/// trips; they simply can't post.
///
/// Two durations, per the moderation policy: **one day** and **forever**.
/// Forever is stored as a document with no `until` field, which is why every
/// check here treats a missing expiry as "still banned" rather than defaulting
/// to unbanned — a truncated or partially-written doc must fail closed.
///
/// The expiry is an absolute timestamp chosen from the *admin's* clock when
/// they press Ban, and compared against the server clock (`request.time`) in
/// the rules. That asymmetry is deliberate and harmless here: skew shifts a
/// 24-hour ban by the skew, nothing more. It is not the pattern rejected in
/// `rate_limit.dart` — there the *client* decided which write shape was legal
/// from its own clock, and skew produced false denials.

/// How long a "one day" ban lasts.
const Duration kOneDayBan = Duration(days: 1);

/// Longest reason an admin may attach — mirrors the 200-char cap in
/// `firestore.rules` (isValidBan).
const int kBanReasonMaxLength = 200;

/// The two bans an admin can hand out.
enum BanDuration {
  oneDay('1 day'),
  forever('Forever');

  const BanDuration(this.label);

  final String label;
}

/// When a [duration] ban started at [from] expires; null for [forever] — the
/// absent expiry that means permanent everywhere else in this file.
DateTime? banExpiry(BanDuration duration, DateTime from) =>
    duration == BanDuration.forever ? null : from.add(kOneDayBan);

/// Whether a ban whose expiry is [until] still bites at [now].
///
/// A null expiry is permanent, so it is always active — see the fail-closed
/// note above.
bool banIsActive({required DateTime? until, required DateTime now}) =>
    until == null || until.isAfter(now);

/// Human expiry, e.g. `30 Jul 2026, 2:15 pm`.
String banExpiryLabel(DateTime until) =>
    DateFormat('d MMM yyyy, h:mm a').format(until.toLocal());

/// What a banned user is told when a write of theirs is refused.
String banNoticeMessage(DateTime? until) => until == null
    ? 'Your account is suspended. You can still use RoadMate, but not post.'
    : 'Your account is suspended until ${banExpiryLabel(until)}.';

/// Field values for a ban document, minus the server-stamped bookkeeping the
/// repository adds (`createdAt`/`createdBy`). Pure so the shape the rules
/// validate is unit-testable without Firestore.
///
/// A permanent ban omits `until` entirely, and a blank reason is dropped —
/// both keep the doc inside `isValidBan`'s key allow-list.
Map<String, Object> banEditData({
  required BanDuration duration,
  required DateTime now,
  String? reason,
}) {
  final until = banExpiry(duration, now);
  final trimmed = reason?.trim();
  return {
    'until': ?until,
    if (trimmed != null && trimmed.isNotEmpty)
      'reason': trimmed.length > kBanReasonMaxLength
          ? trimmed.substring(0, kBanReasonMaxLength)
          : trimmed,
  };
}

/// The write was refused because the user is banned, not because they were
/// merely too quick (see `RateLimitedException` in `rate_limit.dart`).
class BannedException implements Exception {
  const BannedException(this.until);

  /// When the ban lifts; null when it never does.
  final DateTime? until;

  String get message => banNoticeMessage(until);

  @override
  String toString() => message;
}
