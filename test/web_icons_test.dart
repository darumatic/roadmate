import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the web favicon / PWA icon set (derived from
/// assets/images/road-mate-logo.png): every file index.html and manifest.json
/// reference must exist, be a real PNG, and have the advertised dimensions.
void main() {
  const expected = {
    'web/favicon.png': 64,
    'web/icons/Icon-192.png': 192,
    'web/icons/Icon-512.png': 512,
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
  };

  const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  int be32(List<int> b, int offset) =>
      (b[offset] << 24) | (b[offset + 1] << 16) | (b[offset + 2] << 8) |
      b[offset + 3];

  for (final entry in expected.entries) {
    test('${entry.key} is a ${entry.value}px square PNG', () {
      final bytes = File(entry.key).readAsBytesSync();
      expect(bytes.length, greaterThan(pngSignature.length + 24));
      expect(bytes.sublist(0, 8), pngSignature, reason: 'PNG signature');
      // IHDR is always the first chunk: width/height at bytes 16-23.
      expect(be32(bytes, 16), entry.value, reason: 'width');
      expect(be32(bytes, 20), entry.value, reason: 'height');
    });
  }
}
