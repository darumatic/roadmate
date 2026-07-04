import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip.dart';

/// Default manually-set speed limit (km/h) and its adjustment bounds/step,
/// shared by the store and the limit control.
const int kDefaultSpeedLimit = 100;
const int kMinSpeedLimit = 20;
const int kMaxSpeedLimit = 130;
const int kSpeedLimitStep = 1;

/// On-device persistence for saved trips and the manual speed limit. Injectable
/// (mirrors `LocationSource`) so tests use an in-memory fake. Nothing here
/// leaves the device — trips are not sent to our servers.
abstract class TripHistoryStore {
  Future<void> save(Trip trip);
  Future<List<Trip>> all();
  Future<int> loadLimit();
  Future<void> saveLimit(int limitKmh);
}

/// `shared_preferences`-backed store. Trips are a JSON array under [_tripsKey];
/// the limit is a single int under [_limitKey].
class PrefsTripHistoryStore implements TripHistoryStore {
  const PrefsTripHistoryStore();

  static const _tripsKey = 'trips';
  static const _limitKey = 'speedLimit';

  @override
  Future<void> save(Trip trip) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_tripsKey) ?? <String>[];
    raw.add(jsonEncode(trip.toMap()));
    await prefs.setStringList(_tripsKey, raw);
  }

  @override
  Future<List<Trip>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_tripsKey) ?? <String>[];
    return raw
        .map((s) => Trip.fromMap(jsonDecode(s) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  @override
  Future<int> loadLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_limitKey) ?? kDefaultSpeedLimit;
  }

  @override
  Future<void> saveLimit(int limitKmh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_limitKey, limitKmh);
  }
}
