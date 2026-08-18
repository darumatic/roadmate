import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which admin notice this device has dismissed, so a message the
/// driver has already read doesn't come back on every launch.
///
/// Per-device on purpose: dismissal is a reading preference, not account state,
/// and keeping it local costs no Firestore writes (and works for anonymous
/// users). Injectable — mirrors [TripHistoryStore] — so widget tests use an
/// in-memory fake instead of platform channels.
abstract class AnnouncementDismissStore {
  /// The `dismissKey` of the last dismissed notice, or null.
  Future<String?> load();

  Future<void> save(String dismissKey);
}

class PrefsAnnouncementDismissStore implements AnnouncementDismissStore {
  const PrefsAnnouncementDismissStore();

  static const _key = 'dismissedAnnouncement';

  @override
  Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> save(String dismissKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, dismissKey);
  }
}
