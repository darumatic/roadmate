import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android / iOS launcher icons (derived from
/// assets/images/road-mate-logo.png): files exist, are PNGs, and carry the
/// exact dimensions each platform expects.
void main() {
  const expected = {
    // Android legacy launcher icons (shown as-is on API < 26)
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
    // Android adaptive foreground (108dp base)
    'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png': 108,
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png': 432,
    // iOS key sizes (full set shares the same master)
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png': 180,
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png':
        1024,
  };

  const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  int be32(List<int> b, int offset) =>
      (b[offset] << 24) |
      (b[offset + 1] << 16) |
      (b[offset + 2] << 8) |
      b[offset + 3];

  for (final entry in expected.entries) {
    test('${entry.key} is a ${entry.value}px square PNG', () {
      final bytes = File(entry.key).readAsBytesSync();
      expect(bytes.sublist(0, 8), pngSignature, reason: 'PNG signature');
      expect(be32(bytes, 16), entry.value, reason: 'width');
      expect(be32(bytes, 20), entry.value, reason: 'height');
    });
  }

  test('adaptive icon XML wires foreground and background', () {
    final xml = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(xml, contains('@mipmap/ic_launcher_foreground'));
    expect(xml, contains('@color/ic_launcher_background'));
    expect(
      File(
        'android/app/src/main/res/values/ic_launcher_background.xml',
      ).readAsStringSync(),
      contains('ic_launcher_background'),
    );
  });
}
