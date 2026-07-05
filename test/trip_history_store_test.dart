import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/models/trip.dart';
import 'package:roadmate/services/trip_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Trip _trip(String id, DateTime startedAt) => Trip(
  id: id,
  startedAt: startedAt,
  duration: const Duration(minutes: 5),
  distanceKm: 3.2,
  maxSpeedKmh: 88,
  avgSpeedKmh: 40,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = PrefsTripHistoryStore();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save + all round-trips trips, newest first', () async {
    await store.save(_trip('older', DateTime(2026, 7, 4, 9)));
    await store.save(_trip('newer', DateTime(2026, 7, 5, 14)));

    final all = await store.all();
    expect(all.map((t) => t.id), ['newer', 'older']);
    expect(all.first.distanceKm, 3.2);
  });

  test('delete removes only the matching trip', () async {
    await store.save(_trip('keep', DateTime(2026, 7, 4, 9)));
    await store.save(_trip('gone', DateTime(2026, 7, 5, 14)));

    await store.delete('gone');

    expect((await store.all()).map((t) => t.id), ['keep']);
  });

  test('delete of an unknown id is a no-op', () async {
    await store.save(_trip('keep', DateTime(2026, 7, 4, 9)));

    await store.delete('missing');

    expect(await store.all(), hasLength(1));
  });

  test('clear removes every trip', () async {
    await store.save(_trip('a', DateTime(2026, 7, 4, 9)));
    await store.save(_trip('b', DateTime(2026, 7, 5, 14)));

    await store.clear();

    expect(await store.all(), isEmpty);
  });
}
