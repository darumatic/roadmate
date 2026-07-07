import 'package:shared_preferences/shared_preferences.dart';

import 'rate_limit.dart';

/// A snapshot of when this device last voted / reported per site id.
typedef CooldownSnapshot = ({
  Map<String, DateTime> voteAt,
  Map<String, DateTime> reportAt,
});

/// On-device persistence for the vote/report cooldown timestamps (issue #15),
/// so a page refresh mid-cooldown doesn't re-enable the buttons. Injectable
/// (mirrors `TripHistoryStore`) so tests use mock preferences. UX only — the
/// authoritative limit lives in the Firestore rules ledger.
abstract class CooldownStore {
  Future<CooldownSnapshot> loadAll({DateTime? now});
  Future<void> markVote(String siteId, DateTime at);
  Future<void> markReport(String siteId, DateTime at);
}

/// `shared_preferences`-backed store; one int (epoch ms) per site per action.
class PrefsCooldownStore implements CooldownStore {
  const PrefsCooldownStore();

  static const _votePrefix = 'cooldownVote.';
  static const _reportPrefix = 'cooldownReport.';

  /// Loads unexpired timestamps and prunes expired keys so the prefs file
  /// doesn't grow forever.
  @override
  Future<CooldownSnapshot> loadAll({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final at = now ?? DateTime.now();
    final voteAt = <String, DateTime>{};
    final reportAt = <String, DateTime>{};
    for (final key in prefs.getKeys().toList()) {
      final isVote = key.startsWith(_votePrefix);
      final isReport = key.startsWith(_reportPrefix);
      if (!isVote && !isReport) continue;
      final millis = prefs.getInt(key);
      final prefix = isVote ? _votePrefix : _reportPrefix;
      final cooldown = isVote ? kVoteCooldown : kReportCooldown;
      final stamp = millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
      if (stamp == null || !stamp.add(cooldown).isAfter(at)) {
        await prefs.remove(key);
        continue;
      }
      final siteId = key.substring(prefix.length);
      (isVote ? voteAt : reportAt)[siteId] = stamp;
    }
    return (voteAt: voteAt, reportAt: reportAt);
  }

  @override
  Future<void> markVote(String siteId, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_votePrefix$siteId', at.millisecondsSinceEpoch);
  }

  @override
  Future<void> markReport(String siteId, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_reportPrefix$siteId', at.millisecondsSinceEpoch);
  }
}
