import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host-side driver for the web integration suite: receives screenshots taken
/// with `binding.takeScreenshot` and writes them under build/.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      final file = File('build/integration_screenshots/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
