import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/features/speedometer/trip_tile.dart';
import 'package:roadmate/features/user/user_screen.dart';
import 'package:roadmate/models/trip.dart';
import 'package:roadmate/services/providers.dart';
import 'package:roadmate/services/trip_history_store.dart';

class FakeTripStore implements TripHistoryStore {
  final List<Trip> saved = [];

  @override
  Future<void> save(Trip trip) async => saved.add(trip);

  @override
  Future<List<Trip>> all() async => List.of(saved);

  @override
  Future<void> delete(String id) async => saved.removeWhere((t) => t.id == id);

  @override
  Future<void> clear() async => saved.clear();

  @override
  Future<int> loadLimit() async => kDefaultSpeedLimit;

  @override
  Future<void> saveLimit(int limitKmh) async {}

  @override
  Future<bool> loadSoundEnabled() async => true;

  @override
  Future<void> saveSoundEnabled(bool enabled) async {}

  @override
  Future<bool> loadProximityEnabled() async => true;

  @override
  Future<void> saveProximityEnabled(bool enabled) async {}
}

Trip _trip(int i) => Trip(
  id: 'trip-$i',
  startedAt: DateTime(2026, 7, 5 - i, 9),
  duration: Duration(minutes: 5 + i),
  distanceKm: 1.0 + i,
  maxSpeedKmh: 80,
  avgSpeedKmh: 60,
);

Future<void> _pump(WidgetTester tester, FakeTripStore store) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(1200, 2400));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tripHistoryStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(home: UserScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every saved trip (not capped at 3)', (tester) async {
    final store = FakeTripStore()
      ..saved.addAll([for (var i = 0; i < 5; i++) _trip(i)]);
    await _pump(tester, store);

    expect(find.text('User'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('My Trips'), findsOneWidget);
    expect(find.text('5 saved trips'), findsOneWidget);
    expect(find.byType(TripTile), findsNWidgets(5));
    expect(find.text('View all (5)'), findsNothing);
  });

  testWidgets('per-trip delete works via the confirmation dialog', (
    tester,
  ) async {
    final store = FakeTripStore()..saved.addAll([_trip(0), _trip(1)]);
    await _pump(tester, store);

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete Trip'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(store.saved, hasLength(1));
    expect(find.byType(TripTile), findsOneWidget);
  });

  testWidgets('Help & Support row opens the hosted support page', (
    tester,
  ) async {
    final launched = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch') {
          launched.add(call.arguments['url'] as String);
        }
        return true;
      },
    );

    await _pump(tester, FakeTripStore());
    expect(find.text('Help & Support'), findsOneWidget);

    await tester.tap(find.text('Help & Support'));
    await tester.pumpAndSettle();
    expect(launched, ['https://roadmate.club/support.html']);
  });

  testWidgets('Clear all empties the history after confirmation', (
    tester,
  ) async {
    final store = FakeTripStore()..saved.addAll([_trip(0), _trip(1)]);
    await _pump(tester, store);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all'));
    await tester.pumpAndSettle();

    expect(store.saved, isEmpty);
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.text('Clear all'), findsNothing);
  });
}
