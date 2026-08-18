import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the weight of bundled image assets. The Darumatic credit logo
/// renders at 44x44 logical pixels (info_screen.dart), so the bundled file
/// only needs ~132px (3x) — the original 637px marketing export weighed
/// 342KB and was 64% of all flutter_assets across every platform. A
/// re-export of the full-size art should fail here, not ship.
void main() {
  const logoPath = 'assets/images/darumatic-logo.png';
  const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  int be32(List<int> b, int offset) =>
      (b[offset] << 24) |
      (b[offset + 1] << 16) |
      (b[offset + 2] << 8) |
      b[offset + 3];

  test('the bundled Darumatic logo stays small', () {
    final file = File(logoPath);
    expect(file.existsSync(), isTrue, reason: '$logoPath missing');

    final bytes = file.readAsBytesSync();
    expect(bytes.length, lessThan(60 * 1024),
        reason: '$logoPath is ${bytes.length} bytes — it renders at 44x44 '
            'logical pixels, so keep the bundled file under 60KB '
            '(resize a re-export to ~132px before committing)');

    expect(bytes.sublist(0, 8), pngSignature, reason: '$logoPath is not a PNG');
    // IHDR is always the first chunk: width/height at offsets 16/20.
    final width = be32(bytes, 16);
    final height = be32(bytes, 20);
    expect(width, lessThanOrEqualTo(264),
        reason: '$logoPath is ${width}px wide — 132px (3x of 44) is enough');
    expect(height, lessThanOrEqualTo(264),
        reason: '$logoPath is ${height}px tall — 132px (3x of 44) is enough');
  });
}
