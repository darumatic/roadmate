import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a pull-to-refresh should restart a stream provider: only when its
/// last attempt failed. A healthy Firestore snapshot listener is live by
/// definition — never stale — and restarting one re-bills a read for every
/// document in its result set, so refresh must not tear it down.
bool shouldRestartOnRefresh(AsyncValue<Object?> value) => value.hasError;
