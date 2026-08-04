import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/username_logic.dart';

void main() {
  group('generateUsername', () {
    test('is deterministic for a seeded Random', () {
      expect(generateUsername(Random(42)), generateUsername(Random(42)));
    });

    test('every generated name passes validation and stays within caps', () {
      final random = Random(7);
      for (var i = 0; i < 500; i++) {
        final name = generateUsername(random);
        expect(validateUsername(name), isNull, reason: name);
        expect(name.length, lessThanOrEqualTo(kUsernameMaxLength));
        expect(name.length, greaterThanOrEqualTo(kUsernameMinLength));
      }
    });

    test(
      'mixes an adjective (or two) with a noun from the road-themed pool',
      () {
        final random = Random(3);
        final seenLengths = <int>{};
        for (var i = 0; i < 200; i++) {
          final words = generateUsername(random).split(' ');
          seenLengths.add(words.length);
          expect(kUsernameNouns, contains(words.last));
          for (final adjective in words.sublist(0, words.length - 1)) {
            expect(kUsernameAdjectives, contains(adjective));
          }
        }
        // Both the short and the long form actually occur.
        expect(seenLengths, containsAll([2, 3]));
      },
    );
  });

  group('normalizeUsername / usernameKey', () {
    test('trims and collapses whitespace', () {
      expect(normalizeUsername('  Dusty   Nomad '), 'Dusty Nomad');
    });

    test('key is the lowercased normalized name, so casing collides', () {
      expect(usernameKey('DUSTY Nomad'), usernameKey('dusty  nomad '));
      expect(usernameKey('Dusty Nomad'), 'dusty nomad');
    });
  });

  group('validateUsername', () {
    test('accepts letters, digits, spaces, hyphen and underscore', () {
      expect(validateUsername('Dusty Nomad'), isNull);
      expect(validateUsername('Big-Rig_99'), isNull);
      expect(validateUsername('abc'), isNull);
    });

    test('rejects too short and too long', () {
      expect(validateUsername('ab'), isNotNull);
      expect(validateUsername('  a  '), isNotNull);
      expect(validateUsername('a' * (kUsernameMaxLength + 1)), isNotNull);
      // Exactly at the cap is fine.
      expect(validateUsername('a' * kUsernameMaxLength), isNull);
    });

    test('rejects forbidden characters and bad edges', () {
      expect(validateUsername('Dusty!Nomad'), isNotNull);
      expect(validateUsername('-Dusty'), isNotNull);
      expect(validateUsername('Dusty-'), isNotNull);
      expect(validateUsername('Emoji 🚚'), isNotNull);
      expect(validateUsername('slash/name'), isNotNull);
    });
  });

  group('shouldPromptForUsername', () {
    test('prompts an anonymous user with a loaded profile and no name', () {
      expect(
        shouldPromptForUsername(
          isAnonymousUser: true,
          profileLoaded: true,
          username: null,
          dismissed: false,
        ),
        isTrue,
      );
    });

    test('never prompts signed-in users, unloaded profiles, named users or '
        'after Not-now', () {
      expect(
        shouldPromptForUsername(
          isAnonymousUser: false,
          profileLoaded: true,
          username: null,
          dismissed: false,
        ),
        isFalse,
      );
      expect(
        shouldPromptForUsername(
          isAnonymousUser: true,
          profileLoaded: false,
          username: null,
          dismissed: false,
        ),
        isFalse,
      );
      expect(
        shouldPromptForUsername(
          isAnonymousUser: true,
          profileLoaded: true,
          username: 'Dusty Nomad',
          dismissed: false,
        ),
        isFalse,
      );
      expect(
        shouldPromptForUsername(
          isAnonymousUser: true,
          profileLoaded: true,
          username: null,
          dismissed: true,
        ),
        isFalse,
      );
    });
  });
}
