/// Road names — unique, human-readable public handles that sign status votes,
/// activity reports and site submissions ("Dusty Roadtrain", not a uid).
///
/// Pure Dart, no Flutter/Firebase imports, so the generator and validation are
/// directly unit-testable. Uniqueness itself is enforced by the
/// `usernames/{key}` claim collection (see `username_store.dart` and
/// firestore.rules) — everything here must stay in sync with the
/// `isValidUsernameClaim` rule: same length caps, same character set, same
/// lowercase key derivation.
library;

import 'dart:math';

const int kUsernameMinLength = 3;
const int kUsernameMaxLength = 30;

/// Snack shown when a post is abandoned because the user declined to pick a
/// road name — posting is signed, so no name means no post.
const String kRoadNameRequiredMessage =
    'Pick a road name to post — reports are signed with it.';

/// The generator's word pool, road/travel flavoured to match the level ladder
/// (Rookie → Outback Legend). Keep words to ~9 characters so a two-adjective
/// roll stays under [kUsernameMaxLength].
const List<String> kUsernameAdjectives = [
  'Dusty',
  'Rolling',
  'Turbo',
  'Diesel',
  'Chrome',
  'Midnight',
  'Sunburnt',
  'Coastal',
  'Outback',
  'Steady',
  'Roaring',
  'Flying',
  'Restless',
  'Wandering',
  'Longhaul',
  'Redline',
  'Highbeam',
  'Southern',
];

const List<String> kUsernameNouns = [
  'Hauler',
  'Trucker',
  'Roadtrain',
  'Drifter',
  'Cruiser',
  'Navigator',
  'Wanderer',
  'Convoy',
  'Mudflap',
  'Bullbar',
  'Freighter',
  'Nomad',
  'Drover',
  'Overtaker',
  'Rigrunner',
  'Wayfarer',
];

/// "Adjective Noun", sometimes "Adjective Adjective Noun" when the longer
/// form still fits the cap. Deterministic for a seeded [random], so tests can
/// pin outputs; every possible output passes [validateUsername].
String generateUsername(Random random) {
  final noun = kUsernameNouns[random.nextInt(kUsernameNouns.length)];
  final adjective =
      kUsernameAdjectives[random.nextInt(kUsernameAdjectives.length)];
  var name = '$adjective $noun';
  if (random.nextBool()) {
    final extra =
        kUsernameAdjectives[random.nextInt(kUsernameAdjectives.length)];
    final longer = '$extra $name';
    if (extra != adjective && longer.length <= kUsernameMaxLength) {
      name = longer;
    }
  }
  return name;
}

/// Trims and collapses runs of whitespace — "  Dusty   Nomad " and
/// "Dusty Nomad" are the same name.
String normalizeUsername(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// The uniqueness key (and `usernames/{key}` document id): the normalized
/// name lowercased, so "Dusty Nomad" and "DUSTY NOMAD" collide.
String usernameKey(String raw) => normalizeUsername(raw).toLowerCase();

final RegExp _usernameCharset = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9 _-]*[A-Za-z0-9]$',
);

/// Null when [raw] is a usable road name, else the reason it isn't (shown
/// verbatim in the picker). Must stay at least as strict as the
/// `isValidUsernameClaim` rule, or a name the client accepts would die on the
/// server with a generic error.
String? validateUsername(String raw) {
  final name = normalizeUsername(raw);
  if (name.length < kUsernameMinLength) {
    return 'Road names need at least $kUsernameMinLength characters.';
  }
  if (name.length > kUsernameMaxLength) {
    return 'Road names are capped at $kUsernameMaxLength characters.';
  }
  if (!_usernameCharset.hasMatch(name)) {
    return 'Use letters, numbers, spaces, - or _ — starting and ending with '
        'a letter or number.';
  }
  return null;
}

/// Whether the load-time picker should be showing. Only anonymous users are
/// prompted — a signed-in account already signs with its displayName unless
/// it picks a road name — and "Not now" ([dismissed]) quiets it for the
/// session. [profileLoaded] keeps it hidden until the profile stream has
/// actually answered, so a user who *has* a name never sees a flash of the
/// prompt while it loads.
bool shouldPromptForUsername({
  required bool isAnonymousUser,
  required bool profileLoaded,
  required String? username,
  required bool dismissed,
}) {
  return isAnonymousUser &&
      profileLoaded &&
      (username == null || username.trim().isEmpty) &&
      !dismissed;
}
