import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'load_error.dart';

/// The one loading / error / data unwrapping for a screen or tab body:
/// centered spinner while loading, [LoadError] on error, [builder] on data.
///
/// Screens used to hand-roll this triple per call site, and the copies had
/// already drifted (the Nearby screen grew a bespoke error widget). One
/// implementation keeps every surface failing the same way.
Widget asyncBody<T>(AsyncValue<T> value, Widget Function(T data) builder) {
  return value.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (_, _) => const LoadError(),
    data: builder,
  );
}
