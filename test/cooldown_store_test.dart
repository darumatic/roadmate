import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/cooldown_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('marks round-trip per site and per action', () async {
    const store = PrefsCooldownStore();
    final voteTime = DateTime.now();
    final reportTime = voteTime.subtract(const Duration(seconds: 30));

    await store.markVote('nsw-1', voteTime);
    await store.markReport('qld-2', reportTime);

    final snapshot = await store.loadAll(now: voteTime);
    expect(
      snapshot.voteAt['nsw-1']!.millisecondsSinceEpoch,
      voteTime.millisecondsSinceEpoch,
    );
    expect(snapshot.voteAt.containsKey('qld-2'), isFalse);
    expect(
      snapshot.reportAt['qld-2']!.millisecondsSinceEpoch,
      reportTime.millisecondsSinceEpoch,
    );
    expect(snapshot.reportAt.containsKey('nsw-1'), isFalse);
  });

  test('loadAll drops (and prunes) expired stamps', () async {
    const store = PrefsCooldownStore();
    final now = DateTime.now();

    await store.markVote('old', now.subtract(const Duration(hours: 1)));
    await store.markVote('fresh', now);

    final snapshot = await store.loadAll(now: now);
    expect(snapshot.voteAt.keys, ['fresh']);

    // Pruned from storage too, not just filtered out of the snapshot.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('cooldownVote.old'), isNull);
    expect(prefs.getInt('cooldownVote.fresh'), isNotNull);
  });
}
