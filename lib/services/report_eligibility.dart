/// Client side of "only real accounts may post" (spam control).
///
/// Every RoadMate session is already authenticated: `ensureSignedIn` mints an
/// **anonymous** Firebase user at boot so votes, favourites and trips have a uid
/// without a login wall. But that identity is free and unlimited — a spammer who
/// collects a ban reinstalls and gets a fresh one. So *posting* (activity reports
/// and OPEN/BLITZ/CLOSED status changes) requires a linked Google or Apple
/// account, while reading, Nearby, favourites, trips and Add Site stay
/// account-free. Add Site is deliberately left open: submissions land as pending
/// and a moderator has to approve them, so spam is already contained there.
///
/// Nobody loses anything by crossing this line. Signing in **links** the
/// provider onto the existing anonymous uid
/// (`AuthController._signInWithProvider`), so favourites, trip history and past
/// reports all carry over.
///
/// Deliberately Flutter- and Firebase-free (like `status_logic.dart` and
/// `ban_logic.dart`) so the rule is unit-testable without a Firebase app. The
/// repository is the single enforcement point — it checks this before writing,
/// so no UI path can leak a doomed request — and `firestore.rules` enforces the
/// same thing server-side via `isRegistered()`.
library;

/// Whether the current identity may post reports and status votes.
///
/// Anonymous sessions and a missing session both mean no: an absent user is not
/// a licence to post, and the caller shouldn't have to special-case it.
bool canPostReports({required bool signedIn, required bool isAnonymous}) =>
    signedIn && !isAnonymous;

/// Title of the sign-in prompt raised at the moment of posting.
const String kSignInSheetTitle = 'Sign in to report';

/// Why we ask. Shown in the prompt and as the snack/exception text.
const String kSignInToReportMessage =
    'Sign in to report — it keeps the reports trustworthy.';

/// The longer form, for the prompt body: says what stays free.
const String kSignInSheetBody =
    'Reports and status changes need a Google or Apple account. '
    'Browsing, Nearby and your favourites stay open to everyone.';

/// The write was refused because the user has no real account — as opposed to
/// being banned ([BannedException] in `ban_logic.dart`) or too quick
/// ([RateLimitedException] in `rate_limit.dart`).
class SignInRequiredException implements Exception {
  const SignInRequiredException();

  String get message => kSignInToReportMessage;

  @override
  String toString() => message;
}
