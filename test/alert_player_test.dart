import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/alert_player.dart';

void main() {
  // Issue #18: the over-limit beep must be heard over music on both platforms.
  // Issue #37: and it must never change the driver's media volume to do it.
  group('alertAudioContext', () {
    test('Android uses the alarm stream and requests no audio focus', () {
      final android = alertAudioContext().android;
      // Alarm usage sounds at alarm volume even when media volume is low.
      expect(android.usageType, AndroidUsageType.alarm);
      expect(android.contentType, AndroidContentType.sonification);
      // Any focus request asks the music app to duck (or stop) — issue #37.
      expect(android.audioFocus, AndroidAudioFocus.none);
    });

    test('iOS plays over music (and the silent switch) without ducking it', () {
      final ios = alertAudioContext().iOS;
      // `playback` ignores the silent switch — this is a safety alert.
      expect(ios.category, AVAudioSessionCategory.playback);
      // Mix alongside other audio; never duck or interrupt it (issue #37).
      expect(ios.options, contains(AVAudioSessionOptions.mixWithOthers));
      expect(ios.options, isNot(contains(AVAudioSessionOptions.duckOthers)));
      expect(
        ios.options,
        isNot(
          contains(AVAudioSessionOptions.interruptSpokenAudioAndMixWithOthers),
        ),
      );
    });
  });
}
