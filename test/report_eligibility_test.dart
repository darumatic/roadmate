import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/report_eligibility.dart';

void main() {
  group('canPostReports', () {
    test('a linked Google/Apple account may post', () {
      expect(canPostReports(signedIn: true, isAnonymous: false), isTrue);
    });

    test('an anonymous session may not — that is the whole point', () {
      expect(canPostReports(signedIn: true, isAnonymous: true), isFalse);
    });

    test('no session at all may not post', () {
      // Fails closed: an absent user is never a licence to post, so callers
      // don't have to special-case a null.
      expect(canPostReports(signedIn: false, isAnonymous: true), isFalse);
      expect(canPostReports(signedIn: false, isAnonymous: false), isFalse);
    });
  });

  group('SignInRequiredException', () {
    test('explains itself with the sign-in message', () {
      const exception = SignInRequiredException();
      expect(exception.message, kSignInToReportMessage);
      expect(exception.toString(), kSignInToReportMessage);
    });

    test('the prompt copy says what stays free', () {
      // The sheet must not read as "sign in to use RoadMate" — browsing,
      // Nearby and favourites deliberately stay account-free.
      expect(kSignInSheetBody, contains('Browsing'));
      expect(kSignInSheetBody, contains('Nearby'));
    });
  });
}
