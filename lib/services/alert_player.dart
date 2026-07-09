import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Audio session for the over-limit warning (issue #18): the beep must be
/// heard over music playing on the device.
///
/// - Android: the alarm stream (`usageType: alarm`) plays at alarm volume
///   regardless of the media volume, and `gainTransientMayDuck` momentarily
///   lowers ("ducks") any music instead of pausing it.
/// - iOS: the `playback` category sounds even when the silent switch is on
///   (this is a safety alert), and `duckOthers` lowers other apps' audio for
///   the duration of the beep.
AudioContext alertAudioContext() => AudioContext(
  android: const AudioContextAndroid(
    isSpeakerphoneOn: false,
    stayAwake: false,
    contentType: AndroidContentType.sonification,
    usageType: AndroidUsageType.alarm,
    audioFocus: AndroidAudioFocus.gainTransientMayDuck,
  ),
  iOS: AudioContextIOS(
    category: AVAudioSessionCategory.playback,
    options: const {AVAudioSessionOptions.duckOthers},
  ),
);

/// Plays the over-limit warning. Injectable (mirrors `LocationSource`) so widget
/// tests substitute a silent fake and never touch the audio/haptics plugins.
abstract class AlertPlayer {
  Future<void> playOverLimit();
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
  Future<void> playOverLimit() async {
    try {
      await HapticFeedback.heavyImpact();
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
