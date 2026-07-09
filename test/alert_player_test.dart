import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/alert_player.dart';

void main() {
  // Issue #18: the over-limit beep must be heard over music on both platforms.
  group('alertAudioContext', () {
    test('Android uses the alarm stream and ducks other audio', () {
      final android = alertAudioContext().android;
      // Alarm usage sounds at alarm volume even when media volume is low.
      expect(android.usageType, AndroidUsageType.alarm);
      expect(android.contentType, AndroidContentType.sonification);
      // Transient focus lowers music during the beep instead of pausing it.
      expect(android.audioFocus, AndroidAudioFocus.gainTransientMayDuck);
    });

    test('iOS plays over music (and the silent switch) and ducks it', () {
      final ios = alertAudioContext().iOS;
      // `playback` ignores the silent switch — this is a safety alert.
      expect(ios.category, AVAudioSessionCategory.playback);
      expect(ios.options, contains(AVAudioSessionOptions.duckOthers));
    });
  });
}
