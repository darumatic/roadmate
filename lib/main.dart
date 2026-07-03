import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/error_reporter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  const reporter = ErrorReporter();
  FlutterError.onError = reporter.recordFlutterError;
  PlatformDispatcher.instance.onError = reporter.recordError;

  runApp(const ProviderScope(child: RoadMateApp()));
}
