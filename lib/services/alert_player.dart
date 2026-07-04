import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

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

  @override
  Future<void> playOverLimit() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {
      // Haptics unavailable — ignore.
    }
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/beep.wav'));
    } catch (_) {
      // Audio unavailable — ignore.
    }
  }
}
