import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:web/web.dart' as web;

// Web implementation of the update probe (selected via the conditional import
// in update_checker.dart). Reads the deployed build's /version.json — emitted
// by `flutter build web` and served with no-cache headers (firebase.json) so
// it always reflects the latest deploy.

Future<String?> fetchRemoteVersion() async {
  try {
    // Cache-bust twice over: a unique query string and cache: no-store, so
    // neither the service worker nor the HTTP cache can answer for the CDN.
    final url = 'version.json?ts=${DateTime.now().millisecondsSinceEpoch}';
    final response = await web.window
        .fetch(url.toJS, web.RequestInit(cache: 'no-store'))
        .toDart;
    if (!response.ok) return null;
    final body = (await response.text().toDart).toDart;
    final data = jsonDecode(body) as Map<String, dynamic>;
    final version = data['version'] as String?;
    return (version == null || version.isEmpty) ? null : version;
  } catch (e) {
    // Offline or a transient error — never let the update check surface.
    debugPrint('RoadMate: update check failed: $e');
    return null;
  }
}

/// Reloads onto the freshly deployed build in one step: without clearing the
/// service worker + caches first, Flutter's SW serves the old bundle once
/// more and the user must refresh twice.
Future<void> reloadApp() async {
  try {
    final registrations = await web.window.navigator.serviceWorker
        .getRegistrations()
        .toDart;
    for (final registration in registrations.toDart) {
      await registration.unregister().toDart;
    }
    final cacheKeys = (await web.window.caches.keys().toDart).toDart;
    for (final key in cacheKeys) {
      await web.window.caches.delete(key.toDart).toDart;
    }
  } catch (e) {
    // Best-effort — reload regardless; worst case is the double-refresh.
    debugPrint('RoadMate: service worker cleanup failed: $e');
  }
  web.window.location.reload();
}
