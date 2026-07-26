import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip.dart';

/// Default manually-set speed limit (km/h) and its adjustment bounds/step,
/// shared by the store and the limit control.
const int kDefaultSpeedLimit = 100;
const int kMinSpeedLimit = 20;
const int kMaxSpeedLimit = 130;
const int kSpeedLimitStep = 1;

/// On-device persistence for saved trips, the manual speed limit, the
/// alert-sound switch (issue #22) and the site-approach prompt switch.
/// Injectable (mirrors `LocationSource`) so tests use an in-memory fake.
/// Nothing here leaves the device — trips are not sent to our servers.
abstract class TripHistoryStore {
  Future<void> save(Trip trip);
  Future<List<Trip>> all();
  Future<void> delete(String id);
  Future<void> clear();
  Future<int> loadLimit();
  Future<void> saveLimit(int limitKmh);
  Future<bool> loadSoundEnabled();
  Future<void> saveSoundEnabled(bool enabled);
  Future<bool> loadProximityEnabled();
  Future<void> saveProximityEnabled(bool enabled);
}

/// `shared_preferences`-backed store. Trips are a JSON array under [_tripsKey];
/// the limit is a single int under [_limitKey]; the alert-sound switch is a
/// bool under [_soundKey] and the approach-prompt switch under
/// [_proximityKey] (both default on).
class PrefsTripHistoryStore implements TripHistoryStore {
  const PrefsTripHistoryStore();

  static const _tripsKey = 'trips';
  static const _limitKey = 'speedLimit';
  static const _soundKey = 'soundEnabled';
  static const _proximityKey = 'proximityAlertsEnabled';

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
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_tripsKey) ?? <String>[];
    raw.removeWhere((s) => (jsonDecode(s) as Map<String, dynamic>)['id'] == id);
    await prefs.setStringList(_tripsKey, raw);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tripsKey);
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

  @override
  Future<bool> loadSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundKey) ?? true;
  }

  @override
  Future<void> saveSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, enabled);
  }

  @override
  Future<bool> loadProximityEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_proximityKey) ?? true;
  }

  @override
  Future<void> saveProximityEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_proximityKey, enabled);
  }
}
