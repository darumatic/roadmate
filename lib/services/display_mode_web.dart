import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

// Web implementation (selected via the conditional import in
// auth_service.dart): whether the app runs as an installed PWA rather than a
// normal browser tab. Matters for sign-in — a PWA's "popup" is a custom tab
// with no window.opener, so the Firebase popup handler hangs forever there
// and the redirect flow must be used instead.

bool isStandaloneDisplayMode() {
  try {
    for (final mode in ['standalone', 'minimal-ui', 'fullscreen']) {
      if (web.window.matchMedia('(display-mode: $mode)').matches) return true;
    }
    // Legacy iOS home-screen web apps expose navigator.standalone instead.
    final standalone = web.window.navigator.getProperty('standalone'.toJS);
    return standalone.isDefinedAndNotNull && (standalone as JSBoolean).toDart;
  } catch (_) {
    return false; // unknowable — behave like a normal tab
  }
}
