import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The static pages under web/ are served at the site root and are referenced
/// from App Store Connect (support URL, privacy URL) — they must exist and
/// keep their contact/link contract.
void main() {
  test('support page exists with contact email and key links', () {
    final html = File('web/support.html').readAsStringSync();
    expect(html, contains('mailto:info@roadmate.club'));
    expect(html, contains('https://roadmate.club/privacy.html'));
    expect(html, contains('https://roadmate.club/delete-account.html'));
  });

  test('privacy page exists with contact email', () {
    final html = File('web/privacy.html').readAsStringSync();
    expect(html, contains('mailto:info@roadmate.club'));
  });
}
