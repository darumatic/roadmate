import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'rate_limit.dart';

/// When this device last voted/reported per site, for the cooldown UX
/// (issue #15). The Firestore rules ledger is the real enforcement; this only
/// makes honest users see disabled buttons instead of a server rejection.
class CooldownState {
  const CooldownState({
    this.voteAt = const {},
    this.reportAt = const {},
    this.tick = 0,
  });

  final Map<String, DateTime> voteAt;
  final Map<String, DateTime> reportAt;

  /// Bumped by the expiry timer so watchers recompute remaining times (the
  /// maps themselves don't change when a cooldown lapses).
  final int tick;

  Duration? remainingVote(String siteId, DateTime now) => cooldownRemaining(
    lastActionAt: voteAt[siteId],
    now: now,
    cooldown: kVoteCooldown,
  );

  Duration? remainingReport(String siteId, DateTime now) => cooldownRemaining(
    lastActionAt: reportAt[siteId],
    now: now,
    cooldown: kReportCooldown,
  );

  CooldownState copyWith({
    Map<String, DateTime>? voteAt,
    Map<String, DateTime>? reportAt,
    int? tick,
  }) {
    return CooldownState(
      voteAt: voteAt ?? this.voteAt,
      reportAt: reportAt ?? this.reportAt,
      tick: tick ?? this.tick,
    );
  }
}

/// Loads persisted cooldowns, records new ones on successful votes/reports,
/// and wakes watchers when the earliest cooldown expires so buttons re-enable
/// without user interaction. Storage is best-effort (mirrors the trip store).
class CooldownController extends Notifier<CooldownState> {
  Timer? _expiryTimer;

  @override
  CooldownState build() {
    ref.onDispose(() => _expiryTimer?.cancel());
    _load();
    return const CooldownState();
  }

  Future<void> _load() async {
    try {
      final snapshot = await ref.read(cooldownStoreProvider).loadAll();
      state = state.copyWith(
        voteAt: snapshot.voteAt,
        reportAt: snapshot.reportAt,
      );
      _scheduleExpiry();
    } catch (e) {
      // First launch or storage unavailable — start with no cooldowns.
      debugPrint('RoadMate: failed to load cooldowns: $e');
    }
  }

  void markVote(String siteId) {
    final now = DateTime.now();
    state = state.copyWith(voteAt: {...state.voteAt, siteId: now});
    _persist(() => ref.read(cooldownStoreProvider).markVote(siteId, now));
    _scheduleExpiry();
  }

  void markReport(String siteId) {
    final now = DateTime.now();
    state = state.copyWith(reportAt: {...state.reportAt, siteId: now});
    _persist(() => ref.read(cooldownStoreProvider).markReport(siteId, now));
    _scheduleExpiry();
  }

  Future<void> _persist(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      // Persistence is a nicety — the in-memory state still gates the UI.
      debugPrint('RoadMate: failed to save cooldown: $e');
    }
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final now = DateTime.now();
    DateTime? earliest;
    void consider(DateTime stamp, Duration cooldown) {
      final end = stamp.add(cooldown);
      if (end.isAfter(now) && (earliest == null || end.isBefore(earliest!))) {
        earliest = end;
      }
    }

    for (final t in state.voteAt.values) {
      consider(t, kVoteCooldown);
    }
    for (final t in state.reportAt.values) {
      consider(t, kReportCooldown);
    }
    if (earliest == null) return;
    // +1s so the fired tick lands strictly after the cooldown end.
    _expiryTimer = Timer(
      earliest!.difference(now) + const Duration(seconds: 1),
      () {
        state = state.copyWith(tick: state.tick + 1);
        _scheduleExpiry();
      },
    );
  }
}

final cooldownProvider = NotifierProvider<CooldownController, CooldownState>(
  CooldownController.new,
);
