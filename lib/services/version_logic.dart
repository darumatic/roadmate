/// Pure version-string logic, kept Flutter/Firebase-free for fast unit tests.
///
/// A version string is `x.y.z` with an optional `+build` suffix, e.g. `1.0.0+1`.
library;

final _versionPattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');

/// Bumps the patch (third) component and the build number by one.
///
/// `'1.0.0+1'` -> `'1.0.1+2'`. When the build number is absent it defaults to
/// `1` (`'0.0.1'` -> `'0.0.2+1'`... but callers that omit builds get the build
/// appended). Throws [FormatException] on malformed input.
String bumpPatchVersion(String current) {
  final match = _versionPattern.firstMatch(current.trim());
  if (match == null) {
    throw FormatException('Invalid version string: "$current"');
  }
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  final patch = int.parse(match.group(3)!) + 1;
  final buildGroup = match.group(4);
  final build = (buildGroup == null ? 0 : int.parse(buildGroup)) + 1;
  return '$major.$minor.$patch+$build';
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
