import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Audio session for the over-limit warning (issue #18): the beep must be
/// heard over music playing on the device — and (issue #37) it must leave the
/// driver's own media volume exactly as it was before, during and after.
///
/// - Android: the alarm stream (`usageType: alarm`) plays at alarm volume
///   regardless of the media volume, so the beep carries over music without
///   any help. Focus is `none`: a transient focus request
///   (`gainTransientMayDuck`, previously used here) asks the music app to
///   attenuate itself — that duck, not a volume change of ours, is what drivers
///   heard as "the app halved my music", and it can linger past the beep.
/// - iOS: the `playback` category sounds even when the silent switch is on
///   (this is a safety alert), and `mixWithOthers` plays the beep alongside
///   other apps' audio at its own level instead of ducking or pausing it.
AudioContext alertAudioContext() => AudioContext(
  android: const AudioContextAndroid(
    isSpeakerphoneOn: false,
    stayAwake: false,
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.alarm,
    audioFocus: AndroidAudioFocus.none,
  ),
  iOS: AudioContextIOS(
    category: AVAudioSessionCategory.playback,
    options: const {AVAudioSessionOptions.mixWithOthers},
  ),
);

/// Plays the over-limit warning. Injectable (mirrors `LocationSource`) so widget
/// tests substitute a silent fake and never touch the audio/haptics plugins.
abstract class AlertPlayer {
  Future<void> playOverLimit();

  /// Sounds the site-approach prompt. Distinct call site from the over-limit
  /// warning so the two can diverge (different sample, different urgency)
  /// without touching either caller.
  Future<void> playProximity();
}

/// Production player: a short bundled beep plus a haptic buzz. Best-effort —
/// any plugin failure (or the test harness) is swallowed so a missing sound can
/// never interrupt trip tracking.
class BeepAlertPlayer implements AlertPlayer {
  BeepAlertPlayer();

  final AudioPlayer _player = AudioPlayer();
  bool _sessionConfigured = false;

  /// Applies [alertAudioContext] once, lazily, before the first beep. The
  /// global call configures the iOS audio session; the per-player call covers
  /// Android. Web has no audio context — failures are ignored everywhere.
  Future<void> _ensureSession() async {
    if (_sessionConfigured) return;
    _sessionConfigured = true;
    try {
      await AudioPlayer.global.setAudioContext(alertAudioContext());
    } catch (_) {
      // Unsupported platform (web) or plugin unavailable — ignore.
    }
    try {
      await _player.setAudioContext(alertAudioContext());
    } catch (_) {
      // Unsupported platform (web) or plugin unavailable — ignore.
    }
  }

  @override
  Future<void> playOverLimit() => _beep(HapticFeedback.heavyImpact);

  /// Same sample as the over-limit warning but a softer buzz: approaching a
  /// site is information, not a breach.
  @override
  Future<void> playProximity() => _beep(HapticFeedback.mediumImpact);

  Future<void> _beep(Future<void> Function() haptic) async {
    try {
      await haptic();
    } catch (_) {
      // Haptics unavailable — ignore.
    }
    try {
      await _ensureSession();
      await _player.stop();
      await _player.play(AssetSource('sounds/beep.wav'), volume: 1.0);
    } catch (_) {
      // Audio unavailable — ignore.
    }
  }
}
