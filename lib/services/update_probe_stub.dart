// Native (and test) fallback for the web update probe: app stores handle
// updates there, so there is never a remote version to compare against.
// Selected via the conditional import in update_checker.dart.

Future<String?> fetchRemoteVersion() async => null;

Future<void> reloadApp() async {}
