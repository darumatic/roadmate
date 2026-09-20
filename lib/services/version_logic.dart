/// Pure version-string logic, kept Flutter/Firebase-free for fast unit tests.
///
/// A version string is `x.y.z` with an optional `+build` suffix, e.g. `1.0.0+1`.
library;

final _versionPattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');

/// Which component of `x.y.z` a release bumps.
enum VersionPart { major, minor, patch }

/// Bumps [part] of [current] and the build number by one; the components
/// below [part] reset to zero.
///
/// `patch`: `'1.0.0+1'` -> `'1.0.1+2'` · `minor`: `'1.0.27+103'` ->
/// `'1.1.0+104'` · `major`: `'1.4.2+9'` -> `'2.0.0+10'`.
///
/// The build number only ever climbs, whatever happens to the marketing
/// version: Google Play and App Store Connect both refuse an upload whose
/// build number is not higher than the last one, so a minor bump that reset it
/// would be unshippable. When it is absent it counts as 0 (`'0.0.1'` ->
/// `'0.0.2+1'`). Throws [FormatException] on malformed input.
String bumpVersion(String current, {VersionPart part = VersionPart.patch}) {
  final match = _versionPattern.firstMatch(current.trim());
  if (match == null) {
    throw FormatException('Invalid version string: "$current"');
  }
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  final patch = int.parse(match.group(3)!);
  final buildGroup = match.group(4);
  final build = (buildGroup == null ? 0 : int.parse(buildGroup)) + 1;
  final next = switch (part) {
    VersionPart.major => '${major + 1}.0.0',
    VersionPart.minor => '$major.${minor + 1}.0',
    VersionPart.patch => '$major.$minor.${patch + 1}',
  };
  return '$next+$build';
}

/// Bumps the patch (third) component and the build number by one — what every
/// ordinary release does. See [bumpVersion].
String bumpPatchVersion(String current) => bumpVersion(current);

/// Numeric compare of two `x.y.z` versions (any `+build` suffix is ignored):
/// negative when [a] < [b], zero when equal, positive when [a] > [b].
/// So `0.1.9` < `0.1.10`. Throws [FormatException] on malformed input.
int compareVersions(String a, String b) {
  final ma = _versionPattern.firstMatch(a.trim());
  final mb = _versionPattern.firstMatch(b.trim());
  if (ma == null || mb == null) {
    throw FormatException('Invalid version string: "${ma == null ? a : b}"');
  }
  for (var group = 1; group <= 3; group++) {
    final diff = int.parse(ma.group(group)!) - int.parse(mb.group(group)!);
    if (diff != 0) return diff;
  }
  return 0;
}

/// Whether [current] falls below the remotely-configured [minimum]
/// (the forced-update gate). Fails OPEN — a missing or malformed minimum
/// must never lock users out of the app.
bool isBelowMinimum({required String current, String? minimum}) {
  if (minimum == null || minimum.trim().isEmpty) return false;
  try {
    return compareVersions(current, minimum) < 0;
  } on FormatException {
    return false;
  }
}

/// The display-only marketing version (`x.y.z`), stripping any `+build` suffix.
///
/// `'1.0.1+2'` -> `'1.0.1'`. Throws [FormatException] on malformed input.
String marketingVersion(String version) {
  final match = _versionPattern.firstMatch(version.trim());
  if (match == null) {
    throw FormatException('Invalid version string: "$version"');
  }
  return '${match.group(1)}.${match.group(2)}.${match.group(3)}';
}
