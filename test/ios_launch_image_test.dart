import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reads the width/height from a PNG's IHDR chunk (bytes 16-23).
(int, int) pngDimensions(File file) {
  final bytes = file.readAsBytesSync();
  int be32(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  return (be32(16), be32(20));
}

void main() {
  const dir = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';

  // Guards against the iOS launch image regressing to Flutter's blank
  // 1x1 placeholder PNGs.
  test('iOS launch images are the RoadMate truck at 1x/2x/3x sizes', () {
    const expected = {
      '$dir/LaunchImage.png': 170,
      '$dir/LaunchImage@2x.png': 340,
      '$dir/LaunchImage@3x.png': 510,
    };
    expected.forEach((path, size) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path missing');
      final (width, height) = pngDimensions(file);
      expect(width, size, reason: '$path width');
      expect(height, size, reason: '$path height');
    });
  });

  test('launch screen storyboard uses the dark background, not white', () {
    final storyboard =
        File('ios/Runner/Base.lproj/LaunchScreen.storyboard').readAsStringSync();
    expect(storyboard, contains('image="LaunchImage"'));
    expect(
      storyboard,
      isNot(contains('red="1" green="1" blue="1"')),
      reason: 'launch screen background should match the dark logo tile',
    );
  });
}
